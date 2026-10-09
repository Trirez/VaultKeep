---
name: mobile-integration
description: Use when adding Android or iOS specific features to the Flutter password manager, such as biometric unlock, screenshot protection, background locking, or system autofill.
---

# Mobile Integration (Flutter)

## Goal
Add mobile-only features without weakening the vault's security model.

## Already done
- Locks when the app goes to the background (`AppLifecycleState.paused` in `app.dart`) and after 2 minutes idle.

## Screen and app-switcher protection
- Android: set `FLAG_SECURE` on the activity (small platform channel in `MainActivity`, or a maintained package; check its recent release history first).
- iOS: cover the window with a blank view when the app becomes inactive so the app switcher shows no secrets.

## Biometric unlock (opt-in, off by default)
- Biometrics only confirm the user is present. They do not replace the master password for the first unlock after install, reboot, or a biometric enrollment change.
- If offered, store the master password only encrypted by a hardware-backed key (Android Keystore / iOS Keychain with biometric access control) that is invalidated when biometrics change.
- `local_auth` handles the prompt, but it does not bind a key to the biometric. Use a package or platform channel that does (evaluate `biometric_storage` or write a small channel) and verify it is maintained before adding it.
- Tell the user plainly that this trades some security for convenience.

## Autofill
- Android `AutofillService` (Kotlin) and iOS Credential Provider extension (Swift) run outside the Flutter engine, so they need the Rust core built for their own targets and access to the vault file (iOS: App Group container).
- Only fill after the user authenticates, and match on verified app package or web domain, never on a page title.
- Treat this as a separate milestone after the core app is stable.

## Permissions
Do not add the INTERNET permission (Android) or network entitlements until sync is deliberately built.

## Testing
- Unit-test logic with fakes on desktop.
- Biometrics, autofill and screen protection need a real device. Say they were not tested if they were not.
