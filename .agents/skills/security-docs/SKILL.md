---
name: security-docs
description: Maintains threat models, cryptographic design notes, vault format specifications, data-flow diagrams, security rules, recovery documentation, and user-facing privacy/security explanations for a password manager.
---

# Security Documentation

## Required documents
- Threat model and trust boundaries
- Cryptographic design with key hierarchy and algorithms
- Vault envelope and format-version specification
- Key rotation and recovery model
- Cloud data-flow and OAuth scope table
- Sync conflict and restore behavior
- Platform storage and autofill notes
- Security testing matrix
- Privacy policy/data inventory
- Vulnerability disclosure and incident response process

## Rules
- Document actual behavior, not intended behavior.
- State what cloud providers can observe, including metadata.
- Explain master-password loss and recovery limitations clearly.
- Distinguish backup, sync, export and recovery.
- Record why algorithms and parameters were selected and how they are upgraded.
- Every format change needs compatibility, migration and rollback notes.
- Never include real passwords, tokens, keys or production vaults in examples.
- Never claim audit, compliance or security certification unless evidence exists.

## Change process
When code changes a security property, update the relevant document and tests in the same task. Flag design decisions that need security review instead of guessing.
