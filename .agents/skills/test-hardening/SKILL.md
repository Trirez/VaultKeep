---
name: test-hardening
description: Builds security and reliability tests for a Rust encrypted vault and Flutter app, including fuzzing, property tests, tamper tests, sync race tests, restore drills and secret-leak checks.
---

# Test Hardening

## Priorities
1. Crypto envelope and parser negative tests.
2. Key lifecycle and lock/unlock tests.
3. FFI boundary and error-redaction tests.
4. Backup restore and cloud conflict tests.
5. Cross-platform lifecycle and secure-storage tests.

## Test cases
- Correct password unlocks; wrong password fails without partial plaintext.
- Any ciphertext/tag modification is rejected.
- Truncated, oversized, malformed and deeply nested input fails safely.
- Unknown critical version/algorithm is rejected; no downgrade.
- KDF parameters outside safe policy are rejected before expensive allocation/work.
- Random generation uses a CSPRNG-backed implementation.
- Error paths, logs, traces and crash reporting contain no test secrets.
- Interrupted writes preserve the last known-good vault.
- Concurrent cloud revisions preserve both candidates or create an explicit conflict.
- Restore verifies the downloaded envelope before swapping active state.
- OAuth revoked, offline, quota exceeded and provider timeout states do not lose local data.
- Lock, background, suspend/resume and app termination do not leave the UI showing unlocked secrets.
- Importers reject malformed and oversized files.

## Fuzzing
Create fuzz targets for envelope parsing, deserialization, importers, migration and any custom binary format. Keep fuzz corpora synthetic and free of real credentials. Bound runtime and memory in CI.

## Reporting
Only claim tests passed if executed. Include command, environment, test count and failures. Treat flaky security tests as unresolved until explained.
