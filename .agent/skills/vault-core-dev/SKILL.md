---
name: vault-core-dev
description: Use when adding or changing vault features (entries, groups, TOTP, attachments, key files, sync) in the vaultkeep-core Rust crate. Enforces the KDBX4 format, atomic saves and secret-handling rules.
---

# Vault Core Development

## Goal
Extend `crates/core` without breaking KDBX compatibility or leaking secrets. Every frontend depends on this crate, so correctness here matters more than speed.

## Ground rules
1. The vault file is a standard **KDBX4** file via the `keepass` crate. Never invent a custom file format. KeePassXC must always be able to open what we write.
2. KeePassXC itself is C++/Qt and is **not** linked or wrapped. It is the compatibility reference only.
3. Secrets (master password, entry passwords, key file bytes) use `zeroize::Zeroizing` and never appear in `Debug`, logs, errors or panics.
4. Saves are atomic: write temp file in the same directory, `sync_all`, then `rename`. Never write the vault in place.
5. No UI, networking or platform code in `crates/core`. It must compile for Linux, Windows, macOS, Android and iOS targets.
6. Return `VaultError`, never `unwrap()` in library code (tests may unwrap).

## Workflow
1. Read `crates/core/src/vault.rs` and `crates/core/tests/vault.rs` first.
2. Write the failing integration test before the feature.
3. Implement against the public API of `keepass` 0.15 (`Database`, `GroupMut`, `EntryMut`, `fields::*`). Check the crate source in `~/.cargo/registry` if unsure rather than guessing.
4. Run `cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test`.
5. Add an on-disk check when the feature stores secrets: the plaintext must not appear in the saved bytes (see `no_plaintext_secrets_on_disk`).

## After a core change
The Flutter app reaches the core only through `app/rust/src/api/vault.rs` and `app/rust/src/session.rs`. If a feature should be visible in the UI, continue with skills `flutter-rust-bridge` and `flutter-frontend`. Keep that API free of secrets except in `reveal_password` and the entry-save input.

## Do not
- Add a dependency without checking its maintenance status and running `cargo audit`.
- Expose raw `keepass` types in the public API; wrap them so frontends stay stable.
- Cache decrypted passwords in `EntrySummary` or any list view type.
