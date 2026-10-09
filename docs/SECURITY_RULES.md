# Non-negotiable Security Rules

These rules should be treated as release-blocking requirements.

## Cryptography
1. Never design a custom cipher, KDF, RNG, MAC, or key exchange.
2. Use vetted, maintained libraries and documented, standard algorithms.
3. Use Argon2id for master-password key derivation; benchmark parameters on supported devices and version the parameters. Do not blindly use one setting on every device.
4. Use authenticated encryption (AEAD), such as XChaCha20-Poly1305 or another reviewed standard choice. Never use unauthenticated encryption alone.
5. Never reuse a nonce with the same key when the algorithm forbids it. Generate required salts/nonces using a cryptographically secure OS-backed RNG.
6. Separate key-encryption and data-encryption roles. Never derive a vault key using ad hoc concatenation or home-grown hashing.
7. Authenticate important envelope metadata as associated data where the format permits.
8. On authentication failure, reject the data. Do not return partial plaintext or attempt insecure fallback.
9. Use constant-time comparison where secret-dependent comparisons are required and the library offers the appropriate primitive.
10. Document algorithm identifiers, KDF parameters, salt, nonce, key version and format version in the envelope. Never store the master password.

## Secrets and memory
11. Plaintext vault data and keys must not enter logs, analytics, telemetry, crash reports, tracing spans, screenshots, clipboard sync or debug output.
12. Redact sensitive values by construction; do not rely on developers remembering to redact every log statement.
13. Keep decrypted data in memory only as long as necessary. Lock promptly and zeroize sensitive buffers where feasible, while documenting that OS/runtime copies may remain.
14. Never embed API secrets, private keys, recovery keys or provider client secrets in source code or app binaries.
15. OAuth tokens must be stored in OS-protected storage; request the narrowest permissions possible.
16. Biometrics are an OS-mediated local unlock convenience, not a replacement for the vault's cryptographic design.

## Vault file and parser
17. Treat every vault file, cloud response, import, sync metadata object and custom field as untrusted input.
18. Enforce size limits, field limits, nesting limits and strict schema validation before allocation or decryption.
19. Reject unknown critical versions/algorithms and unsupported KDF parameters safely; never silently downgrade.
20. Use authenticated encryption and validate all metadata before trusting it.
21. Migrations must preserve a recoverable backup and must never overwrite the only valid copy.
22. Avoid writing plaintext temporary files. If unavoidable, document the risk, restrict access, minimize lifetime and test cleanup.

## Cloud and sync
23. Encrypt locally before any cloud upload. Cloud APIs must receive ciphertext only.
24. Never upload the master password, plaintext entries, data-encryption key or recovery key.
25. Use least-privilege OAuth scopes and clearly explain permissions to the user.
26. Treat remote names, metadata, content and revision identifiers as untrusted.
27. Use conditional writes/revision checks when available; never silently overwrite concurrent edits.
28. Preserve prior encrypted versions and make restore a deliberate, verified action.
29. Revoke/disconnect should remove local tokens and stop sync; explain that it cannot necessarily delete copies already downloaded or retained by the provider.
30. Do not claim that cloud backup prevents deletion, ransomware or provider-account compromise; it only adds a recovery path.

## Application and platform
31. Keep the cryptographic boundary in Rust. Flutter should call narrow typed APIs and should not implement parallel encryption logic.
32. Avoid FFI APIs that pass raw key bytes or plaintext strings around unnecessarily.
33. Never use `unsafe` Rust for convenience; isolate and document any unavoidable unsafe block and review it.
34. Avoid secrets in URLs, deep links, notifications, app-switcher previews and clipboard by default.
35. Use secure transport for provider APIs; never disable TLS verification.
36. Do not weaken security checks for debug builds in a way that can accidentally ship to release.
37. Minimize permissions and platform capabilities.
38. Keep dependencies pinned/reviewed; audit changes and remove unused crates/plugins.

## Testing and release
39. Test tampering, truncation, wrong passwords, malformed lengths, unsupported versions, nonce/metadata errors, interrupted writes, conflict races, and restore failures.
40. Add fuzzing for vault parsing and importers; add property tests for serialization and round trips.
41. Never use real passwords or production vaults in test fixtures.
42. Keep a written threat model and security assumptions.
43. Do not claim “unhackable,” “military-grade,” or “audited” without evidence.
44. Do not release for real password storage until an experienced independent reviewer has assessed the cryptographic design and implementation.
45. If a vulnerability is found, prioritize containment, user communication, safe migration and a documented fix over preserving backward compatibility.

## Required negative tests
- A one-bit ciphertext modification fails authentication.
- Wrong master password never yields partial plaintext.
- Truncated/oversized/invalid envelopes fail safely without panic or excessive allocation.
- Unsupported algorithm/version is rejected, not downgraded.
- Logs and crash/error paths contain no secrets.
- Cloud mock sees ciphertext only.
- Concurrent remote change does not silently erase either revision.
- A backup restore is verified before replacing the current vault.
