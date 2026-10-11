---
name: prelogin-auth-tokenables
description: >-
  Implement enumeration-resistant prelogin KDF negotiation and factory-minted
  cryptographic security tokens for VaultKeep authentication flows. Use when creating
  or reviewing login/prelogin endpoints, email verification tokens, WebAuthn challenges,
  session tokens, or invite/recovery tokens.
---

# Enumeration-Resistant Prelogin & Factory-Minted Tokenables

## Scope
Applies to local WebAuthn/passkey assertion challenge factories (`crates/core/src/passkey.rs`) in M0–M5, and to VaultKeep M6+ cloud sync authentication, prelogin KDF lookup, registration verification, and time-limited security tokens.

## Core Security Patterns (Adapted from Bitwarden `AccountsController` & `auth-tokenables`)

### 1. Prelogin KDF Enumeration Protection
When a client requests KDF parameters (`KdfType`, iterations, memory, parallelism, salt) for an email/identifier before login:
- **Never return `404 Not Found` or a static single fallback** that distinguishes non-existent users or changes randomly across requests.
- **Normalize the identifier** first: `email.trim().to_lowercase()`.
- **Deterministic HMAC Fallback Pool**:
  - Maintain a weighted static pool of realistic KDF configurations (e.g., default `PBKDF2 600k`, `Argon2id 6/32MB/4`, `Argon2id 3/64MB/4`).
  - If the user does not exist, compute `HMAC-SHA256(server_kdf_hmac_secret, normalized_email)` to deterministically select an index from the KDF pool, and `HMAC-SHA256(server_kdf_hmac_secret, normalized_email + ":salt")` to deterministically select/derive the salt representation.
  - Return a deep copy so repeated prelogin queries for the same non-existent email always yield identical KDF parameters in constant-like time.

### 2. Factory-Minted Security Tokens (`Tokenables`)
- **No Ad-Hoc Construction**: Security-relevant tokens (email verification, WebAuthn challenge options, recovery, device approval) MUST NEVER be instantiated via raw `new` / struct literals at call sites.
- **Dedicated Token Factory**:
  - Define an `I{Name}TokenableFactory` (or Rust trait/module factory) registered in dependency injection.
  - Keep the token's lifetime-setting constructor `internal` / module-private (`pub(crate)` in Rust) so callers outside the factory cannot mint tokens with arbitrary or missing expiration dates.
- **Configuration-Driven Expiry**:
  - The factory MUST set `expiration_date` from a centralized configuration setting (never hardcoded at the call site) and bind a shared validator + scope enum (e.g., `Authentication` vs. `Registration`) before sealing/protecting the token.

## Review & Validation Steps
1. Grep for direct token struct instantiation outside factory modules.
2. Verify that every token validates: (a) cryptographic signature/AEAD tag, (b) `expiration_date > UtcNow`, (c) expected scope/purpose, and (d) subject binding (e.g., normalized email or user ID).
3. Test prelogin responses for both existing and non-existent accounts to confirm identical schema and deterministic repeatability across casing variations (`User@Example.com` vs `user@example.com`).
