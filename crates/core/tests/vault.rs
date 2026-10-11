use vaultkeep_core::{
    generate_password, CustomFieldInput, EntryInput, KdfParams, PasswordPolicy, Vault, VaultError,
};

fn input(title: &str, user: &str, pw: &str) -> EntryInput {
    EntryInput {
        title: title.into(),
        username: user.into(),
        password: pw.to_string().into(),
        url: format!("https://{}.example", title.to_lowercase()),
        notes: String::new(),
        group_id: None,
        otp: None,
        last_known_revision_date: None,
        email: String::new(),
        phone: String::new(),
        security_question: String::new(),
        security_answer: None,
        sections: Vec::new(),
        custom_fields: Vec::new(),
    }
}

#[test]
fn roundtrip_persists_entries() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");

    let mut v = Vault::create(&path, "correct horse").unwrap();
    let id = v.add(&input("GitHub", "kingshuk", "s3cret!")).unwrap();
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
    let id = v.add(&input("Mail", "a", "old")).unwrap();
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
    v.add(&input("Bank", "alice", "UNIQUE-MARKER-9f3a"))
        .unwrap();
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

    // Adding an entry with a nonexistent group_id must fail with GroupNotFound
    let mut invalid_grp_item = input("Orphan", "user", "secret");
    invalid_grp_item.group_id = Some(uuid::Uuid::nil());
    assert!(matches!(
        v.add(&invalid_grp_item),
        Err(VaultError::GroupNotFound)
    ));

    let mut item = input("Work Email", "corp\\alice", "secret");
    item.group_id = Some(work_id);
    let entry_id = v.add(&item).unwrap();
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
    let raw_uri = "otpauth://totp/GitLab:alice?secret=JBSWY3DPEHPK3PXP&issuer=GitLab&digits=6";
    item.otp = Some(raw_uri.to_string().into());
    let id = v.add(&item).unwrap();
    v.save().unwrap();

    let details = v.details(id).unwrap();
    assert!(details.has_otp);
    assert_eq!(
        v.otp_uri(id).unwrap().as_deref().map(|s| s.as_str()),
        Some(raw_uri)
    );

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

    assert!(!v.details(id).unwrap().has_otp);
    assert!(v.otp_uri(id).unwrap().is_none());
    let no_token = v.totp(id).unwrap();
    assert!(no_token.is_none());
}

#[test]
fn attachments_crud() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "master").unwrap();

    let id = v.add(&input("SecureServer", "root", "toor")).unwrap();
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
    // Removing a nonexistent attachment must return AttachmentNotFound
    assert!(matches!(
        v.remove_attachment(id, "badge.png"),
        Err(VaultError::AttachmentNotFound)
    ));
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
    let id_shared = va.add(&input("SharedEntry", "user1", "pass1")).unwrap();
    va.save().unwrap();
    drop(va);

    // Copy to path_b
    std::fs::copy(&path_a, &path_b).unwrap();

    // In vault A: add Entry A
    let mut va = Vault::open(&path_a, "master").unwrap();
    let id_a = va.add(&input("OnlyOnA", "userA", "passA")).unwrap();
    va.save().unwrap();

    // In vault B: add Entry B
    let mut vb = Vault::open(&path_b, "master").unwrap();
    let id_b = vb.add(&input("OnlyOnB", "userB", "passB")).unwrap();
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
    let id_a = va.add(&input("EntryA", "alice", "secretA")).unwrap();
    va.save().unwrap();

    let mut vb = Vault::create(&path_b, "masterB").unwrap();
    vb.add(&input("EntryB", "bob", "secretB")).unwrap();
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
    let id_a = va.add(&input("EntryA", "alice", "secretA")).unwrap();
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
    let id_a = va.add(&input("EntryA", "alice", "secretA")).unwrap();
    va.save().unwrap();

    let mut vb = Vault::create(&path_b, "master").unwrap();
    vb.add(&input("EntryB", "bob", "secretB")).unwrap();
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
    va.add(&input("EntryA", "alice", "secretA")).unwrap();
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
    va.add(&input("EntryA", "alice", "secretA")).unwrap();
    va.save().unwrap();
    drop(va);

    // Clone to path_b (sharing same root and master password)
    std::fs::copy(&path_a, &path_b).unwrap();
    let mut vb = Vault::open(&path_b, "common_master").unwrap();
    let id_b = vb.add(&input("EntryB", "bob", "secretB")).unwrap();
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
    let id_shared = va.add(&input("Shared", "shared", "pw")).unwrap();
    va.save().unwrap();
    drop(va);

    // Replica vault_b
    std::fs::copy(&path_a, &path_b).unwrap();

    // Vault A adds Entry A
    let mut va = Vault::open(&path_a, "master").unwrap();
    let id_a = va.add(&input("OnlyA", "alice", "pwA")).unwrap();
    va.save().unwrap();

    // Vault B adds Entry B
    let mut vb = Vault::open(&path_b, "master").unwrap();
    let id_b = vb.add(&input("OnlyB", "bob", "pwB")).unwrap();
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
    v.add(&e1).unwrap();

    let mut e2 = input("GitHub Work", "octocat", "ghp_123");
    e2.url = "https://github.com/login".into();
    v.add(&e2).unwrap();

    let mut e3 = input("AWS Console", "admin", "pass");
    e3.url = String::new(); // No URL, title only
    v.add(&e3).unwrap();

    let google_hits = v.find_for_domain("google.com");
    assert_eq!(google_hits.len(), 1);
    assert_eq!(google_hits[0].title, "Google Account");

    let github_hits = v.find_for_domain("github.com");
    assert_eq!(github_hits.len(), 1);
    assert_eq!(github_hits[0].title, "GitHub Work");

    let aws_hits = v.find_for_domain("aws");
    assert_eq!(aws_hits.len(), 1);
    assert_eq!(aws_hits[0].title, "AWS Console");

    // Negative tests: Phishing sites, reverse-subdomain queries, and substring spoofing must be rejected!
    assert!(v.find_for_domain("evil-google.com").is_empty());
    assert!(v.find_for_domain("google.com.attacker.site").is_empty());
    assert!(v.find_for_domain("evil-aws.com").is_empty());
    assert!(v
        .find_for_domain("https://phishing.site/google.com")
        .is_empty());
    // Reverse subdomain check: entry for github.com must NOT match arbitrary subdomain queries like evil.github.com
    assert!(v.find_for_domain("evil.github.com").is_empty());
    assert!(v.find_for_domain("").is_empty());
}

#[test]
fn passkey_generation_storage_and_category_detection() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "master").unwrap();

    // 1. Entry on a known passkey-supported domain (github.com)
    let mut gh = input("GitHub", "octocat", "pw123");
    gh.url = "https://github.com/login".into();
    let gh_id = v.add(&gh).unwrap();

    // 2. Entry on an internal domain (not passkey-supported by default)
    let mut lan = input("Router Admin", "admin", "pw456");
    lan.url = "https://router.internal.lan".into();
    let lan_id = v.add(&lan).unwrap();

    // 3. Entry with spoofed domain (must NOT be flagged as passkey-supported)
    let mut spoof = input("Custom Portal", "user", "pw789");
    spoof.url = "https://evil-google.com/login".into();
    let spoof_id = v.add(&spoof).unwrap();
    v.save().unwrap();

    let list_initial = v.search("");
    let gh_sum = list_initial.iter().find(|e| e.id == gh_id).unwrap();
    assert!(!gh_sum.has_passkey);
    assert!(gh_sum.passkey_supported);

    let lan_sum = list_initial.iter().find(|e| e.id == lan_id).unwrap();
    assert!(!lan_sum.has_passkey);
    assert!(!lan_sum.passkey_supported);

    let spoof_sum = list_initial.iter().find(|e| e.id == spoof_id).unwrap();
    assert!(!spoof_sum.has_passkey);
    assert!(!spoof_sum.passkey_supported);

    // Generate a passkey for GitHub (auto-inferring rp_id and username from entry)
    let pk = v.generate_passkey(gh_id, "", "").unwrap();
    assert_eq!(pk.rp_id, "github.com");
    assert_eq!(pk.username, "octocat");
    assert!(!pk.credential_id.is_empty());
    assert!(!pk.user_handle.is_empty());

    // Ensure private key PEM is encrypted on disk and never appears in plaintext bytes
    let raw_bytes = std::fs::read(&path).unwrap();
    let raw_str = String::from_utf8_lossy(&raw_bytes);
    assert!(!raw_str.contains("BEGIN PRIVATE KEY"));

    // Reopen vault from disk and verify persistence
    drop(v);
    let mut v = Vault::open(&path, "master").unwrap();
    let list_after = v.search("");
    let gh_after = list_after.iter().find(|e| e.id == gh_id).unwrap();
    assert!(gh_after.has_passkey);
    assert!(gh_after.passkey_supported);

    let details = v.details(gh_id).unwrap();
    assert_eq!(details.passkey, Some(pk));
    assert!(details.passkey_supported);

    // Remove passkey and confirm state resets to passkey_supported=true, has_passkey=false
    v.remove_passkey(gh_id).unwrap();
    let details_removed = v.details(gh_id).unwrap();
    assert!(details_removed.passkey.is_none());
    assert!(details_removed.passkey_supported);
}

#[test]
fn sequential_uuid_v7_and_argon2id_defaults() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "master").unwrap();

    // Verify new vaults use hardened Argon2id KDF defaults (not keepass's 1MB Argon2d default)
    let kdf = v.kdf_params().expect("vault should use Argon2id");
    assert_eq!(kdf, KdfParams::default());
    assert_eq!(kdf.iterations, 6);
    assert_eq!(kdf.memory_bytes, 32 * 1024 * 1024);
    assert_eq!(kdf.parallelism, 4);

    // Verify root group, created groups, and created entries all use sequential UUIDv7 (version 7)
    let gid = v.create_group("Ops").unwrap();
    assert_eq!(gid.get_version_num(), 7);
    for g in v.list_groups() {
        assert_eq!(g.id.get_version_num(), 7, "group {} must be UUIDv7", g.name);
    }

    let e1 = v.add(&input("First", "u1", "p1")).unwrap();
    let e2 = v.add(&input("Second", "u2", "p2")).unwrap();
    assert_eq!(e1.get_version_num(), 7);
    assert_eq!(e2.get_version_num(), 7);
    assert_ne!(e1, e2);
}

#[test]
fn optimistic_concurrency_rejects_stale_revision_date() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "master").unwrap();

    let id = v.add(&input("ProdDB", "admin", "initial-pw")).unwrap();
    v.save().unwrap();

    let initial_rev = v
        .details(id)
        .unwrap()
        .revision_date
        .expect("revision_date present");

    // First update advances revision_date monotonically
    let mut upd1 = input("ProdDB", "admin", "updated-pw-1");
    upd1.last_known_revision_date = Some(initial_rev);
    v.update(id, &upd1).unwrap();
    v.save().unwrap();

    let new_rev = v
        .details(id)
        .unwrap()
        .revision_date
        .expect("revision_date present");
    assert!(
        new_rev > initial_rev,
        "revision_date must strictly advance on update"
    );

    // Stale client attempting to overwrite using an outdated revision_date (>1s older) is rejected
    let mut stale_upd = input("ProdDB", "admin", "stale-overwrite");
    stale_upd.last_known_revision_date = Some(new_rev - 5);
    let err = v.update(id, &stale_upd).unwrap_err();
    assert!(matches!(err, VaultError::StaleRevision { .. }));

    // Password remains the newer one
    assert_eq!(v.password(id).unwrap().as_str(), "updated-pw-1");
}

#[test]
fn sync_propagates_entry_edits_and_deletion_tombstones() {
    let dir = tempfile::tempdir().unwrap();
    let path_a = dir.path().join("vault_a.kdbx");
    let path_b = dir.path().join("vault_b.kdbx");

    let mut va = Vault::create(&path_a, "master").unwrap();
    let id_edit_a = va.add(&input("EditInA", "alice", "v1")).unwrap();
    let id_delete_a = va.add(&input("DeleteInA", "bob", "v1")).unwrap();
    let id_edit_b = va.add(&input("EditInB", "carol", "v1")).unwrap();
    let id_delete_b = va.add(&input("DeleteInB", "dave", "v1")).unwrap();
    va.save().unwrap();
    drop(va);

    std::fs::copy(&path_a, &path_b).unwrap();

    // In Vault A: update EditInA and delete DeleteInA
    let mut va = Vault::open(&path_a, "master").unwrap();
    va.update(id_edit_a, &input("EditInA", "alice", "v2-from-a"))
        .unwrap();
    va.remove(id_delete_a).unwrap();
    va.save().unwrap();

    // In Vault B: update EditInB and delete DeleteInB
    let mut vb = Vault::open(&path_b, "master").unwrap();
    vb.update(id_edit_b, &input("EditInB", "carol", "v2-from-b"))
        .unwrap();
    vb.remove(id_delete_b).unwrap();
    vb.save().unwrap();
    drop(vb);

    // Sync Vault A with Vault B
    let events = va.sync_with_file(&path_b, "master").unwrap();
    assert!(events >= 1);

    // Both Vault A and Vault B must reflect all updates and deletion tombstones from both replicas
    assert_eq!(va.password(id_edit_a).unwrap().as_str(), "v2-from-a");
    assert_eq!(va.password(id_edit_b).unwrap().as_str(), "v2-from-b");
    assert!(matches!(va.details(id_delete_a), Err(VaultError::NotFound)));
    assert!(matches!(va.details(id_delete_b), Err(VaultError::NotFound)));

    let vb = Vault::open(&path_b, "master").unwrap();
    assert_eq!(vb.password(id_edit_a).unwrap().as_str(), "v2-from-a");
    assert_eq!(vb.password(id_edit_b).unwrap().as_str(), "v2-from-b");
    assert!(matches!(vb.details(id_delete_a), Err(VaultError::NotFound)));
    assert!(matches!(vb.details(id_delete_b), Err(VaultError::NotFound)));
}

#[test]
fn attachments_are_stored_protected_in_kdbx4() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "master").unwrap();
    let id = v.add(&input("SSH", "root", "pw")).unwrap();
    v.save().unwrap();

    v.add_attachment(id, "id_ed25519", b"SECRET-SSH-KEY-MATERIAL")
        .unwrap();
    assert!(v.is_attachment_protected(id, "id_ed25519").unwrap());

    drop(v);
    let v_reopened = Vault::open(&path, "master").unwrap();
    assert!(v_reopened
        .is_attachment_protected(id, "id_ed25519")
        .unwrap());
    assert_eq!(
        v_reopened.get_attachment(id, "id_ed25519").unwrap(),
        b"SECRET-SSH-KEY-MATERIAL"
    );
}

#[test]
fn master_password_rotation_is_atomic_and_bumps_revisions() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "old-master").unwrap();
    let id = v.add(&input("AWS", "root", "aws-secret")).unwrap();
    v.save().unwrap();

    let rev_before = v.details(id).unwrap().revision_date.unwrap();

    // Wrong current password (same length, shorter prefix, and longer suffix) must fail with InvalidMasterPassword
    assert!(matches!(
        v.change_master_password("wrong-old!", "new-master"),
        Err(VaultError::InvalidMasterPassword)
    ));
    assert!(matches!(
        v.change_master_password("old", "new-master"),
        Err(VaultError::InvalidMasterPassword)
    ));
    assert!(matches!(
        v.change_master_password("old-master-extra", "new-master"),
        Err(VaultError::InvalidMasterPassword)
    ));
    assert!(matches!(
        v.change_master_password("old-master", ""),
        Err(VaultError::EmptyMasterPassword)
    ));

    // Valid master password rotation
    v.change_master_password("old-master", "new-master-strong")
        .unwrap();
    let rev_after = v.details(id).unwrap().revision_date.unwrap();
    assert!(
        rev_after > rev_before,
        "rotation must bump revision_date on all entries"
    );
    drop(v);

    // Old password must no longer open the vault on disk
    assert!(Vault::open(&path, "old-master").is_err());

    // New password opens the vault and preserves all decrypted secrets
    let v_new = Vault::open(&path, "new-master-strong").unwrap();
    assert_eq!(v_new.password(id).unwrap().as_str(), "aws-secret");
}

#[test]
fn enpass_advanced_password_generator_and_strength_audit() {
    use vaultkeep_core::{
        evaluate_password_strength, generate_password_advanced, AdvancedPasswordPolicy,
    };

    // 1. Default 32-char Enpass policy produces an Excellent password
    let def_pw = generate_password_advanced(&AdvancedPasswordPolicy::default()).unwrap();
    assert_eq!(def_pw.len(), 32);
    let (score, label, compromised) = evaluate_password_strength(&def_pw);
    assert!(score >= 80, "expected >=80, got {score}");
    assert_eq!(label, "Excellent");
    assert!(!compromised);

    // 2. Pronounceable mode respects length, uppercase, digits, and symbols
    let pron_policy = AdvancedPasswordPolicy {
        length: 20,
        pronounceable: true,
        upper: true,
        digits: true,
        symbols: true,
        ..Default::default()
    };
    let pron_pw = generate_password_advanced(&pron_policy).unwrap();
    assert_eq!(pron_pw.len(), 20);
    assert!(pron_pw.chars().any(|c| c.is_ascii_uppercase()));
    assert!(pron_pw.chars().any(|c| c.is_ascii_digit()));

    // 3. Exact mode places exact counts of uppercase, digits, and symbols
    let exact_policy = AdvancedPasswordPolicy {
        length: 16,
        pronounceable: false,
        lower: true,
        upper: true,
        digits: true,
        symbols: true,
        exact_mode: true,
        min_upper: 2,
        min_digits: 3,
        min_symbols: 2,
        ..Default::default()
    };
    let exact_pw = generate_password_advanced(&exact_policy).unwrap();
    assert_eq!(exact_pw.len(), 16);
    assert_eq!(
        exact_pw.chars().filter(|c| c.is_ascii_uppercase()).count(),
        2
    );
    assert_eq!(exact_pw.chars().filter(|c| c.is_ascii_digit()).count(), 3);
    assert_eq!(
        exact_pw
            .chars()
            .filter(|c| !c.is_ascii_alphanumeric())
            .count(),
        2
    );

    // 4. Exclude characters are never emitted
    let excl_policy = AdvancedPasswordPolicy {
        length: 24,
        exclude_chars: "aeiouAEIOU23456789".into(),
        allow_ambiguous: true,
        ..Default::default()
    };
    let excl_pw = generate_password_advanced(&excl_policy).unwrap();
    assert_eq!(excl_pw.len(), 24);
    assert!(!excl_pw.chars().any(|c| "aeiouAEIOU23456789".contains(c)));

    // 5. Adversarial policy rejections (exceeding length or empty pools)
    let impossible = AdvancedPasswordPolicy {
        length: 8,
        min_upper: 5,
        min_digits: 5,
        ..Default::default()
    };
    assert!(generate_password_advanced(&impossible).is_err());

    // 6. Compromised / breached common password detection
    let (bad_score, bad_label, bad_comp) = evaluate_password_strength("password123");
    assert!(bad_comp);
    assert_eq!(bad_label, "Weak");
    assert!(bad_score < 30);
}

#[test]
fn enpass_audit_engine_categories_tags_and_rolling_backups() {
    use vaultkeep_core::EntryMetadata;

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let backup_dir = dir.path().join("Backups");

    let mut v = Vault::create(&path, "master-key").unwrap();

    // 1. Add two entries sharing the same password ("ReusedSecret#2026!") to test Identical detection
    let id1 = v
        .add(&input(
            "Binance",
            "trader@example.com",
            "ReusedSecret#2026!",
        ))
        .unwrap();
    let id2 = v
        .add(&input(
            "Coinspot",
            "trader@example.com",
            "ReusedSecret#2026!",
        ))
        .unwrap();
    // 2. Add an entry with a known compromised password ("123456")
    let id_comp = v.add(&input("LegacyForum", "user", "123456")).unwrap();
    // 3. Add an entry with a strong unique password
    let id_strong = v
        .add(&input(
            "ProtonMail",
            "sec@proton.me",
            "w$ZLV8*2S4.rG_@Z.(Wq#K/.ja>]Dx0s",
        ))
        .unwrap();

    // Set Enpass Category, Tags, Favorite, Archived on id_strong
    v.set_entry_metadata(
        id_strong,
        &EntryMetadata {
            category: "Finance".into(),
            tags: vec!["Crypto".into(), "Cards".into()],
            is_favorite: true,
            is_archived: false,
            is_trashed: false,
            is_compromised: false,
            is_expired: false,
        },
    )
    .unwrap();

    let all = v.search("");
    let s1 = all.iter().find(|e| e.id == id1).unwrap();
    let s2 = all.iter().find(|e| e.id == id2).unwrap();
    assert!(s1.is_identical, "id1 must be flagged as identical/reused");
    assert!(s2.is_identical, "id2 must be flagged as identical/reused");
    assert!(s1.two_fa_supported, "Binance is a 2FA-supported domain");

    let s_comp = all.iter().find(|e| e.id == id_comp).unwrap();
    assert!(s_comp.is_compromised);
    assert!(s_comp.is_weak);
    assert_eq!(s_comp.password_strength, "Weak");

    let s_strong = all.iter().find(|e| e.id == id_strong).unwrap();
    assert!(!s_strong.is_identical);
    assert!(!s_strong.is_weak);
    assert_eq!(s_strong.password_strength, "Excellent");
    assert_eq!(s_strong.category, "Finance");
    assert_eq!(
        s_strong.tags,
        vec!["Crypto".to_string(), "Cards".to_string()]
    );
    assert!(s_strong.is_favorite);

    // Search by tag and category
    assert_eq!(v.search("crypto").len(), 1);
    assert_eq!(v.search("finance").len(), 1);

    // Rolling backups: create 5 backups with max_backups = 3 and verify only latest 3 remain
    for _ in 0..5 {
        let bpath = v.create_backup(&backup_dir, 3).unwrap();
        assert!(bpath.exists());
    }
    let retained: Vec<_> = std::fs::read_dir(&backup_dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .collect();
    assert_eq!(
        retained.len(),
        3,
        "only max_backups=3 snapshots must be preserved"
    );
}

#[test]
fn windows_and_android_passkey_ceremonies_and_adversarial_checks() {
    use vaultkeep_core::{
        passkey::{self, flags},
        PasskeyCeremonyScope, PasskeyChallengeFactory, PasskeyPlatform, PasskeyTokenConfig,
        UserVerificationRequirement, COSE_ALG_ES256,
    };

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("passkey_ceremony.kdbx");
    let mut v = Vault::create(&path, "master-passkey-test").unwrap();

    let mut gh = input("GitHub", "octocat", "pw123");
    gh.url = "https://github.com/login".into();
    let gh_id = v.add(&gh).unwrap();
    v.save().unwrap();

    let factory = PasskeyChallengeFactory::new(PasskeyTokenConfig::default()).unwrap();
    let now_unix = 1_790_000_000i64;

    // 1. Windows Registration (MakeCredential) happy path with UV=true
    let reg_token = factory
        .mint_challenge("github.com", PasskeyCeremonyScope::Registration, now_unix)
        .unwrap();
    let reg_resp = v
        .register_webauthn_passkey(
            gh_id,
            PasskeyPlatform::Windows,
            "github.com",
            "octocat",
            "Octocat GitHub",
            "https://github.com",
            &reg_token,
            &factory,
            now_unix + 5,
            UserVerificationRequirement::Required,
            true,
            &[],
            &[],
            None,
            None,
        )
        .unwrap();

    assert_eq!(reg_resp.rp_id, "github.com");
    assert_eq!(reg_resp.username, "octocat");
    assert_eq!(reg_resp.display_name, "Octocat GitHub");
    assert_eq!(reg_resp.platform, PasskeyPlatform::Windows);
    assert_eq!(reg_resp.authenticator_attachment, "platform");
    assert_eq!(
        reg_resp.transports,
        vec!["hybrid".to_string(), "internal".to_string()]
    );
    assert_eq!(reg_resp.cose_algorithm, COSE_ALG_ES256);
    assert!(reg_resp.cred_props_rk);
    // passkeys.dev synced passkey create flags: UP(0x01) | UV(0x04) | BE(0x08) | BS(0x10) | AT(0x40) = 0x5d
    assert_eq!(
        reg_resp.flags,
        flags::UP | flags::UV | flags::BE | flags::BS | flags::AT
    );
    assert_eq!(reg_resp.flags, 0x5d);

    let cose_bytes = passkey::decode_base64url(&reg_resp.public_key_cose_b64url).unwrap();
    assert_eq!(cose_bytes.len(), 77);
    assert_eq!(
        &cose_bytes[0..7],
        &[0xa5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01]
    );

    // 2. Adversarial: excludeCredentials matching existing credential must fail with InvalidStateError
    let reg_token_dup = factory
        .mint_challenge("github.com", PasskeyCeremonyScope::Registration, now_unix)
        .unwrap();
    let dup_err = v
        .register_webauthn_passkey(
            gh_id,
            PasskeyPlatform::Windows,
            "github.com",
            "octocat",
            "Octocat",
            "https://github.com",
            &reg_token_dup,
            &factory,
            now_unix + 10,
            UserVerificationRequirement::Preferred,
            true,
            std::slice::from_ref(&reg_resp.credential_id),
            &[],
            None,
            None,
        )
        .unwrap_err();
    assert!(matches!(dup_err, VaultError::Policy(_)));

    // 3. Adversarial: Strict User Verification (passkeys.dev Known Issue compliance)
    // Required + user_verified=false MUST fail closed!
    let auth_token = factory
        .mint_challenge("github.com", PasskeyCeremonyScope::Authentication, now_unix)
        .unwrap();
    let uv_err = v
        .authenticate_webauthn_passkey(
            gh_id,
            PasskeyPlatform::Windows,
            "https://github.com",
            &auth_token,
            &factory,
            now_unix + 10,
            UserVerificationRequirement::Required,
            false,
            &[],
            None,
        )
        .unwrap_err();
    assert!(matches!(uv_err, VaultError::Policy(_)));

    // Preferred + user_verified=false MUST succeed with UV=0 (flags = 0x19: UP | BE | BS, no UV!)
    let auth_unverified = v
        .authenticate_webauthn_passkey(
            gh_id,
            PasskeyPlatform::Windows,
            "https://github.com",
            &auth_token,
            &factory,
            now_unix + 10,
            UserVerificationRequirement::Preferred,
            false,
            &[],
            None,
        )
        .unwrap();
    assert!(!auth_unverified.user_verified);
    assert_eq!(auth_unverified.flags, flags::UP | flags::BE | flags::BS);
    assert_eq!(auth_unverified.flags, 0x19);

    // 4. Android Authentication (GetAssertion) with APK key-hash origin and UV=true
    let android_assert = v
        .authenticate_webauthn_passkey(
            gh_id,
            PasskeyPlatform::Android,
            "android:apk-key-hash:p256_apk_signing_cert_sha256_digest_b64url",
            &auth_token,
            &factory,
            now_unix + 15,
            UserVerificationRequirement::Required,
            true,
            &[],
            Some("com.github.android"),
        )
        .unwrap();
    // passkeys.dev synced passkey get flags: UP(0x01) | UV(0x04) | BE(0x08) | BS(0x10) = 0x1d
    assert_eq!(
        android_assert.flags,
        flags::UP | flags::UV | flags::BE | flags::BS
    );
    assert_eq!(android_assert.flags, 0x1d);
    let client_json = String::from_utf8(
        passkey::decode_base64url(&android_assert.client_data_json_b64url).unwrap(),
    )
    .unwrap();
    assert!(client_json.contains(r#""androidPackageName":"com.github.android""#));

    // 5. Adversarial: Expired challenge token, wrong scope, wrong RP ID, and forged factory key
    let expired_err = v
        .authenticate_webauthn_passkey(
            gh_id,
            PasskeyPlatform::Windows,
            "https://github.com",
            &auth_token,
            &factory,
            now_unix + 500, // beyond 120s TTL
            UserVerificationRequirement::Preferred,
            true,
            &[],
            None,
        )
        .unwrap_err();
    assert!(matches!(expired_err, VaultError::Policy(_)));

    let wrong_scope_err = v
        .authenticate_webauthn_passkey(
            gh_id,
            PasskeyPlatform::Windows,
            "https://github.com",
            &reg_token, // Registration token used for Authentication
            &factory,
            now_unix + 10,
            UserVerificationRequirement::Preferred,
            true,
            &[],
            None,
        )
        .unwrap_err();
    assert!(matches!(wrong_scope_err, VaultError::Policy(_)));

    let other_factory = PasskeyChallengeFactory::new(PasskeyTokenConfig::default()).unwrap();
    let forged_err = v
        .authenticate_webauthn_passkey(
            gh_id,
            PasskeyPlatform::Windows,
            "https://github.com",
            &auth_token,
            &other_factory,
            now_unix + 10,
            UserVerificationRequirement::Preferred,
            true,
            &[],
            None,
        )
        .unwrap_err();
    assert!(matches!(forged_err, VaultError::Policy(_)));

    // 6. Related Origin Requests (ROR) 5-unique-eTLD-1 label rule
    // Phishing origin without ROR fails
    assert!(
        passkey::validate_rp_id_for_origin("github.com", "https://evil-github.com", &[]).is_err()
    );

    // ROR with 5 unique labels (where shopping.com and shopping.co.uk count as 1 label "shopping") succeeds
    let valid_ror = vec![
        "https://shopping.com".to_string(),
        "https://shopping.co.uk".to_string(),
        "https://brand-two.com".to_string(),
        "https://brand-three.org".to_string(),
        "https://brand-four.net".to_string(),
        "https://brand-five.io".to_string(),
    ];
    assert!(passkey::validate_rp_id_for_origin(
        "shopping.com",
        "https://brand-five.io",
        &valid_ror
    )
    .is_ok());

    // ROR exceeding 5 unique labels (6 distinct labels) must fail
    let excessive_ror = vec![
        "https://label1.com".to_string(),
        "https://label2.com".to_string(),
        "https://label3.com".to_string(),
        "https://label4.com".to_string(),
        "https://label5.com".to_string(),
        "https://label6.com".to_string(),
    ];
    assert!(
        passkey::validate_rp_id_for_origin("label1.com", "https://label6.com", &excessive_ror)
            .is_err()
    );

    // 7. Optimistic concurrency check on passkey mutations
    let rev = v.details(gh_id).unwrap().revision_date.unwrap();
    let stale_err = v
        .generate_passkey_with_revision(gh_id, "github.com", "octocat", Some(rev - 30))
        .unwrap_err();
    assert!(matches!(stale_err, VaultError::StaleRevision { .. }));

    // 8. Discoverable Credential lookup & WebAuthn Level 3 Signal API
    let discovered = v.find_passkeys_for_rp("login.github.com", &[]);
    assert_eq!(discovered.len(), 1);
    assert_eq!(discovered[0].0, gh_id);

    // signalCurrentUserDetails updates username
    let updated = v
        .signal_current_user_details(
            "github.com",
            &reg_resp.user_handle,
            "octocat-renamed",
            "Octocat Renamed",
        )
        .unwrap();
    assert_eq!(updated, 1);
    assert_eq!(
        v.details(gh_id).unwrap().passkey.unwrap().username,
        "octocat-renamed"
    );

    // signalAllAcceptedCredentials keeps credential when listed, prunes when omitted
    let pruned_none = v
        .signal_all_accepted_credentials(
            "github.com",
            &reg_resp.user_handle,
            std::slice::from_ref(&reg_resp.credential_id),
        )
        .unwrap();
    assert_eq!(pruned_none, 0);
    assert!(v.details(gh_id).unwrap().passkey.is_some());

    let removed = v
        .signal_unknown_credential("github.com", &reg_resp.credential_id)
        .unwrap();
    assert!(removed);
    assert!(v.details(gh_id).unwrap().passkey.is_none());
}

#[test]
fn enpass_structured_fields_custom_fields_and_backup_restore_erase() {
    use zeroize::Zeroizing;

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("structured.kdbx");
    let backup_dir = dir.path().join("Backups");

    let mut v = Vault::create(&path, "master-key").unwrap();

    let mut entry = input("Chase Bank", "alice_banking", "BankPass#99");
    entry.email = "alice@banking.example".into();
    entry.phone = "+1-800-555-0199".into();
    entry.security_question = "Mother's maiden name?".into();
    entry.security_answer = Some(Zeroizing::new("SECRET_ANSWER_8821".into()));
    entry.sections = vec!["WIRE DETAILS".into(), "RECOVERY".into()];
    entry.custom_fields = vec![
        CustomFieldInput {
            name: "Routing Number".into(),
            value: Zeroizing::new("021000021".into()),
            field_type: "text".into(),
            sensitive: false,
            section: "WIRE DETAILS".into(),
        },
        CustomFieldInput {
            name: "Telebanking PIN".into(),
            value: Zeroizing::new("PIN_SECRET_7744".into()),
            field_type: "password".into(),
            sensitive: true,
            section: "RECOVERY".into(),
        },
    ];

    let id = v.add(&entry).unwrap();
    v.save().unwrap();

    // Ensure neither security answer nor sensitive custom field value appears in plaintext on disk
    let raw_bytes = std::fs::read(&path).unwrap();
    let raw_str = String::from_utf8_lossy(&raw_bytes);
    assert!(!raw_str.contains("SECRET_ANSWER_8821"));
    assert!(!raw_str.contains("PIN_SECRET_7744"));

    // Reopen from disk and verify round-trip persistence
    drop(v);
    let mut v = Vault::open(&path, "master-key").unwrap();

    // Search matches email, phone, security_question, and non-sensitive custom field value
    assert_eq!(v.search("alice@banking.example").len(), 1);
    assert_eq!(v.search("800-555-0199").len(), 1);
    assert_eq!(v.search("maiden").len(), 1);
    assert_eq!(v.search("021000021").len(), 1);

    let details = v.details(id).unwrap();
    assert_eq!(details.email, "alice@banking.example");
    assert_eq!(details.phone, "+1-800-555-0199");
    assert_eq!(details.security_question, "Mother's maiden name?");
    assert!(details.has_security_answer);
    assert_eq!(
        details.sections,
        vec!["WIRE DETAILS".to_string(), "RECOVERY".to_string()]
    );
    assert_eq!(details.custom_fields.len(), 2);
    assert_eq!(details.custom_fields[0].name, "Routing Number");
    assert_eq!(details.custom_fields[0].value, "021000021");
    assert!(!details.custom_fields[0].sensitive);
    assert_eq!(details.custom_fields[1].name, "Telebanking PIN");
    assert_eq!(details.custom_fields[1].value, ""); // omitted from summary because sensitive == true
    assert!(details.custom_fields[1].sensitive);

    // Reveal protected values
    assert_eq!(
        v.security_answer(id)
            .unwrap()
            .as_deref()
            .map(|s| s.as_str()),
        Some("SECRET_ANSWER_8821")
    );
    assert_eq!(v.custom_field_value(id, 0).unwrap().as_str(), "021000021");
    assert_eq!(
        v.custom_field_value(id, 1).unwrap().as_str(),
        "PIN_SECRET_7744"
    );
    assert!(v.custom_field_value(id, 99).is_err());

    // Update entry with security_answer: None -> preserves existing security answer!
    let mut upd = input("Chase Bank", "alice_banking", "BankPass#99");
    upd.email = "alice@banking.example".into();
    upd.security_question = "Mother's maiden name?".into();
    upd.security_answer = None; // preserve existing
    upd.custom_fields = vec![CustomFieldInput {
        name: "Single Field".into(),
        value: Zeroizing::new("val".into()),
        field_type: "text".into(),
        sensitive: false,
        section: String::new(),
    }];
    v.update(id, &upd).unwrap();
    v.save().unwrap();
    assert_eq!(
        v.security_answer(id)
            .unwrap()
            .as_deref()
            .map(|s| s.as_str()),
        Some("SECRET_ANSWER_8821")
    );
    assert_eq!(v.details(id).unwrap().custom_fields.len(), 1);
    // Old index 1 must have been cleaned up
    assert!(v.custom_field_value(id, 1).is_err());

    // Vault info check
    let info = v.vault_info();
    assert_eq!(info.entry_count, 1);
    assert_eq!(info.kdf_iterations, 6);

    // Backup list & restore (SEC-007: unrelated .kdbx files in backup_dir are ignored)
    let bpath = v.create_backup(&backup_dir, 5).unwrap();
    std::fs::write(backup_dir.join("other_keepass.kdbx"), b"decoy").unwrap();
    let listed = Vault::list_backups(&backup_dir).unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0], bpath);

    // Mutate current vault (remove entry), then restore from backup
    v.remove(id).unwrap();
    v.save().unwrap();
    assert!(v.search("").is_empty());

    // Wrong password for backup restore must fail without corrupting active vault
    assert!(v.restore_backup(&bpath, "wrong-password").is_err());
    v.restore_backup(&bpath, "master-key").unwrap();
    assert_eq!(v.search("").len(), 1);

    // Erase vault file: wrong master password must fail
    assert!(matches!(
        v.erase_vault_file("wrong-password"),
        Err(VaultError::InvalidMasterPassword)
    ));
    assert!(path.exists());

    v.erase_vault_file("master-key").unwrap();
    assert!(!path.exists());
}

#[test]
fn duplicate_export_and_import_csv_roundtrip_and_adversarial_checks() {
    use zeroize::Zeroizing;

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("menu_ops.kdbx");
    let mut v = Vault::create(&path, "master-secret").unwrap();

    // 1. Add an entry with protected custom fields, security answer, and attachment, then duplicate it
    let mut item = input("GitHub Enterprise", "octocat", "DupPass#2026!");
    item.email = "octocat@github.com".into();
    item.security_question = "Favorite repo?".into();
    item.security_answer = Some(Zeroizing::new("linux".into()));
    item.custom_fields = vec![CustomFieldInput {
        name: "PAT Token".into(),
        value: Zeroizing::new("ghp_secret_999".into()),
        field_type: "password".into(),
        sensitive: true,
        section: "API".into(),
    }];
    let orig_id = v.add(&item).unwrap();
    v.add_attachment(orig_id, "recovery.txt", b"codes-123").unwrap();
    v.save().unwrap();

    // Adversarial: duplicating nonexistent UUID must fail with NotFound
    assert!(matches!(
        v.duplicate_entry(uuid::Uuid::nil()),
        Err(VaultError::NotFound)
    ));

    let dup_id = v.duplicate_entry(orig_id).unwrap();
    assert_ne!(dup_id, orig_id);
    assert_eq!(dup_id.get_version_num(), 7);
    let dup_details = v.details(dup_id).unwrap();
    assert_eq!(dup_details.title, "GitHub Enterprise - Copy");
    assert_eq!(dup_details.username, "octocat");
    assert_eq!(dup_details.email, "octocat@github.com");
    assert_eq!(v.password(dup_id).unwrap().as_str(), "DupPass#2026!");
    assert_eq!(
        v.security_answer(dup_id)
            .unwrap()
            .as_deref()
            .map(|s| s.as_str()),
        Some("linux")
    );
    assert_eq!(
        v.custom_field_value(dup_id, 0).unwrap().as_str(),
        "ghp_secret_999"
    );
    assert_eq!(
        v.get_attachment(dup_id, "recovery.txt").unwrap(),
        b"codes-123"
    );

    // 2. Export checks (adversarial: wrong master password & self-path overwrite rejected)
    let export_kdbx = dir.path().join("exported.kdbx");
    let export_csv = dir.path().join("exported.csv");
    assert!(matches!(
        v.export_vault_file(&export_kdbx, "wrong-master", "kdbx"),
        Err(VaultError::InvalidMasterPassword)
    ));
    assert!(matches!(
        v.export_vault_file(&path, "master-secret", "kdbx"),
        Err(VaultError::SelfMerge)
    ));

    let kdbx_count = v
        .export_vault_file(&export_kdbx, "master-secret", "kdbx")
        .unwrap();
    assert_eq!(kdbx_count, 2);
    let reopened = Vault::open(&export_kdbx, "master-secret").unwrap();
    assert_eq!(reopened.search("").len(), 2);

    let csv_count = v
        .export_vault_file(&export_csv, "master-secret", "csv")
        .unwrap();
    assert_eq!(csv_count, 2);
    let csv_text = std::fs::read_to_string(&export_csv).unwrap();

    // 3. Import CSV into a fresh vault
    let imported_path = dir.path().join("imported.kdbx");
    let mut v2 = Vault::create(&imported_path, "import-master").unwrap();
    let imported_n = v2.import_csv(&csv_text).unwrap();
    assert_eq!(imported_n, 2);
    let hits = v2.search("GitHub Enterprise");
    assert_eq!(hits.len(), 2);
}

