---
name: flutter-frontend
description: Use when building or changing the Flutter UI (unlock, entry list, entry edit, settings) of the password manager for Android, iOS, Windows, macOS and Linux. Keeps all logic in Rust and the Dart layer thin.
---

# Flutter Frontend

## Goal
A small, clean Flutter app in `app/` that only presents state. Every secret operation (open, save, generate, search) happens in Rust.

## Layout
```
app/lib/
  main.dart            init Rust, pick default vault path, run app
  app.dart             MaterialApp, auto-lock on background, closes pushed routes on lock
  vault_controller.dart  ChangeNotifier: status, items, search, idle auto-lock
  backend.dart         plain Dart models + VaultBackend interface (no Rust imports)
  rust_backend.dart    the ONLY file importing generated bindings (src/rust/)
  clipboard_guard.dart copy with timed clear
  screens/             unlock, vault list, entry edit
app/test/              controller tests using a FakeBackend (no native library needed)
```

## Rules
1. Screens and the controller depend on `VaultBackend`, never on `src/rust/`. This keeps `flutter test` runnable without Rust.
2. No crypto, KDBX parsing, or password generation in Dart.
3. `VaultItem` and `VaultEntry` carry no password. Only `revealPassword` returns one; call it only for copy, reveal or the edit screen.
4. Never log secrets. No `print`/`debugPrint` of form values; `EntryDraft` intentionally has no `toString`.
5. Anything pushed on the Navigator must be closed when the vault locks (see `_closeRoutesWhenLocked` in `app.dart`).
6. Layouts must work from a 360 px phone to a wide desktop window (constrain content width, scroll on small heights).
7. Keep `ChangeNotifier` + `ListenableBuilder`. Do not add a state-management package without a concrete need.
8. Do not add a network permission or dependency. The app has no internet access until sync is deliberately built.

## Adding a feature (in this order)
1. Core: implement and test in `crates/core` (skill `vault-core-dev`).
2. Bridge: expose it in `app/rust/src/api/vault.rs` and regenerate (skill `flutter-rust-bridge`).
3. Dart: add the method to `VaultBackend`, implement it in `RustBackend`, and update `FakeBackend` in `app/test/`.
4. Controller: add the method plus a test in `app/test/vault_controller_test.dart`.
5. UI: build the screen last.

## Verify
```
cd app && flutter analyze && flutter test
```
Run the app on at least one desktop target and say which targets were actually tried.
