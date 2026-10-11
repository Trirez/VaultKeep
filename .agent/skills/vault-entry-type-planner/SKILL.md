---
name: vault-entry-type-planner
description: >-
  Plans and guides the creation or modification of a vault entry type or
  credential section (e.g., Login, Passkey, TOTP, Credit Card, Secure Note,
  Identity, SSH Key, Bank Account, or Custom Fields) end to end across
  VaultKeep's KDBX4 Rust core, FFI bridge, and Flutter UI. Use whenever adding
  a new item type, category filter, or structured field group to the vault.
---

# Vault Entry Type & Credential Section Planner

Adapted from Bitwarden's `cipher-type-planner` workflow for VaultKeep's KDBX4 + Flutter architecture. Adding a new credential type or structured section touches every layer; skipping a step causes items to vanish from filters, leak secrets in list views, or fail during KDBX4 save/merge.

## Step 1: Gather & Define Requirements

Before writing code, clarify or define:
1. **Type / Section Name & KDBX4 Representation**:
   - How is it stored in KDBX4 (`crates/core`)? (Standard KDBX entry fields, protected custom string attributes, or binary attachments? Note: never invent a non-standard file format; it must survive a KeePassXC round-trip.)
2. **Field Matrix**:
   - List every field with: **Name**, **Data Type**, **Protected/Encrypted in KDBX Memory? (`yes`/`no`)**, **Required? (`yes`/`no`)**, and **Copiable from Quick Actions? (`yes`/`no`)**.
3. **List Summary (`VaultItem`) vs. Detail (`VaultEntry`)**:
   - What non-sensitive subtitle/badge appears in `VaultItem` list rows (e.g., masked card tail `•••• 4242`, username, RP ID, `hasPasskey`, `hasTotp`)?
   - **Rule**: `VaultItem` must NEVER carry secret values (passwords, CVVs, private keys, TOTP seeds).
4. **Sidebar / Category Filter Participation**:
   - Should this type/capability have a filter chip or sidebar category in `VaultCategoryFilter` (`vault_controller.dart`) and a count getter?
5. **Icon & Avatar Mapping**:
   - How does `TacticalDomainAvatar` or the type badge in `theme.dart` represent this item offline?
6. **Autofill Participation**:
   - Does this type participate in `findEntriesForDomain` / mobile autofill?

## Step 2: End-to-End Implementation Checklist

Always implement and verify in this exact layer order:

### 1. Rust Core (`crates/core/`)
- [ ] Map fields to KDBX4 `Entry` attributes in `crates/core/src/vault.rs` (use protected values for secrets and `Zeroizing<String>` for inputs/outputs).
- [ ] Redact all sensitive fields in manual `fmt::Debug` implementations.
- [ ] Ensure `EntrySummary` exposes only non-secret metadata/flags needed for list rendering and filtering.
- [ ] Add unit + round-trip persistence + 3-way merge tests in `crates/core/tests/`.

### 2. FFI Bridge (`app/rust/`)
- [ ] Update DTO structs and functions in `app/rust/src/api/vault.rs`.
- [ ] Regenerate bindings via `flutter_rust_bridge_codegen generate` (never hand-edit `frb_generated.*`).

### 3. Dart Backend Contract (`app/lib/backend.dart` & `rust_backend.dart`)
- [ ] Update `VaultItem` (summary flags/subtitle), `VaultEntry` (detail fields), and `EntryDraft` (save payload—ensure `EntryDraft` has **no** `toString()`).
- [ ] Add any dedicated reveal/generation methods to `VaultBackend` and implement in `RustBackend`.
- [ ] Update `FakeBackend` in `app/test/` so all controller and widget tests run without native FFI.

### 4. Vault Filters & Controller (`app/lib/vault_controller.dart`) — CRITICAL
- [ ] **Filter registration**: If the type has a category filter, add it to `VaultCategoryFilter`, add a count getter on `VaultController`, and wire it into the filtered items predicate in `VaultScreen`. *(Without this, items of the new category cannot be filtered in the sidebar or mobile chips.)*
- [ ] Ensure `lock()` resets any selected filter or active state for the new type.

### 5. Form & View UI Sections (`app/lib/screens/entry_screen.dart` & `vault_screen.dart`)
- [ ] **Form/Inspector Section (`EntryScreen`)**:
  - Add controllers/state fields, initialize them in `_load()`, and **reset/clear them in both `didUpdateWidget` and `dispose()`**.
  - Set `obscureText: true`, `enableSuggestions: false`, `autocorrect: false`, and `enableIMEPersonalizedLearning: false` on all secret inputs.
- [ ] **Quick Copy Actions (`VaultScreen` & `EntryScreen`)**:
  - Only expose fields meant to be copiable.
  - Route all copies through `ClipboardGuard.copySecret(...)` with a specific toast message (`"<FieldLabel> copied. Clears in 15 seconds."`).
  - For secret fields not loaded in `VaultItem`, fetch on demand via `controller` when clicked.

### 6. Tests (`app/test/`)
- [ ] Add controller unit tests in `app/test/vault_controller_test.dart` covering create, edit, filter counts, and lock clearing.
- [ ] Add widget tests verifying form input, reveal toggles, copy actions, and responsive rendering.
