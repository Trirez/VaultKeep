---
name: security-review
description: Use before merging any change that touches secrets, crypto, clipboard, storage, the Rust/Dart bridge, sync, logging or dependencies in VaultKeep. Runs the threat-model checklist, adversarial checks, and automated audits.
---

# Security Review

## Goal
Catch secret leaks, boundary violations, and unsafe failure modes in VaultKeep before they ship. Assume all files, replica inputs, and FFI arguments may be malformed or malicious.

## Checklist

**Secrets in Rust**
- Master password, replica passwords, TOTP seeds, and entry passwords use `Zeroizing<String>`; the open `Vault` is dropped on lock.
- No `#[derive(Debug)]` on a type holding a secret; use manual `fmt::Debug` with `"[REDACTED]"`.
- No secret in `format!`, logs, error strings or panic messages. Errors crossing the bridge are plain strings.

**Secrets in Dart**
- Dart `String`s are immutable and cannot be wiped, so keep their lifetime short: no caching of passwords in controllers, lists or static fields; clear `TextEditingController`s on submit and `dispose()`.
- Only `revealPassword` returns a password; list and detail models have none.
- No `print`/`debugPrint` of form values; no analytics or crash reporters that capture state.

**Secrets & Safety on Disk**
- Only the encrypted `.kdbx` is persisted. No plaintext exports, caches or screenshots.
- Enforce input size bounds (`MAX_VAULT_BYTES`, `MAX_ATTACHMENT_BYTES`, non-empty check) before allocation.
- Saves and 3-way merges (`sync_with_file`) are atomic (`tempfile::Builder` in same directory, `sync_all`, `persist`) and clean up temporary files on error.
- Failed unlock, save, merge, or restore must never overwrite a valid vault.

**Clipboard and UI**
- Copied passwords and TOTP codes are cleared after 15 s and on lock **only** if the clipboard still holds the tracked active secret (`ClipboardGuard`).
- Password and TOTP URI fields are masked by default, with `enableSuggestions: false` and `autocorrect: false`.
- Auto-lock on idle (2 min) and on mobile `inactive`/`hidden`/`paused`; pushed routes are closed on lock.
- Mobile: Android `FLAG_SECURE`, `android:allowBackup="false"`, and iOS blur overlay on `sceneWillResignActive`.

**Crypto**
- No custom crypto or redundant encryption layers. KDBX4 KDF (Argon2id) and cipher settings come from the `keepass` crate. Random values come from `OsRng`.

**Platform**
- No INTERNET permission or network code until sync exists.
- Decide `android:allowBackup` deliberately (`false` in `AndroidManifest.xml`).
- Release builds use `--obfuscate --split-debug-info`.

**Dependencies**
- Rust: `cargo audit` and `cargo deny check` pass.
- Dart: review `flutter pub outdated` and pub.dev advisories; prefer few, maintained packages.

## Run
```
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo audit
cargo deny check
cd app && flutter analyze && flutter test
```

## Finding Output Format
Report findings using the structure in `docs/NEXT_STEPS.md` (`SEC-XXX`, Severity, Component, Preconditions, Impact, Fix, Regression Test, and Evidence/Status: `PASS` / `BLOCKED` / `N/A`). Do not claim "no issues" for uninspected paths, and never claim an independent audit.
