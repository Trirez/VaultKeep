# Starter Prompts for Antigravity

Run these one at a time, after copying `.agents/` into the repository.

## 1. Start with planning
`/vault-planner Inspect this repository. Do not implement crypto yet. Produce a project inventory, open design decisions, a threat model draft, and a milestone plan. Identify missing docs and ask before making irreversible choices.`

## 2. Review the security boundary
`/security-review Review the planned Flutter/Rust/cloud architecture against docs/SECURITY_RULES.md. Do not modify code yet. Return prioritized findings and unresolved assumptions.`

## 3. Define the vault format
`/security-docs Draft a versioned encrypted vault envelope and key hierarchy proposal. Compare design options, document metadata leakage and recovery consequences, and clearly label the proposal as requiring independent review before implementation.`

## 4. Implement local-only Rust core
`/rust-vault-security Implement only the approved, documented local vault core in small steps. Do not add cloud sync. Add negative tests and run the available checks. Stop if the crypto design is not approved.`

## 5. Add Flutter bridge
`/flutter-rust-boundary Connect Flutter to the Rust core using the repository's selected bridge. Expose narrow typed operations only; do not expose raw key bytes. Add tests for bridge errors and lifecycle behavior.`

## 6. Add cloud provider
`/encrypted-cloud-sync Implement one cloud provider behind the provider-neutral interface. Review current official provider docs and OAuth scopes first. Upload ciphertext only, add revision checks, preserve conflicts, and test restore before replacement.`

## 7. Harden before release
`/test-hardening Build and run the security test matrix. Report exact commands and results, open risks, fuzzing coverage, and any checks that could not run. Do not claim the app is production-secure or audited.`
