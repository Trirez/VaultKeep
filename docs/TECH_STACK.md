# Suggested Tools and Resources

## Core
- Flutter + Dart: cross-platform UI.
- Rust stable toolchain + Cargo workspace: security core.
- `flutter_rust_bridge`: typed Flutter/Rust integration.
- RustCrypto `argon2`: Argon2id key derivation.
- RustCrypto `chacha20poly1305`: authenticated encryption options.
- `zeroize`: best-effort clearing of sensitive buffers.
- `rand` / OS-backed CSPRNG interfaces: cryptographic random values; review the chosen crate and platform behavior.
- `serde` with a strict, versioned schema: serialization; do not treat serialization as validation.
- `thiserror` or equivalent: structured errors that do not include secrets.
- `proptest` and `cargo-fuzz`/libFuzzer: property and fuzz testing.

## Flutter / platform
- Flutter DevTools, Dart analyzer, `flutter_test`.
- Platform secure-storage plugin only after verifying platform-specific implementation, maintenance and backup behavior.
- Native platform APIs for Keychain, Android Keystore, Windows credential protection, and Linux secret services as appropriate.
- Android Autofill Framework and Apple AutoFill extensions later, not in the initial vault milestone.

## Cloud
- Google Drive API: compare `drive.file` and `appDataFolder` use cases; choose the least-privilege scope that fits the product.
- Microsoft Graph OneDrive app folder: `Files.ReadWrite.AppFolder` is designed for scoped app-folder access.
- OAuth 2.0 authorization code flow with PKCE where applicable; use official provider guidance and native-app best practices.
- A provider-neutral cloud interface so cloud SDKs do not enter the crypto core.

## Quality and security
- `cargo fmt`, `cargo clippy`, `cargo test`.
- `cargo audit` and `cargo deny` for dependency policy checks.
- Fuzz tests for all parsers/importers.
- GitHub Actions or another CI system; secret scanning; locked dependencies.
- OWASP MASVS and MASTG for mobile app security review.
- OWASP Cryptographic Storage Cheat Sheet.
- RFC 9106 for Argon2.
- NIST SP 800-63B guidance for authentication/password guidance where applicable.
- Independent cryptographic review before production.

## Official starting links
- Flutter supported platforms: https://docs.flutter.dev/reference/supported-platforms
- Flutter Rust Bridge: https://cjycode.com/flutter_rust_bridge/
- Argon2 crate: https://docs.rs/argon2/latest/argon2/
- RustCrypto AEAD: https://docs.rs/chacha20poly1305/latest/chacha20poly1305/
- OWASP Cryptographic Storage: https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html
- OWASP Password Storage: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
- OWASP MASVS: https://mas.owasp.org/MASVS/
- Google Drive API auth/scopes: https://developers.google.com/workspace/drive/api/guides/api-specific-auth
- Google Drive appDataFolder: https://developers.google.com/workspace/drive/api/guides/appdata
- Microsoft Graph OneDrive app folder: https://learn.microsoft.com/en-us/graph/onedrive-sharepoint-appfolder
- Google Antigravity Skills: https://www.antigravity.google/docs/skills
