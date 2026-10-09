Run the full verification pass for VaultKeep.

1. Run `cargo fmt --check` and fix formatting if it fails.
2. Run `cargo clippy --all-targets -- -D warnings` and fix every warning.
3. Run `cargo test` and report the pass/fail counts.
4. In `app/`, run `flutter analyze` and `flutter test` (skip with a note if Flutter is not installed or bindings are not generated yet).
5. Apply the `security-review` skill to the diff since the last commit.
6. Summarize results in a short list. State clearly anything that could not be run.
