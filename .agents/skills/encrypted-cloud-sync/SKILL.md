---
name: encrypted-cloud-sync
description: Designs and implements encrypted vault backup and synchronization with Google Drive, OneDrive, or other user-owned cloud storage, including OAuth, revision checks, conflict handling, restore and offline behavior.
---

# Encrypted Cloud Sync

## Architecture
Cloud adapters are transport/storage only. The Rust core produces and validates encrypted vault envelopes. Provider APIs must never receive plaintext entries, master passwords, encryption keys or recovery keys.

## Workflow
1. Read the threat model and vault format.
2. Define provider-neutral interfaces before implementing provider-specific calls.
3. Review official current provider docs and select the narrowest appropriate OAuth scopes.
4. Decide whether to use an app-private folder or a user-visible file; document discoverability, deletion and permissions trade-offs.
5. Store OAuth tokens in platform-protected storage.
6. Implement upload/download, remote revision/ETag tracking, conditional writes where supported, retry and cancellation.
7. If the remote revision changed, preserve the remote/local versions and surface a conflict. Never silently overwrite.
8. Keep historical encrypted backups and verify a candidate restore before replacing the current vault.
9. Test offline edits, interrupted upload, partial download, expired/revoked tokens, quota errors, duplicate files, account disconnect and concurrent updates.

## Rules
- Encrypt before upload and validate after download.
- Never assume a successful upload means a restorable backup.
- Treat remote files and metadata as untrusted input.
- Do not put secrets in file names or cloud metadata.
- Do not request full-drive access if an app-folder or narrower permission meets requirements.
- Clearly distinguish backup from synchronization.
- Explain that users can delete cloud data and that a cloud provider can observe some metadata.
- Do not build a custom sync protocol that silently drops revisions.

## Acceptance criteria
- Mock provider can inspect requests and sees ciphertext only.
- Revision mismatch creates a recoverable conflict.
- Restore validates authentication before replacing the active vault.
- Token revocation and cloud errors fail safely.
