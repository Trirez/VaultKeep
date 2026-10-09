# VaultKeep project rules

- Stack: Flutter (Dart) frontend in `app/`, Rust backend in `crates/core` (vault logic) and `app/rust` (flutter_rust_bridge layer). `crates/cli` is a test frontend.
- Vault format: KDBX4 via the `keepass` crate. Never create a custom format.
- All vault logic stays in Rust. Dart never does crypto, KDBX parsing or password generation.
- Never log, print or serialize secrets. Use `Zeroizing` in Rust; keep Dart password lifetimes short.
- Generated files (`app/rust/src/frb_generated.rs`, `app/lib/src/rust/**`) are never edited by hand.
- Before declaring work done run `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test`, and in `app/`: `flutter analyze`, `flutter test`.
- Say plainly what was and was not verified. Do not claim KeePassXC compatibility, mobile behaviour, biometrics or autofill work unless they were actually run.
- Use the matching skill in `.agent/skills/`: `vault-core-dev`, `flutter-rust-bridge`, `flutter-frontend`, `mobile-integration`, `security-review`, `kdbx-interop-testing`, `release-supply-chain`.
