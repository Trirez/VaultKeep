---
name: vault-sync-concurrency
description: >-
  Implement and audit optimistic concurrency control, revision timestamp validation,
  soft-delete tombstones, and attachment upload flows for VaultKeep vault persistence
  and cloud sync. Use when building or reviewing vault save, sync, conflict resolution,
  or attachment storage logic.
---

# Vault Sync & Optimistic Concurrency Control

## Scope
Applies to VaultKeep vault item mutations (`crates/core`), KDBX4 3-way merge (`sync_with_file`), conflict detection, deletion tombstones (`db.deleted_objects`), and encrypted attachment lifecycles.

## Core Patterns (Adapted from Bitwarden `CipherService` & `SyncController` to KDBX4)
1. **Optimistic Concurrency via `last_known_revision_date` & KDBX4 `EntryTrack`**:
   - Expose `revision_date: Option<i64>` (UTC Unix timestamp in seconds from `entry.times.last_modification`) on `EntrySummary` and `EntryDetails`.
   - Accept `last_known_revision_date: Option<i64>` on `EntryInput` (and attachment/passkey mutation paths).
   - Before persisting changes on an existing entry, if `last_known_revision_date` is `Some(expected)`, compare with the stored `revision_date`:
     - If `|stored_revision_date - expected| > 1` (1-second tolerance for KDBX4 integer-second timestamp serialization), reject the write with `VaultError::StaleRevision` so stale views cannot silently overwrite newer edits.
   - Always mutate existing KDBX4 entries through `entry.edit_tracking(|e| ...)` or `entry.track_changes()` in `keepass 0.15` so `times.last_modification` is bumped to `Times::now()` and a history snapshot is pushed to `entry.history` (preventing `MergeError::EntryModificationTimeNotUpdated` during KDBX4 3-way merges).
2. **Deletion Tombstones (`db.deleted_objects` & `EntryTrack::remove`)**:
   - In KDBX4 (`keepass 0.15`), calling `entry.remove()` directly on `EntryMut` drops the node without recording a tombstone!
   - Always delete entries via `entry.track_changes().remove()` (`EntryTrack::remove`) and move entries via `entry.track_changes().move_to(...)`, which records `(uuid, Some(Times::now()))` in `db.deleted_objects` / updates `times.location_changed`.
   - KDBX4 3-way merge (`Database::merge`) uses `db.deleted_objects` tombstones so offline/synced copies propagate deletions rather than resurrecting deleted entries.
3. **Protected & Atomic Attachment Storage**:
   - Local KDBX4 attachments (`add_attachment`) MUST validate the filename (`validate_attachment_name`) and byte size (`MAX_ATTACHMENT_BYTES`), store the binary payload in the KDBX4 inner header using `Value::protected(data.to_vec())` (encrypted in memory and by the KDBX4 inner ChaCha20 stream), bump the parent entry's `last_modification` timestamp via `edit_tracking`, and persist via `save_atomic`.
   - For M6+ cloud-streamed attachments, use a two-step metadata lease + stream commit flow with byte-length verification.

## Verification Checklist
1. Check all entry update, passkey bind/remove, group move, and attachment commands for `last_known_revision_date` validation and `times.last_modification` updates.
2. Verify that `Vault::remove` uses `entry.track_changes().remove()` so `db.deleted_objects` contains the deleted UUID and timestamp.
3. Confirm `add_attachment` wraps bytes in `Value::protected(...)` rather than `Value::unprotected(...)`.

## Required Tests
- Concurrent edit / stale revision test: Fetching an entry at $T_0$, updating it at $T_1$, and attempting a second update with stale `last_known_revision_date = T_0 - 10` fails with `VaultError::StaleRevision` without overwriting the $T_1$ state.
- Deletion tombstone sync test: Deleting an entry in Vault A and running `sync_with_file` against Vault B propagates the deletion via KDBX4 `deleted_objects` tombstones.
- Modified entry merge test: Updating an entry's password/fields in Vault A updates `revision_date` and merges cleanly with Vault B via `sync_with_file` without `MergeError::EntryModificationTimeNotUpdated`.

