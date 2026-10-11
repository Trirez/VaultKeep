---
name: flutter-frontend
description: >-
  Use when building, refactoring, or reviewing the Flutter UI (unlock, vault list,
  inspector pane, entry form, dialogs, or controller state) of VaultKeep across
  desktop and mobile. Enforces strict Rust/Dart boundaries, thin composable
  widgets, secret-input hygiene, and lock-safe async state.
---

# Flutter Frontend

## Goal
A thin, security-hardened Flutter presentation layer in `app/` modeled on Bitwarden's client architecture (`libs/common` vs. `libs/vault`). Every cryptographic, KDBX4, search, and password/TOTP generation operation happens in Rust.

## Layout
```
app/lib/
  main.dart              init Rust, pick default vault path, run app
  app.dart               MaterialApp, auto-lock on background, closes pushed routes on lock
  theme.dart             TacticalTheme semantic tokens and shared security UI primitives
  vault_controller.dart  ChangeNotifier: status, items, groups, filters, search, idle auto-lock
  backend.dart           plain Dart models + VaultBackend interface (no Rust or Flutter UI imports)
  rust_backend.dart      the ONLY file importing generated bindings (src/rust/)
  clipboard_guard.dart   copy with timed 15s clear and lock wipe
  screens/               unlock, vault list/inspector, entry view/edit, file picker
app/test/                controller and widget tests using FakeBackend (no native library needed)
```

## Critical Architecture & Security Rules
1. **Strict Boundary (`VaultBackend` only)**: Screens and `VaultController` depend exclusively on `VaultBackend` (`backend.dart`), never on `src/rust/`. Keep `backend.dart` free of Flutter UI and Rust FFI imports so `flutter test` runs pure Dart tests with `FakeBackend`.
2. **Zero Crypto in Dart**: Never implement encryption, KDBX parsing, URI domain parsing for autofill, TOTP computation, or password/passkey generation in Dart.
3. **List vs. Detail Secret Separation**:
   - `VaultItem` (list summary) and `VaultEntry` (detail view) carry **no plaintext password**.
   - Call `revealPassword(id)` only on explicit user intent (copy, reveal toggle, or opening edit mode).
4. **Zero Secret Logging**: Never `print`, `debugPrint`, or include form values, passwords, or OTP URIs in error messages or analytics. `EntryDraft` intentionally omits `toString()`.
5. **Lock-Safe Lifecycle & Async Guards**:
   - Locking (`controller.lock()`) must clear in-memory `items`, `groups`, `query`, and active inspector selection *before* awaiting backend lock, wipe `ClipboardGuard`, and pop all pushed Navigator routes (`_closeRoutesWhenLocked` in `app.dart`).
   - Every async callback (`search`, `_load`, `_refreshTotp`) must check `mounted` and `controller.status == VaultStatus.unlocked` (plus sequence IDs where applicable) after `await` so stale responses never populate a locked UI.
6. **Secret Input & Inspector Reset Hygiene**:
   - Every password, master-password, or OTP secret `TextField` must set `obscureText: !_show`, `enableSuggestions: false`, `autocorrect: false`, and `enableIMEPersonalizedLearning: false`.
   - When `EntryScreen` is embedded in the desktop split-pane inspector, `didUpdateWidget` **must** cancel active TOTP timers, reset `_show = false` and `_showOtp = false`, and clear all `TextEditingController` buffers before loading the newly selected entry.
   - Always overwrite (`controller.text = ''`) and `dispose()` secret `TextEditingController` instances in `dispose()` or `finally` blocks for dialogs.
7. **Thin Composable Widgets**:
   - Keep screens focused on layout orchestration. Extract reusable sections (e.g., login credentials section, passkey card, TOTP bar, attachment list, sidebar filter tree) into standalone `StatelessWidget`/`StatefulWidget` classes rather than growing monolithic screen files.
   - Follow existing patterns in the file you are editing; do not introduce third-party state-management packages (`ChangeNotifier` + `ListenableBuilder` is standard).
8. **Responsive Split-Pane & Mobile Adaptation**:
   - Support 360 px mobile viewports (single-column list + pushed `EntryScreen` route + drawer filters) through wide desktop viewports (3-pane layout: sidebar filter tree, virtualized `ListView.builder` item list, embedded inspector pane).
9. **Zero Network Access**: Do not add `INTERNET` permissions, HTTP clients, or remote font/favicon fetches. Use offline `TacticalDomainAvatar` badges.

## Adding a feature (in this order)
1. Core: implement and test in `crates/core` (skill `vault-core-dev`).
2. Bridge: expose it in `app/rust/src/api/vault.rs` and regenerate (skill `flutter-rust-bridge`).
3. Dart: add the method to `VaultBackend`, implement it in `RustBackend`, and update `FakeBackend` in `app/test/`.
4. Controller: add the method plus a test in `app/test/vault_controller_test.dart`.
5. UI: build or update the screen/section using `TacticalTheme` tokens (skill `vault-ui-components`) and add widget tests.

## Verify
```powershell
cd app && flutter analyze && flutter test
```
Run the app on at least one desktop target and say which targets were actually tried.
