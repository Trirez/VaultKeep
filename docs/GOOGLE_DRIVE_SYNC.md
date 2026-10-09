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

## 🔄 Two Modes of Operation

### 1. Built-in Sandbox Simulation Mode (Default)
To allow testing immediately without setting up OAuth client IDs and cloud consoles:
- VaultKeep includes a local sandbox simulation engine.
- Simulates Google Drive cloud storage in `[Documents]/VaultKeep_GoogleDrive_Cloud/`.
- Fully tests the upload, timestamp comparisons, remote download, and 3-way KDBX merge conflicts.

### 2. Live Google Drive API v3 Mode
To sync with real Google Drive accounts:
1. Obtain an OAuth 2.0 Access Token with the `https://www.googleapis.com/auth/drive.file` scope.
2. Enter your account email and access token in the **Google Drive Sync** screen.
3. VaultKeep will query `https://www.googleapis.com/drive/v3/files` and manage multipart ciphertext uploads and updates.

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
