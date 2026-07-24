# Incident Report — LedgerPoint Secure File Storage

## Summary
During execution of `deploy.sh` (the automated end-to-end deployment script), the deployment failed partway through at step 7 of 8 while attempting to configure S3 server access logging.

## Symptom
Running `./deploy.sh` completed steps 1–6 successfully (files bucket created, public access blocked, versioning enabled, encryption enabled, logs bucket created, public access blocked on logs bucket), then failed at step 7 with the following error:

```
[7/8] Granting S3 log delivery permission on logs bucket...
aws: [ERROR]: An error occurred (ParamValidation): Error parsing parameter '--policy':
Unable to load paramfile file:///tmp/logging-policy.json:
[Errno 2] No such file or directory: '/tmp/logging-policy.json'
```

The script exited before applying the logging permission policy or enabling access logging on the files bucket, leaving the deployment incomplete — the storage and IAM layers were correctly provisioned, but the audit-logging pipeline was not yet active.

## Investigation Trail
1. Confirmed steps 1–6 had genuinely succeeded by checking bucket existence and config directly:
   `aws s3api get-public-access-block --bucket ledgerpoint-files-2026-jul` and `aws s3api get-bucket-versioning --bucket ledgerpoint-files-2026-jul` both returned expected values, ruling out a broader script or credentials failure.
2. Re-read the failing command: the script wrote a JSON policy file to `/tmp/logging-policy.json` using a bash heredoc, then referenced that same path in `--policy file:///tmp/logging-policy.json`.
3. Checked whether `/tmp` existed and was writable in the current shell (Git Bash on Windows):
   `ls -la /tmp` — the directory was accessible from Git Bash's own POSIX layer, but the native Windows-compiled `aws.exe` binary does not share Git Bash's `/tmp` mapping and could not resolve the path.
4. This ruled out an IAM permissions issue or a malformed JSON file — the failure was purely a path-resolution mismatch between the bash environment writing the file and the Windows AWS CLI binary reading it.

## Root Cause
The deployment script wrote temporary files to `/tmp`, a path that Git Bash resolves internally but that the native Windows AWS CLI executable cannot see, causing the CLI to report the file as missing even though it existed from the shell's point of view.

## Fix
Changed the script to write `logging-policy.json` and `logging-config.json` to the current working directory (`./`) instead of `/tmp`, and updated the corresponding `file://` references and cleanup step (`rm -f`) to match. This path is resolvable by both Git Bash and the native Windows AWS CLI, since it does not depend on a POSIX-only mount.

**Before (excerpt):**
```bash
cat > /tmp/logging-policy.json <<EOF
...
aws s3api put-bucket-policy --bucket "$LOGS_BUCKET" --policy file:///tmp/logging-policy.json
```

**After (excerpt):**
```bash
cat > ./logging-policy.json <<EOF
...
aws s3api put-bucket-policy --bucket "$LOGS_BUCKET" --policy file://./logging-policy.json
```

**Proof the fix works:** after applying the corrected paths, the policy and logging configuration were applied manually using the same commands with local paths, and both succeeded without error:
```
$ aws s3api put-bucket-policy --bucket ledgerpoint-logs-2026-jul --policy file://logging-policy.json
$ aws s3api put-bucket-logging --bucket ledgerpoint-files-2026-jul --bucket-logging-status file://logging-config.json
```
Both commands returned no error, and `aws s3api get-bucket-logging --bucket ledgerpoint-files-2026-jul` subsequently confirmed the `LoggingEnabled` configuration was active, targeting `ledgerpoint-logs-2026-jul`.

## Design Reflection
This failure was a build/tooling issue rather than an access-control design flaw — my Phase 0 decisions (presigned URLs, private buckets, separate logs bucket) were not implicated and did not make the failure more likely. However, the Phase 0 design did make the failure *easier to catch quickly*: because logging was planned as a distinct, separate step targeting an isolated logs bucket rather than being bundled into bucket creation, the deployment failed cleanly at a single, identifiable step rather than partially misconfiguring multiple resources at once, and the earlier steps (storage, encryption, versioning) remained verifiably correct and unaffected. If I were changing the design specifically to reduce this class of failure, I would have the deployment script validate its own environment (e.g., confirm `/tmp` or any temp path is actually resolvable by the AWS CLI binary in use) before attempting any AWS API calls that depend on it, rather than discovering a path mismatch mid-deployment.