//! Public API surface scanned by `flutter_rust_bridge_codegen`.
//!
//! Every `pub` item here becomes a Dart function or class. Rules:
//! - use `u32`/`i32`, never `usize` (it becomes `BigInt` in Dart);
//! - errors are plain strings that never contain secrets;
//! - list/detail types carry no password; it is fetched only by `reveal_password`.

use std::sync::{Mutex, MutexGuard};

use uuid::Uuid;
use vaultkeep_core::{generate_password, EntryInput, PasswordPolicy};
use zeroize::Zeroizing;

use crate::session::Session;

static SESSION: Mutex<Session> = Mutex::new(Session::new());

fn session() -> MutexGuard<'static, Session> {
    SESSION
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn parse_id(id: &str) -> Result<Uuid, String> {
    Uuid::parse_str(id).map_err(|_| "invalid entry id".to_string())
}

/// One row in the entry list. No secrets.
#[derive(Debug, Clone)]
pub struct EntryItem {
    pub id: String,
    pub title: String,
    pub username: String,
    pub url: String,
    pub group_name: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AttachmentItem {
    pub name: String,
    pub size: u32,
}

#[derive(Debug, Clone)]
pub struct GroupItem {
    pub id: String,
    pub name: String,
    pub entry_count: u32,
}

#[derive(Clone)]
pub struct TotpItem {
    pub code: String,
    pub seconds_remaining: u32,
    pub period: u32,
}

impl std::fmt::Debug for TotpItem {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TotpItem")
            .field("code", &"[REDACTED]")
            .field("seconds_remaining", &self.seconds_remaining)
            .field("period", &self.period)
            .finish()
    }
}

/// Everything about an entry except its password.
#[derive(Clone)]
pub struct EntryDetails {
    pub id: String,
    pub title: String,
    pub username: String,
    pub url: String,
    pub notes: String,
    pub group_id: Option<String>,
    pub group_name: Option<String>,
    pub otp_uri: Option<String>,
    pub attachments: Vec<AttachmentItem>,
}

impl std::fmt::Debug for EntryDetails {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EntryDetails")
            .field("id", &self.id)
            .field("title", &self.title)
            .field("username", &self.username)
            .field("url", &self.url)
            .field("notes", &self.notes)
            .field("group_id", &self.group_id)
            .field("group_name", &self.group_name)
            .field("otp_uri", &self.otp_uri.as_ref().map(|_| "[REDACTED]"))
            .field("attachments", &self.attachments)
            .finish()
    }
}

/// Data from the edit screen. Deliberately no `Debug` (it holds a password).
pub struct EntryData {
    pub title: String,
    pub username: String,
    pub password: String,
    pub url: String,
    pub notes: String,
    pub group_id: Option<String>,
    pub otp: Option<String>,
}

/// Create a new vault file and leave it unlocked. Fails if the file exists.
pub fn create_vault(path: String, master: String) -> Result<(), String> {
    let master = Zeroizing::new(master);
    session().create(&path, &master).map_err(|e| e.to_string())
}

pub fn unlock_vault(path: String, master: String) -> Result<(), String> {
    let master = Zeroizing::new(master);
    session().unlock(&path, &master).map_err(|e| e.to_string())
}

/// Drop the open vault; its master password is zeroized.
pub fn lock_vault() {
    session().lock();
}

pub fn is_unlocked() -> bool {
    session().is_unlocked()
}

pub fn list_entries(query: String) -> Result<Vec<EntryItem>, String> {
    let found = session().search(&query).map_err(|e| e.to_string())?;
    Ok(found
        .into_iter()
        .map(|s| EntryItem {
            id: s.id.to_string(),
            title: s.title,
            username: s.username,
            url: s.url,
            group_name: s.group_name,
        })
        .collect())
}

pub fn get_entry(id: String) -> Result<EntryDetails, String> {
    let d = session()
        .details(parse_id(&id)?)
        .map_err(|e| e.to_string())?;
    Ok(EntryDetails {
        id: d.id.to_string(),
        title: d.title,
        username: d.username,
        url: d.url,
        notes: d.notes,
        group_id: d.group_id.map(|g| g.to_string()),
        group_name: d.group_name,
        otp_uri: d.otp_uri,
        attachments: d
            .attachments
            .into_iter()
            .map(|a| AttachmentItem {
                name: a.name,
                size: a.size as u32,
            })
            .collect(),
    })
}

/// The only call that returns a password. Use for copy/reveal.
pub fn reveal_password(id: String) -> Result<String, String> {
    let pw = session()
        .password(parse_id(&id)?)
        .map_err(|e| e.to_string())?;
    Ok(pw.to_string())
}

/// Add (`id == None`) or update an entry and save the vault. Returns the entry id.
pub fn save_entry(id: Option<String>, data: EntryData) -> Result<String, String> {
    let id = id.as_deref().map(parse_id).transpose()?;
    let group_id = data.group_id.as_deref().map(parse_id).transpose()?;
    let input = EntryInput {
        title: data.title,
        username: data.username,
        password: Zeroizing::new(data.password),
        url: data.url,
        notes: data.notes,
        group_id,
        otp: data.otp.map(Zeroizing::new),
    };
    session()
        .save_entry(id, &input)
        .map(|id| id.to_string())
        .map_err(|e| e.to_string())
}

pub fn delete_entry(id: String) -> Result<(), String> {
    session().delete(parse_id(&id)?).map_err(|e| e.to_string())
}

/// Random password from the OS CSPRNG (lower, upper, digits, optional symbols).
pub fn generate_new_password(length: u32, symbols: bool) -> Result<String, String> {
    let policy = PasswordPolicy {
        length: length as usize,
        symbols,
        ..Default::default()
    };
    generate_password(&policy).map_err(|e| e.to_string())
}

pub fn list_groups() -> Result<Vec<GroupItem>, String> {
    let list = session().list_groups().map_err(|e| e.to_string())?;
    Ok(list
        .into_iter()
        .map(|g| GroupItem {
            id: g.id.to_string(),
            name: g.name,
            entry_count: g.entry_count as u32,
        })
        .collect())
}

pub fn create_group(name: String) -> Result<String, String> {
    session()
        .create_group(&name)
        .map(|id| id.to_string())
        .map_err(|e| e.to_string())
}

pub fn get_totp(id: String) -> Result<Option<TotpItem>, String> {
    let token = session().totp(parse_id(&id)?).map_err(|e| e.to_string())?;
    Ok(token.map(|t| TotpItem {
        code: t.code,
        seconds_remaining: t.seconds_remaining,
        period: t.period,
    }))
}

pub fn add_attachment(entry_id: String, name: String, data: Vec<u8>) -> Result<(), String> {
    session()
        .add_attachment(parse_id(&entry_id)?, &name, &data)
        .map_err(|e| e.to_string())
}

pub fn get_attachment(entry_id: String, name: String) -> Result<Vec<u8>, String> {
    session()
        .get_attachment(parse_id(&entry_id)?, &name)
        .map_err(|e| e.to_string())
}

pub fn remove_attachment(entry_id: String, name: String) -> Result<(), String> {
    session()
        .remove_attachment(parse_id(&entry_id)?, &name)
        .map_err(|e| e.to_string())
}

pub fn list_attachments(entry_id: String) -> Result<Vec<AttachmentItem>, String> {
    let list = session()
        .list_attachments(parse_id(&entry_id)?)
        .map_err(|e| e.to_string())?;
    Ok(list
        .into_iter()
        .map(|a| AttachmentItem {
            name: a.name,
            size: a.size as u32,
        })
        .collect())
}

pub fn merge_vault(other_path: String, other_master: String) -> Result<u32, String> {
    let other_master = Zeroizing::new(other_master);
    let count = session()
        .merge(&other_path, &other_master)
        .map_err(|e| e.to_string())?;
    Ok(count as u32)
}

pub fn find_entries_for_domain(domain: String) -> Result<Vec<EntryItem>, String> {
    let list = session()
        .find_for_domain(&domain)
        .map_err(|e| e.to_string())?;
    Ok(list
        .into_iter()
        .map(|s| EntryItem {
            id: s.id.to_string(),
            title: s.title,
            username: s.username,
            url: s.url,
            group_name: s.group_name,
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn data(password: &str) -> EntryData {
        EntryData {
            title: "GitHub".into(),
            username: "kingshuk".into(),
            password: password.into(),
            url: "https://github.com".into(),
            notes: "n".into(),
            group_id: None,
            otp: None,
        }
    }

    // One sequential test: the API owns a process-wide session.
    #[test]
    fn full_flow_through_the_api() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("v.kdbx").to_string_lossy().into_owned();
        let master = "correct horse battery".to_string();

        create_vault(path.clone(), master.clone()).unwrap();
        assert!(is_unlocked());

        let gid = create_group("Engineering".into()).unwrap();
        let groups = list_groups().unwrap();
        assert!(groups
            .iter()
            .any(|g| g.id == gid && g.name == "Engineering"));

        let mut entry_input = data("pw-1");
        entry_input.group_id = Some(gid.clone());
        entry_input.otp =
            Some("otpauth://totp/GH:kingshuk?secret=JBSWY3DPEHPK3PXP&period=30&digits=6".into());

        let id = save_entry(None, entry_input).unwrap();
        assert_eq!(list_entries("git".into()).unwrap().len(), 1);
        let details = get_entry(id.clone()).unwrap();
        assert_eq!(details.notes, "n");
        assert_eq!(details.group_id, Some(gid));
        assert_eq!(details.group_name.as_deref(), Some("Engineering"));
        assert!(details.otp_uri.is_some());
        assert_eq!(reveal_password(id.clone()).unwrap(), "pw-1");

        let token = get_totp(id.clone()).unwrap().expect("totp token present");
        assert_eq!(token.code.len(), 6);

        add_attachment(id.clone(), "token.txt".into(), b"my-token".to_vec()).unwrap();
        let atts = list_attachments(id.clone()).unwrap();
        assert_eq!(atts.len(), 1);
        assert_eq!(atts[0].name, "token.txt");
        assert_eq!(atts[0].size, 8);
        assert_eq!(
            get_attachment(id.clone(), "token.txt".into()).unwrap(),
            b"my-token"
        );

        remove_attachment(id.clone(), "token.txt".into()).unwrap();
        assert!(list_attachments(id.clone()).unwrap().is_empty());

        let domain_hits = find_entries_for_domain("github.com".into()).unwrap();
        assert_eq!(domain_hits.len(), 1);

        save_entry(Some(id.clone()), data("pw-2")).unwrap();
        assert_eq!(reveal_password(id.clone()).unwrap(), "pw-2");

        lock_vault();
        assert!(!is_unlocked());
        assert_eq!(list_entries(String::new()).unwrap_err(), "vault is locked");
        assert!(unlock_vault(path.clone(), "wrong".into()).is_err());
        assert!(!is_unlocked());

        unlock_vault(path, master).unwrap();
        assert_eq!(reveal_password(id.clone()).unwrap(), "pw-2");
        delete_entry(id).unwrap();
        assert!(list_entries(String::new()).unwrap().is_empty());
        lock_vault();

        assert_eq!(
            get_entry("not-a-uuid".into()).unwrap_err(),
            "invalid entry id"
        );
        assert_eq!(generate_new_password(20, false).unwrap().len(), 20);
    }
}
