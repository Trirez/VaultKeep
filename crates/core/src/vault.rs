use std::{
    fmt,
    fs::{self, File},
    io::{BufReader, BufWriter, Write},
    path::{Path, PathBuf},
};

use keepass::{
    db::{fields, EntryId, GroupId, GroupRef, Value},
    Database, DatabaseKey,
};
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::VaultError;

/// Attachment summary for list display.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AttachmentSummary {
    pub name: String,
    pub size: usize,
}

/// Group summary.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GroupSummary {
    pub id: Uuid,
    pub name: String,
    pub entry_count: usize,
}

/// Generated TOTP token.
#[derive(Clone, PartialEq, Eq)]
pub struct TotpToken {
    pub code: String,
    pub seconds_remaining: u32,
    pub period: u32,
}

impl fmt::Debug for TotpToken {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("TotpToken")
            .field("code", &"[REDACTED]")
            .field("seconds_remaining", &self.seconds_remaining)
            .field("period", &self.period)
            .finish()
    }
}

/// Data needed to create or update an entry. Secrets are zeroized on drop.
#[derive(Default)]
pub struct EntryInput {
    pub title: String,
    pub username: String,
    pub password: Zeroizing<String>,
    pub url: String,
    pub notes: String,
    pub group_id: Option<Uuid>,
    pub otp: Option<Zeroizing<String>>,
}

impl fmt::Debug for EntryInput {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("EntryInput")
            .field("title", &self.title)
            .field("username", &self.username)
            .field("password", &"[REDACTED]")
            .field("url", &self.url)
            .field("notes", &self.notes)
            .field("group_id", &self.group_id)
            .field("otp", &self.otp.as_ref().map(|_| "[REDACTED]"))
            .finish()
    }
}

/// Non-secret view of an entry, safe to show in lists.
#[derive(Debug, Clone)]
pub struct EntrySummary {
    pub id: Uuid,
    pub title: String,
    pub username: String,
    pub url: String,
    pub group_name: Option<String>,
}

/// Full non-secret fields of one entry, for an edit screen.
#[derive(Clone)]
pub struct EntryDetails {
    pub id: Uuid,
    pub title: String,
    pub username: String,
    pub url: String,
    pub notes: String,
    pub group_id: Option<Uuid>,
    pub group_name: Option<String>,
    pub otp_uri: Option<String>,
    pub attachments: Vec<AttachmentSummary>,
}

impl fmt::Debug for EntryDetails {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
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

/// Maximum vault file size accepted (100 MB). Prevents resource exhaustion from malicious files.
pub const MAX_VAULT_BYTES: u64 = 100 * 1024 * 1024;

/// Maximum single attachment size (25 MB).
pub const MAX_ATTACHMENT_BYTES: usize = 25 * 1024 * 1024;

pub struct Vault {
    db: Database,
    path: PathBuf,
    master: Zeroizing<String>,
}

impl fmt::Debug for Vault {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Vault")
            .field("path", &self.path)
            .field("master", &"[REDACTED]")
            .finish()
    }
}

impl Vault {
    /// Create a new KDBX4 vault at `path` (fails if the file already exists).
    pub fn create(path: impl AsRef<Path>, master: &str) -> Result<Self, VaultError> {
        if master.is_empty() {
            return Err(VaultError::EmptyMasterPassword);
        }
        let path = path.as_ref().to_path_buf();
        if path.exists() {
            return Err(VaultError::Io(std::io::Error::new(
                std::io::ErrorKind::AlreadyExists,
                "vault file already exists",
            )));
        }
        let vault = Self {
            db: Database::new(),
            path,
            master: Zeroizing::new(master.to_owned()),
        };
        vault.save()?;
        Ok(vault)
    }

    pub fn open(path: impl AsRef<Path>, master: &str) -> Result<Self, VaultError> {
        let path = path.as_ref().to_path_buf();
        let file = File::open(&path)?;
        let metadata = file.metadata()?;
        if metadata.len() > MAX_VAULT_BYTES {
            return Err(VaultError::FileTooLarge(metadata.len(), MAX_VAULT_BYTES));
        }
        if metadata.len() == 0 {
            return Err(VaultError::Malformed("vault file is empty"));
        }
        let mut reader = BufReader::new(file);
        let db = Database::open(&mut reader, key(master))?;
        Ok(Self {
            db,
            path,
            master: Zeroizing::new(master.to_owned()),
        })
    }

    /// Atomic save: write a temp file next to the vault, fsync, then rename.
    /// A crash mid-write can never corrupt the existing vault.
    pub fn save(&self) -> Result<(), VaultError> {
        self.save_to(&self.path, &self.master)
    }

    /// Atomic save to a specific destination path with a given master password.
    pub fn save_to(&self, dest_path: impl AsRef<Path>, master: &str) -> Result<(), VaultError> {
        let dest = dest_path.as_ref();
        let parent = dest.parent().unwrap_or_else(|| Path::new("."));
        let mut tmp_file = tempfile::Builder::new()
            .prefix(".vaultkeep_tmp_")
            .suffix(".kdbx")
            .tempfile_in(parent)?;

        let write_res = (|| -> Result<(), VaultError> {
            {
                let mut w = BufWriter::new(&mut tmp_file);
                self.db.save(&mut w, key(master))?;
                w.flush()?;
            }
            tmp_file.as_file().sync_all()?;
            Ok(())
        })();

        write_res?;

        tmp_file.persist(dest).map_err(|e| e.error)?;
        Ok(())
    }

    pub fn add(&mut self, input: &EntryInput) -> Uuid {
        if let Some(gid) = input.group_id {
            if let Some(mut grp) = self.db.group_mut(GroupId::from(gid)) {
                let mut entry = grp.add_entry();
                apply(&mut entry, input);
                return entry.id().uuid();
            }
        }
        let mut root = self.db.root_mut();
        let mut entry = root.add_entry();
        apply(&mut entry, input);
        entry.id().uuid()
    }

    pub fn update(&mut self, id: Uuid, input: &EntryInput) -> Result<(), VaultError> {
        let eid = self.find(id)?;
        let target_group_id = match input.group_id {
            Some(gid) => GroupId::from(gid),
            None => self.db.root().id(),
        };
        let mut entry = self.db.entry_mut(eid).ok_or(VaultError::NotFound)?;
        apply(&mut entry, input);
        if entry.parent_mut().id() != target_group_id {
            entry
                .move_to(target_group_id)
                .map_err(|_| VaultError::GroupNotFound)?;
        }
        Ok(())
    }

    pub fn remove(&mut self, id: Uuid) -> Result<(), VaultError> {
        let eid = self.find(id)?;
        self.db.entry_mut(eid).ok_or(VaultError::NotFound)?.remove();
        Ok(())
    }

    /// Case-insensitive match on title, username, URL, or group name. Empty query lists all.
    pub fn search(&self, query: &str) -> Vec<EntrySummary> {
        let q = query.to_lowercase();
        let mut out: Vec<EntrySummary> = self
            .db
            .iter_all_entries()
            .map(|e| {
                let parent = e.parent();
                let group_name = if parent.name.is_empty() {
                    None
                } else {
                    Some(parent.name.clone())
                };
                EntrySummary {
                    id: e.id().uuid(),
                    title: e.get_title().unwrap_or_default().to_owned(),
                    username: e.get_username().unwrap_or_default().to_owned(),
                    url: e.get_url().unwrap_or_default().to_owned(),
                    group_name,
                }
            })
            .filter(|s| {
                q.is_empty()
                    || s.title.to_lowercase().contains(&q)
                    || s.username.to_lowercase().contains(&q)
                    || s.url.to_lowercase().contains(&q)
                    || s.group_name
                        .as_deref()
                        .unwrap_or_default()
                        .to_lowercase()
                        .contains(&q)
            })
            .collect();
        out.sort_by_key(|a| a.title.to_lowercase());
        out
    }

    /// Non-secret fields of one entry (the password is fetched separately).
    pub fn details(&self, id: Uuid) -> Result<EntryDetails, VaultError> {
        let eid = self.find(id)?;
        let e = self.db.entry(eid).ok_or(VaultError::NotFound)?;
        let field = |k: &str| e.get(k).unwrap_or_default().to_owned();
        let parent = e.parent();
        let is_root = parent.id() == self.db.root().id();
        let group_id = if is_root {
            None
        } else {
            Some(parent.id().uuid())
        };
        let group_name = if parent.name.is_empty() {
            None
        } else {
            Some(parent.name.clone())
        };
        let otp_uri = e.get_raw_otp_value().map(|s| s.to_string());
        let attachments = e
            .attachments_named()
            .map(|(name, att)| AttachmentSummary {
                name: name.to_string(),
                size: att.data.len(),
            })
            .collect();

        Ok(EntryDetails {
            id,
            title: field(fields::TITLE),
            username: field(fields::USERNAME),
            url: field(fields::URL),
            notes: field(fields::NOTES),
            group_id,
            group_name,
            otp_uri,
            attachments,
        })
    }

    /// Fetch the password only when explicitly requested (e.g. on copy).
    pub fn password(&self, id: Uuid) -> Result<Zeroizing<String>, VaultError> {
        let eid = self.find(id)?;
        let e = self.db.entry(eid).ok_or(VaultError::NotFound)?;
        Ok(Zeroizing::new(
            e.get_password().unwrap_or_default().to_owned(),
        ))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    // --- Groups API ---

    pub fn list_groups(&self) -> Vec<GroupSummary> {
        let mut list = Vec::new();
        fn collect_groups(group: GroupRef<'_>, list: &mut Vec<GroupSummary>) {
            let entry_count = group.entries().count();
            list.push(GroupSummary {
                id: group.id().uuid(),
                name: group.name.clone(),
                entry_count,
            });
            for sub in group.groups() {
                collect_groups(sub, list);
            }
        }
        collect_groups(self.db.root(), &mut list);
        list
    }

    pub fn create_group(&mut self, name: &str) -> Result<Uuid, VaultError> {
        let mut root = self.db.root_mut();
        let mut grp = root.add_group();
        grp.name = name.to_string();
        let id = grp.id().uuid();
        self.save()?;
        Ok(id)
    }

    // --- TOTP API ---

    pub fn totp(&self, id: Uuid) -> Result<Option<TotpToken>, VaultError> {
        let eid = self.find(id)?;
        let entry = self.db.entry(eid).ok_or(VaultError::NotFound)?;
        match entry.get_otp() {
            Ok(totp) => {
                let otp_code = totp
                    .value_now()
                    .map_err(|_| VaultError::Policy("system clock error"))?;
                Ok(Some(TotpToken {
                    code: otp_code.code,
                    seconds_remaining: otp_code.valid_for.as_secs() as u32,
                    period: otp_code.period.as_secs() as u32,
                }))
            }
            Err(keepass::db::TOTPError::NoRecord) => Ok(None),
            Err(e) => Err(VaultError::Totp(e)),
        }
    }

    // --- Attachments API ---

    pub fn add_attachment(
        &mut self,
        entry_id: Uuid,
        name: &str,
        data: &[u8],
    ) -> Result<(), VaultError> {
        if data.len() > MAX_ATTACHMENT_BYTES {
            return Err(VaultError::AttachmentTooLarge(
                data.len(),
                MAX_ATTACHMENT_BYTES,
            ));
        }
        if name.trim().is_empty() {
            return Err(VaultError::Policy("attachment name must not be empty"));
        }
        let eid = self.find(entry_id)?;
        let mut entry = self.db.entry_mut(eid).ok_or(VaultError::NotFound)?;
        entry.add_attachment(name.to_string(), Value::unprotected(data.to_vec()));
        self.save()?;
        Ok(())
    }

    pub fn get_attachment(&self, entry_id: Uuid, name: &str) -> Result<Vec<u8>, VaultError> {
        let eid = self.find(entry_id)?;
        let entry = self.db.entry(eid).ok_or(VaultError::NotFound)?;
        let att = entry
            .attachment_by_name(name)
            .ok_or(VaultError::AttachmentNotFound)?;
        Ok(att.data.get().clone())
    }

    pub fn remove_attachment(&mut self, entry_id: Uuid, name: &str) -> Result<(), VaultError> {
        let eid = self.find(entry_id)?;
        let mut entry = self.db.entry_mut(eid).ok_or(VaultError::NotFound)?;
        entry.remove_attachment_by_name(name);
        self.save()?;
        Ok(())
    }

    pub fn list_attachments(&self, entry_id: Uuid) -> Result<Vec<AttachmentSummary>, VaultError> {
        let eid = self.find(entry_id)?;
        let entry = self.db.entry(eid).ok_or(VaultError::NotFound)?;
        let mut list = Vec::new();
        for (name, att) in entry.attachments_named() {
            list.push(AttachmentSummary {
                name: name.to_string(),
                size: att.data.len(),
            });
        }
        Ok(list)
    }

    // --- Sync / 3-Way Merge API ---

    /// Merges changes from `other_path` into `self`.
    /// If `other_master` is empty, uses `self.master` as the credential.
    pub fn merge_from_file(
        &mut self,
        other_path: impl AsRef<Path>,
        other_master: &str,
    ) -> Result<usize, VaultError> {
        let other_path = other_path.as_ref();
        if self.is_same_path(other_path) {
            return Err(VaultError::SelfMerge);
        }
        let effective_master = if other_master.is_empty() {
            &self.master
        } else {
            other_master
        };
        let other = Vault::open(other_path, effective_master)?;
        if self.db.root().id().uuid() != other.db.root().id().uuid() {
            return Err(VaultError::IncompatibleVaultRoots);
        }
        let log = self.db.merge(&other.db)?;
        self.save()?;
        Ok(log.events.len())
    }

    /// Bidirectional sync: merges `other_path` into `self`, saves `self`,
    /// and also updates `other_path` with the unified merged database.
    pub fn sync_with_file(
        &mut self,
        other_path: impl AsRef<Path>,
        other_master: &str,
    ) -> Result<usize, VaultError> {
        let other_path = other_path.as_ref();
        if self.is_same_path(other_path) {
            return Err(VaultError::SelfMerge);
        }
        let effective_master = if other_master.is_empty() {
            &self.master
        } else {
            other_master
        };
        let other = Vault::open(other_path, effective_master)?;
        if self.db.root().id().uuid() != other.db.root().id().uuid() {
            return Err(VaultError::IncompatibleVaultRoots);
        }
        let log = self.db.merge(&other.db)?;
        self.save()?;
        self.save_to(other_path, effective_master)?;
        Ok(log.events.len())
    }

    fn is_same_path(&self, other: &Path) -> bool {
        if self.path == other {
            return true;
        }
        match (fs::canonicalize(&self.path), fs::canonicalize(other)) {
            (Ok(p1), Ok(p2)) => p1 == p2,
            _ => false,
        }
    }

    // --- Autofill Domain Query ---

    pub fn find_for_domain(&self, target_domain: &str) -> Vec<EntrySummary> {
        let target_clean = clean_domain_or_host(target_domain);
        if target_clean.is_empty() {
            return Vec::new();
        }

        self.search("")
            .into_iter()
            .filter(|e| {
                if !e.url.trim().is_empty() {
                    let entry_host = clean_domain_or_host(&e.url);
                    if matches_host(&entry_host, &target_clean) {
                        return true;
                    }
                }

                // If URL is empty or did not match, fallback to strict title match:
                // Only match if title equals target query or title has an exact matching word.
                // NEVER do `target.contains(title)` as that permits phishing domains to match!
                let title_lower = e.title.to_lowercase();
                if title_lower == target_clean {
                    return true;
                }
                if !target_clean.contains('.') {
                    title_lower
                        .split(|c: char| !c.is_alphanumeric())
                        .any(|word| word == target_clean)
                } else {
                    false
                }
            })
            .collect()
    }

    fn find(&self, id: Uuid) -> Result<EntryId, VaultError> {
        self.db
            .iter_all_entries()
            .find(|e| e.id().uuid() == id)
            .map(|e| e.id())
            .ok_or(VaultError::NotFound)
    }
}

fn clean_domain_or_host(input: &str) -> String {
    let s = input.trim().to_lowercase();
    let s = if let Some(idx) = s.find("://") {
        &s[idx + 3..]
    } else {
        &s
    };
    let s = s.split(['/', '?', '#']).next().unwrap_or(s);
    let s = if let Some(idx) = s.rfind('@') {
        &s[idx + 1..]
    } else {
        s
    };
    let s = s.split(':').next().unwrap_or(s);
    let s = s.strip_prefix("www.").unwrap_or(s);
    s.trim_end_matches('.').to_string()
}

fn matches_host(entry_host: &str, target_host: &str) -> bool {
    if entry_host.is_empty() || target_host.is_empty() {
        return false;
    }
    if entry_host == target_host {
        return true;
    }
    if entry_host.ends_with(&format!(".{target_host}")) {
        return true;
    }
    if target_host.ends_with(&format!(".{entry_host}")) {
        return true;
    }
    false
}

fn key(master: &str) -> DatabaseKey {
    DatabaseKey::new().with_password(master)
}

fn apply(entry: &mut keepass::db::EntryMut<'_>, input: &EntryInput) {
    entry.set_unprotected(fields::TITLE, input.title.as_str());
    entry.set_unprotected(fields::USERNAME, input.username.as_str());
    entry.set_protected(fields::PASSWORD, input.password.as_str());
    entry.set_unprotected(fields::URL, input.url.as_str());
    entry.set_unprotected(fields::NOTES, input.notes.as_str());
    if let Some(ref otp) = input.otp {
        if otp.is_empty() {
            entry.fields.remove(fields::OTP);
        } else {
            entry.set_protected(fields::OTP, otp.as_str());
        }
    }
}
