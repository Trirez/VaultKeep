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
Follow `docs/FLUTTER_SETUP.md`. The Flutter code has not been compiled yet, so the first run needs the setup steps there.

## Building it with Antigravity
Open this folder in Antigravity; skills in `.agent/skills/` are picked up automatically (restart the agent session if they do not appear). Example prompts:

- "Follow docs/FLUTTER_SETUP.md and get the app running on Linux. Use the flutter-rust-bridge skill."
- "Use vault-core-dev, flutter-rust-bridge and flutter-frontend to add groups."
- "Use mobile-integration to add screenshot protection on Android."
- "Run the verify workflow."
- "Use security-review on my last change."

See `docs/ARCHITECTURE.md` for the design and current status.
See `docs/SECURITY_AUDIT_LOG.md` for the security audit ledger and history of vulnerability fixes.

## License
GPL-3.0-or-later (chosen to stay compatible with KeePassXC's license; change in `Cargo.toml` if you prefer another).

## Recommended first-release scope
- Local-only encrypted vault
- Master password unlock
- Rust-owned cryptographic boundary
- Password generator
- Encrypted export/import and verified restore
- Google Drive app-data folder OR user-visible file backup (choose intentionally)
- OneDrive app-folder support
- Conflict detection and retained versions
- No hosted account system in v1

## Antigravity installation
Copy the `.agents/` directory into the root of your project repository. Antigravity's current default workspace skill path is `.agents/skills/`; older `.agent/skills/` is supported by some versions. Open/reload the workspace, then invoke a skill by slash command, for example:
- `/vault-planner`
- `/rust-vault-security`
- `/flutter-rust-boundary`
- `/encrypted-cloud-sync`
- `/security-review`
- `/test-hardening`

Review each generated change yourself. Skills are guidance for an agent, not a security certification.

## Safety note
This kit is a development planning aid, not a cryptographic design review. Do not ship a password manager or claim it is secure until the implementation has been reviewed by experienced security engineers and independently audited.
