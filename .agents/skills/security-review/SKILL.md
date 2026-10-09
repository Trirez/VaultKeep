---
name: security-review
description: Performs a security-focused review of a Flutter and Rust password manager, checking threat boundaries, cryptography, secret handling, cloud permissions, sync conflicts, and release blockers.
---

# Security Review

## Review stance
Assume all files, cloud responses, imports, IPC/FFI inputs, and provider metadata may be malicious. Review for exploitability and user impact, not just style.

## Review checklist
- Is there an approved threat model and documented crypto design?
- Are standard, maintained cryptographic libraries used correctly?
- Is key derivation memory-hard and parameterized for target devices?
- Are salts/nonces generated correctly and are nonce uniqueness rules respected?
- Is authenticated encryption checked before plaintext is trusted?
- Are key roles separated and key rotation/recovery documented?
- Can malformed input cause panic, excessive allocation, path traversal or unsafe deserialization?
- Can secrets enter logs, telemetry, errors, crash reports, clipboard or app-switcher previews?
- Are OAuth permissions least-privilege and tokens stored securely?
- Does any cloud request include plaintext or key material?
- Can a revision race overwrite a valid vault?
- Does restore preserve the old vault until the candidate is verified?
- Are FFI and `unsafe` boundaries narrow and documented?
- Are tests, fuzzing, dependency review and platform checks present?
- Are claims and documentation accurate about remaining limitations?

## Output
Report:
1. Finding and severity (Critical/High/Medium/Low/Informational).
2. File/function and relevant code path.
3. Attack preconditions and user impact.
4. Evidence and reproduction/test.
5. Remediation.
6. Regression test.
7. Any uncertainty or unverified assumptions.

Do not report “no issues” if key design or important paths were not inspected. Do not claim an independent audit.
