# VaultKeep Threat Model & Cryptographic Security Architecture

## 1. Executive Summary & Trust Boundaries
VaultKeep is a cross-platform, local-first password manager engineered with a pure-Rust cryptographic core (`vaultkeep-core`) and a lightweight Flutter presentation layer (`app/lib`). All vault parsing, key derivation, authenticated encryption, secret manipulation, and serialization execute strictly inside Rust.

```
+─────────────────────────────────────────────────────────────+
|                         USER DEVICE                         |
|                                                             |
|  +───────────────────────────────────────────────────────+  |
|  | Flutter Presentation Layer (Dart VM)                  |  |
|  | - Ephemeral UI state                                   |  |
|  | - Timed clipboard auto-clear (15s)                    |  |
|  | - Inactivity / Background auto-lock                    |  |
|  | - Android FLAG_SECURE / iOS Privacy Blur Overlay      |  |
|  +─────────────────────────┬─────────────────────────────+  |
|                            │ FFI Boundary                   |
|                            │ (Plain string errors,          |
|                            │  no secrets in list/details)   |
|  +─────────────────────────▼─────────────────────────────+  |
|  | Rust Bridge & Core (vaultkeep-core)                   |  |
|  | - Zeroizing<String> memory scrubbing                  |  |
|  | - Master password lifecycle                           |  |
|  | - Pure-Rust KDBX4 parser (keepass crate)              |  |
|  | - CSPRNG via rand::rngs::OsRng                        |  |
|  +─────────────────────────┬─────────────────────────────+  |
|                            │ Atomic File I/O                |
|                            │ (temp file, sync_all, rename)  |
|  +─────────────────────────▼─────────────────────────────+  |
|  | Encrypted Persistence (.kdbx)                         |  |
|  | - KDBX4 Envelope (Argon2id KDF, ChaCha20/AES-256)     |  |
|  | - Inner Protected XML Stream (Salsa20 / ChaCha20)     |  |
|  +───────────────────────────────────────────────────────+  |
+─────────────────────────────────────────────────────────────+
                             ▲
                             │ Passive replica synchronization
                             │ (User-owned local cloud folders)
+────────────────────────────▼────────────────────────────────+
| UNTRUSTED CLOUD / REPLICA STORAGE (Google Drive / OneDrive)  |
| - Sees encrypted .kdbx ciphertext only                      |
| - Zero network code or permissions in VaultKeep binary       |
| - Sync resolved via offline KDBX 3-way merge               |
+─────────────────────────────────────────────────────────────+
```

### Trust Boundary Details
1. **Dart UI <-> Rust FFI**: Dart strings are immutable and cannot be wiped from memory by user code. To mitigate memory residue, Dart models never retain passwords. Only explicit `revealPassword` returns a secret, and edit inputs are cleared immediately upon submission or dialog disposal.
2. **Rust Core <-> Filesystem**: The host filesystem is considered potentially hostile to partial writes and race conditions. All saves are atomic: written to `<vault>.kdbx.tmp`, flushed, synced to physical media (`sync_all`), and renamed. On any error, the temporary file is immediately unlinked.
3. **Application <-> Cloud Providers**: VaultKeep operates with **zero network permissions** (`android.permission.INTERNET` is omitted). Cloud synchronization occurs via local directory synchronization managed by the user's OS cloud client (e.g. Google Drive, OneDrive). Sync conflicts are resolved inside Rust via KDBX 3-way merge.

---

## 2. Cryptographic Design & Key Hierarchy

### Key Derivation Function (KDF)
- **Algorithm**: Argon2id (RFC 9106)
- **Parameters**: Default KDBX4 Argon2id parameters enforcing high memory and iteration bounds designed to resist GPU/ASIC parallelized dictionary cracking.
- **Master Password**: Ingested directly into `zeroize::Zeroizing<String>`, preventing retention in deallocated memory.

### Master Key Hierarchy
```
User Master Password
        │
        ▼
   [Argon2id KDF] ─── (Header Salt + Parameters)
        │
        ▼
  Master Seed / Composite Key
        │
        ▼
 [HMAC-SHA256 Transform]
        │
        ▼
  Master Encryption Key & Header HMAC Key
        │
        ├─ Encrypts KDBX4 Body (ChaCha20 or AES-256-CBC with HMAC-SHA256)
        └─ Encrypts Inner XML Random Stream (ChaCha20 / Salsa20 for protected fields)
```

### Authenticated Encryption & Integrity
- **Envelope Format**: KDBX version 4.
- **Cipher**: Standard authenticated encryption or cipher-with-HMAC (ChaCha20-Poly1305 or AES-256-CBC with Encrypt-then-MAC via HMAC-SHA256).
- **Tamper Resistance**: Any single-bit modification to header or ciphertext triggers an immediate authentication rejection during `Database::open`. No partial plaintext is ever returned.

---

## 3. Data-Flow & Threat Matrix

| Threat / Adversary | Attack Vector | Security Control | Severity / Impact |
|---|---|---|---|
| **Stolen / Lost Device** | Extraction of `.kdbx` file from storage | AES-256 / ChaCha20 encryption with Argon2id KDF | Mitigated; offline attacks require breaking master password |
| **Android Auto Backup** | App data extracted via Google Drive backup or `adb backup` | `android:allowBackup="false"` declared in `AndroidManifest.xml` | Prevented; app directory excluded from OS backups |
| **App-Switcher Snooping** | OS snapshotting app preview when task-switched | Android `FLAG_SECURE`, iOS `UIBlurEffect` on `sceneWillResignActive` | Prevented; app switcher displays blurred/black screen |
| **Memory Scraping (Heap)** | Scanning RAM for unencrypted secrets | `Zeroizing<String>` in Rust; prompt controller clearing in Flutter | Mitigated; secret lifespans minimized |
| **Malicious Keyboard App** | Predictive text indexing passwords / TOTP seeds | `autocorrect: false` & `enableSuggestions: false` on secret fields | Prevented; keyboards cannot learn credentials |
| **Cloud Provider Snooping** | Google Drive / OneDrive reading synced vault | Zero network access; cloud sees only encrypted `.kdbx` file | Prevented; cloud provider has zero plaintext access |
| **Concurrent Edit Loss** | Saving conflicting changes on two devices | KDBX 3-way merge (`Vault::merge_from_file`) | Prevented; entry history and additions merged cleanly |
| **Logging / Panic Leaks** | Secrets output in logs, debug consoles, or panics | Redacted manual `fmt::Debug` implementations across all structs | Prevented; secrets rendered as `[REDACTED]` |
| **Autofill Phishing / Spoofing** | Phishing site querying credentials for target domain | Strict hostname & subdomain validation (`clean_domain_or_host`, `matches_host`) | Prevented; prefix and arbitrary substring matches rejected |
| **Symlink / TOCTOU Overwrite** | Pre-creating predictable `.kdbx.tmp` file | `tempfile::Builder` with random suffix, `O_EXCL`, and 0600 permissions | Prevented; symlinks rejected and permissions restricted |

---

## 4. Platform Storage & Autofill Notes
- **Desktop (Windows/Linux/macOS)**: Vault files are saved to user-selected locations. No plaintext temporary files or cache directories are created. Atomic commits utilize randomized `tempfile::Builder` instances with strict file permissions (`0600` on Unix).
- **Android**: `FLAG_SECURE` prevents screenshots, screen recording, and task switcher snapshots. `android:allowBackup="false"` stops ADB and cloud backup leakage.
- **iOS**: Privacy blur overlay intercepts `sceneWillResignActive` to safeguard task previews.
- **Autofill**: VaultKeep implements a secure domain query algorithm (`Vault::find_for_domain`) that parses and cleans domains, matching only exact hostnames or registered subdomains. In mobile platforms, full autofill services run out-of-process via dedicated native plugins querying the Rust core.
- **Clipboard Protection**: Clipboard entries auto-wipe after 15 seconds, and are wiped immediately upon lock ONLY if the clipboard still contains the actively copied secret. Unrelated clipboard contents are never destroyed.

---

## 5. Security Testing Matrix

| Test Suite | Command | Coverage |
|---|---|---|
| **Memory Zeroization** | `cargo test session` | Dropping `Vault` drops `Session`; failed unlocks leave session locked |
| **Crypto & File Tampering** | `cargo test vault` | Wrong password rejection; empty master password rejection; unencrypted disk inspection (`no_plaintext_secrets_on_disk`) |
| **TOTP Generation** | `cargo test totp` | RFC 6238 token generation, expiration timing, secret wiping |
| **3-Way Merge** | `cargo test merge` | Concurrent edits on two independent replicas successfully merged |
| **Static Code Quality** | `cargo clippy --all-targets -- -D warnings` | 0 warnings across all crates |
| **Flutter UI & Lifecycle** | `flutter test` | Auto-lock on idle, auto-lock on app pause/inactive, clipboard clearing, group filtering |

---

## 6. Vulnerability Disclosure & Incident Response

### Reporting
Security researchers discovering vulnerabilities should submit findings privately to the project maintainers with reproducible steps and proof-of-concept details.

### Remediation Protocol
1. **Triage (24h)**: Classify severity (Critical, High, Medium, Low) and determine if existing vaults or stored secrets are compromised.
2. **Containment (48h)**: Develop patches in private branches; verify with negative test cases and regression suites.
3. **Disclosure & Release**: Release patched binaries alongside an updated `docs/SECURITY_AUDIT_LOG.md` entry. Never publish exploit payloads.
