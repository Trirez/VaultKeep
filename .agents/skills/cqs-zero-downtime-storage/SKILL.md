---
name: cqs-zero-downtime-storage
description: >-
  Structure VaultKeep backend and persistence code using Command Query Separation (CQS),
  application-generated sequential COMB/UUIDv7 IDs, forward-only idempotent migrations,
  and real Rust-encrypted test fixtures. Use when adding commands, queries, repositories,
  schema migrations, or database integration tests.
---

# CQS Architecture, Sequential IDs & Evolutionary Storage

## Scope
Applies to VaultKeep domain logic (`crates/core`), sequential KDBX4 entity ID generation (`Uuid::now_v7()`), future M6+ SQLite/PostgreSQL sync persistence layers, and integration test fixtures.

## Architectural Conventions (Adapted from Bitwarden Server Skills)

### 1. Command Query Separation (CQS)
- Keep read-only query methods (`summaries`, `get`, `search`, `groups`, `totp_code_for_entry`, `list_attachments`, `get_attachment`) strictly side-effect-free and separate from state-mutating command methods (`add`, `update`, `remove`, `create_group`, `move_entry_to_group`, `bind_passkey`, `remove_passkey`, `add_attachment`, `delete_attachment`, `change_master_password`, `sync_with_file`).
- Every state-mutating command on `Vault` must validate inputs first, apply tracked mutations, and atomically persist to disk (`save_atomic`).

### 2. Application-Generated Sequential IDs (UUIDv7 / COMB)
- **Never** rely on unseeded or random `Uuid::new_v4()` defaults when creating new KDBX4 roots, groups, or entries in `crates/core`.
- Always generate sequential timestamp-ordered UUIDv7 identifiers (`uuid::Uuid::now_v7()`) in Rust application code and pass them to `Database::new_with_root_id(GroupId::from_uuid(Uuid::now_v7()))`, `GroupMut::add_entry_with_id(EntryId::from_uuid(Uuid::now_v7()))`, and `GroupMut::add_group_with_id(GroupId::from_uuid(Uuid::now_v7()))`.
- UUIDv7 is a valid 128-bit RFC 9562 UUID (`[u8; 16]`) that preserves 100% KDBX4 (`<UUID>` Base64) and KeePassXC interoperability while providing monotonic ordering and index locality.

### 3. Evolutionary Schema & Custom Data Compatibility
- **KDBX4 Custom Data & Fields (M0–M5)**: Treat custom entry fields (`VK_PASSKEY_*`, `_vk_*`) as forward-compatible schemas — never rename or drop existing field keys without supporting fallback parsing for existing `.kdbx` files.
- **SQL Migrations (M6+ Cloud/Index Storage)**: Design schema migrations assuming code can roll back, but database migrations cannot (idempotent `IF NOT EXISTS`, expand-and-contract, inline `DEFAULT` constraints).

### 4. Cryptographically Authentic Test Seeding
- Integration and unit tests MUST use VaultKeep's actual Rust crypto core (`crates/core::Vault`) to create and encrypt real `.kdbx` files on `tempfile::tempdir()`, never unencrypted mock blobs masquerading as KDBX4 ciphertexts.

## Verification Steps
1. Check that read-only `Vault` queries never mutate `Database` state or touch the filesystem.
2. Verify all root, group, and entry creation paths in `crates/core/src/vault.rs` use `Uuid::now_v7()` (`uuid.get_version_num() == 7`).
3. Confirm KDBX4 field additions maintain backward compatibility with previously saved `.kdbx` vaults.

