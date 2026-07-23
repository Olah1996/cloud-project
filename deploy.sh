#!/usr/bin/env bash
#
# deploy.sh — LedgerPoint secure file storage: end-to-end deployment
#
# Provisions:
#   - Files bucket (private, versioned, encrypted)
#   - Logs bucket (private)
#   - Server access logging: files bucket -> logs bucket
#
# Run with the ADMIN AWS CLI profile (bucket creation is not permitted
# for the least-privilege ledgerpoint-tool identity by design).
#
# Usage: ./deploy.sh

set -euo pipefail

# ---- Config ----
FILES_BUCKET="${LEDGERPOINT_BUCKET:-ledgerpoint-files-2026-jul}"
LOGS_BUCKET="${LEDGERPOINT_LOGS_BUCKET:-ledgerpoint-logs-2026-jul}"
REGION="${LEDGERPOINT_REGION:-us-east-1}"

echo "=== LedgerPoint Secure Storage: Deployment ==="
echo "Files bucket: ${FILES_BUCKET}"
echo "Logs bucket:  ${LOGS_BUCKET}"
echo "Region:       ${REGION}"
echo ""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Deploying to account: ${ACCOUNT_ID}"
echo ""

# ---- Step 1: Create files bucket ----
echo "[1/8] Creating files bucket..."
if [[ "$REGION" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "$FILES_BUCKET" --region "$REGION" 2>/dev/null || echo "  (already exists, continuing)"
else
  aws s3api create-bucket --bucket "$FILES_BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null || echo "  (already exists, continuing)"
fi

# ---- Step 2: Block public access on files bucket ----
echo "[2/8] Blocking public access on files bucket..."
aws s3api put-public-access-block --bucket "$FILES_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ---- Step 3: Enable versioning ----
echo "[3/8] Enabling versioning on files bucket..."
aws s3api put-bucket-versioning --bucket "$FILES_BUCKET" \
  --versioning-configuration Status=Enabled

# ---- Step 4: Enable default encryption ----
echo "[4/8] Enabling default encryption on files bucket..."
aws s3api put-bucket-encryption --bucket "$FILES_BUCKET" \
  --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

# ---- Step 5: Create logs bucket ----
echo "[5/8] Creating logs bucket..."
if [[ "$REGION" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "$LOGS_BUCKET" --region "$REGION" 2>/dev/null || echo "  (already exists, continuing)"
else
  aws s3api create-bucket --bucket "$LOGS_BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null || echo "  (already exists, continuing)"
fi

# ---- Step 6: Block public access on logs bucket ----
echo "[6/8] Blocking public access on logs bucket..."
aws s3api put-public-access-block --bucket "$LOGS_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ---- Step 7: Grant log delivery permission on logs bucket ----
echo "[7/8] Granting S3 log delivery permission on logs bucket..."
cat > ./logging-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ServerAccessLogsPolicy",
      "Effect": "Allow",
      "Principal": {"Service": "logging.s3.amazonaws.com"},
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${LOGS_BUCKET}/*",
      "Condition": {
        "StringEquals": {"aws:SourceAccount": "${ACCOUNT_ID}"}
      }
    }
  ]
}
EOF
aws s3api put-bucket-policy --bucket "$LOGS_BUCKET" --policy file://./logging-policy.json

# ---- Step 8: Enable access logging on files bucket -> logs bucket ----
echo "[8/8] Enabling access logging: ${FILES_BUCKET} -> ${LOGS_BUCKET}..."
cat > ./logging-config.json <<EOF
{
  "LoggingEnabled": {
    "TargetBucket": "${LOGS_BUCKET}",
    "TargetPrefix": "access-logs/"
  }
}
EOF
aws s3api put-bucket-logging --bucket "$FILES_BUCKET" --bucket-logging-status file://./logging-config.json

rm -f ./logging-policy.json ./logging-config.json

echo ""
echo "=== Deployment complete ==="
echo "Files bucket:  ${FILES_BUCKET} (private, versioned, encrypted)"
echo "Logs bucket:   ${LOGS_BUCKET} (private, receiving access logs)"
echo ""
echo "Next: use filetool.sh with the ledgerpoint-tool profile to upload/share/download/delete files."