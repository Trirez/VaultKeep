---
name: vault-ui-components
description: >-
  Use when designing, building, styling, or auditing Flutter UI components,
  dialogs, credential cards, or design-system widgets in VaultKeep. Applies
  Bitwarden's component library standards adapted to VaultKeep's TacticalTheme:
  semantic design tokens, color-coded accessible passwords, protected clipboard
  actions, live TOTP indicators, deterministic widget keys, and state-matrix
  verification.
---

# VaultKeep UI Component & Design System Guide

Distilled from Bitwarden's `@bitwarden/components` and `@bitwarden/vault` frontend patterns, adapted to VaultKeep's **Tactical Carbon & Amber** (`TacticalTheme`) Flutter design system.

## 1. Semantic Design Tokens Only (No Raw Hex or Ad-Hoc Styles)
Just as Bitwarden enforces semantic theme tokens over raw CSS values:
- **Never hardcode raw `Color(0xFF...)` values inside screen or widget files.** Always reference semantic tokens from `TacticalTheme` in `app/lib/theme.dart`:
  - **Surfaces**: `bgDeepCarbon` (scaffold/inputs), `bgPanel` (headers/sidebars/dialogs), `bgSurface` (cards/rows), `bgElevated` (action squares/snackbars), `bgHover` (interactive hover).
  - **Borders**: `borderSubtle` (dividers), `borderTech` (1px structural borders), `borderFocus` (active input/selection highlight).
  - **Accents**: `amberPrimary` / `amberBright` / `amberDim` (primary actions, security badges), `cyanTactical` / `cyanDim` (secondary actions, passkeys, links), `emeraldReady` / `emeraldDim` (active/verified status), `crimsonDanger` (destructive actions, urgent TOTP `<= 20%`, errors).
  - **Typography**: Use `TacticalTheme.monoStyle(...)` for all technical identifiers, passwords, TOTP codes, file paths, and telemetry headers.
- If a new semantic color or shared widget is needed, add it to `TacticalTheme` in `app/lib/theme.dart` rather than scattering inline styles.

## 2. Password-Manager Component Patterns (From Bitwarden `libs/components` & `libs/vault`)

### A. Color-Coded & Screen-Reader-Safe Passwords (`color-password` pattern)
When displaying revealed passwords or generated credentials:
- Render in `TacticalTheme.monoStyle` so ambiguous characters (`0`/`O`, `1`/`l`/`I`) are distinguishable, optionally coloring digits (`cyanTactical`) and symbols (`amberBright`) distinct from letters (`textPrimary`).
- **Accessibility (`Semantics`)**: Screen readers group adjacent letters into spoken words and collapse spaces. When exposing a revealed password to `Semantics`, provide a character-by-character label joined by commas with literal spaces replaced by `"space"` (e.g., `password.split('').map((c) => c == ' ' ? 'space' : c).join(', ')`), matching Bitwarden's `accessiblePassword` pattern. Never expose masked passwords to `Semantics` values.

### B. Protected Copy Actions (`copy-click` & `copy-cipher-field` pattern)
- Every copy button (`TacticalActionSquare` or menu item) must:
  1. Route through `ClipboardGuard.copySecret(value)` so the clipboard auto-clears after 15 seconds and wipes immediately on vault lock.
  2. Display a floating `SnackBar` naming the specific field copied: `"<Field Name> copied. Clears in 15 seconds."`
  3. Include a descriptive `Tooltip` (e.g., `'Copy username'`, `'Copy password'`, `'Copy TOTP code'`).

### C. TOTP Countdown & Token Display (`totp-countdown` pattern)
- Use `SegmentedAmberBar(fraction: remaining / period)` from `theme.dart`.
- When `fraction <= 0.2` (last 6 seconds of a 30s period), the bar automatically shifts from `amberPrimary` to `crimsonDanger` to warn the user before token roll-over.
- Format 6-digit TOTP codes with a middle space (`123 456`) in `TacticalTheme.monoStyle` for fast visual scanning, while copying the raw unspaced digits (`123456`) to `ClipboardGuard`.
- Always cancel the periodic 1-second timer in `dispose()`, `didUpdateWidget` (when entry ID changes), and when the vault locks.

### D. Secret Form Fields & Destructive Confirmations
- All secret `TextField`s must set:
  ```dart
  obscureText: !_show,
  enableSuggestions: false,
  autocorrect: false,
  enableIMEPersonalizedLearning: false,
  ```
- Destructive actions (deleting an entry, removing a passkey, deleting an attachment, or overwriting/merging a vault) must require explicit confirmation via an `AlertDialog` styled with `crimsonDanger` or `amberPrimary` borders, and must clean up any dialog `TextEditingController`s in a `finally` block.

## 3. Deterministic Automation Keys & Accessibility
Adapted from Bitwarden's `<component>_<element>_<name>` QA ID rule:
- Give key interactive inputs and buttons predictable `ValueKey`s formatted as `<screen>_<element>_<name>` (e.g., `ValueKey('unlock_input_master_password')`, `ValueKey('unlock_button_submit')`, `ValueKey('vault_input_search')`, `ValueKey('entry_button_save')`).
- Ensure every icon-only button (`IconButton`, `TacticalActionSquare`) has a non-empty `tooltip` (which also provides the accessibility label).
- Support keyboard navigation on desktop: `onSubmitted` on text fields, `Enter`/`Space` activation on custom `InkWell` rows, and `Escape` to dismiss dialogs.

## 4. Component State Matrix & Verification
Before declaring a UI component or screen change complete, verify all 6 visual/behavioral states:
1. **Default / Populated state** (normal items, groups, badges)
2. **Selected / Active state** (desktop split-pane inspector selection, active filter chip)
3. **Loading / Busy state** (disabled submit buttons, progress indicator during KDBX4 Argon2id unlock/save)
4. **Empty state** (empty vault prompt, no search results match filter)
5. **Error state** (wrong master password banner, invalid file path, corrupt vault toast)
6. **Locked transition state** (route popping, inspector reset, secret controller clearing)

Run static analysis and widget/layout tests:
```powershell
cd app && flutter analyze && flutter test
```
