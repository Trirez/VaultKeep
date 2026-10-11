# Zero-Knowledge Google Drive Cloud Sync

VaultKeep features a zero-knowledge cloud synchronization engine designed to sync your KDBX4 vault across desktop and mobile devices via **Google Drive API v3**.

---

## 🔐 Zero-Knowledge Security Model

1. **Pure Ciphertext Transmission**:
   - Google Drive only receives and stores the strongly encrypted `.kdbx` binary container (Argon2id + ChaCha20/AES256).
   - The master password, keyfiles, unencrypted entries, and passwords are never transmitted over the network or saved unencrypted in cloud memory.
2. **End-to-End Encryption**:
   - Even if Google Drive account credentials or cloud storage were compromised, an attacker would obtain only an encrypted KDBX4 container protected by high-workfactor Argon2id key derivation.

---

## 🔄 Modes of Operation (Current vs. Planned M6)

### 1. Local Cloud-Folder & Sandbox 3-Way Merge (Implemented — Zero Network Permissions)
VaultKeep currently operates with **zero network permissions** (`android.permission.INTERNET` is omitted):
- Users select a replica `.kdbx` file inside a locally synced Google Drive, OneDrive, or Dropbox folder (or use the built-in `[Documents]/VaultKeep_GoogleDrive_Cloud/` sandbox directory).
- `Vault::sync_with_file` (`merge_vault` in the Flutter bridge) performs an offline 3-way KDBX merge in Rust and atomically updates both the active vault and the replica file.

### 2. Direct Google Drive API v3 OAuth Adapter (Planned — Milestone M6 Only)
Direct HTTP/OAuth synchronization is intentionally **deferred to Milestone M6** (after local reliability and backup/restore verification in M0–M5; see `docs/NEXT_STEPS.md` and `.agents/skills/encrypted-cloud-sync/SKILL.md`):
1. Will use OAuth 2.0 with PKCE and least-privilege scope (`drive.file` or `appDataFolder`).
2. Will store tokens in OS-protected storage and enforce remote revision/ETag checks before replacing local files.

---

## 🔀 Conflict Resolution: Smart 3-Way KDBX Merge

When changes occur simultaneously on multiple devices (e.g. adding an entry on a phone while editing an entry on a desktop):
1. **Timestamp Detection**: VaultKeep detects that the cloud timestamp is newer than the local base version.
2. **Download & Stage**: Downloads the cloud `.kdbx` ciphertext into a secure temporary location.
3. **Rust KDBX 3-Way Merge**: Calls `Vault::merge_from_file`, which invokes KeePass's native 3-way merge logic:
   - Entries added on device A are retained.
   - Entries added on device B are merged in.
   - Modified entry timestamps determine the latest field values.
4. **Atomic Save & Re-upload**: The merged database is written locally via atomic swap and then re-uploaded to Google Drive to bring both ends into synchronized harmony.
5. **Sanitization**: The staged temporary file is wiped and deleted immediately.
