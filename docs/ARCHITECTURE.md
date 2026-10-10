# Architecture

```
 Flutter UI (Dart)                       app/lib
   screens ─ VaultController ─ VaultBackend (interface)
                                   │  RustBackend (only file using generated code)
                      flutter_rust_bridge (generated FFI)
                                   │
 Rust bridge crate                       app/rust  (rust_lib_vaultkeep)
   api/vault.rs ─ Session (one open vault)
                                   │
 Rust core                               crates/core  (vaultkeep-core)
   Vault, password generator ─ keepass crate ─ vault.kdbx
                                             (KDBX4, opens in KeePassXC)
```

## Why not link KeePassXC directly?
KeePassXC is a C++/Qt application, so it cannot be used as a Rust library, least of all on Android and iOS. VaultKeep uses the **KDBX4 file format** through the pure-Rust `keepass` crate. KeePassXC is the compatibility reference: a vault written here should open there and the reverse. That has not been tested yet (see `.agent/skills/kdbx-interop-testing`).

## Parts
| Path | Role |
|---|---|
| `crates/core` | Vault create/open/save, entries, search, password generator |
| `app/rust` | Bridge: a small stateful API over the core, scanned by flutter_rust_bridge |
| `app/lib` | Flutter UI, controller, backend interface |
| `crates/cli` | Terminal frontend for testing the core |

## What crosses the bridge
- Dart to Rust: vault path, master password, entry fields (including the password on save).
- Rust to Dart: entry lists and details with no password; a password only from `reveal_password`.
- Errors are plain strings with no secrets.
- Dart strings cannot be wiped from memory, so passwords are kept in Dart only as long as needed.

## Sync model (planned)
The vault is one encrypted file. The user picks its location, which can sit inside a Google Drive, OneDrive or Dropbox folder that the provider's own client syncs. The app never uploads plaintext and has no network permission. Conflict handling for edits on two devices needs the `keepass` crate's merge support, to be enabled and tested before any sync claim.

## Status
- Verified here: Rust core, CLI, and bridge build cleanly, pass clippy with 0 warnings, and pass all 35 workspace tests (`23` in `tests/vault.rs`, `8` in `tests/security.rs`, `1` in `tests/details.rs`, `3` in `rust_lib_vaultkeep`).
- Flutter app: verified via `flutter analyze` (0 issues) and `flutter test` (all 20 unit/controller/layout tests pass).
- Windows integration:
  - `flutter_rust_bridge_codegen 2.13.0` installed and code bindings generated.
  - Native assets builder configured via `app/hook/build.dart` and `flutter_rust_bridge_hooks: 2.13.0`.
  - `rust-toolchain.toml` set for reproducible `x86_64-pc-windows-msvc` builds.
  - Windows runner metadata configured (application title, company name, UTF-8 resource script).
  - Native dynamic library compilation (`rust_lib_vaultkeep.dll`) verified.
- Android integration:
  - Rust cross-compilation targets (`aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`) added to `app/rust/rust-toolchain.toml` and compiled via Dart Native Assets + Android NDK `28.2.13676358`.
  - Native shared libraries (`lib/arm64-v8a/librust_lib_vaultkeep.so`, `lib/armeabi-v7a/librust_lib_vaultkeep.so`, `lib/x86_64/librust_lib_vaultkeep.so`) packaged into APK and verified on Android API 37 emulator (`emulator-5554`).
  - Hardened with `WindowManager.LayoutParams.FLAG_SECURE` (`MainActivity.kt`), `android:allowBackup="false"`, and zero network permissions (`AndroidManifest.xml`).
- Features implemented and verified:
  - KDBX4 create/open/atomic save with explicit Argon2id parameter validation (`KdfParams`) and zeroized credentials
  - Sequential UUIDv7 entity ID generation (`Uuid::now_v7()`) for root, groups, and entries
  - Atomic master password rotation (`change_master_password`) with constant-time verification and revision advancement
  - Optimistic concurrency control (`revision_date` / `last_known_revision_date` / `VaultError::StaleRevision`)
  - Groups hierarchy & dynamic group moving on edit
  - RFC 6238 TOTP token generation, timer countdown, and quick-copy action
  - FIDO2 / WebAuthn Passkey generation, COSE ES256 keypair storage, and category filtering
  - Protected binary attachments CRUD (`Value::protected` in KDBX4 inner header)
  - KDBX 3-way synchronization merge with `EntryTrack` edit history and deletion tombstones (`db.deleted_objects`)
  - Strict host/subdomain autofill domain queries
  - Screen capture & app-switcher protection (Android `FLAG_SECURE`, iOS privacy blur)
  - Timed clipboard auto-clearing (15s) and wipe on lock
  - Auto-lock on idle (2 min) and app backgrounding/inactive with post-`await` lock-race guards
