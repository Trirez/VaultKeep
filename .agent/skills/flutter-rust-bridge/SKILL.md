---
name: flutter-rust-bridge
description: Use when exposing Rust functions to Flutter, regenerating Dart bindings, setting up flutter_rust_bridge for the first time, or debugging bridge errors in the password manager.
---

# flutter_rust_bridge Workflow

## Goal
Keep the Rust API in `app/rust/src/api/` and the generated Dart bindings in sync, with no secrets leaking across the boundary.

## Versions
The Rust crate, the Dart package and the codegen tool must be the **same version**. Currently `=2.13.0` in `app/rust/Cargo.toml`.
```
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
```
Pin `flutter_rust_bridge: 2.13.0` (exact) in `app/pubspec.yaml`. Upgrade all three together.

## Files
- `app/flutter_rust_bridge.yaml`: `rust_input: crate::api`, `rust_root: rust/`, `dart_output: lib/src/rust`
- `app/rust/src/api/vault.rs`: the public API codegen scans (every `pub` item becomes Dart)
- `app/rust/src/session.rs`: private; holds the one open vault
- Generated, never edit by hand: `app/rust/src/frb_generated.rs`, `app/lib/src/rust/**`

## Change workflow
1. Edit `app/rust/src/api/vault.rs`; add a test; run `cargo test`.
2. `cd app && flutter_rust_bridge_codegen generate` (or `generate --watch`).
3. Update `app/lib/rust_backend.dart` to the new generated signatures.
4. `flutter analyze && flutter test`.

## API rules
- Use `u32`/`i32`, never `usize` or `u64` (they become `BigInt` in Dart).
- Pass ids as `String` (UUID text). Parse and validate in Rust.
- Return `Result<T, String>`. Error strings must never contain secrets.
- Define data structs inside the api module with `pub` fields. A struct holding a password must not derive `Debug`.
- List and detail structs carry no password. Only `reveal_password` returns one.
- Leave functions async (the default). Opening a vault runs a slow key derivation that must stay off the UI thread. Do not use `#[frb(sync)]` for anything touching the vault.
- Wrap incoming secrets in `Zeroizing` immediately, as the existing functions do. The Dart copy cannot be wiped; keep its lifetime short.

## First-time setup
Follow `docs/FLUTTER_SETUP.md`. Flags change between releases, so run `flutter_rust_bridge_codegen integrate --help` and compare with https://cjycode.com/flutter_rust_bridge/quickstart before running anything. Commit first so `git diff` shows what `integrate` changed, and restore our `app/lib/` and `app/rust/` files if it overwrote them.

## Troubleshooting
- "content hash mismatch" or version errors: codegen, crate and Dart package versions differ.
- Library not found at runtime: the Rust crate name must stay `rust_lib_vaultkeep`.
- Android build fails: install the NDK and Rust Android targets (`rustup target add aarch64-linux-android`).
- If codegen does not add `mod frb_generated;` to `app/rust/src/lib.rs`, add it.
