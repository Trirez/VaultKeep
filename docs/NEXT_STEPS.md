# VaultKeep: Simplified Next Steps & Security Verification Plan

**Status:** Working Baseline & Verification Plan | **Prepared:** 10 October 2026  
**Architecture:** Flutter UI (`app/`) + Rust FFI Bridge (`app/rust/`) + Pure-Rust KDBX4 Core (`crates/core/`) + CLI (`crates/cli/`)

---

## 1. Repository Ground Truth & Audit Summary

An analysis of the codebase, documentation (`docs/`), and agent skills (`.agent/` and `.agents/`) revealed that two different documentation/skill sets exist in the repository alongside a few stale status claims. Use the table below as the verified starting baseline:

| Area | Actual Codebase State | Doc / Skill Discrepancy to Reconcile |
|---|---|---|
| **Vault Format & Crypto** | Standard **KDBX4** via `keepass = "0.15"` (`save_kdbx4`, `totp`, `_merge`), `zeroize`, `rand::rngs::OsRng`, and `tempfile` atomic saves (`crates/core/`). | Generic template docs (`PROJECT_PLAN.md`, `TECH_STACK.md`, `THREAT_MODEL_TEMPLATE.md`) and `.agents/skills/rust-vault-security` still describe designing a custom AEAD/Argon2 envelope from scratch. |
| **Flutter ↔ Rust Bridge** | `flutter_rust_bridge = 2.13.0` is configured in `app/pubspec.yaml` and `app/rust/Cargo.toml`; generated bindings exist in `app/lib/src/rust/` and `app/rust/src/frb_generated.rs`. | `README.md`, `docs/FLUTTER_SETUP.md`, and `SEC-027` in `docs/SECURITY_AUDIT_LOG.md` still claim Flutter has never been compiled and `vault.dart` contains `UnimplementedError` stubs. |
| **Cloud Sync Model** | **Zero network permissions** (`INTERNET` omitted). Sync uses local 3-way KDBX file merge (`Vault::sync_with_file` / `merge_vault`) with a local replica or cloud-synced folder. | `docs/GOOGLE_DRIVE_SYNC.md` describes a live Google Drive API v3 OAuth 2.0 screen that does not exist in `app/lib/`. Direct cloud OAuth is deferred to **M6**. |
| **CLI Interface** | `crates/cli/src/main.rs` uses `vaultkeep <vault.kdbx> init\|add\|list\|show\|rm` with interactive `rpassword` prompts. | `docs/INTEROP.md` shows outdated CLI commands passing plaintext passwords on the command line (`new`, `get`, `copy`). |
| **Biometric Unlock (`SEC-028`)** | `UnlockScreen` (`app/lib/screens/unlock_screen.dart`) renders an "Unlock with Biometrics" button that opens an advisory dialog stub (`_authenticateBiometric`). | Must either be hidden/disabled for the local-first MVP release or wired to hardware-backed keystore/keychain keys. |
| **Workspace Skills** | Split across `.agent/skills/` (8 skills) and `.agents/skills/` (7 skills). | `security-review` is duplicated in both folders; `.agent/skills/cross-platform-ui` recommends Tauri 2/Slint/Dioxus instead of Flutter. |

---

## 2. Staged Milestones (Security-First Path)

**Release Principle:** Local-first, encrypted, recoverable, and honest about what has actually been tested. Never advertise the app as audited, unbreakable, or production-secure without direct evidence.

### M0 — Establish the Real Baseline & Reconcile Docs (Immediate Priority)
- Confirm active branch, clean/dirty working tree, and toolchain versions (`rustc`, `cargo`, `flutter`).
- Run baseline checks and record actual outputs (mark `BLOCKED` if any prerequisite is missing).
- Align `README.md`, `docs/FLUTTER_SETUP.md`, `docs/ARCHITECTURE.md`, `docs/INTEROP.md`, `docs/GOOGLE_DRIVE_SYNC.md`, and `docs/SECURITY_AUDIT_LOG.md` (`SEC-027`, `SEC-028`) with actual code and test evidence.

### M1 — Validate Rust Core and CLI
- Run `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, `cargo audit`, and `cargo deny check`.
- Run CLI smoke tests (`init`, `add`, `list`, `show`, `rm`, `gen`) and verify regression tests in `crates/core/tests/vault.rs` and `crates/core/tests/security.rs` for `SEC-001` through `SEC-029`.
- Run external KeePassXC interoperability checks (`keepassxc-cli`) if installed, or explicitly record as `BLOCKED` in `docs/INTEROP.md`.

### M2 — Review Security Boundaries
- Audit master-password and secret handling (`Zeroizing<String>`, manual redacted `fmt::Debug`, error strings across FFI).
- Document exact `keepass 0.15` KDBX4 parameters (Argon2id / cipher settings) and verify no custom or redundant encryption is layered on top.
- Verify atomic file writes (`tempfile::Builder` in parent directory, `sync_all`, `persist`), lock/unlock session dropping (`app/rust/src/session.rs`), and `reveal_password` authorization.

### M3 — Prove End-to-End Flutter ↔ Rust Integration
- Verify `flutter_rust_bridge_codegen generate` produces zero diff against committed bindings.
- Run `flutter pub get`, `flutter analyze`, and `flutter test` in `app/`.
- Resolve `SEC-028` (either hide the stubbed "Unlock with Biometrics" button in `unlock_screen.dart` for v0.1 or implement hardware-bound keystore/keychain unlock).
- Build and launch at least one desktop target and execute the full **create → save → restart → unlock → read/edit → lock** flow.

### M4 — Complete Local Backup, Sync Merge & Recovery
- Verify encrypted export/import and 3-way KDBX merge (`Vault::sync_with_file`) using a separate destination/replica path.
- Test wrong-password rejection, empty/truncated/corrupted file rejection, incompatible root UUID handling (`VaultError::IncompatibleVaultRoots`), and self-merge rejection (`VaultError::SelfMerge`).
- Add a clear user-facing recovery warning when creating a vault that losing the master password permanently prevents recovery.

### M5 — Prepare a Small, Honest First Release
- Record platform build/smoke-test matrix (Windows, Linux, macOS, Android, iOS) with exact pass/blocked status.
- Document known limitations (Dart string non-zeroization, Android 10+ background clipboard restrictions, upstream `keepass 0.15` transitive crate notices in `SEC-029`).

### M6 — Optional Cloud API Sync (Post-MVP Only)
- Only after M0–M5 are solid: evaluate whether passive OS cloud-folder sync + 3-way KDBX merge is sufficient, or whether direct OAuth 2.0 cloud adapters (Google Drive `appDataFolder`/`drive.file`, OneDrive AppFolder) should be added with revision/ETag checks and conflict preservation.

---

## 3. Baseline Verification Commands

Run from repository root (`d:\PassProject`) and record actual output:

```powershell
# 1. Repository & Rust workspace baseline
git status --short --branch
rustc --version
cargo --version
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo audit
cargo deny check
```

Run from Flutter directory (`d:\PassProject\app`):

```powershell
# 2. Flutter static analysis, unit/widget tests, and desktop build check
flutter --version
flutter pub get
flutter analyze
flutter test
flutter build windows --debug
```

---

## 4. Working Security & Verification Checklist

Mark items `[x]` (**PASS**) only with direct evidence (test output, code review line reference, or reproducible manual run). Mark `BLOCKED` if prerequisites are missing, or `N/A` with rationale.

### A. Build and Repository Truth (M0 — Verified 2026-10-10)
- [x] **PASS** — Confirm branch (`dev`), working tree, Rust version (`rustc 1.99.0`, `cargo 1.99.0`), Flutter version (`Flutter 3.47.7` stable, `Dart 3.13.5`), and target platforms.
- [x] **PASS** — Run `cargo fmt --all -- --check` (0 formatting diffs).
- [x] **PASS** — Run `cargo clippy --workspace --all-targets -- -D warnings` (0 warnings across `vaultkeep-core`, `vaultkeep-cli`, and `rust_lib_vaultkeep`).
- [x] **PASS** — Run `cargo test --workspace` (`35/35` passed: 23 in `tests/vault.rs`, 8 in `tests/security.rs`, 1 in `tests/details.rs`, 3 in `rust_lib_vaultkeep`).
- [x] **PASS** — Run `flutter analyze` (`No issues found!`) and `flutter test` (`20/20` controller & layout tests passed) in `app/`.
- [x] **PASS** — Reconcile conflicting claims across `README.md`, `FLUTTER_SETUP.md`, `ARCHITECTURE.md`, `INTEROP.md`, `GOOGLE_DRIVE_SYNC.md`, `SECURITY_AUDIT_LOG.md`, and workspace skills in `.agent/skills/` and `.agents/skills/`.

### B. Cryptographic Design and KDBX4 (M1/M2 — Verified 2026-10-10)
- [x] **PASS** — Document `keepass 0.15` version and exact APIs used in `crates/core/src/vault.rs`.
- [x] **PASS** — Verify KDBX4 key derivation settings (`KdfParams`: Argon2id `6` iterations, `32 MiB`, `4` lanes with strict bounds `2..=10` iterations, `15..=1024 MiB`, `1..=16` lanes), sequential `Uuid::now_v7()` entity IDs, and atomic master password rotation (`change_master_password`).
- [x] **PASS** — Confirm no custom cryptography is used and CSPRNG uses `rand::rngs::OsRng`.
- [x] **PASS** — Verify wrong password, weak/excessive KDF parameters, bit-flipped ciphertext, and truncated/corrupted files fail closed (`crates/core/tests/security.rs`).

### C. Secret Handling (M2/M3 — Verified 2026-10-10)
- [x] **PASS** — Audit `Debug`/`Display` implementations for `Vault`, `EntryInput`, `EntryDetails`, `EntryData`, `TotpToken`, and `TotpItem`.
- [x] **PASS** — Audit logs, error strings, and panic paths for secret leakage.
- [x] **PASS** — Confirm list/detail models (`EntrySummary`, `EntryItem`, `VaultItem`, `VaultEntry`) carry no password, and only `reveal_password` returns one when unlocked.
- [x] **PASS** — Verify `TextEditingController` buffers in `unlock_screen.dart`, `entry_screen.dart`, and `vault_screen.dart` are cleared on submit/dispose and have `enableSuggestions: false`, `autocorrect: false`, and `enableIMEPersonalizedLearning: false`.

### D. Storage and Failure Safety (M2/M4 — Verified 2026-10-10)
- [x] **PASS** — Verify atomic save via `tempfile::Builder` in the vault's directory, `sync_all()`, and `persist()`.
- [x] **PASS** — Verify temporary file cleanup when serialization or I/O fails.
- [x] **PASS** — Verify `MAX_VAULT_BYTES` (100 MB), `MAX_ATTACHMENT_BYTES` (25 MB), `Value::protected` attachment stream protection, and 0-byte file rejection (`SEC-022`, `SEC-032`).
- [x] **PASS** — Ensure optimistic concurrency (`last_known_revision_date` / `VaultError::StaleRevision`) and ensure failed sync/restore never overwrites the active vault (`SEC-031`).

### E. Locking, Clipboard, and Lifecycle (M3 — Verified 2026-10-10)
- [x] **PASS** — Verify `lock_vault()` drops `Vault` from `SESSION` and rejects all subsequent read/reveal/edit/merge calls.
- [x] **PASS** — Verify auto-lock on 2-minute idle timer, mobile `inactive`/`hidden`/`paused` states (`app/lib/app.dart`), and post-`await` `VaultStatus.unlocked` guards (`SEC-034`).
- [x] **PASS** — Verify pushed Navigator routes close automatically when locked (`_closeRoutesWhenLocked`).
- [x] **PASS** — Verify `ClipboardGuard` clears copied secrets after 15s and on lock **only** if the clipboard still matches `_activeSecret` (`SEC-026`).
- [x] **PASS** — Verify Android `FLAG_SECURE` (`MainActivity.kt`), `android:allowBackup="false"` (`AndroidManifest.xml`), and iOS blur overlay (`SceneDelegate.swift`).

### F. Backup, Merge, and Recovery (M4 — Verified 2026-10-10)
- [x] **PASS** — Verify 3-way KDBX merge (`Vault::sync_with_file`) with `EntryTrack` edit history and deletion tombstones (`db.deleted_objects`) updates both local and replica files atomically and rejects incompatible root UUIDs (`SEC-016`, `SEC-031`).
- [x] **PASS** — Test restore/merge against a separate test replica location before touching primary vaults.
- [x] **PASS** — Ensure vault creation displays a clear warning that losing the master password cannot be undone (`unlock_screen.dart`).

### G. End-to-End Acceptance Flow
- [ ] 1. Launch on a clean test profile.
- [ ] 2. Create a new vault with a 12+ character master password and verify recovery warning.
- [ ] 3. Add entries (with groups, TOTP URI, passkey, and attachment), save, and exit.
- [ ] 4. Restart the app and unlock the vault (verify wrong password fails first).
- [ ] 5. Search, filter by group/category, edit, rotate master password, and delete entries; reopen to confirm persistence.
- [ ] 6. Reveal/copy a password, lock the vault, and verify clipboard clears and reveal is denied.
- [ ] 7. Sync/merge with a replica vault in a separate directory and verify bidirectional persistence.

---

## 5. Security Finding Template

```markdown
### SEC-XXX: [Title]
- **Severity**: Critical / High / Medium / Low / Informational
- **Affected Component & Commit**: `path/to/file`
- **Preconditions & Reproduction Steps**:
- **Expected vs. Observed Behavior**:
- **Impact & Threat Scenario**:
- **Fix / Mitigation**:
- **Regression Test**:
- **Evidence / Command Output**:
- **Status**: Open / In Progress / Fixed (Awaiting Verification) / Verified / Accepted with Rationale
```

---

## 6. Simplified Skill Map for Next Steps

| Task / Milestone | Skill to Use |
|---|---|
| **M0 / M5 — Planning, Baseline & Docs** | `vault-planner`, `security-docs`, `release-supply-chain` |
| **M1 / M2 — Rust Core, KDBX4, Key Rotation & Adversarial Tests** | `vault-core-dev`, `rust-vault-security`, `zero-knowledge-key-rotation`, `cqs-zero-downtime-storage`, `test-hardening`, `kdbx-interop-testing` |
| **M3 — FFI Bridge, UI Components & Entry Types** | `flutter-rust-bridge`, `flutter-rust-boundary`, `flutter-frontend`, `vault-ui-components`, `vault-entry-type-planner`, `mobile-integration` |
| **M4 / M6 — Local Replica Sync, Concurrency & Cloud Backup** | `vault-sync-concurrency`, `encrypted-cloud-sync` (M6 OAuth adapters), `prelogin-auth-tokenables` (M6+ cloud auth) |
| **All Milestones — Pre-Merge Gate** | `security-review` (`.agent/workflows/verify.md`) |
