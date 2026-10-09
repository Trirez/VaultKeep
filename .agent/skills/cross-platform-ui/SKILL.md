---
name: cross-platform-ui
description: Use when building the desktop (Windows, macOS, Linux) or mobile (Android, iOS) frontends that sit on top of vaultkeep-core. Keeps all logic in Rust and the UI layer thin.
---

# Cross-Platform Frontends in Rust

## Goal
One Rust codebase for desktop and mobile where the UI is a thin layer over `vaultkeep-core`.

## Recommended approach
- Use **Tauri 2** (Rust backend, web UI) as the default shell. It targets desktop and Android/iOS from one project. Confirm current mobile support and setup steps in the official Tauri docs before starting, because the mobile toolchain changes often.
- Alternative if a pure-Rust UI is preferred: **Slint** or **Dioxus**. Pick one, do not mix.
- Create `crates/app` as a workspace member. Expose only small command functions (`unlock`, `lock`, `search`, `copy_password`, `add`, `update`, `remove`, `generate`).

## Rules
1. The UI never receives a password except for the explicit "reveal" or "copy" action. Lists use `EntrySummary` only.
2. Hold the open `Vault` in backend state behind a `Mutex<Option<Vault>>`. Locking sets it to `None`, which drops and zeroizes it.
3. No business logic in JavaScript/TypeScript. Validation and crypto stay in Rust.
4. Vault file location is chosen by the user (local folder or a cloud-synced folder such as Drive, OneDrive or Dropbox). The app syncs by reading and writing that one file; see the `vault-sync` notes in `docs/ARCHITECTURE.md`.
5. Platform integration lives behind a small trait (`SecureStore`, `Clipboard`, `Biometrics`) with per-OS implementations, so core logic stays testable on desktop CI.

## Steps
1. Scaffold `crates/app` and make a lock screen + vault list screen.
2. Wire commands to `vaultkeep-core`; add a Rust test per command.
3. Add auto-lock timer and clipboard clearing.
4. Add biometric unlock last (see `mobile-integration`).
