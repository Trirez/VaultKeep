use vaultkeep_core::{generate_password, EntryInput, PasswordPolicy, Vault, VaultError};

fn input(title: &str, user: &str, pw: &str) -> EntryInput {
    EntryInput {
        title: title.into(),
        username: user.into(),
        password: pw.to_string().into(),
        url: format!("https://{}.example", title.to_lowercase()),
        notes: String::new(),
        group_id: None,
        otp: None,
    }
}

#[test]
fn roundtrip_persists_entries() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");

    let mut v = Vault::create(&path, "correct horse").unwrap();
    let id = v.add(&input("GitHub", "kingshuk", "s3cret!"));
    v.save().unwrap();
    drop(v);

    let v = Vault::open(&path, "correct horse").unwrap();
    let hits = v.search("github");
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].id, id);
    assert_eq!(hits[0].username, "kingshuk");
    assert_eq!(v.password(id).unwrap().as_str(), "s3cret!");
}

#[test]
fn wrong_password_is_rejected() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    Vault::create(&path, "right").unwrap();
    assert!(matches!(
        Vault::open(&path, "wrong"),
        Err(VaultError::Open(_))
    ));
}

#[test]
fn empty_master_and_overwrite_are_refused() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    assert!(matches!(
        Vault::create(&path, ""),
        Err(VaultError::EmptyMasterPassword)
    ));
    Vault::create(&path, "x").unwrap();
    assert!(Vault::create(&path, "x").is_err());
}

#[test]
fn update_and_remove() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "m").unwrap();
    let id = v.add(&input("Mail", "a", "old"));
    v.update(id, &input("Mail", "a", "new")).unwrap();
    assert_eq!(v.password(id).unwrap().as_str(), "new");
    v.remove(id).unwrap();
    assert!(v.search("").is_empty());
    assert!(matches!(v.remove(id), Err(VaultError::NotFound)));
}

#[test]
fn no_plaintext_secrets_on_disk() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "m").unwrap();
    v.add(&input("Bank", "alice", "UNIQUE-MARKER-9f3a"));
    v.save().unwrap();
    let bytes = std::fs::read(&path).unwrap();
    let hay = String::from_utf8_lossy(&bytes);
    assert!(!hay.contains("UNIQUE-MARKER-9f3a"));
    assert!(!hay.contains("alice"));
}

#[test]
fn generator_respects_policy() {
    let p = PasswordPolicy {
        length: 32,
        symbols: false,
        ..Default::default()
    };
    let pw = generate_password(&p).unwrap();
    assert_eq!(pw.len(), 32);
    assert!(pw.chars().any(|c| c.is_ascii_lowercase()));
    assert!(pw.chars().any(|c| c.is_ascii_uppercase()));
    assert!(pw.chars().any(|c| c.is_ascii_digit()));
    assert!(pw.chars().all(|c| c.is_ascii_alphanumeric()));
    assert_ne!(pw, generate_password(&p).unwrap());

    let bad = PasswordPolicy {
        lower: false,
        upper: false,
        digits: false,
        symbols: false,
        length: 12,
    };
    assert!(generate_password(&bad).is_err());
}

#[test]
fn groups_and_hierarchy() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "master").unwrap();

    let work_id = v.create_group("Work").unwrap();
    let personal_id = v.create_group("Personal").unwrap();

    let groups = v.list_groups();
    assert!(groups.len() >= 3); // Root + Work + Personal
    assert!(groups.iter().any(|g| g.id == work_id && g.name == "Work"));
    assert!(groups
        .iter()
        .any(|g| g.id == personal_id && g.name == "Personal"));

    let mut item = input("Work Email", "corp\\alice", "secret");
    item.group_id = Some(work_id);
    let entry_id = v.add(&item);
    v.save().unwrap();

    let details = v.details(entry_id).unwrap();
    assert_eq!(details.group_id, Some(work_id));
    assert_eq!(details.group_name.as_deref(), Some("Work"));

    let hits = v.search("Work");
    assert!(hits.iter().any(|h| h.id == entry_id));

    // Test moving entry from Work group to Personal group
    item.group_id = Some(personal_id);
    v.update(entry_id, &item).unwrap();
    v.save().unwrap();

    let details_moved = v.details(entry_id).unwrap();
    assert_eq!(details_moved.group_id, Some(personal_id));
    assert_eq!(details_moved.group_name.as_deref(), Some("Personal"));
}

#[test]
fn totp_generation_and_storage() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "master").unwrap();

    let mut item = input("GitLab", "alice", "pw123");
    // Standard RFC 6238 test URI with base32 secret
    item.otp = Some(
        "otpauth://totp/GitLab:alice?secret=JBSWY3DPEHPK3PXP&issuer=GitLab&digits=6"
            .to_string()
            .into(),
    );
    let id = v.add(&item);
    v.save().unwrap();

    let details = v.details(id).unwrap();
    assert!(details.otp_uri.is_some());

    let token = v.totp(id).unwrap().expect("should produce totp token");
    assert_eq!(token.code.len(), 6);
    assert!(token.code.chars().all(|c| c.is_ascii_digit()));
    assert_eq!(token.period, 30);
    assert!(token.seconds_remaining <= 30);

    // Clear OTP
    let mut updated = input("GitLab", "alice", "pw123");
    updated.otp = Some(String::new().into());
    v.update(id, &updated).unwrap();
    v.save().unwrap();

    let no_token = v.totp(id).unwrap();
    assert!(no_token.is_none());
}

#[test]
fn attachments_crud() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "master").unwrap();

    let id = v.add(&input("SecureServer", "root", "toor"));
    v.save().unwrap();

    let png_data = b"\x89PNG\r\n\x1a\nfakeimagebytes";
    let key_data = b"ssh-rsa AAAAB3NzaC1yc2E...";

    v.add_attachment(id, "backup_key.pub", key_data).unwrap();
    v.add_attachment(id, "badge.png", png_data).unwrap();

    let list = v.list_attachments(id).unwrap();
    assert_eq!(list.len(), 2);
    assert!(list
        .iter()
        .any(|a| a.name == "backup_key.pub" && a.size == key_data.len()));
    assert!(list
        .iter()
        .any(|a| a.name == "badge.png" && a.size == png_data.len()));

    let read_key = v.get_attachment(id, "backup_key.pub").unwrap();
    assert_eq!(read_key, key_data);

    let read_png = v.get_attachment(id, "badge.png").unwrap();
    assert_eq!(read_png, png_data);

    // Reopen vault from disk to ensure persistence
    drop(v);
    let mut v = Vault::open(&path, "master").unwrap();
    assert_eq!(v.get_attachment(id, "badge.png").unwrap(), png_data);

    v.remove_attachment(id, "badge.png").unwrap();
    let list_after = v.list_attachments(id).unwrap();
    assert_eq!(list_after.len(), 1);
    assert!(matches!(
        v.get_attachment(id, "badge.png"),
        Err(VaultError::AttachmentNotFound)
    ));
}

#[test]
fn merge_from_file_3way() {
    let dir = tempfile::tempdir().unwrap();
    let path_a = dir.path().join("vault_a.kdbx");
    let path_b = dir.path().join("vault_b.kdbx");

    // Base vault
    let mut va = Vault::create(&path_a, "master").unwrap();
    let id_shared = va.add(&input("SharedEntry", "user1", "pass1"));
    va.save().unwrap();
    drop(va);

    // Copy to path_b
    std::fs::copy(&path_a, &path_b).unwrap();

    // In vault A: add Entry A
    let mut va = Vault::open(&path_a, "master").unwrap();
    let id_a = va.add(&input("OnlyOnA", "userA", "passA"));
    va.save().unwrap();

    // In vault B: add Entry B
    let mut vb = Vault::open(&path_b, "master").unwrap();
    let id_b = vb.add(&input("OnlyOnB", "userB", "passB"));
    vb.save().unwrap();
    drop(vb);

    // Merge B into A
    let events = va.merge_from_file(&path_b, "master").unwrap();
    assert!(events > 0);

    let hits = va.search("");
    let hit_ids: Vec<_> = hits.into_iter().map(|e| e.id).collect();
    assert!(hit_ids.contains(&id_shared));
    assert!(hit_ids.contains(&id_a));
    assert!(hit_ids.contains(&id_b));
}

#[test]
fn merge_auth_failure_preserves_active_vault() {
    let dir = tempfile::tempdir().unwrap();
    let path_a = dir.path().join("vault_a.kdbx");
    let path_b = dir.path().join("vault_b.kdbx");

    let mut va = Vault::create(&path_a, "masterA").unwrap();
    let id_a = va.add(&input("EntryA", "alice", "secretA"));
    va.save().unwrap();

    let mut vb = Vault::create(&path_b, "masterB").unwrap();
    vb.add(&input("EntryB", "bob", "secretB"));
    vb.save().unwrap();
    drop(vb);

    // Wrong password for replica
    let res = va.merge_from_file(&path_b, "wrong_master");
    assert!(res.is_err());
    assert!(matches!(res.unwrap_err(), VaultError::Open(_)));

    // Active vault must be unmodified
    let hits = va.search("");
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].id, id_a);
}

#[test]
fn merge_corrupt_and_missing_replicas_fail_safely() {
    let dir = tempfile::tempdir().unwrap();
    let path_a = dir.path().join("vault_a.kdbx");
    let missing_path = dir.path().join("missing.kdbx");
    let corrupt_path = dir.path().join("corrupt.kdbx");
    let empty_path = dir.path().join("empty.kdbx");

    let mut va = Vault::create(&path_a, "master").unwrap();
    let id_a = va.add(&input("EntryA", "alice", "secretA"));
    va.save().unwrap();

    // 1. Missing file
    let res_missing = va.merge_from_file(&missing_path, "master");
    assert!(res_missing.is_err());
    assert!(matches!(res_missing.unwrap_err(), VaultError::Io(_)));

    // 2. Corrupt / random bytes
    std::fs::write(&corrupt_path, b"not a kdbx database header at all").unwrap();
    let res_corrupt = va.merge_from_file(&corrupt_path, "master");
    assert!(res_corrupt.is_err());
    assert!(matches!(res_corrupt.unwrap_err(), VaultError::Open(_)));

    // 3. Zero-byte empty file
    std::fs::write(&empty_path, b"").unwrap();
    let res_empty = va.merge_from_file(&empty_path, "master");
    assert!(res_empty.is_err());
    assert!(matches!(res_empty.unwrap_err(), VaultError::Malformed(_)));

    // Ensure active vault remains intact
    let hits = va.search("");
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].id, id_a);
}

#[test]
fn merge_unrelated_vaults_fails_safely_without_panic() {
    let dir = tempfile::tempdir().unwrap();
    let path_a = dir.path().join("vault_a.kdbx");
    let path_b = dir.path().join("vault_b.kdbx");

    let mut va = Vault::create(&path_a, "master").unwrap();
    let id_a = va.add(&input("EntryA", "alice", "secretA"));
    va.save().unwrap();

    let mut vb = Vault::create(&path_b, "master").unwrap();
    vb.add(&input("EntryB", "bob", "secretB"));
    vb.save().unwrap();
    drop(vb);

    // Merge two independently created vaults (different root groups)
    let res = va.merge_from_file(&path_b, "master");
    assert!(res.is_err());
    assert!(matches!(
        res.unwrap_err(),
        VaultError::IncompatibleVaultRoots
    ));

    // Ensure active vault remains intact
    let hits = va.search("");
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].id, id_a);
}

#[test]
fn merge_self_is_prevented() {
    let dir = tempfile::tempdir().unwrap();
    let path_a = dir.path().join("vault_a.kdbx");
    let mut va = Vault::create(&path_a, "master").unwrap();
    va.add(&input("EntryA", "alice", "secretA"));
    va.save().unwrap();

    let res = va.merge_from_file(&path_a, "master");
    assert!(res.is_err());
    assert!(matches!(res.unwrap_err(), VaultError::SelfMerge));
}

#[test]
fn merge_with_empty_password_uses_active_master() {
    let dir = tempfile::tempdir().unwrap();
    let path_a = dir.path().join("vault_a.kdbx");
    let path_b = dir.path().join("vault_b.kdbx");

    let mut va = Vault::create(&path_a, "common_master").unwrap();
    va.add(&input("EntryA", "alice", "secretA"));
    va.save().unwrap();
    drop(va);

    // Clone to path_b (sharing same root and master password)
    std::fs::copy(&path_a, &path_b).unwrap();
    let mut vb = Vault::open(&path_b, "common_master").unwrap();
    let id_b = vb.add(&input("EntryB", "bob", "secretB"));
    vb.save().unwrap();
    drop(vb);

    // Open A and merge B passing empty password ""
    let mut va = Vault::open(&path_a, "common_master").unwrap();
    let events = va.merge_from_file(&path_b, "").unwrap();
    assert!(events > 0);
    let hits = va.search("");
    assert!(hits.iter().any(|e| e.id == id_b));
}

#[test]
fn sync_with_file_updates_both_replicas_bidirectionally() {
    let dir = tempfile::tempdir().unwrap();
    let path_a = dir.path().join("vault_a.kdbx");
    let path_b = dir.path().join("vault_b.kdbx");

    // Base vault
    let mut va = Vault::create(&path_a, "master").unwrap();
    let id_shared = va.add(&input("Shared", "shared", "pw"));
    va.save().unwrap();
    drop(va);

    // Replica vault_b
    std::fs::copy(&path_a, &path_b).unwrap();

    // Vault A adds Entry A
    let mut va = Vault::open(&path_a, "master").unwrap();
    let id_a = va.add(&input("OnlyA", "alice", "pwA"));
    va.save().unwrap();

    // Vault B adds Entry B
    let mut vb = Vault::open(&path_b, "master").unwrap();
    let id_b = vb.add(&input("OnlyB", "bob", "pwB"));
    vb.save().unwrap();
    drop(vb);

    // Run bidirectional sync from A
    let events = va.sync_with_file(&path_b, "master").unwrap();
    assert!(events > 0);

    // Vault A now has all entries
    let hits_a: Vec<_> = va.search("").into_iter().map(|e| e.id).collect();
    assert!(hits_a.contains(&id_shared));
    assert!(hits_a.contains(&id_a));
    assert!(hits_a.contains(&id_b));
    drop(va);

    // Vault B on disk also now has all entries!
    let vb_reopened = Vault::open(&path_b, "master").unwrap();
    let hits_b: Vec<_> = vb_reopened.search("").into_iter().map(|e| e.id).collect();
    assert!(hits_b.contains(&id_shared));
    assert!(hits_b.contains(&id_a));
    assert!(hits_b.contains(&id_b));
}

#[test]
fn domain_autofill_query() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "master").unwrap();

    let mut e1 = input("Google Account", "user@gmail.com", "pass");
    e1.url = "https://accounts.google.com/signin/v2/identifier".into();
    v.add(&e1);

    let mut e2 = input("GitHub Work", "octocat", "ghp_123");
    e2.url = "https://github.com/login".into();
    v.add(&e2);

    let mut e3 = input("AWS Console", "admin", "pass");
    e3.url = String::new(); // No URL, title only
    v.add(&e3);

    let google_hits = v.find_for_domain("google.com");
    assert_eq!(google_hits.len(), 1);
    assert_eq!(google_hits[0].title, "Google Account");

    let github_hits = v.find_for_domain("github.com");
    assert_eq!(github_hits.len(), 1);
    assert_eq!(github_hits[0].title, "GitHub Work");

    let aws_hits = v.find_for_domain("aws");
    assert_eq!(aws_hits.len(), 1);
    assert_eq!(aws_hits[0].title, "AWS Console");

    // Negative tests: Phishing sites and substring spoofing must be rejected!
    assert!(v.find_for_domain("evil-google.com").is_empty());
    assert!(v.find_for_domain("google.com.attacker.site").is_empty());
    assert!(v.find_for_domain("evil-aws.com").is_empty());
    assert!(v
        .find_for_domain("https://phishing.site/google.com")
        .is_empty());
    assert!(v.find_for_domain("").is_empty());
}
