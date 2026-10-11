use vaultkeep_core::{EntryInput, Vault, VaultError};

#[test]
fn details_return_fields_without_password() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("v.kdbx");
    let mut v = Vault::create(&path, "m").unwrap();
    let id = v
        .add(&EntryInput {
            title: "Mail".into(),
            username: "me".into(),
            password: "pw".to_string().into(),
            url: "https://mail.example".into(),
            notes: "backup codes in safe".into(),
            ..Default::default()
        })
        .unwrap();

    let d = v.details(id).unwrap();
    assert_eq!(d.id, id);
    assert_eq!(d.title, "Mail");
    assert_eq!(d.username, "me");
    assert_eq!(d.url, "https://mail.example");
    assert_eq!(d.notes, "backup codes in safe");
    assert!(!d.has_otp);
    assert!(d.revision_date.is_some());

    assert!(matches!(
        v.details(uuid::Uuid::nil()),
        Err(VaultError::NotFound)
    ));
}
