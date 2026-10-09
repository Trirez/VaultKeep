# Project Planner: Flutter + Rust Password Manager

## Product statement
Build a cross-platform password manager with a Flutter UI and a Rust security core. The user's vault is encrypted locally and can be backed up/synchronized as ciphertext to user-authorized cloud storage such as Google Drive and OneDrive. The provider must not receive the master password or plaintext vault contents.

## Initial product decisions
- [ ] Target platforms for MVP: Windows, Android, macOS, Linux, iOS (confirm build/signing access for Apple platforms).
- [ ] Cloud model: user-owned cloud storage; no vendor-operated vault server in v1.
- [ ] Sync model: one encrypted vault file with revisions and conflict-safe backup.
- [ ] Recovery model: optional user-held recovery key, designed and documented before implementation.
- [ ] Vault file format: versioned envelope with algorithm/KDF metadata, salt, nonce(s), encrypted payload, and authenticated associated data.
- [ ] Threat model: define what is protected against and what is explicitly out of scope.
- [ ] Privacy policy and data-flow diagram before public release.

## Milestone 0: Research and design
- [ ] Write `docs/THREAT_MODEL.md`.
- [ ] Write `docs/CRYPTO_DESIGN.md`; get design reviewed before implementation.
- [ ] Define vault format and migration policy.
- [ ] Define key hierarchy and recovery behavior.
- [ ] Decide cloud storage location: app-specific private folder vs user-visible backup file.
- [ ] Document OAuth scopes and provider consent requirements.
- [ ] Decide what metadata may be visible to cloud provider (file name, size, timestamps, revisions).
- [ ] Define supported OS versions and CI/build matrix.

Exit criteria: reviewed threat model, crypto design, file format, recovery and sync conflict behavior.

## Milestone 1: Rust core
- [ ] Create a Rust workspace with a small `vault_core` library.
- [ ] Implement typed vault models and strict serialization validation.
- [ ] Implement key derivation using a vetted Argon2id library; benchmark and document parameters per target device.
- [ ] Implement authenticated encryption using a vetted RustCrypto AEAD library.
- [ ] Generate salts, data keys, nonces and recovery material with OS-backed cryptographic randomness.
- [ ] Separate master-password-derived key from a random vault data-encryption key.
- [ ] Implement unlock, lock, create vault, read entry, write entry, export and import APIs.
- [ ] Ensure wrong passwords, malformed files, unsupported versions and authentication failures fail closed.
- [ ] Add unit tests, property tests and fuzz targets for parsing and envelope validation.

Exit criteria: deterministic tests for format logic, cryptographic round-trip tests, tamper tests, fuzzing harness and documented API.

## Milestone 2: Flutter app and FFI
- [ ] Create Flutter app and connect Rust using `flutter_rust_bridge` (or a deliberately reviewed alternative).
- [ ] Keep encryption/key-handling operations in Rust; Flutter should not reimplement cryptography.
- [ ] Build onboarding, unlock, vault list, entry details, create/edit, search and settings.
- [ ] Add password/passphrase generator backed by a CSPRNG.
- [ ] Add inactivity lock and manual lock.
- [ ] Add clipboard copy with configurable clearing and clear-on-lock best effort.
- [ ] Add accessible UI and platform-aware navigation.
- [ ] Ensure error messages never include passwords, keys or decrypted payloads.

Exit criteria: local encrypted vault works without any cloud account.

## Milestone 3: Local storage and platform security
- [ ] Store vault in app-private storage by default.
- [ ] Store only a wrapped key or OS-protected token in Keychain/Keystore/credential store where appropriate.
- [ ] Treat biometric unlock as a way to release a protected local key, not as a replacement for sound key management.
- [ ] Prevent sensitive data from entering logs, analytics, crash reports, notifications, clipboard history where controllable, or app-switcher previews.
- [ ] Review backup/restore behavior on each OS.
- [ ] Document that memory wiping is best-effort and cannot guarantee removal of every copy.

Exit criteria: platform storage tests and documented residual risks.

## Milestone 4: Cloud backup and sync
- [ ] Define a provider-neutral `CloudStorage` interface: list, download, upload, get revision, conditional update, delete, and restore history where supported.
- [ ] Implement Google Drive using the narrowest suitable OAuth scope.
- [ ] Decide between `appDataFolder` and a user-visible backup location; explain trade-offs.
- [ ] Implement OneDrive using least-privilege app-folder permissions where suitable.
- [ ] Store OAuth refresh tokens only in platform-protected storage.
- [ ] Upload ciphertext only; never upload plaintext vaults, keys or master passwords.
- [ ] Use remote revision/ETag checks and conditional writes where supported.
- [ ] Detect concurrent edits and preserve conflicting copies instead of silently overwriting.
- [ ] Keep a configurable number of historical encrypted versions.
- [ ] Verify downloaded backups by decrypting/authenticating locally before offering restore.
- [ ] Test interrupted uploads, offline changes, revoked OAuth, quota limits and provider outages.

Exit criteria: recoverable encrypted backup and no silent conflict data loss.

## Milestone 5: Quality and hardening
- [ ] Add integration tests for all supported platforms.
- [ ] Add malformed input tests, fuzzing, dependency audit and static analysis.
- [ ] Add secret scanning and lockfile review to CI.
- [ ] Add release signing and reproducible-build goals where practical.
- [ ] Complete OWASP MASVS-based mobile review.
- [ ] Complete independent cryptographic/security review before production release.
- [ ] Publish a security contact, vulnerability disclosure process and release notes.
- [ ] Conduct restore drills and document recovery limitations.

Exit criteria: no known critical/high findings; security reviewer signs off on residual risks.

## Milestone 6: Later features (not MVP)
- [ ] Browser extension and native messaging bridge.
- [ ] Android Autofill Framework integration.
- [ ] Apple AutoFill Credential Provider extension.
- [ ] Desktop browser autofill integration.
- [ ] TOTP authenticator.
- [ ] Importers for KeePass/Bitwarden-compatible formats (after format and threat review).
- [ ] Passkey support, sharing, emergency access and breach monitoring only after a separate threat/design review.

## Definition of done for every security-sensitive change
- [ ] Threat and trust boundaries considered.
- [ ] No plaintext secrets in logs, telemetry, tests, fixtures or error messages.
- [ ] Tests cover success, failure, tampering and malformed input.
- [ ] Dependency and API choices are documented.
- [ ] Failure is closed and does not silently downgrade security.
- [ ] Documentation and migration/versioning behavior updated.
