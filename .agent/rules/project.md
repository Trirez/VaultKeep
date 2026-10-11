# VaultKeep project rules

- Stack: Flutter (Dart) frontend in `app/`, Rust backend in `crates/core` (vault logic) and `app/rust` (flutter_rust_bridge layer). `crates/cli` is a test frontend.
- Vault format: KDBX4 via the `keepass` crate (`0.15`). Never create a custom format or add redundant encryption layers without a written threat-model rationale.
- All vault logic stays in Rust. Dart never does crypto, KDBX parsing or password generation.
- Never log, print or serialize secrets. Use `Zeroizing` and manual redacted `fmt::Debug` in Rust; keep Dart password lifetimes short and clear `TextEditingController`s on submit/dispose.
- Saves must use randomized atomic tempfiles (`tempfile::Builder` in the target directory, `sync_all`, `persist`) and clean up on failure.
- Generated files (`app/rust/src/frb_generated.rs`, `app/lib/src/rust/**`) are never edited by hand.
- Follow the staged milestone order (`M0` -> `M6`) and verification checklist in `docs/NEXT_STEPS.md`. Local reliability and backup/restore (`M0`–`M5`) always precede network cloud sync (`M6`).
- Before declaring work done run `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, and in `app/`: `flutter analyze`, `flutter test`.
- Evidence-based reporting: mark checks `PASS` only with actual command output; mark `BLOCKED` (never passed) if prerequisites/tools are missing. Never claim an independent audit, KeePassXC binary interop, or mobile device behavior unless actually executed.
- Keep documentation (`README.md`, `docs/ARCHITECTURE.md`, `docs/FLUTTER_SETUP.md`, `docs/SECURITY_AUDIT_LOG.md`, `docs/NEXT_STEPS.md`) synchronized with actual code state in the same task.
- Use the matching workspace skills: `vault-core-dev`, `rust-vault-security`, `flutter-rust-bridge`, `flutter-rust-boundary`, `flutter-frontend`, `vault-ui-components`, `vault-entry-type-planner`, `zero-knowledge-key-rotation`, `vault-sync-concurrency`, `cqs-zero-downtime-storage`, `prelogin-auth-tokenables`, `mobile-integration`, `security-review`, `test-hardening`, `kdbx-interop-testing`, `release-supply-chain`, `vault-planner`, `security-docs`, `encrypted-cloud-sync`.

