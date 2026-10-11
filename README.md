# VaultKeep

A personal password manager. **Flutter** frontend, **Rust** backend. The vault is a standard **KDBX4** file (the KeePass format), so it can be opened in KeePassXC.

```
app/lib      Flutter UI (Dart)
app/rust     flutter_rust_bridge layer
crates/core  vault logic (Rust, uses the keepass crate)
crates/cli   terminal frontend for testing
```

## Try the Rust side now
```
cargo test
cargo run -p vaultkeep-cli -- my.kdbx init
cargo run -p vaultkeep-cli -- my.kdbx add GitHub kingshuk https://github.com
cargo run -p vaultkeep-cli -- my.kdbx list
```

## Run the Flutter app
`flutter_rust_bridge 2.13.0` bindings (`app/lib/src/rust/**`, `app/rust/src/frb_generated.rs`) and platform runners are configured in `app/`. See `docs/FLUTTER_SETUP.md` for toolchain prerequisites and binding regeneration steps.

## Development Plan & Verification Checklist
See `docs/NEXT_STEPS.md` for the staged **M0–M6 Development Plan**, baseline commands, and working security verification checklist.
See `docs/ARCHITECTURE.md` for the system design and current verified status.
See `docs/SECURITY_AUDIT_LOG.md` for the security audit ledger and vulnerability remediations.

## Building it with Antigravity
Open this folder in Antigravity; project rules in `GEMINI.md` and `.agent/rules/project.md` and workspace skills in `.agent/skills/` and `.agents/skills/` are loaded automatically:
- `/vault-planner`, `/security-docs`, `/release-supply-chain` — planning, docs, and release verification
- `/vault-core-dev`, `/rust-vault-security`, `/zero-knowledge-key-rotation`, `/cqs-zero-downtime-storage`, `/test-hardening`, `/kdbx-interop-testing` — Rust KDBX4 core, Argon2id key rotation, CQS & adversarial testing
- `/flutter-rust-bridge`, `/flutter-rust-boundary`, `/flutter-frontend`, `/vault-ui-components`, `/vault-entry-type-planner`, `/mobile-integration` — FFI bridge, TacticalTheme UI components, entry types & mobile security
- `/vault-sync-concurrency`, `/encrypted-cloud-sync`, `/prelogin-auth-tokenables` — optimistic concurrency, 3-way merge & M6+ cloud sync architecture
- `/security-review` — pre-merge security gate (`.agent/workflows/verify.md`)

Review each generated change yourself. Skills are guidance for an agent, not a security certification.

## License
GPL-3.0-or-later (chosen to stay compatible with KeePassXC's license; change in `Cargo.toml` if you prefer another).

## Safety note
Do not ship a password manager for production use or claim it is audited until the implementation has been reviewed by experienced security engineers and independently audited.
