# LedgerPoint Secure File Storage — Setup Guide

This is the Group 2 capstone project: a secure S3-based file storage and
sharing tool for LedgerPoint's auditors, using presigned URLs instead of
public buckets.

## What this does
- Stores client financial statements in a **private** S3 bucket (never public)
- Lets staff upload/download/list/delete files via a CLI tool
- Generates **time-limited share links** (presigned URLs) that external
  auditors can open with no AWS account or login
- Logs every action for audit purposes

## Prerequisites (each teammate needs their own)
1. An AWS account
2. AWS CLI v2 installed — https://awscli.amazonaws.com (Mac/Windows/Linux
   installers on the official page)
3. A bash-capable terminal: **Git Bash** (Windows), or the native terminal
   (Mac/Linux)
4. Your own AWS **admin** IAM user (not root) with an access key, used only
   to provision infrastructure

## One-time setup

1. Clone/copy this project folder, containing:
   - `deploy.sh` — provisions all AWS infrastructure
   - `filetool.sh` — the CLI tool for day-to-day file operations

2. Configure your admin AWS credentials:
```bash
   aws configure
```
   Enter your own admin access key, secret key, region, and output format.

3. **Pick a unique bucket name.** S3 bucket names are globally unique across
   *all* AWS accounts worldwide, so you cannot reuse `ledgerpoint-files-2026-jul`.
   Set your own via environment variables before deploying:
```bash
   export LEDGERPOINT_BUCKET="ledgerpoint-files-<yourname>-2026"
   export LEDGERPOINT_LOGS_BUCKET="ledgerpoint-logs-<yourname>-2026"
```

4. Make the scripts executable and deploy:
```bash
   chmod +x deploy.sh filetool.sh
   ./deploy.sh
```
   This provisions: a private, versioned, encrypted files bucket; a separate
   private logs bucket; and server access logging wired between them.

5. Create a least-privilege IAM user for day-to-day tool use (don't use your
   admin credentials for this):
   - AWS Console → IAM → Users → Create user → name it `ledgerpoint-tool`
   - Attach a policy scoped to `s3:PutObject`, `GetObject`, `DeleteObject`,
     and `ListBucket` on your specific bucket ARN only
   - Create an access key for this user

6. Configure a named profile for that tool user:
```bash
   aws configure --profile ledgerpoint-tool
```

## Daily use

All commands run through `filetool.sh`, which uses the `ledgerpoint-tool`
profile and your bucket by default (override with the env vars above if
your bucket name differs from the default in the script):

```bash
./filetool.sh upload <local-file>              # upload a file
./filetool.sh list                              # list files in the bucket
./filetool.sh download <s3-key> [dest-path]     # download a file
./filetool.sh share <s3-key> <hours>            # generate a time-limited link
./filetool.sh delete <s3-key>                   # delete (and revoke access to) a file
```

Every action is appended to `filetool-actions.log` in the project folder.

## Revoking a link early

Presigned URLs can't be individually cancelled once issued. To revoke
access before natural expiry (e.g. a link went to the wrong person), delete
the underlying file:
```bash
./filetool.sh delete <s3-key>
```
This invalidates the link immediately, even if it hasn't hit its expiry
time yet. The correct recipient will need a freshly generated link.

## Notes for the group
- Each teammate should use their **own** AWS account and bucket for local
  testing to avoid stepping on each other's data. Only the final demo/grading
  run needs to happen against one shared account/bucket, agreed on by the group.
- `deploy.sh` is idempotent — safe to re-run; it skips bucket creation if the
  bucket already exists and re-applies configuration.