# VaultKeep Security Audit & Remediation Log

This document records all security audits, vulnerability findings, architectural defects, and applied remediations. It serves as an immutable reference to prevent security regressions.

---

## 🛡️ Security Audit Ledger

### SEC-001: Plaintext Secret Exposure via `#[derive(Debug)]` on `EntryInput`
- **Date**: 2026-10-09
- **Severity**: **HIGH**
- **Component**: `crates/core/src/vault.rs`
- **Vulnerability**: `EntryInput` derived Rust's default `Debug` macro while holding `pub password: Zeroizing<String>`. `Zeroizing<T>` delegates `fmt::Debug` directly to `T::fmt`, causing `println!("{:?}", input)`, log formatting, panic messages, or assertions to leak the plaintext password into logs or console streams.
- **Rule Violated**: `.agent/skills/security-review/SKILL.md` (*"No `#[derive(Debug)]` on a type holding a secret unless the field is redacted"*).
- **Remediation**:
  - Removed `#[derive(Debug)]` from `EntryInput`.
  - Implemented manual `std::fmt::Debug` with `password` explicitly set to `"[REDACTED]"`.
- **Verification**: `cargo clippy --all-targets -- -D warnings` and `cargo test` pass.

---

### SEC-002: Dangling Temporary File on Atomic Save Failure
- **Date**: 2026-10-09
- **Severity**: **HIGH**
- **Component**: `crates/core/src/vault.rs`
- **Vulnerability**: In `Vault::save`, if database serialization, buffer flushing, file syncing, or atomic renaming encountered an error, the function returned early via `?`, abandoning a partially written `.kdbx.tmp` file on disk.
- **Rule Violated**: `.agent/skills/security-review/SKILL.md` (*"Temp files are created in the vault's own directory and renamed, never left behind on error"*).
- **Remediation**: Wrapped the file creation, serialization, flush, sync, and rename pipeline. If any stage errors out, `std::fs::remove_file(&tmp)` is automatically executed before returning `Err`.
- **Verification**: Tested in `crates/core/tests/vault.rs` (`no_plaintext_secrets_on_disk`).

---

### SEC-003: Mobile App Switcher Snapshot Exposure
- **Date**: 2026-10-09
- **Severity**: **HIGH**
- **Component**: `app/lib/app.dart`
- **Vulnerability**: `didChangeAppLifecycleState` only locked the vault on `AppLifecycleState.paused`. On iOS and Android, swiping into the multitasking / recent apps view triggers `AppLifecycleState.inactive` *prior* to `paused`. During `inactive`, the OS takes a snapshot for the app switcher, exposing unlocked vault items and open credentials.
- **Rule Violated**: `.agent/skills/mobile-integration/SKILL.md` (*"iOS: cover the window with a blank view when the app becomes inactive so the app switcher shows no secrets"*).
- **Remediation**: Updated `didChangeAppLifecycleState` to trigger `controller.lock()` on `AppLifecycleState.inactive` and `hidden` for mobile devices (`TargetPlatform.iOS` and `TargetPlatform.android`).
- **Verification**: Verified via `dart analyze` on `app.dart`.

---

### SEC-004: Clipboard Secret Retention After Vault Lock
- **Date**: 2026-10-09
- **Severity**: **HIGH**
- **Component**: `app/lib/clipboard_guard.dart` & `app/lib/app.dart`
- **Vulnerability**: When a user copied a password and immediately locked the vault or allowed the idle timer to expire, the copied password remained in the system clipboard for the remainder of the 15-second timer.
- **Rule Violated**: `.agent/skills/security-review/SKILL.md` (*"Copied passwords are cleared after a timeout only if the clipboard still holds our value"*).
- **Remediation**: Added `ClipboardGuard.clearNow()` and integrated it into `_closeRoutesWhenLocked()` in `app.dart` so that the system clipboard is cleared the moment the vault transitions to the locked state.
- **Verification**: Verified via `dart analyze`.

---

### SEC-005: Unzeroized Master Passwords in CLI Frontend
- **Date**: 2026-10-09
- **Severity**: **MEDIUM**
- **Component**: `crates/cli/src/main.rs` & `crates/cli/Cargo.toml`
- **Vulnerability**: `rpassword::prompt_password` returned a standard heap `String`. Master passwords entered during `vaultkeep init` and `vaultkeep <path> ...` remained unzeroized in heap memory upon command exit or panic.
- **Rule Violated**: `.agent/rules/project.md` (*"Never log, print or serialize secrets. Use Zeroizing in Rust"*).
- **Remediation**: Added `zeroize` dependency to `crates/cli/Cargo.toml` and wrapped `pw` and `again` variables in `zeroize::Zeroizing::new(...)`.
- **Verification**: `cargo test -p vaultkeep-cli` builds and runs cleanly.

---

### SEC-006: Silent "Create" vs "Unlock" Mode Confusion
- **Date**: 2026-10-09
- **Severity**: **MEDIUM (Data Loss Prevention)**
- **Component**: `app/lib/screens/unlock_screen.dart`
- **Vulnerability**: `bool get _creating => !File(_path.text.trim()).existsSync();` automatically toggled the UI into database creation mode whenever a file did not exist. If a user entered a typo in their vault file path, the app silently switched to "Create vault" mode, leading users to believe their vault was wiped.
- **Remediation**:
  - Added an explicit `SegmentedButton<bool>` mode selector (`[ Unlock | Create ]`).
  - Added strict validation: in Unlock mode, an error is raised if the file does not exist; in Create mode, an error is raised if a file already exists at that path.
- **Verification**: Verified via `dart analyze`.

---

### SEC-007: Lingering Master Password in TextEditingControllers
- **Date**: 2026-10-09
- **Severity**: **LOW**
- **Component**: `app/lib/screens/unlock_screen.dart`
- **Vulnerability**: Master passwords entered into `_master` and `_confirm` controllers remained inside controller state even after successful unlock.
- **Remediation**: Added explicit `.clear()` calls on `_master` and `_confirm` immediately upon successful unlock or creation, and reset `.text = ''` in `dispose()`.
- **Verification**: Verified via `dart analyze`.

---

### SEC-008: Double Route Pop & Silent Empty Password Creation
- **Date**: 2026-10-09
- **Severity**: **LOW**
- **Component**: `app/lib/screens/entry_screen.dart`
- **Vulnerability**:
  - `Navigator.of(context).pop()` was called unconditionally after save/delete. If auto-lock fired while awaiting backend I/O, `_closeRoutesWhenLocked()` had already popped the route, causing an unwanted double pop out of the application.
  - The entry creation form lacked password validation, allowing users to accidentally save entries with empty passwords.
- **Remediation**:
  - Guarded navigation pops with `if (mounted && Navigator.of(context).canPop())`.
  - Added an explicit confirmation modal if the user attempts to save an entry with an empty password.
- **Verification**: Verified via `dart analyze`.

---

### SEC-009: EntryData Debug Redaction at Rust/Flutter FFI Boundary
- **Date**: 2026-10-09
- **Severity**: **HIGH**
- **Component**: `app/rust/src/api/vault.rs`
- **Vulnerability**: `EntryData` carries `pub password: String` across the bridge when an entry is created or updated. Deriving `Debug` on this struct would permit logging or print statements in Flutter/Rust bridge internals to leak passwords.
- **Rule Violated**: `.agent/skills/security-review/SKILL.md` (*"A struct holding a password must not derive Debug"*).
- **Remediation**: Explicitly omitted `#[derive(Debug)]` on `EntryData`. Password field is immediately wrapped in `Zeroizing<String>` upon ingestion into `save_entry()`.
- **Verification**: `cargo test --workspace` and `cargo clippy --workspace --all-targets -- -D warnings` pass.

---

### SEC-010: Ephemeral TOTP Tokens & Secret URI Isolation
- **Date**: 2026-10-09
- **Severity**: **MEDIUM**
- **Component**: `crates/core/src/vault.rs` & `app/lib/screens/entry_screen.dart`
- **Vulnerability**: RFC 6238 TOTP shared secret keys are persistent high-value credentials. Displaying TOTP seeds in list summaries or storing unencrypted temporary codes increases memory attack surface.
- **Remediation**:
  - `EntrySummary` and `VaultItem` never carry OTP URIs or generated codes.
  - Codes are computed on-demand via `Vault::totp()` returning ephemeral 6-digit tokens with dynamic second countdowns.
  - TOTP code copying enforces the 15-second timed clipboard wiper.
- **Verification**: Verified in `tests/vault.rs` (`totp_generation_and_storage`) and `vault_controller_test.dart`.

---

### SEC-011: Binary Attachment In-Memory Encryption & Atomic Disk Writes
- **Date**: 2026-10-09
- **Severity**: **MEDIUM**
- **Component**: `crates/core/src/vault.rs` & `app/lib/screens/entry_screen.dart`
- **Vulnerability**: Insecure attachment handlers frequently write unencrypted temporary files to `/tmp` or system temp directories for thumbnail generation or inspection, leaving residual secrets.
- **Remediation**:
  - Attachments are stored directly in KDBX4 protected attachment pools.
  - Adding or removing attachments triggers atomic temporary file saves with instant cleanup on failure (`fs::remove_file(&tmp)`).
  - No plaintext files are written to disk during listing, reading, or metadata queries.
- **Verification**: Tested in `tests/vault.rs` (`attachments_crud`) and `vault_controller_test.dart`.

---

### SEC-012: Safe Cloud Synchronization via KDBX 3-Way Merge
- **Date**: 2026-10-09
- **Severity**: **HIGH (Integrity & Data Loss Prevention)**
- **Component**: `crates/core/src/vault.rs` & `app/lib/screens/vault_screen.dart`
- **Vulnerability**: Naive file-sync (overwriting whole `.kdbx` files on cloud providers like Google Drive or OneDrive) causes silent data loss when simultaneous edits occur on multiple devices. Direct socket syncing introduces network attack surface.
- **Remediation**:
  - Implemented 3-way KDBX merge (`Database::merge`) without granting network permissions or embedding third-party cloud SDK binaries.
  - Merge executes between local vault and a user-selected cloud replica with atomic disk commit.
- **Verification**: Tested in `tests/vault.rs` (`merge_from_file_3way`) and `vault_controller_test.dart`.

---

### SEC-013: Opt-In Biometrics with Explicit Security Advisory
- **Date**: 2026-10-09
- **Severity**: **MEDIUM**
- **Component**: `app/lib/screens/unlock_screen.dart`
- **Vulnerability**: Unrestricted biometric unlocks allow unauthorized access if secondary biometric profiles (e.g. spouse or child fingerprint) are enrolled on the device.
- **Rule Violated**: `.agent/skills/mobile-integration/SKILL.md` (*"Biometrics only confirm the user is present. They do not replace the master password for the first unlock... Tell the user plainly that this trades some security for convenience."*).
- **Remediation**:
  - Biometric authentication is strictly opt-in and does not bypass master password requirement on initial creation or after reboot.
  - Added an explicit in-app security advisory informing users that biometrics trade security for convenience.
- **Verification**: Verified in `app/lib/screens/unlock_screen.dart`.

---

### SEC-014: Plaintext TOTP Secret Key Exposure via Derived `Debug`
- **Date**: 2026-10-09
- **Severity**: **HIGH**
- **Component**: `crates/core/src/vault.rs` & `app/rust/src/api/vault.rs`
- **Vulnerability**: `EntryDetails`, `TotpToken`, and `TotpItem` derived `Debug` directly while holding `otp_uri` (which contains HMAC-SHA1/SHA256 secret keys) or current 6-digit TOTP tokens. Logging these structs or formatting them in error messages leaked 2FA credentials in plaintext.
- **Rule Violated**: `.agent/skills/security-review/SKILL.md` (*"No `#[derive(Debug)]` on a type holding a secret"*).
- **Remediation**: Removed default `Debug` derives and implemented manual `std::fmt::Debug` with `otp_uri` and `code` explicitly redacted (`"[REDACTED]"`).
- **Verification**: Verified via `cargo clippy --all-targets -- -D warnings` and `cargo test`.

---

### SEC-015: Unzeroized TOTP Seed and Replica Master Passwords in Memory
- **Date**: 2026-10-09
- **Severity**: **HIGH**
- **Component**: `crates/core/src/vault.rs` & `app/rust/src/api/vault.rs`
- **Vulnerability**:
  - `EntryInput.otp` stored secrets in a plain `Option<String>`, leaving TOTP seed strings lingering on the heap after entries were saved.
  - In `app/rust/src/api/vault.rs`, `merge_vault` accepted `other_master: String` without wrapping it in `Zeroizing`, leaving the master password of replica vaults in heap memory.
- **Rule Violated**: `.agent/skills/security-review/SKILL.md` (*"Master password and entry passwords use Zeroizing<String>"*).
- **Remediation**:
  - Changed `EntryInput.otp` to `Option<Zeroizing<String>>`.
  - Wrapped `other_master` in `Zeroizing::new(other_master)` in `merge_vault()`.
- **Verification**: Verified via `cargo test` and `cargo clippy`.

---

### SEC-016: Cleartext TOTP URI in UI Input and Predictive Keyboard Leakage
- **Date**: 2026-10-09
- **Severity**: **MEDIUM**
- **Component**: `app/lib/screens/entry_screen.dart`
- **Vulnerability**: The TOTP URI field was unmasked in the entry screen without `obscureText`, exposing the base32 secret to shoulder surfing. Furthermore, `enableSuggestions` was not disabled, allowing mobile OS keyboards to index the 2FA secret into predictive dictionary suggestions.
- **Rule Violated**: `.agent/skills/security-review/SKILL.md` (*"Password fields are masked by default, with suggestions and autocorrect off"*).
- **Remediation**: Added `obscureText: !_showOtp`, a visibility toggle, `enableSuggestions: false`, `autocorrect: false`, and guaranteed controller wiping (`_otpUri.text = ''`) on `dispose()`.
- **Verification**: Verified via `flutter analyze`.

---

### SEC-017: Silent Group Update Loss on Entry Edits
- **Date**: 2026-10-09
- **Severity**: **MEDIUM (Data Integrity)**
- **Component**: `crates/core/src/vault.rs`
- **Vulnerability**: In `Vault::update`, `input.group_id` was ignored. If a user edited an entry to move it to a different group, the change was silently dropped.
- **Remediation**: Updated `Vault::update` to inspect `input.group_id`, resolve `target_group_id`, and invoke `entry.move_to(target_group_id)` if the group changed.
- **Verification**: Added unit test in `crates/core/tests/vault.rs` (`groups_and_hierarchy`).

---

### SEC-018: In-Memory Leakage of Replica Master Passwords in Dialog Controllers
- **Date**: 2026-10-09
- **Severity**: **MEDIUM**
- **Component**: `app/lib/screens/vault_screen.dart`
- **Vulnerability**: `_syncVault` instantiated `passCtrl` for the replica master password without calling `dispose()` or clearing its buffer, causing the password to persist indefinitely in memory.
- **Remediation**: Wrapped dialog execution in `try ... finally`, explicitly wiping `passCtrl.text = ''` and disposing all controllers (`passCtrl`, `pathCtrl`, `nameCtrl`, `queryCtrl`).
- **Verification**: Verified via `flutter analyze`.

---

### SEC-019: Inadvertent Group Filter Blanking Due to ID/Name Mismatch
- **Date**: 2026-10-09
- **Severity**: **LOW (Functional Bug)**
- **Component**: `app/lib/screens/vault_screen.dart`
- **Vulnerability**: Group filter chips set `selectedGroupId` (a UUID), but `build()` filtered via `i.groupName == selectedGroupId`. Because `groupName` contains the human-readable group name (e.g. "Work"), selecting any group resulted in an empty list.
- **Remediation**: Resolved `selectedGroupName` from `selectedGroupId` in `controller.groups` and matched against both `groupName` and `groupId`.
- **Verification**: Verified via `flutter analyze` and `flutter test`.

---

### SEC-020: Android Auto Backup Exposure
- **Date**: 2026-10-09
- **Severity**: **HIGH**
- **Component**: `app/android/app/src/main/AndroidManifest.xml`
- **Vulnerability**: `android:allowBackup` was omitted from `<application>`, defaulting to `true`. This permitted Android Cloud Backup and `adb backup` to capture local application data, preferences, and cached state.
- **Rule Violated**: `.agent/skills/security-review/SKILL.md` (*"Decide android:allowBackup deliberately; the vault file is encrypted but other app data should not be backed up"*).
- **Remediation**: Explicitly declared `android:allowBackup="false"` in `AndroidManifest.xml`.
- **Verification**: Verified in `AndroidManifest.xml`.

---

### SEC-021: Missing Android & iOS Screen & Task-Switcher Privacy Protection
- **Date**: 2026-10-09
- **Severity**: **HIGH**
- **Component**: `app/android/app/src/main/kotlin/.../MainActivity.kt` & `app/ios/Runner/SceneDelegate.swift`
- **Vulnerability**:
  - Android activity lacked `FLAG_SECURE`, allowing device screenshots, screen recorders, and the task switcher to capture decrypted credentials.
  - iOS scene delegate lacked a privacy overlay on `sceneWillResignActive`, allowing the iOS app switcher snapshot to reveal vault entries.
- **Rule Violated**: `.agent/skills/mobile-integration/SKILL.md` (*"Screen and app-switcher protection: Android set FLAG_SECURE on the activity; iOS cover the window with a blank view when the app becomes inactive"*).
- **Remediation**:
  - Configured `window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)` in Android `MainActivity.kt`.
  - Added dynamic `UIBlurEffect` privacy overlay in iOS `SceneDelegate.swift` on `sceneWillResignActive` and removed on `sceneDidBecomeActive`.
- **Verification**: Verified in `MainActivity.kt` and `SceneDelegate.swift`.

---

### SEC-022: Unbounded Input File and Attachment Size Limits (Resource Exhaustion / DoS Prevention)
- **Date**: 2026-10-09
- **Severity**: **MEDIUM (Denial of Service / Memory Exhaustion)**
- **Component**: `crates/core/src/vault.rs`, `crates/core/src/error.rs`, `crates/core/src/lib.rs`
- **Vulnerability**: `Vault::open` and `Vault::add_attachment` lacked explicit size boundaries. An adversary could supply oversized vault envelopes (e.g. multi-gigabyte files or malicious sync targets) or arbitrarily large attachment blobs, triggering excessive heap allocations, process starvation, or out-of-memory crashes on memory-constrained mobile platforms.
- **Rule Violated**: `.agents/skills/rust-vault-security/SKILL.md` (*"Parse untrusted input with strict bounds before large allocations. Fail closed on wrong passwords, authentication failures, malformed files and unknown critical versions"*).
- **Remediation**:
  - Enforced `MAX_VAULT_BYTES` (100 MB) with immediate early rejection before envelope parsing.
  - Enforced 0-byte / empty file validation returning `VaultError::Malformed("vault file is empty")`.
  - Enforced `MAX_ATTACHMENT_BYTES` (25 MB) and non-empty attachment names in `Vault::add_attachment`.
  - Added structured error variants: `VaultError::FileTooLarge(u64, u64)`, `VaultError::AttachmentTooLarge(usize, usize)`, and `VaultError::Malformed(&'static str)`.
  - Implemented manual `fmt::Debug` for `Vault` struct redacting `master` (`"[REDACTED]"`).
- **Verification**: Verified in `crates/core/tests/security.rs` (`input_bounds_enforce_file_and_attachment_limits`).

---

### SEC-023: Missing Negative Cryptographic Tests, Invariant Property Tests & Dependencies
- **Date**: 2026-10-09
- **Severity**: **HIGH (Assurance & Tamper Hardening)**
- **Component**: `Cargo.toml`, `crates/core/Cargo.toml`, `crates/core/tests/security.rs`
- **Vulnerability**: Workspace lacked dependencies and integration tests required by `rust-vault-security`:
  1. Bit-flipped ciphertext failing authentication.
  2. Truncated envelope safety.
  3. Header corruption and unknown/unsupported version fail-closed without downgrade.
  4. Redaction assurance in debug and error strings.
  5. Property-based invariant testing and parser fuzzing for arbitrary inputs.
- **Rule Violated**: `.agents/skills/rust-vault-security/SKILL.md` (*"Required tests: Bit-flipped ciphertext fails authentication. Truncated, oversized and malformed envelopes fail safely. Unknown algorithm/version fails without downgrade. Serialization property tests and parser fuzzing. Ensure error/log output contains no secrets."*).
- **Remediation**:
  - Promoted `uuid` to workspace dependency and added `proptest = "1.6"` to root `Cargo.toml` and `crates/core/Cargo.toml`.
  - Built comprehensive `crates/core/tests/security.rs` covering:
    - Single-bit flips across header, payload blocks, and HMAC authentication fields.
    - Truncated envelopes at critical boundary lengths.
    - Malformed magic bytes (`0x9AA2D903`, `0xB54BFB67`) and invalid/legacy versions.
    - Debug formatting redaction across `EntryInput`, `EntryDetails`, `TotpToken`, `Vault`, and `VaultError`.
    - `proptest` generator policy invariant fuzzing and random byte envelope parsing safety.
- **Verification**: `cargo test --workspace` (22 passed), `cargo clippy --workspace --all-targets -- -D warnings`, `cargo fmt --all -- --check`.

---

### SEC-016: Cloud Sync Hardening, Root Incompatibility Panic Fix & Bidirectional Sync Guarantee
- **Date**: 2026-10-09
- **Severity**: **HIGH (Denial of Service & Data Divergence)**
- **Component**: `crates/core/src/error.rs`, `crates/core/src/vault.rs`, `app/rust/src/session.rs`, `app/lib/screens/vault_screen.dart`, `app/lib/screens/file_picker_dialog.dart`
- **Vulnerabilities Discovered & Remediated**:
  1. **Root Group Incompatibility Denial of Service (Panic in `keepass-0.15.0`)**: Merging two independently created `.kdbx` databases with different root group UUIDs caused an unhandled panic inside `keepass::db::merge::merge.rs` (`cannot re-add root`). In release mode (`panic = "abort"`), this would immediately crash the app. Fixed by pre-validating matching root UUIDs before invoking `db.merge()`, returning `VaultError::IncompatibleVaultRoots`.
  2. **Self-Merge Re-entrancy / Corruption Hazard**: Merging the active vault file with itself bypassed checks, triggering redundant serialization and file replacement. Remediated with `is_same_path` canonical path checks and `VaultError::SelfMerge`.
  3. **One-Way Sync Stale Replica Data Loss**: Previous `merge_from_file` only persisted updates to the local database, leaving the replica / cloud file untouched. As a result, subsequent syncs or devices relying on the cloud file never received local updates. Implemented `sync_with_file` to atomically commit the unified merged database to both local and replica targets.
  4. **Authentication Ergonomics & Memory Leaks**: When syncing replicas sharing the same master password, leaving the replica password blank previously triggered an authentication error. Now seamlessly falls back to `self.master`.
  5. **Empty Path Validation & Cloud Directory Discovery**: UI now validates replica path existence and provides multi-candidate discovery on Windows/Linux/macOS for OneDrive, Google Drive, and Documents, plus a one-click Cloud Sandbox simulation folder (`[Documents]/VaultKeep_GoogleDrive_Cloud`).
- **Rule Violated**: `.agents/skills/encrypted-cloud-sync/SKILL.md` (*"Do not build a custom sync protocol that silently drops revisions. Token revocation and cloud errors fail safely."*).
- **Verification**: Verified with 6 targeted tests in `crates/core/tests/vault.rs` (17 total passed), `app/test/vault_controller_test.dart` (9 passed), and `cargo clippy --all-targets -- -D warnings`.

---

### SEC-024: Critical Autofill Credential Phishing & Domain Spoofing Vulnerability
- **Date**: 2026-10-09
- **Severity**: **CRITICAL (Credential Exposure & Phishing)**
- **Component**: `crates/core/src/vault.rs` (`Vault::find_for_domain`)
- **Vulnerability**: `find_for_domain` previously performed loose substring matching:
  `url_lower.contains(&target) || target.contains(&e.title.to_lowercase())`.
  An attacker controlling a phishing domain (e.g. `evil-google.com` or `google.com.attacker.site` or `phishing.site/oauth?redirect=google.com`) would match real credentials stored for `google.com` or entries with title `"Google"`, causing the app or autofill helper to automatically expose passwords to the attacker.
- **Rule Violated**: `.agents/skills/rust-vault-security/SKILL.md` (*"Parse untrusted input with strict bounds. Never leak secrets across boundaries"*).
- **Remediation**:
  - Implemented strict host extraction (`clean_domain_or_host`) stripping schemes, paths, query parameters, userinfo, and ports.
  - Implemented strict host and subdomain validation (`matches_host`), ensuring that only exact hostnames or legitimate subdomains (`.target_host`) can match. Substring prefixes (e.g., `evil-google.com`) are strictly rejected.
  - Replaced arbitrary title substring matching with tokenized word boundary checks only for non-domain queries (no dots), preventing phishing domains from matching generic titles.
  - Added negative test suite in `crates/core/tests/vault.rs` verifying that spoofed domains and phishing URLs are rejected.
- **Verification**: `cargo test vault::domain_autofill_query` passed with 5 negative phishing assertions.

---

### SEC-025: Insecure Predictable Temporary File Path & Permissions on Atomic Save
- **Date**: 2026-10-09
- **Severity**: **HIGH (Local Privilege Escalation & TOCTOU)**
- **Component**: `crates/core/src/vault.rs` (`Vault::save_to`)
- **Vulnerability**: `save_to` used `dest.with_extension("kdbx.tmp")`. This static, predictable filename allowed local adversaries on shared filesystems to pre-create symlinks pointing to sensitive files, causing `File::create` to truncate and overwrite them. Furthermore, standard `File::create` created files with default umask (`0644`), making the database world-readable on POSIX/Android systems.
- **Rule Violated**: `.agent/skills/security-review/SKILL.md` (*"Temp files are created in the vault's own directory and renamed, never left behind on error"*).
- **Remediation**:
  - Replaced manual temporary path with `tempfile::Builder::new().prefix(".vaultkeep_tmp_").suffix(".kdbx").tempfile_in(parent)`.
  - Enforced cryptographically random temporary filenames created with `O_CREAT | O_EXCL` and mode `0600` on Unix systems.
  - Utilized atomic `tmp_file.persist(dest)` which replaces the destination file safely and unlinks temporary files automatically if serialization fails.
- **Verification**: Verified via `cargo test --workspace` (28 passed).

---

### SEC-026: Blind Destruction of User System Clipboard upon Vault Lock
- **Date**: 2026-10-09
- **Severity**: **HIGH (Data Destruction / Unintended Side-Effects)**
- **Component**: `app/lib/clipboard_guard.dart` & `app/lib/app.dart`
- **Vulnerability**: `ClipboardGuard.clearNow()` called `Clipboard.setData(const ClipboardData(text: ''))` unconditionally whenever the vault locked. When auto-lock fired after 2 minutes of idle time or when the user minimized the app, any data the user had placed on their system clipboard from other applications was destroyed, even if no secret was ever copied in VaultKeep.
- **Rule Violated**: `.agent/skills/security-review/SKILL.md` (*"Copied passwords are cleared after a timeout only if the clipboard still holds our value"*).
- **Remediation**:
  - Added `_activeSecret` tracking in `ClipboardGuard`.
  - Updated both `Timer` expiration and `clearNow()` to inspect `Clipboard.getData()` and only overwrite the clipboard if the current clipboard text matches the tracked active secret.
  - Reset `_activeSecret = null` once cleared so secrets do not linger in static state.
- **Verification**: Verified in `app/lib/clipboard_guard.dart`.

---

### SEC-027: Flutter Rust Bridge Codegen Bindings & Native Assets Integration
- **Date**: 2026-10-09 (Updated 2026-10-10)
- **Severity**: **CRITICAL RELEASE BLOCKER (RESOLVED)**
- **Component**: `app/lib/src/rust/api/vault.dart`, `app/rust/src/frb_generated.rs`, `app/pubspec.yaml`
- **Vulnerability / Blocker**:
  - Previously, `app/lib/src/rust/api/vault.dart` contained placeholder functions that threw `UnimplementedError('Generated by flutter_rust_bridge')` and `app/pubspec.yaml` lacked `flutter_rust_bridge: 2.13.0`.
- **Remediation**:
  1. Configured `flutter_rust_bridge: 2.13.0` and `flutter_rust_bridge_hooks: 2.13.0` in `app/pubspec.yaml` alongside `app/hook/build.dart`.
  2. Generated complete FFI bindings in `app/lib/src/rust/` and `app/rust/src/frb_generated.rs` via `flutter_rust_bridge_codegen 2.13.0`.
- **Verification**: Verified via `cargo test --workspace`, `flutter analyze`, and `flutter test`.

---

### SEC-028: Release Blocker / Security Advisory — Biometric Authentication UI Stub
- **Date**: 2026-10-09
- **Severity**: **MEDIUM RELEASE BLOCKER (Functional Completeness & Cryptographic Binding)**
- **Component**: `app/lib/screens/unlock_screen.dart` (`_authenticateBiometric`)
- **Vulnerability / Blocker**:
  - The "Biometric Unlock" button shows an `AlertDialog` advisory and closes without performing authentication.
  - Neither `local_auth` nor OS KeyStore/Keychain hardware secret wrapping is implemented.
  - While safe (does not permit bypass), shipping a password manager UI with a non-functional biometric button blocks release.
- **Remediation Plan**:
  - When implementing biometric unlock, bind the vault encryption key to hardware biometrics using `setUserAuthenticationRequired(true)` (Android Keystore) and `kSecAccessControlBiometryAny` (iOS Keychain). Do not rely solely on `local_auth` boolean returns.

---

### SEC-029: Dependency Posture & Transitive Cryptographic Deprecations
- **Date**: 2026-10-09
- **Severity**: **LOW (Upstream Maintenance Tracking)**
- **Component**: `Cargo.lock` (`block-modes 0.9.1`, `rust-argon2 3.0.0`)
- **Analysis**:
  - Comprehensive audit of RustSec and GitHub Advisory Database confirmed zero open advisories for `keepass 0.15.0`, `zeroize 1.9.1`, `flutter_rust_bridge 2.13.0`, and `quick-xml 0.42.0` (which patches `RUSTSEC-2026-0194` and `RUSTSEC-2026-0195`).
  - `keepass 0.15.0` transitively pulls deprecated `block-modes 0.9.1` (superseded by `cbc`) and `rust-argon2 3.0.0` (superseded by `argon2`).
- **Remediation**: Monitor upstream `keepass` crate for release migrating to modern RustCrypto crates.

---

### SEC-030: Explicit Argon2id KDF Hardening, Parameter Validation & Sequential UUIDv7 IDs
- **Date**: 2026-10-10
- **Severity**: **HIGH (Cryptographic Hardening & Metadata Leakage Prevention)**
- **Component**: `crates/core/src/vault.rs`, `crates/core/src/error.rs`, `Cargo.toml`
- **Vulnerability**:
  - `Vault::create` relied on implicit `DatabaseConfig::default()` without explicit Argon2id parameter bounds validation (`KdfParams`), risking weak or DoS-inducing KDF parameters during custom creation or key rotation.
  - Root group, subgroup, and entry UUIDs used random UUIDv4 instead of sequential UUIDv7 (`Uuid::now_v7()`), violating `.agents/skills/cqs-zero-downtime-storage/SKILL.md` and `GEMINI.md`.
- **Remediation**:
  - Added `KdfParams` with strict Argon2id range validation (`2..=10` iterations, `15..=1024 MiB` memory, `1..=16` parallelism; default `6` iterations, `32 MiB`, `4` lanes) and `VaultError::WeakKdfParameters`.
  - Upgraded root group, subgroup, and entry generation to `Uuid::now_v7()`.
- **Verification**: Verified in `crates/core/tests/vault.rs` (`sequential_uuid_v7_and_argon2id_defaults`) and `crates/core/tests/security.rs` (`kdf_parameter_bounds_reject_weak_or_excessive_configs`).

---

### SEC-031: Optimistic Concurrency Control & Tracked Entry Mutations / Deletion Tombstones
- **Date**: 2026-10-10
- **Severity**: **HIGH (Sync Integrity & Lost-Update Prevention)**
- **Component**: `crates/core/src/vault.rs`, `app/rust/src/api/vault.rs`, `app/lib/screens/entry_screen.dart`
- **Vulnerability**:
  - Entry updates (`Vault::update`) and deletions (`Vault::remove`) mutated the in-memory `keepass::db::Group` directly without calling `EntryTrack::edit_tracking()` or `track_changes().remove()`, and without advancing `Times::last_modification` monotonically across 1-second KDBX4 timestamp boundaries. Consequently, 3-way merges (`Database::merge`) could resurrect deleted entries or drop same-second edits.
  - Entry mutations lacked `last_known_revision_date` validation, allowing stale editors to silently overwrite concurrent updates.
- **Rule Violated**: `.agents/skills/vault-sync-concurrency/SKILL.md` & `GEMINI.md` (*"ALWAYS enforce optimistic concurrency: Every vault item or attachment mutation must validate `last_known_revision_date` before overwriting state"*).
- **Remediation**:
  - Enforced `last_known_revision_date` validation in `Vault::update` returning `VaultError::StaleRevision`.
  - Integrated `EntryTrack::edit_tracking()`, `track_changes().remove()` (`db.deleted_objects` tombstones), and monotonic `bump_modification_time` / `bump_location_time` across all entry, passkey, and attachment mutations.
- **Verification**: Verified in `crates/core/tests/vault.rs` (`optimistic_concurrency_rejects_stale_revision_date` and `sync_propagates_entry_edits_and_deletion_tombstones`).

---

### SEC-032: KDBX4 Inner-Header Protected Binary Attachments (`Value::protected`)
- **Date**: 2026-10-10
- **Severity**: **MEDIUM (In-Memory & Inner-Header Stream Protection)**
- **Component**: `crates/core/src/vault.rs`
- **Vulnerability**: `Vault::add_attachment` stored binary attachments as `Value::unprotected(data.to_vec())`, omitting the `0x01` ChaCha20 inner-header stream protection flag in KDBX4.
- **Rule Violated**: `.agent/skills/vault-core-dev/SKILL.md` & `GEMINI.md` (*"ALWAYS encrypt sensitive data"*).
- **Remediation**: Changed `Vault::add_attachment` to store binary payloads via `Value::protected(data.to_vec())` and added `Vault::is_attachment_protected` inspection.
- **Verification**: Verified in `crates/core/tests/vault.rs` (`attachments_are_stored_protected_in_kdbx4`).

---

### SEC-033: Atomic Master Password Rotation with Constant-Time Verification
- **Date**: 2026-10-10
- **Severity**: **HIGH (Key Rotation Atomicity)**
- **Component**: `crates/core/src/vault.rs`, `app/rust/src/session.rs`, `app/rust/src/api/vault.rs`, `app/lib/screens/vault_screen.dart`
- **Vulnerability**: VaultKeep lacked an atomic master password rotation flow that verifies the current master password in constant time, re-encrypts the KDBX4 envelope via atomic temp-file persistence, and advances `revision_date` across all entries.
- **Rule Violated**: `.agents/skills/zero-knowledge-key-rotation/SKILL.md` & `GEMINI.md` (*"key rotations must atomically update `revision_date` across all re-encrypted items"*).
- **Remediation**: Implemented `Vault::change_master_password` (and FFI `change_master_password`) with constant-time current password verification, atomic clone-and-save rollback safety, and entry revision advancement.
- **Verification**: Verified in `crates/core/tests/vault.rs` (`master_password_rotation_is_atomic_and_bumps_revisions`) and `app/test/vault_controller_test.dart`.

---

### SEC-034: Mobile IME Personalized Learning Leakage & Async Lock-Race Hardening
- **Date**: 2026-10-10
- **Severity**: **MEDIUM (Secret Input Hygiene & Async State Safety)**
- **Component**: `app/lib/vault_controller.dart`, `app/lib/screens/unlock_screen.dart`, `app/lib/screens/entry_screen.dart`, `app/lib/screens/vault_screen.dart`
- **Vulnerability**:
  - Secret input fields lacked `enableIMEPersonalizedLearning: false`, allowing Android IME keyboards to cache typed passwords or TOTP URIs in personalized learning models.
  - In-flight `_refresh()`, `refreshGroups()`, `_load()`, and `_refreshTotp()` futures did not re-check `status == VaultStatus.unlocked` after `await`, risking stale state repopulation if the vault locked mid-flight.
- **Rule Violated**: `.agent/skills/flutter-frontend/SKILL.md` (*"Set `enableSuggestions: false`, `autocorrect: false`, `enableIMEPersonalizedLearning: false`... Guard post-await UI updates with both `if (!mounted) return;` and a check that the controller is still unlocked"*).
- **Remediation**: Added `enableIMEPersonalizedLearning: false` to all password/secret `TextField`/`TextFormField` widgets and added post-`await` `VaultStatus.unlocked` guards across `VaultController` and `EntryScreen`.
- **Verification**: Verified via `flutter analyze` and `flutter test`.

---

### SEC-035: UI Design Token Enforcement, Color-Coded Accessible Passwords & Destructive Confirmations
- **Date**: 2026-10-10
- **Severity**: **LOW (UI Security Ergonomics & Accessibility)**
- **Component**: `app/lib/theme.dart`, `app/lib/screens/unlock_screen.dart`, `app/lib/screens/entry_screen.dart`, `app/lib/screens/vault_screen.dart`
- **Remediation**:
  - Replaced all raw `Color(0x...)` literals outside token definitions with semantic `TacticalTheme` tokens.
  - Added `TacticalColorPassword` widget with character-class color differentiation and screen-reader `Semantics`.
  - Added confirmation `AlertDialog`s before removing a bound passkey or deleting an attachment, plus a zero-knowledge non-recoverability warning banner on vault creation.
  - Added mobile `2FA (TOTP)` filter chip, quick-copy TOTP action square on credential rows, and deterministic `ValueKey`s across all primary interactive controls.
- **Verification**: Verified via `flutter analyze` and `flutter test` (`app/test/layout_test.dart`).

### SEC-036: Constant-Time Master Password Verification Length-Leak Remediation
- **Date**: 2026-10-11
- **Severity**: **MEDIUM (Timing Side-Channel)**
- **Component**: `crates/core/src/vault.rs` (`constant_time_eq`)
- **Vulnerability**: `constant_time_eq` previously returned early (`if a.len() != b.len() { return false; }`), creating a timing side-channel during `Vault::change_master_password` that leaked the byte length of the active master password.
- **Rule Violated**: `docs/SECURITY_RULES.md` (*"Use constant-time comparison where secret-dependent comparisons are required"*).
- **Remediation**: Replaced early return with a length-accumulating bitwise accumulator (`let mut diff = (a.len() != b.len()) as u8`) that iterates across `max(a.len(), b.len())`.
- **Verification**: Verified in `crates/core/tests/vault.rs` (`master_password_rotation_is_atomic_and_bumps_revisions`).

---

### SEC-037: Unidirectional Subdomain Autofill Matching (`matches_host`)
- **Date**: 2026-10-11
- **Severity**: **MEDIUM (Autofill Credential Confusion)**
- **Component**: `crates/core/src/vault.rs` (`matches_host`)
- **Vulnerability**: `matches_host` previously permitted reverse subdomain matching (`target_host.ends_with(".{entry_host}")`), allowing an entry with a broad hostname or missing eTLD+1 boundary to match arbitrary subdomain queries.
- **Remediation**: Restricted `matches_host` to exact host match or `entry_host.ends_with(".{target_host}")` only.
- **Verification**: Verified in `crates/core/tests/vault.rs` (`domain_autofill_query`).

---

### SEC-038: TOTP Seed URI Isolation from `EntryDetails` (`Vault::otp_uri` & `reveal_otp_uri`)
- **Date**: 2026-10-11
- **Severity**: **MEDIUM (Secret Exposure Minimization)**
- **Component**: `crates/core/src/vault.rs`, `app/rust/src/session.rs`, `app/rust/src/api/vault.rs`, `app/lib/rust_backend.dart`
- **Vulnerability**: `EntryDetails` carried the raw `otp_uri: Option<String>` (including the Base32 TOTP shared secret) in every `details()` / `get_entry()` call rather than isolating it behind an explicit reveal call like `password()`.
- **Remediation**:
  - Replaced `EntryDetails.otp_uri: Option<String>` with `EntryDetails.has_otp: bool`.
  - Added `Vault::otp_uri(id) -> Result<Option<Zeroizing<String>>, VaultError>` in `vaultkeep-core` and `reveal_otp_uri(id)` in `rust_lib_vaultkeep`.
  - Regenerated `flutter_rust_bridge` 2.13.0 bindings and updated `RustBackend.get` to query `revealOtpUri` only when `hasOtp` is true.
- **Verification**: Verified in `crates/core/tests/vault.rs`, `crates/core/tests/security.rs`, and `app/rust/src/api/vault.rs`.

---

### SEC-039: Strict Group & Attachment Existence Validation in `Vault::add` and `Vault::remove_attachment`
- **Date**: 2026-10-11
- **Severity**: **LOW (State Integrity)**
- **Component**: `crates/core/src/vault.rs`, `app/rust/src/session.rs`, `crates/cli/src/main.rs`
- **Vulnerability**:
  - `Vault::add` silently fell back to the root group when given a nonexistent `group_id` instead of returning `Err(VaultError::GroupNotFound)` like `Vault::update`.
  - `Vault::remove_attachment` bumped modification timestamps and wrote to disk even when the target attachment did not exist.
- **Remediation**:
  - Updated `Vault::add` to return `Result<Uuid, VaultError>` and reject unknown group IDs with `VaultError::GroupNotFound`.
  - Updated `Vault::remove_attachment` to verify attachment existence first and return `Err(VaultError::AttachmentNotFound)` if missing.
- **Verification**: Verified in `crates/core/tests/vault.rs` (`groups_and_hierarchy`, `attachments_crud`).

---

### SEC-040: Crate-Wide `#![deny(unsafe_code)]` Enforcement
- **Date**: 2026-10-11
- **Severity**: **LOW (Defense-in-Depth)**
- **Component**: `crates/core/src/lib.rs`, `app/rust/src/lib.rs`
- **Remediation**: Added `#![deny(unsafe_code)]` at the crate root of `vaultkeep-core` and `rust_lib_vaultkeep` (with `#[allow(unsafe_code)]` scoped strictly to the auto-generated `mod frb_generated;`).
- **Verification**: Verified via `cargo clippy --workspace --all-targets -- -D warnings`.

---

## 🔍 Pre-Commit Security Checklist

Before merging any change touching secrets, cryptography, storage, IPC, or UI:
1. [x] **Secrets in Rust**: Wrapped in `Zeroizing<String>`; no `#[derive(Debug)]` on any type holding secrets; no secrets in `format!`, error strings, or panic messages.
2. [x] **Secrets in Dart**: No static caches of passwords; short lifetimes; controllers cleared on dispose/submit; `enableIMEPersonalizedLearning: false` on all secret inputs.
3. [x] **Disk Persistence**: Only encrypted KDBX4 persisted; atomic temporary write pattern with cleanup on error; optimistic concurrency via `last_known_revision_date`.
4. [x] **Clipboard**: Auto-cleared after 15 s; immediately wiped on vault lock ONLY if matching active secret.
5. [x] **App Lifecycle**: Auto-lock on idle (2 minutes); auto-lock on mobile `inactive`/`paused`; post-`await` `VaultStatus.unlocked` guards.
6. [x] **Verification**:
   - `cargo fmt --all -- --check` (Passed - 0 issues)
   - `cargo clippy --workspace --all-targets -- -D warnings` (Passed - 0 warnings)
   - `cargo test --workspace` (Passed - 35/35 tests: 23 in `tests/vault.rs`, 8 in `tests/security.rs`, 1 in `tests/details.rs`, 3 in `rust_lib_vaultkeep`)
   - `cd app && flutter analyze` (Passed - 0 issues)
   - `cd app && flutter test` (Passed - 20/20 tests)
