---
name: release-supply-chain
description: Use when preparing builds, CI, dependency updates or releases for the Flutter + Rust password manager across desktop and mobile targets.
---

# Release and Supply Chain

## Goal
Ship reproducible, auditable builds with a small dependency surface.

## Steps
1. Commit `Cargo.lock` and `app/pubspec.lock`. Build Rust with `--locked`.
2. Decide whether generated bindings (`app/lib/src/rust/**`, `app/rust/src/frb_generated.rs`) are committed. Recommended: commit them, and have CI fail if `flutter_rust_bridge_codegen generate` (pinned version) produces a diff.
3. CI jobs:
   - Rust (Linux): `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test`, `cargo audit`, `cargo deny check`.
   - Flutter (Linux): `flutter analyze`, `flutter test`.
   - Platform builds: Windows, macOS (also iOS), Linux, Android.
4. Release builds:
   ```
   flutter build apk --release --obfuscate --split-debug-info=build/symbols
   flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
   flutter build windows|macos|linux|ios --release
   ```
5. The workspace release profile uses LTO, `strip` and `panic = "abort"`. Keep it, and remember an abort skips destructors, so zeroizing relies on normal paths.
6. Sign artifacts and publish SHA-256 checksums. Keep a `CHANGELOG.md`; call out any change to KDF parameters or file-format handling.

## Dependency policy
- Rust: pin `flutter_rust_bridge` exactly and upgrade it with the codegen tool and Dart package together.
- Prefer crates and packages with recent releases and several maintainers.
- Read the diff of any update to `keepass`, crypto crates, or auth/storage plugins before merging.
