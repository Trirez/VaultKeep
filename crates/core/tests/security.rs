use std::{
    fs::{self, File},
    io::Write,
};

use proptest::prelude::*;
use tempfile::tempdir;
use zeroize::Zeroizing;

use vaultkeep_core::{
    generate_password, EntryInput, PasswordPolicy, Vault, VaultError, MAX_ATTACHMENT_BYTES,
    MAX_VAULT_BYTES,
};

fn sample_entry(title: &str, user: &str, pw: &str) -> EntryInput {
    EntryInput {
        title: title.into(),
        username: user.into(),
        password: Zeroizing::new(pw.to_string()),
        url: format!("https://{}.example.com", title.to_lowercase()),
        notes: "Confidential security notes".into(),
        group_id: None,
        otp: Some(Zeroizing::new(
            "otpauth://totp/Ex:user?secret=JBSWY3DPEHPK3PXP&period=30&digits=6".into(),
        )),
    }
}

// ---------------------------------------------------------------------------
// 1. Bit-Flipped Ciphertext Fails Authentication
// ---------------------------------------------------------------------------
#[test]
fn bit_flipped_ciphertext_fails_authentication() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("vault.kdbx");
    let master = "correct-horse-battery-staple";

    let mut v = Vault::create(&path, master).unwrap();
    v.add(&sample_entry("GitHub", "octocat", "super-secret-token"));
    v.add(&sample_entry("Bank", "alice", "p@ssw0rd999"));
    v.save().unwrap();
    drop(v);

    let original_bytes = fs::read(&path).unwrap();
    assert!(original_bytes.len() > 100);

    // KDBX4 authenticates header with HMAC-SHA256 and payload blocks with HMAC-SHA256.
    // Flipping any bit in the ciphertext or authenticated metadata must cause Vault::open to fail.
    let tamper_offsets = [
        original_bytes.len() / 2,  // Middle payload block
        original_bytes.len() - 16, // Near end of file
        original_bytes.len() - 64, // Payload HMAC block
        48,                        // Header metadata section
    ];

    for &offset in &tamper_offsets {
        let mut tampered = original_bytes.clone();
        tampered[offset] ^= 0x01; // flip a single bit

        let tampered_path = dir.path().join(format!("tampered_{offset}.kdbx"));
        fs::write(&tampered_path, &tampered).unwrap();

        let open_res = Vault::open(&tampered_path, master);
        assert!(
            open_res.is_err(),
            "bit flip at offset {offset} must fail authentication"
        );
        match open_res {
            Err(VaultError::Open(_)) => {
                // Expected: keepass DatabaseOpenError from HMAC or decryption mismatch
            }
            Err(other) => {
                panic!("unexpected error variant on bit flip at {offset}: {other:?}");
            }
            Ok(_) => panic!("tampered file at offset {offset} must never open"),
        }
    }
}

// ---------------------------------------------------------------------------
// 2. Truncated Envelopes Fail Safely
// ---------------------------------------------------------------------------
#[test]
fn truncated_envelopes_fail_safely() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("vault.kdbx");
    let master = "correct-horse-battery-staple";

    let mut v = Vault::create(&path, master).unwrap();
    v.add(&sample_entry("Test", "user", "secret"));
    v.save().unwrap();
    drop(v);

    let original_bytes = fs::read(&path).unwrap();

    // 0-byte file must be caught by bounded validation
    let empty_path = dir.path().join("empty.kdbx");
    File::create(&empty_path).unwrap();
    let empty_res = Vault::open(&empty_path, master);
    assert!(
        matches!(empty_res, Err(VaultError::Malformed(_))),
        "empty file must fail with Malformed error"
    );

    // Partial truncations at various critical boundaries
    let truncate_lengths = [1, 4, 8, 12, 32, 64, original_bytes.len() / 2];

    for &len in &truncate_lengths {
        let truncated = &original_bytes[..len];
        let trunc_path = dir.path().join(format!("trunc_{len}.kdbx"));
        fs::write(&trunc_path, truncated).unwrap();

        let res = Vault::open(&trunc_path, master);
        assert!(
            res.is_err(),
            "truncated file at length {len} must fail safely"
        );
    }
}

// ---------------------------------------------------------------------------
// 3. Malformed Headers Fail Safely (Magic & Version)
// ---------------------------------------------------------------------------
#[test]
fn malformed_magic_and_version_fail_without_downgrade() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("vault.kdbx");
    let master = "correct-horse-battery-staple";

    let mut v = Vault::create(&path, master).unwrap();
    v.add(&sample_entry("Test", "user", "secret"));
    v.save().unwrap();
    drop(v);

    let original_bytes = fs::read(&path).unwrap();

    // Verify valid KDBX4 signatures:
    // Magic 1: 0x9AA2D903 (little-endian: 03 D9 A2 9A)
    // Magic 2: 0xB54BFB67 (little-endian: 67 FB 4B B5)
    // Version: 0x00040000 (little-endian: minor 00 00, major 04 00)
    assert_eq!(&original_bytes[0..4], &[0x03, 0xD9, 0xA2, 0x9A]);
    assert_eq!(&original_bytes[4..8], &[0x67, 0xFB, 0x4B, 0xB5]);
    assert_eq!(&original_bytes[8..10], &[0x01, 0x00]); // Minor version 1 (KDBX 4.1)
    assert_eq!(&original_bytes[10..12], &[0x04, 0x00]); // Major version 4

    // Corrupt magic 1
    let mut bad_magic1 = original_bytes.clone();
    bad_magic1[0] = 0xFF;
    let p_magic1 = dir.path().join("bad_magic1.kdbx");
    fs::write(&p_magic1, bad_magic1).unwrap();
    assert!(Vault::open(&p_magic1, master).is_err());

    // Corrupt magic 2
    let mut bad_magic2 = original_bytes.clone();
    bad_magic2[4] = 0x00;
    let p_magic2 = dir.path().join("bad_magic2.kdbx");
    fs::write(&p_magic2, bad_magic2).unwrap();
    assert!(Vault::open(&p_magic2, master).is_err());

    // Unknown/unsupported major version (e.g. version 99.0: 0x63, 0x00)
    let mut bad_version = original_bytes.clone();
    bad_version[10] = 0x63;
    let p_ver = dir.path().join("bad_version.kdbx");
    fs::write(&p_ver, bad_version).unwrap();
    let ver_res = Vault::open(&p_ver, master);
    assert!(ver_res.is_err(), "unknown version must fail closed");

    // Legacy unsupported KDBX 1.0 (major version 1)
    let mut legacy_version = original_bytes.clone();
    legacy_version[10] = 0x01;
    let p_leg = dir.path().join("legacy_version.kdbx");
    fs::write(&p_leg, legacy_version).unwrap();
    assert!(
        Vault::open(&p_leg, master).is_err(),
        "legacy version must not downgrade silently"
    );
}

// ---------------------------------------------------------------------------
// 4. Bounded Input Validation (File & Attachment Limits)
// ---------------------------------------------------------------------------
#[test]
fn input_bounds_enforce_file_and_attachment_limits() {
    let dir = tempdir().unwrap();

    // 1. File size bound check
    let large_file_path = dir.path().join("oversized.kdbx");
    let large_file = File::create(&large_file_path).unwrap();
    large_file.set_len(MAX_VAULT_BYTES + 1024).unwrap();

    let open_res = Vault::open(&large_file_path, "master");
    assert!(
        matches!(open_res, Err(VaultError::FileTooLarge(size, max)) if size > max),
        "oversized vault file must be rejected before reading"
    );

    // 2. Attachment bounds check
    let vault_path = dir.path().join("normal.kdbx");
    let mut v = Vault::create(&vault_path, "master").unwrap();
    let entry_id = v.add(&sample_entry("Service", "admin", "pass"));

    // Attachment name must not be empty
    let empty_name_res = v.add_attachment(entry_id, "   ", b"payload");
    assert!(matches!(empty_name_res, Err(VaultError::Policy(_))));

    // Attachment size over limit
    let oversized_data = vec![0u8; MAX_ATTACHMENT_BYTES + 1];
    let att_res = v.add_attachment(entry_id, "big_file.bin", &oversized_data);
    assert!(
        matches!(att_res, Err(VaultError::AttachmentTooLarge(size, max)) if size > max),
        "oversized attachment must be rejected"
    );
}

// ---------------------------------------------------------------------------
// 5. Redaction: Secrets Never Appear in Debug, Display, or Errors
// ---------------------------------------------------------------------------
#[test]
fn secrets_never_leak_in_debug_and_error_representations() {
    let secret_pw = "TOP_SECRET_PASSWORD_12345!@#";
    let secret_otp = "otpauth://totp/Sec:user?secret=SUPERSECRETSEED2FA";

    let input = EntryInput {
        title: "TestTitle".into(),
        username: "TestUser".into(),
        password: Zeroizing::new(secret_pw.into()),
        url: "https://secure.example".into(),
        notes: "Confidential Notes".into(),
        group_id: None,
        otp: Some(Zeroizing::new(secret_otp.into())),
    };

    let input_debug = format!("{input:?}");
    assert!(
        !input_debug.contains(secret_pw),
        "EntryInput debug leaked password"
    );
    assert!(
        !input_debug.contains("SUPERSECRETSEED2FA"),
        "EntryInput debug leaked OTP secret"
    );
    assert!(
        input_debug.contains("[REDACTED]"),
        "EntryInput debug should show [REDACTED]"
    );

    let dir = tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let master_pass = "MASTER_KEY_SECRET_789";
    let mut v = Vault::create(&path, master_pass).unwrap();
    let id = v.add(&input);
    v.save().unwrap();

    let details = v.details(id).unwrap();
    let details_debug = format!("{details:?}");
    assert!(
        !details_debug.contains(secret_pw),
        "EntryDetails debug leaked password"
    );
    assert!(
        !details_debug.contains("SUPERSECRETSEED2FA"),
        "EntryDetails debug leaked OTP secret"
    );
    assert!(details_debug.contains("[REDACTED]"));

    let token = v.totp(id).unwrap().unwrap();
    let token_debug = format!("{token:?}");
    assert!(
        !token_debug.contains(&token.code),
        "TotpToken debug leaked 6-digit code"
    );
    assert!(token_debug.contains("[REDACTED]"));

    let vault_debug = format!("{v:?}");
    assert!(
        !vault_debug.contains(master_pass),
        "Vault debug leaked master password"
    );
    assert!(vault_debug.contains("[REDACTED]"));

    // Check VaultError display & debug
    let err = VaultError::EmptyMasterPassword;
    assert!(!format!("{err:?}").contains("SECRET"));
    assert!(!format!("{err}").contains("SECRET"));

    let policy_err = VaultError::Policy("length must be between class count and 256");
    assert!(!format!("{policy_err:?}").contains("SECRET"));
}

// ---------------------------------------------------------------------------
// 6. Property-Based Testing: Password Policy Generation Invariants
// ---------------------------------------------------------------------------
proptest! {
    #[test]
    fn prop_password_generator_satisfies_all_invariants(
        length in 4usize..=128usize,
        lower in any::<bool>(),
        upper in any::<bool>(),
        digits in any::<bool>(),
        symbols in any::<bool>(),
    ) {
        let active_count = [lower, upper, digits, symbols].into_iter().filter(|&x| x).count();
        let policy = PasswordPolicy {
            length,
            lower,
            upper,
            digits,
            symbols,
        };

        if active_count == 0 || length < active_count {
            prop_assert!(generate_password(&policy).is_err());
        } else {
            let pw = generate_password(&policy).unwrap();
            prop_assert_eq!(pw.len(), length);

            if lower {
                prop_assert!(pw.chars().any(|c| "abcdefghijkmnopqrstuvwxyz".contains(c)));
            }
            if upper {
                prop_assert!(pw.chars().any(|c| "ABCDEFGHJKLMNPQRSTUVWXYZ".contains(c)));
            }
            if digits {
                prop_assert!(pw.chars().any(|c| "23456789".contains(c)));
            }
            if symbols {
                let has_symbols = pw.chars().any(|c| "!@#$%^&*()-_=+[]{};:,.?".contains(c));
                prop_assert!(has_symbols);
            }
        }
    }

    #[test]
    fn prop_malformed_random_bytes_never_panic_on_open(
        data in proptest::collection::vec(any::<u8>(), 0..=512)
    ) {
        let dir = tempdir().unwrap();
        let path = dir.path().join("fuzzy.kdbx");
        let mut file = File::create(&path).unwrap();
        file.write_all(&data).unwrap();
        drop(file);

        // Vault::open must return an Err, and must NEVER panic on untrusted inputs
        let res = Vault::open(&path, "any-password");
        prop_assert!(res.is_err());
    }
}
