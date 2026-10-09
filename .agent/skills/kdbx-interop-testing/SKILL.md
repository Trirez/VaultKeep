---
name: kdbx-interop-testing
description: Use to verify that vaults written by vaultkeep open correctly in KeePassXC and that KeePassXC-created vaults open in vaultkeep.
---

# KDBX Interoperability Testing

## Goal
Prove two-way compatibility with KeePassXC, since "KeePass backend" means the KDBX file format.

## Steps
1. Check for the reference CLI: `which keepassxc-cli`. If missing, install it (`apt install keepassxc` on Debian/Ubuntu) or ask the user to run the manual check below.
2. **Write test:** create a vault with the vaultkeep CLI, add an entry, then run
   `keepassxc-cli ls vault.kdbx` and `keepassxc-cli show -s vault.kdbx "<title>"`. The entry and password must match.
3. **Read test:** create a vault with `keepassxc-cli db-create -p vault.kdbx`, add an entry with `keepassxc-cli add -p`, then run `vaultkeep vault.kdbx list`.
4. **Features to cover when added:** groups, custom fields, attachments, TOTP, key files, password history.
5. Record results in `docs/INTEROP.md` as a table (feature, direction, pass/fail, KeePassXC version).

## Notes
- Do not claim compatibility for features that are not in the table.
- A passing round trip inside Rust tests is not interop evidence; only a real KeePassXC run counts.
