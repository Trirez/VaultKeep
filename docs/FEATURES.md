# Feature Catalogue

## MVP: required
### Vault
- Create/unlock/lock vault
- Login entries: title, username, password, URLs, notes, custom fields
- Folders, tags, favorites
- Search and sort
- Create/edit/duplicate/delete
- Secure notes
- Password and passphrase generator
- Import/export through an explicit encrypted or warned plaintext workflow

### Security
- Master-password setup
- Argon2id key derivation with benchmarked, versioned parameters
- Authenticated encryption
- Random vault data key and key hierarchy
- Strict vault envelope and format version
- Automatic/manual lock
- Clipboard timeout
- No secrets in logs/analytics/crash reports
- Safe error handling and tamper detection

### Backup
- Manual encrypted export
- Restore validation
- Cloud provider authorization
- Upload/download ciphertext only
- Revision checks, conflict copies and version retention
- Clear status for sync failures

## Phase 2
- Google Drive and OneDrive background sync refinements
- Biometric convenience unlock backed by OS secure storage
- Browser extensions
- Android Autofill
- Apple AutoFill
- TOTP codes
- Importers, password audit and duplicate detection
- Better accessibility, localization and theming

## Explicitly out of scope for first release
- Self-hosted or vendor-operated sync server
- Shared vaults / organizations
- Emergency access
- Passkeys
- Breach-monitoring service
- Web app that can expose vault data to a remote runtime
- Any claim of independent audit or certification before it exists
