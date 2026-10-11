# VaultKeep Security & Engineering Guardrails

## Critical Zero-Knowledge & Security Invariants
- **NEVER compromise zero-knowledge principles**: User vault data, passwords, derived keys, and decrypted entry fields must remain client-encrypted and inaccessible to server/sync infrastructure.
- **NEVER log or expose sensitive data**: No PII, master passwords, KDF outputs, symmetric/asymmetric keys, or decrypted vault records in logs, `Debug`/`Display` formatting, panic messages, or error responses.
- **ALWAYS encrypt sensitive data**: All vault data must be encrypted at rest, in transit, and in use with authenticated encryption (KDBX4 outer AEAD / ChaCha20-Poly1305 or AES-256 + HMAC-SHA256 + inner stream protection `Value::Protected`, or COSE Encrypt0 for M6+ sync payloads).
- **NEVER mint security tokens ad-hoc**: All authentication, verification, WebAuthn challenge, and sync session tokens must be minted through a dedicated factory with configuration-driven expiration.
- **ALWAYS enforce optimistic concurrency**: Every vault item or attachment mutation must validate `last_known_revision_date` (when provided) before overwriting state and update KDBX4 modification timestamps (`Times`), and master password / key rotations must atomically update `revision_date` across all re-encrypted items.
- **ALWAYS generate sequential entity IDs in application code**: Use sequential UUIDv7 (`Uuid::now_v7()`) / COMB generators in Rust (`EntryId::from_uuid(Uuid::now_v7())`, `GroupId::from_uuid(Uuid::now_v7())`) rather than random UUIDv4 or database-generated defaults.
- **ALWAYS add unit and adversarial tests**: Every new command, query, or security fix requires unit tests (covering both happy path and tampered/unauthorized/stale-revision failure cases).

