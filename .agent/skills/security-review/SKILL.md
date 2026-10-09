---
name: security-review
description: Use before merging any change that touches secrets, crypto, clipboard, storage, the Rust/Dart bridge, logging or dependencies in the password manager. Runs a threat-model checklist and automated audits.
---

# Security Review

## Goal
Catch secret leaks and unsafe defaults in a password manager before they ship.

## Checklist

**Secrets in Rust**
- Master password and entry passwords use `Zeroizing<String>`; the open `Vault` is dropped on lock.
- No `#[derive(Debug)]` on a type holding a secret.
- No secret in `format!`, logs, error strings or panic messages. Errors crossing the bridge are plain strings.

**Secrets in Dart**
- Dart `String`s are immutable and cannot be wiped, so keep their lifetime short: no caching of passwords in controllers, lists or static fields.
- Only `revealPassword` returns a password; list and detail models have none.
- No `print`/`debugPrint` of form values; no analytics or crash reporters that capture state.
- Known limit: the edit screen loads the entry's password into a text field. Prefer a "password unchanged" flag over round-tripping it if this is revisited.

**Secrets on disk**
- Only the encrypted `.kdbx` is persisted. No plaintext exports, caches or screenshots.
- Saves are atomic (temp file, fsync, rename) and the temp file is never left holding secrets.

**Clipboard and UI**
- Copied passwords are cleared after 15 s only if the clipboard still holds our value. Known limit: Android 10+ blocks clipboard reads for a backgrounded app, so the clear may be skipped.
- Password fields are masked by default, with suggestions and autocorrect off.
- Auto-lock on idle and on background; pushed routes are closed on lock.
- Mobile: screenshot and app-switcher protection (see `mobile-integration`).

**Crypto**
- No custom crypto. KDF and cipher settings come from the `keepass` crate defaults or stronger. Random values come from `OsRng`.

**Platform**
- No INTERNET permission or network code until sync exists.
- Decide `android:allowBackup` deliberately; the vault file is encrypted but other app data should not be backed up.
- Release builds use `--obfuscate --split-debug-info`.

**Dependencies**
- Rust: `cargo audit` and `cargo deny check` pass.
- Dart: review `flutter pub outdated` and pub.dev advisories; prefer few, maintained packages.

## Run
```
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo audit
cargo deny check
cd app && flutter analyze && flutter test
```
Report findings as a list: severity, file:line, fix. If a tool is not installed, say so instead of skipping silently.
