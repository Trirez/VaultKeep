---
name: zero-knowledge-key-rotation
description: >-
  Design, implement, and review KDF parameter validation, key wrapping hierarchies,
  and atomic user key or master password rotation in VaultKeep. Use when working on
  master password changes, KDF upgrades (Argon2id/PBKDF2), user/account key rotation,
  or cryptographic format version migrations.
---

# Zero-Knowledge Key Rotation & KDF Hardening

## Scope
Applies to VaultKeep's Rust cryptographic core (`crates/core`), CLI (`crates/cli`), Flutter bridge (`app/rust`), and future M6+ sync/backend key management endpoints.

## Architectural Rules (Adapted from Bitwarden Server to VaultKeep KDBX4)
1. **Hardened KDF Range Validation**:
   - Enforce strict min/max/default range constants (`KdfParams`) for all KDF parameters before deriving or persisting keys:
     - `Argon2id` (required default for new vaults via `keepass::config::KdfConfig::Argon2id`): iterations `2..=10` (default `6`), memory `15..=1024 MB` (default `32 MB` for mobile compatibility, `64 MB+` desktop), parallelism `1..=16` (default `4`).
     - Note: `keepass::config::DatabaseConfig::default()` defaults to `KdfConfig::Argon2` (Argon2d, 1 MB). Always explicitly configure `KdfConfig::Argon2id` with validated parameters when creating or rotating vaults!
     - `AES-KDF` / `PBKDF2-SHA256` (legacy KDBX interoperability only): `600_000..=2_000_000` rounds/iterations.
   - Reject out-of-range KDF parameters at both the Rust core boundary and API validation layer (`VaultError::WeakKdfParameters`).
2. **Versioned Envelope & Key Separation**:
   - **Local KDBX4 Vaults (M0–M5)**: Rely on KDBX4's native two-tier key hierarchy — never add custom redundant encryption wrappers around KDBX4 files (per `.agent/rules/project.md`). KDBX4 derives a transformed key from the composite credentials (`DatabaseKey`: password + optional keyfile) via `Argon2id`, combines it with the per-save random `MasterSeed` to protect the outer payload (AES-256 / Twofish / ChaCha20 + HMAC-SHA256 block stream), and uses the random `InnerRandomStreamKey` (ChaCha20) to protect in-memory `Value::Protected` secrets (passwords, TOTP seeds, passkey private keys, and attachment bytes).
   - **Cloud Sync / Account Layer (M6+)**: Never encrypt account-level sync envelopes directly with the Master Key; wrap a symmetric **User Key** and tag envelopes with an explicit version header (`COSE Encrypt0` / `XChaCha20-Poly1305`).
3. **Atomic Key / Master Password Rotation Transaction**:
   - Master password change (`Vault::change_master_password`) or KDF rotation with re-encryption MUST execute as an all-or-nothing atomic transaction:
     - Verify the current master password against the active vault state before mutating any keys or timestamps.
     - Re-configure `db.config.kdf_config` to validated `KdfConfig::Argon2id` parameters so legacy or weak KDF vaults are transparently upgraded on rotation.
     - Bump `revision_date` (`times.last_modification = Some(Times::now())`) on **every** entry and group during rotation so de-synced copies or stale UI views cannot overwrite newly rotated records.
     - Persist via `save_atomic` (randomized tempfile in target dir → `write_all` → `sync_all` → `persist`). Only update the in-memory `Zeroizing<String>` master password after the atomic rename succeeds.

## Implementation & Review Procedure
1. **Inspect KDF & Envelope Definitions**:
   - Check that KDF parameters are validated via a range-checked struct (`KdfParams::validate`) before creating, rotating, or accepting KDF configurations.
   - Confirm all sensitive fields AND binary attachments in KDBX4 use `Value::protected(...)` rather than `Value::unprotected(...)`.
2. **Trace the Rotation Path**:
   - Verify old authentication credential verification happens before any state mutation.
   - Ensure local KDBX4 saves use write-temp → `sync_all` → atomic rename, and rollback in-memory mutations if disk persistence fails.
3. **Check Stale-Client Protection**:
   - Confirm every rotated item's `revision_date` (`last_modification`) is updated to `now`.

## Required Verification Tests
- Master password rotation (`change_master_password`) succeeds, re-encrypts the vault under `Argon2id`, bumps `revision_date` on all entries, allows unlocking with the new password, and rejects the old password.
- Rotation fails atomically (preserving the prior master password and file on disk) if current master password verification fails.
- Out-of-range KDF parameters (e.g., `Argon2id` memory `< 15 MB` or iterations `< 2`) fail fast with `VaultError::WeakKdfParameters`.
- Post-rotation write attempt using a pre-rotation `last_known_revision_date` is rejected with `VaultError::StaleRevision`.

