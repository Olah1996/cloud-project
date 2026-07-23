#!/usr/bin/env bash
#
# filetool.sh — LedgerPoint secure file storage CLI
#
# Wraps AWS CLI S3 operations for the ledgerpoint-tool IAM identity.
# Subcommands: upload, download, list, delete, share
#
# Usage:
#   ./filetool.sh upload <local-file-path>
#   ./filetool.sh download <s3-key> [destination-path]
#   ./filetool.sh list
#   ./filetool.sh delete <s3-key>
#   ./filetool.sh share <s3-key> <hours>

set -euo pipefail

# ---- Config ----
BUCKET="${LEDGERPOINT_BUCKET:-ledgerpoint-files-2026-jul}"
PROFILE="${LEDGERPOINT_PROFILE:-ledgerpoint-tool}"
LOGFILE="./filetool-actions.log"

# ---- Helpers ----
log_action() {
  local action="$1"
  local detail="$2"
  local status="$3"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "${timestamp} | user=$(whoami) | action=${action} | detail=${detail} | status=${status}" >> "${LOGFILE}"
}

usage() {
  echo "Usage: $0 {upload|download|list|delete|share} [args]"
  echo "  upload   <local-file-path>"
  echo "  download <s3-key> [destination-path]"
  echo "  list"
  echo "  delete   <s3-key>"
  echo "  share    <s3-key> <hours>"
  exit 1
}

# ---- Subcommands ----
cmd_upload() {
  local filepath="${1:-}"
  [[ -z "$filepath" ]] && { echo "Error: missing file path"; usage; }
  [[ ! -f "$filepath" ]] && { echo "Error: file not found: $filepath"; exit 1; }

  local filename
  filename=$(basename "$filepath")

  if aws s3 cp "$filepath" "s3://${BUCKET}/${filename}" --profile "$PROFILE"; then
    echo "Uploaded: $filename"
    log_action "upload" "$filename" "success"
  else
    log_action "upload" "$filename" "failed"
    echo "Upload failed."
    exit 1
  fi
}

cmd_download() {
  local key="${1:-}"
  local dest="${2:-./$key}"
  [[ -z "$key" ]] && { echo "Error: missing S3 key"; usage; }

  if aws s3 cp "s3://${BUCKET}/${key}" "$dest" --profile "$PROFILE"; then
    echo "Downloaded: $key -> $dest"
    log_action "download" "$key" "success"
  else
    log_action "download" "$key" "failed"
    echo "Download failed."
    exit 1
  fi
}

cmd_list() {
  echo "Files in ${BUCKET}:"
  if aws s3 ls "s3://${BUCKET}/" --profile "$PROFILE"; then
    log_action "list" "-" "success"
  else
    log_action "list" "-" "failed"
    exit 1
  fi
}

cmd_delete() {
  local key="${1:-}"
  [[ -z "$key" ]] && { echo "Error: missing S3 key"; usage; }

  if aws s3 rm "s3://${BUCKET}/${key}" --profile "$PROFILE"; then
    echo "Deleted: $key"
    log_action "delete" "$key" "success"
  else
    log_action "delete" "$key" "failed"
    echo "Delete failed."
    exit 1
  fi
}

cmd_share() {
  local key="${1:-}"
  local hours="${2:-}"
  [[ -z "$key" || -z "$hours" ]] && { echo "Error: usage: share <s3-key> <hours>"; usage; }

  local seconds=$((hours * 3600))
  local url

  if url=$(aws s3 presign "s3://${BUCKET}/${key}" --expires-in "$seconds" --profile "$PROFILE"); then
    echo "Share link (expires in ${hours}h):"
    echo "$url"
    log_action "share" "${key} (expires ${hours}h)" "success"
  else
    log_action "share" "$key" "failed"
    echo "Share link generation failed."
    exit 1
  fi
}

# ---- Main dispatch ----
[[ $# -lt 1 ]] && usage

subcommand="$1"
shift

case "$subcommand" in
  upload)   cmd_upload "$@" ;;
  download) cmd_download "$@" ;;
  list)     cmd_list "$@" ;;
  delete)   cmd_delete "$@" ;;
  share)    cmd_share "$@" ;;
  *)        usage ;;
esac