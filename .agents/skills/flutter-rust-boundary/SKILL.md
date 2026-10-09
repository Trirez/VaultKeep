---
name: flutter-rust-boundary
description: Designs and reviews the Flutter/Dart to Rust FFI boundary for a password manager, keeping cryptography in Rust and preventing secret leakage across UI, logs, errors, and memory.
---

# Flutter-Rust Boundary

## Goals
Flutter owns presentation and interaction. Rust owns vault models where security-sensitive, key derivation, encryption/decryption, password generation, vault validation and cryptographic decisions.

## Rules
1. Use the project's chosen bridge (prefer `flutter_rust_bridge` if already adopted) and follow its current official setup.
2. Expose narrow typed operations such as `create_vault`, `unlock_vault`, `list_entries`, `save_entry`, `lock_vault`, `export_encrypted_vault`, and `verify_backup`.
3. Do not expose raw encryption keys to Dart.
4. Avoid copying master passwords and decrypted secrets between layers unnecessarily; keep their lifetime short.
5. Never include secret values in exceptions, debug prints, analytics, widget keys, route arguments, URLs or crash reports.
6. Treat all bridge arguments as untrusted and validate in Rust, even if Flutter already validates them.
7. Keep UI validation for usability only; security validation belongs in Rust.
8. Avoid storing decrypted vault state in global singletons or long-lived state containers.
9. Lock and clear app state when the vault locks; understand that Dart/runtime copies may not be reliably zeroized.
10. Ensure desktop/mobile platform differences are handled by small adapters rather than contaminating the crypto core.

## Tests and review
- Test cancellation, repeated unlock/lock, bridge errors, malformed data, large vaults and app lifecycle transitions.
- Confirm no raw key or master password is returned from Rust APIs.
- Confirm errors shown to users are helpful but non-sensitive.
- Review app-switcher preview, clipboard, keyboard autofill and background/resume behavior.
