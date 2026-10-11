# VaultKeep: Enpass 1:1 Feature Parity Roadmap

**Status:** Active Implementation Plan | **Prepared:** 11 October 2026  
**Architecture:** Flutter UI (`app/`) + Rust FFI Bridge (`app/rust/`) + Pure-Rust KDBX4 Core (`crates/core/`)  
**Reference Inputs:** `Screenshots/aas.txt` (Enpass OSS Notices) & `Screenshots/Enpass_*.png` (14 UI Reference Captures)

---

## 1. Goal

Deliver a **1:1 functional and UI experience matching Enpass Password Manager** inside **VaultKeep**, while preserving VaultKeep's strict **KDBX4 (Argon2id + ChaCha20-Poly1305)** interoperability with KeePassXC and its zero-knowledge Rust security boundary.

---

## 2. Architectural Decisions & Open-Source Stack Mapping

Enpass Desktop (`Screenshots/aas.txt`) is a C++/Qt application built around `sqlcipher`, `OpenSSL`, `zxcvbn`, `gtotp`, `tinycbor`, `srp`, `Starscream`, `qmdnsengine`, `qtkeychain`, `webdav`, `libcurl`, `CxxUrl`, `libzip`, `nlohmann/json`, `cppcodec`, `crossguid`, `zupply`, and `Sentry`.

In **VaultKeep**, we achieve 1:1 feature parity without sacrificing KDBX4 compatibility or introducing C++ memory-safety risks:

| Enpass Subsystem | Enpass OSS Library (`aas.txt`) | VaultKeep Implementation (Rust + Flutter) |
| :--- | :--- | :--- |
| **Encrypted Vault Engine** | `sqlcipher` + `OpenSSL` | `keepass = "0.15"` (`save_kdbx4`, `Argon2id`, `Value::Protected`) + `zeroize` (`crates/core/src/vault.rs`) |
| **Sequential UUIDs** | `crossguid` | `uuid = "1.27"` (`Uuid::now_v7()`) |
| **Password Generator & Entropy Audit** | `OpenSSL` + `zxcvbn` | `crates/core/src/generator.rs` (`OsRng` CSPRNG, pronounceable syllable generator, exact/minimum class counts, include/exclude/ambiguous sets, entropy + breach-pattern scorer) |
| **TOTP (One-Time Codes)** | `gtotp` + `cppcodec` | `keepass` (`totp` feature, RFC 6238) + `SegmentedAmberBar` countdown UI |
| **Passkeys (WebAuthn / FIDO2)** | `tinycbor` + `OpenSSL` | KDBX4 `KPEX_PASSKEY_*` protected fields + relying-party directory matcher |
| **Categories, Tags, Favorites, Archive/Trash** | `sqlcipher` tables | Standard KDBX4 custom fields (`VK_CATEGORY`, `VK_TAGS`, `VK_FAVORITE`, `VK_ARCHIVED`, `VK_TRASHED`) + KDBX4 entry tags (`entry.tags`) |
| **Auto Backups (Last 60 Preserved)** | `libzip` | Atomic KDBX4 snapshot rotation (`Vault::create_backup`) preserving the latest 60 encrypted `.kdbx` backups |
| **Cloud & Folder Sync** | `libcurl` + `webdav` | KDBX4 3-way merge (`Vault::sync_with_file`) for local/cloud-mounted folders (Google Drive, OneDrive, iCloud, Dropbox, Box, NextCloud, WebDAV) |
| **Wi-Fi Sync & Browser Autofill** | `qmdnsengine` + `srp` + `Starscream` + `CxxUrl` | Strict host/subdomain matcher (`find_for_domain`) + Autofill & Wi-Fi Sync configuration surfaces |

---

## 3. Phased Task Breakdown (Mapped to the 14 Screenshots)

### Phase 1 — Rust Core: Advanced Password Generator, Audit Engine & Rolling Backups (`crates/core`)
- **Target Screenshots:** `Enpass_UNGNDpANfa.png`, `Enpass_4B5a9NsMjk.png`, `Enpass_5dPDQrZflh.png`, `Enpass_H1MKK11Thm.png`
- **Files:** `crates/core/src/generator.rs`, `crates/core/src/vault.rs`, `crates/core/src/lib.rs`, `crates/core/tests/vault.rs`, `crates/core/tests/security.rs`
- **Deliverables:**
  1. **Enpass 1:1 Password Generator (`PasswordPolicy`)**:
     - Support `length` (`4..=256`), `pronounceable` (syllable-based passphrases), `upper`, `digits`, `symbols`, `exact_mode` (`Minimum` vs `Exactly` class counts), `min_upper`, `min_digits`, `min_symbols`, `exclude_chars`, `include_chars`, and `allow_ambiguous` (`0`, `O`, `1`, `l`, `I`).
  2. **Zero-Knowledge Password Audit & Strength Engine**:
     - Evaluate password strength (`Excellent`, `Good`, `Moderate`, `Weak` + `0..=100` score) and common/breached patterns entirely in Rust so plaintext passwords never cross FFI for list/audit views.
     - Detect **Identical (reused)** passwords across vault entries inside `Vault::search` without exposing plaintext passwords.
     - Detect **2FA-Supported** websites (`is_two_fa_supported`), **Passkey-Supported** websites (`is_passkey_supported`), and **Expired / Old** passwords (`3-6 Months`, `6-12 Months`, `1-3 Years`).
  3. **Enpass Categories, Tags, Favorites, Archive & Trash**:
     - Persist `category` (`Login`, `Credit Card`, `Identity`, `Note`, `Password`, `Finance`, `License`, `Travel`, `Computer`, `Miscellaneous`), `tags`, `is_favorite`, `is_archived`, `is_trashed`, `is_compromised`, and `is_expired` in KDBX4 custom fields.
  4. **Rolling 60-Snapshot Auto Backup (`Vault::create_backup`)**:
     - Atomically write timestamped encrypted `.kdbx` backups to the configured backup directory and prune snapshots beyond the most recent 60 files.

### Phase 2 — FFI Bridge & Dart Backend Layer (`app/rust` & `app/lib`)
- **Files:** `app/rust/src/api/vault.rs`, `app/rust/src/session.rs`, `app/lib/backend.dart`, `app/lib/rust_backend.dart`, `app/lib/vault_controller.dart`
- **Deliverables:**
  1. Expose advanced password generation (`generate_password_custom`), rolling backup creation (`create_vault_backup`), and enriched non-secret `EntryItem` / `EntryDetails` / `EntryData` structs over `flutter_rust_bridge`.
  2. Regenerate bindings with `flutter_rust_bridge_codegen generate`.
  3. Extend `VaultController` with computed **Security Score (`0..=100`)**, audit counters, category/tag filters, sort modes (`Title`, `Username`, `URL`, `Last Modified`), and reactive Enpass settings state.

### Phase 3 — Enpass 1:1 UI Components (`app/lib/screens/`)
- **Target Screenshots:** All 20 screenshots (`Enpass_UNGNDpANfa.png` – `Enpass_AnOaTZCopB.png`)
- **Files:**
  - `app/lib/screens/home_dashboard_pane.dart` (New)
  - `app/lib/screens/password_generator_sheet.dart` (New)
  - `app/lib/screens/enpass_settings_dialog.dart` (New)
  - `app/lib/screens/vault_screen.dart` (Updated)
  - `app/lib/screens/entry_screen.dart` (Updated)
- **Deliverables:**
  1. **Home Security Score Dashboard (`home_dashboard_pane.dart`)**:
     - Security Score progress banner (`0–100` + rating label), Total Items counter, and 8 clickable audit cards (`Excellent`, `Compromised`, `Weak`, `Passkey Supported`, `Breached`, `Identical`, `2FA-supported`, `Expired`).
  2. **Full Enpass Left Sidebar (`vault_screen.dart`)**:
     - `Primary` vault selector header, `Home`, `Favorites`, all 10 **Categories** (`Login`, `Credit Card`, `Identity`, `Note`, `Password`, `Finance`, `License`, `Travel`, `Computer`, `Miscellaneous`), **Tags**, **Groups (`Group Tree`)**, **Audit** (`Excellent`, `Compromised`, `Weak`, `Identical`, `Breached`, `Passkey Supported`, `2FA Supported`, `Expired`, `1-3 Years old`, `3-6 Months old`, `6-12 Months old`), and **Others** (`Passkeys`, `One-time Codes`, `Attachments`, `Archived`, `Trashed`).
  3. **Alphabetical Item Grouping & Sort Bar (`vault_screen.dart`)**:
     - `Sort By: Title` dropdown and alphabetical section headers (`0-9`, `A`, `B`, `C`...) with toggleable subtitles and item counts.
  4. **Slide-Over / Modal Password Generator & Generator History (`password_generator_sheet.dart`, `entry_screen.dart`, `Enpass_5dPDQrZflh.png`, `Enpass_rfEIu8FoJV.png`)**:
     - Color-coded password preview, strength badge, `Length` slider, `Pronounceable` switch, `Uppercase`/`Digits`/`Symbols` switches, `Using: Minimum | Exactly` sliders, `Exclude`/`Include` character filter, and `Ambiguous Characters` toggle.
     - **Generator History (`Enpass_rfEIu8FoJV.png`)**: Popover listing recently generated passwords with domain/context label, masked password with eye reveal toggle, timestamp, and 1-click `Fill` button.
  5. **Enpass Item Editor: Add Field / Add Section / Add Attachment, Additional Details & Field Options (`entry_screen.dart`, `Enpass_RUtKiX9m54.png` – `Enpass_AnOaTZCopB.png`)**:
     - Top action bar with `Cancel`, `Add v` dropdown (`Add Field`, `Add Section`, `Add Attachment`), and `Save` button (`Enpass_AnOaTZCopB.png`).
     - Structured `ADDITIONAL DETAILS` section (`E-mail`, `Phone number`, `One-time code`, `Security question`, protected `Security answer`), dynamic user-defined `Section` headers, `Tags` input, and `Drag and drop or click here to attach files` attachment zone (`Enpass_RUtKiX9m54.png`, `Enpass_HV9F8dBiu5.png`).
     - Per-field drag handle (`≡`) and `•••` menu opening the **`Field Options`** modal (`Enpass_1xVwnTUhyR.png`, `Enpass_ETlwI2CT5x.png`) with `Field Name`, `Field Type` selector (`Username`, `E-mail`, `Password`, `URL`, `Phone`, `One-time Code`, `Multiline`, `Cardholder Name`, `Card Number`, `CVC`, `PIN`, `Text`), `Sensitive` toggle switch, `Delete Field`, and `Save`.
  6. **8-Tab Enpass Settings Dialog (`enpass_settings_dialog.dart`)**:
     - `General`, `Vaults` (including `Add New Vault -> Select Storage` with OneDrive, Google Drive, iCloud, Dropbox, Box, WebDAV, NextCloud, Wi-Fi Sync, Folder Sync, This PC), `Security` (Windows Hello, PIN, Master Password rotation, Autolock triggers), `Customize` (Appearance, Sidebar counts, Subtitles, Old passwords in Audit, Website Icons, Categories & Templates), `Autofill` (Browser Extensions & Code Signature Verification), `Backup` (Auto Backups & 60-backup retention), `Wi-Fi Sync` (Local Wi-Fi Sync Server control), `Advanced` (Compromised password check, Proxy, SSL pinning, Pre-Shared Keys, Clipboard check, Alerts, Logs, Reset), and `About` (Open-Source Licenses).

---

## 4. Security Risks & Guardrails

1. **Zero Secret Leakage in Audit Views**: Password strength (`Excellent`/`Weak`), compromised check, and duplicate detection (`Identical`) **must** execute inside `crates/core` in Rust. `EntrySummary`, `EntryItem`, and `VaultItem` must never carry plaintext passwords or password hashes.
2. **Optimistic Concurrency & Atomic Persistence**: Updating an entry's category, tags, favorite, archive, or trash state must preserve `last_known_revision_date` checks and save via atomic `tempfile` + `sync_all` + `persist`.
3. **Secret Controller Hygiene**: All password, PIN, and Pre-Shared Key `TextEditingController`s in dialogs and sheets must disable IME learning/suggestions/autocorrect and clear their text buffers in `dispose()` / `finally`.

---

## 5. Verification & Acceptance Criteria

- `cargo fmt --all -- --check` passes with 0 diffs.
- `cargo clippy --workspace --all-targets -- -D warnings` passes with 0 warnings.
- `cargo test --workspace` passes all existing and new unit/adversarial tests.
- `flutter analyze` reports `No issues found!`.
- `flutter test` passes all existing and new controller/widget/layout tests across mobile (`360x640`) and desktop (`1920x1080`) viewports.

---

## 6. Deferred Work (Post-Local Parity)

- Live OAuth 2.0 cloud transport adapters (Google Drive, OneDrive, Dropbox, Box, iCloud, WebDAV) and live mDNS/SRP/WebSocket network listeners remain gated behind M6 so the local-first app maintains its zero-network security posture until explicitly enabled.
