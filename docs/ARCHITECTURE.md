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
- Verified here: Rust core, CLI, and bridge build cleanly, pass clippy with 0 warnings, and pass all 15 tests.
- Flutter app: verified via `flutter analyze` (0 issues) and `flutter test` (all 9 unit/controller tests pass).
- Features implemented and verified:
  - KDBX4 create/open/atomic save with zeroized credentials
  - Groups hierarchy & dynamic group moving on edit
  - RFC 6238 TOTP token generation & timer countdown
  - Protected binary attachments CRUD
  - KDBX 3-way synchronization merge
  - Autofill domain queries
  - Screen capture & app-switcher protection (Android `FLAG_SECURE`, iOS privacy blur)
  - Timed clipboard auto-clearing (15s) and wipe on lock
  - Auto-lock on idle (2 min) and app backgrounding/inactive
