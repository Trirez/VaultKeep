---
name: rust-vault-security
description: Implements or reviews Rust code for a password manager's cryptographic core, key derivation, authenticated encryption, vault parsing, key lifecycle, and secret handling. Use for security-sensitive Rust backend changes.
---

# Rust Vault Security

## Before changing code
1. Read `docs/THREAT_MODEL_TEMPLATE.md`, `docs/SECURITY_RULES.md`, and the vault format/crypto design.
2. Inspect current dependencies and API boundaries.
3. If no approved crypto design exists, stop before implementing cryptographic primitives. Propose a design review first.
4. State assumptions and identify whether the change affects file compatibility or key rotation.

## Implementation rules
- Use maintained, reviewed crates and standard constructions; never invent algorithms.
- Prefer a random data-encryption key wrapped by a key derived from the master password, with a documented recovery strategy.
- Use Argon2id with parameters benchmarked for supported hardware and recorded in a versioned envelope.
- Use a reviewed AEAD construction; enforce nonce requirements and authenticate relevant envelope metadata.
- Use OS-backed cryptographic randomness.
- Parse untrusted input with strict bounds before large allocations.
- Fail closed on wrong passwords, authentication failures, malformed files and unknown critical versions.
- Keep crypto APIs narrow and typed. Avoid exporting raw keys or plaintext more widely than necessary.
- Use structured errors that never include secrets or decrypted content.
- Minimize `unsafe`; any unavoidable unsafe code needs a safety comment, isolated module and explicit review.
- Use `zeroize` where appropriate, but never promise perfect memory erasure.
- Never log secrets, key bytes, serialized plaintext, or sensitive FFI arguments.

## Required tests
- Round-trip encrypt/decrypt.
- Wrong password fails.
- Bit-flipped ciphertext fails authentication.
- Truncated, oversized and malformed envelopes fail safely.
- Unknown algorithm/version fails without downgrade.
- Serialization property tests and parser fuzzing.
- Ensure error/log output contains no secrets.
- Check compatibility/migration tests for every format change.

## Commands
Inspect project scripts and CI first. Typical checks:
- `cargo fmt --all -- --check`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test --workspace`
- dependency audit and fuzz targets where configured

Do not state checks passed unless you ran them and saw the result.
