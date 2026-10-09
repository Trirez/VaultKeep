# Threat Model Template

Do not start implementation of cryptographic workflows until this is filled and reviewed.

## Assets
- Master password (in memory only)
- Key-encryption key / derived key
- Vault data-encryption key
- Decrypted entries and secure notes
- Encrypted vault file and historical backups
- OAuth access/refresh tokens
- Recovery key
- Build and release signing credentials

## Trust boundaries
- Flutter UI <-> Rust core FFI
- Rust core <-> local filesystem
- App <-> OS secure storage
- App <-> Google Drive / Microsoft Graph
- Imported file <-> vault parser
- Debug/test tooling <-> sensitive runtime data

## Adversaries and risks
- Lost or stolen device
- Malware running as the same user
- Compromised cloud account
- Malicious or compromised cloud response
- Offline attacker with a copied vault file
- Malformed vault/import file
- Accidental overwrite, deletion or corrupted sync
- Malicious dependency or compromised build pipeline
- Memory scraping / screen capture / clipboard leakage
- Weak or reused master password

## Security goals
- Cloud provider sees ciphertext, not plaintext vault data or keys.
- Vault tampering is detected.
- Wrong passwords and invalid files fail closed.
- Sync never silently loses a concurrent change.
- Restore can be tested and verified.
- Secrets are excluded from logs and telemetry.

## Explicit limitations to document
- A compromised unlocked device may expose plaintext.
- A weak master password can permit offline guessing if an attacker gets the vault file.
- Cloud providers can observe some metadata such as file size and timestamps.
- Clipboard managers, screenshots and OS memory behavior may create residual exposure.
- No cryptographic design can recover a lost master password unless a separately designed recovery mechanism exists.
- End-to-end encryption does not prevent deletion or denial of service by a cloud account/provider.

## Review record
- Reviewer:
- Date:
- Open findings:
- Accepted residual risks:
- Approval before implementation:
