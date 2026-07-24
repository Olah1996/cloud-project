# Phase 0: Design Worksheet — LedgerPoint Secure File Storage

## 2.1 Access mechanism decision

I'm using S3 presigned URLs rather than a public bucket or public object
ACLs. A presigned URL is a temporary, cryptographically signed link scoped
to one specific file — it lets an external auditor download it directly in
a browser with no AWS account or login required, satisfying the "no login"
requirement. Critically, the bucket itself stays fully private (Block
Public Access enabled) at all times, so nothing is discoverable by search
engines or guessable by URL — only someone holding the exact signed link,
before it expires, can access the file. This avoids the trap of making the
storage account/bucket public, which would expose every file indefinitely.

## 2.2 Expiry and revocation policy

By default, share links expire after 72 hours, which is enough time for an
auditor to receive and open a document without leaving old links live
indefinitely. If a client calls and says a document was sent to the wrong
auditor, revocation happens by deleting (or renaming) the specific object
in S3 — since presigned URLs derive their validity from the object existing
at that key, removing it immediately breaks the link for anyone who has it,
including the wrong recipient. The tradeoff is that the correct auditor
would also lose access and need a fresh link re-issued, but this is
preferable to leaving a sensitive financial document accessible for the
remainder of the 72-hour window.

## 2.3 Logging plan

| Action | What gets logged | Where it's stored | Who can read it |
|---|---|---|---|
| Upload | Timestamp, filename, uploading user | `ledgerpoint-logs-2026-jul` bucket (S3 access logs) | Office manager IAM user only |
| Download | Timestamp, filename, requester IP | `ledgerpoint-logs-2026-jul` bucket | Office manager IAM user only |
| Share link created | Timestamp, filename, expiry duration, user who generated it | `ledgerpoint-logs-2026-jul` bucket | Office manager IAM user only |
| Delete | Timestamp, filename, user who deleted it | `ledgerpoint-logs-2026-jul` bucket | Office manager IAM user only |