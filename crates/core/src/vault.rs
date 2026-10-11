use std::{
    fmt,
    fs::{self, File},
    io::{BufReader, BufWriter, Write},
    path::{Path, PathBuf},
    time::Duration,
};

use keepass::{
    config::{DatabaseConfig, KdfConfig},
    db::{fields, EntryId, GroupId, GroupRef, Times, Value},
    Database, DatabaseKey,
};
use rand::RngCore;
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::VaultError;

const KPEX_PASSKEY_CREDENTIAL_ID: &str = "KPEX_PASSKEY_CREDENTIAL_ID";
const KPEX_PASSKEY_PRIVATE_KEY_PEM: &str = "KPEX_PASSKEY_PRIVATE_KEY_PEM";
const KPEX_PASSKEY_RELYING_PARTY: &str = "KPEX_PASSKEY_RELYING_PARTY";
const KPEX_PASSKEY_USERNAME: &str = "KPEX_PASSKEY_USERNAME";
const KPEX_PASSKEY_USER_HANDLE: &str = "KPEX_PASSKEY_USER_HANDLE";
const KPEX_PASSKEY_FLAG_BE: &str = "KPEX_PASSKEY_FLAG_BE";
const KPEX_PASSKEY_FLAG_BS: &str = "KPEX_PASSKEY_FLAG_BS";
const KPEX_PASSKEY_SIGN_COUNT: &str = "KPEX_PASSKEY_SIGN_COUNT";
const KPEX_PASSKEY_DISPLAY_NAME: &str = "KPEX_PASSKEY_DISPLAY_NAME";

const VK_CATEGORY: &str = "VK_CATEGORY";
const VK_TAGS: &str = "VK_TAGS";
const VK_FAVORITE: &str = "VK_FAVORITE";
const VK_ARCHIVED: &str = "VK_ARCHIVED";
const VK_TRASHED: &str = "VK_TRASHED";
const VK_COMPROMISED: &str = "VK_COMPROMISED";
const VK_EXPIRED: &str = "VK_EXPIRED";
const VK_EMAIL: &str = "VK_EMAIL";
const VK_PHONE: &str = "VK_PHONE";
const VK_SECURITY_QUESTION: &str = "VK_SECURITY_QUESTION";
const VK_SECURITY_ANSWER: &str = "VK_SECURITY_ANSWER";
const VK_SECTIONS: &str = "VK_SECTIONS";
const VK_CF_COUNT: &str = "VK_CF_COUNT";

/// Enpass-compatible custom field input. Sensitive values are wrapped in `Zeroizing`
/// and persisted as KDBX4 `Value::Protected` (ChaCha20 inner stream encrypted).
#[derive(Clone, PartialEq, Eq)]
pub struct CustomFieldInput {
    pub name: String,
    pub field_type: String,
    pub section: String,
    pub sensitive: bool,
    pub value: Zeroizing<String>,
}

impl fmt::Debug for CustomFieldInput {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let val: &str = if self.sensitive {
            "[REDACTED]"
        } else {
            self.value.as_str()
        };
        f.debug_struct("CustomFieldInput")
            .field("name", &self.name)
            .field("field_type", &self.field_type)
            .field("section", &self.section)
            .field("sensitive", &self.sensitive)
            .field("value", &val)
            .finish()
    }
}

/// Non-secret metadata + non-sensitive value for a custom field returned in `EntryDetails`.
/// When `sensitive == true`, `value` is empty here and fetched only via `Vault::custom_field_value`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CustomFieldSummary {
    pub name: String,
    pub field_type: String,
    pub section: String,
    pub sensitive: bool,
    pub value: String,
}

/// Non-secret vault container and KDF summary for `Settings -> Vaults -> VAULT INFO`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VaultInfo {
    pub path: String,
    pub entry_count: usize,
    pub group_count: usize,
    pub kdf_iterations: u64,
    pub kdf_memory_bytes: u64,
    pub kdf_parallelism: u32,
}

/// Enpass-compatible item organization and lifecycle metadata stored in KDBX4 custom fields.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct EntryMetadata {
    pub category: String,
    pub tags: Vec<String>,
    pub is_favorite: bool,
    pub is_archived: bool,
    pub is_trashed: bool,
    pub is_compromised: bool,
    pub is_expired: bool,
}

/// Hardened Argon2id KDF parameters and range bounds for KDBX4 vaults.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KdfParams {
    pub iterations: u64,
    pub memory_bytes: u64,
    pub parallelism: u32,
}

impl KdfParams {
    pub const MIN_ITERATIONS: u64 = 2;
    pub const MAX_ITERATIONS: u64 = 10;
    pub const DEFAULT_ITERATIONS: u64 = 6;

    pub const MIN_MEMORY_BYTES: u64 = 15 * 1024 * 1024;
    pub const MAX_MEMORY_BYTES: u64 = 1024 * 1024 * 1024;
    pub const DEFAULT_MEMORY_BYTES: u64 = 32 * 1024 * 1024;

    pub const MIN_PARALLELISM: u32 = 1;
    pub const MAX_PARALLELISM: u32 = 16;
    pub const DEFAULT_PARALLELISM: u32 = 4;

    pub fn validate(&self) -> Result<(), VaultError> {
        if !(Self::MIN_ITERATIONS..=Self::MAX_ITERATIONS).contains(&self.iterations) {
            return Err(VaultError::WeakKdfParameters(
                "Argon2id iterations must be between 2 and 10",
            ));
        }
        if !(Self::MIN_MEMORY_BYTES..=Self::MAX_MEMORY_BYTES).contains(&self.memory_bytes) {
            return Err(VaultError::WeakKdfParameters(
                "Argon2id memory must be between 15 MiB and 1024 MiB",
            ));
        }
        if !(Self::MIN_PARALLELISM..=Self::MAX_PARALLELISM).contains(&self.parallelism) {
            return Err(VaultError::WeakKdfParameters(
                "Argon2id parallelism must be between 1 and 16",
            ));
        }
        Ok(())
    }
}

impl Default for KdfParams {
    fn default() -> Self {
        Self {
            iterations: Self::DEFAULT_ITERATIONS,
            memory_bytes: Self::DEFAULT_MEMORY_BYTES,
            parallelism: Self::DEFAULT_PARALLELISM,
        }
    }
}

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

/// Public/non-secret metadata of a KDBX4 Passkey (KeePassXC-compatible `KPEX_PASSKEY_*` fields).
/// The private key (`KPEX_PASSKEY_PRIVATE_KEY_PEM`) is stored protected in KDBX4 and never included here.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PasskeySummary {
    pub rp_id: String,
    pub username: String,
    pub credential_id: String,
    pub user_handle: String,
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
    /// Optional optimistic concurrency revision timestamp (UTC seconds).
    /// When `Some`, `Vault::update` verifies that the entry's stored `revision_date`
    /// has not diverged by more than 1 second before overwriting state.
    pub last_known_revision_date: Option<i64>,
    pub email: String,
    pub phone: String,
    pub security_question: String,
    pub security_answer: Option<Zeroizing<String>>,
    pub sections: Vec<String>,
    pub custom_fields: Vec<CustomFieldInput>,
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
            .field("last_known_revision_date", &self.last_known_revision_date)
            .field("email", &self.email)
            .field("phone", &self.phone)
            .field("security_question", &self.security_question)
            .field(
                "security_answer",
                &self.security_answer.as_ref().map(|_| "[REDACTED]"),
            )
            .field("sections", &self.sections)
            .field("custom_fields", &self.custom_fields)
            .finish()
    }
}

/// Non-secret view of an entry, safe to show in lists and audit views.
#[derive(Debug, Clone)]
pub struct EntrySummary {
    pub id: Uuid,
    pub title: String,
    pub username: String,
    pub email: String,
    pub url: String,
    pub group_name: Option<String>,
    pub has_passkey: bool,
    pub passkey_supported: bool,
    pub has_totp: bool,
    pub revision_date: Option<i64>,
    pub category: String,
    pub tags: Vec<String>,
    pub is_favorite: bool,
    pub is_archived: bool,
    pub is_trashed: bool,
    pub has_attachment: bool,
    pub two_fa_supported: bool,
    pub password_strength: String,
    pub strength_score: u8,
    pub is_weak: bool,
    pub is_identical: bool,
    pub is_compromised: bool,
    pub is_breached: bool,
    pub is_expired: bool,
}

/// Full non-secret fields of one entry, for an edit screen.
#[derive(Clone)]
pub struct EntryDetails {
    pub id: Uuid,
    pub title: String,
    pub username: String,
    pub email: String,
    pub url: String,
    pub phone: String,
    pub security_question: String,
    pub has_security_answer: bool,
    pub notes: String,
    pub group_id: Option<Uuid>,
    pub group_name: Option<String>,
    pub has_otp: bool,
    pub attachments: Vec<AttachmentSummary>,
    pub passkey: Option<PasskeySummary>,
    pub passkey_supported: bool,
    pub revision_date: Option<i64>,
    pub category: String,
    pub tags: Vec<String>,
    pub is_favorite: bool,
    pub is_archived: bool,
    pub is_trashed: bool,
    pub two_fa_supported: bool,
    pub password_strength: String,
    pub strength_score: u8,
    pub is_weak: bool,
    pub is_identical: bool,
    pub is_compromised: bool,
    pub is_breached: bool,
    pub is_expired: bool,
    pub sections: Vec<String>,
    pub custom_fields: Vec<CustomFieldSummary>,
}

impl fmt::Debug for EntryDetails {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("EntryDetails")
            .field("id", &self.id)
            .field("title", &self.title)
            .field("username", &self.username)
            .field("email", &self.email)
            .field("url", &self.url)
            .field("phone", &self.phone)
            .field("security_question", &self.security_question)
            .field("has_security_answer", &self.has_security_answer)
            .field("notes", &self.notes)
            .field("group_id", &self.group_id)
            .field("group_name", &self.group_name)
            .field("has_otp", &self.has_otp)
            .field("attachments", &self.attachments)
            .field("passkey", &self.passkey)
            .field("passkey_supported", &self.passkey_supported)
            .field("revision_date", &self.revision_date)
            .field("category", &self.category)
            .field("tags", &self.tags)
            .field("is_favorite", &self.is_favorite)
            .field("is_archived", &self.is_archived)
            .field("is_trashed", &self.is_trashed)
            .field("two_fa_supported", &self.two_fa_supported)
            .field("password_strength", &self.password_strength)
            .field("strength_score", &self.strength_score)
            .field("is_weak", &self.is_weak)
            .field("is_identical", &self.is_identical)
            .field("is_compromised", &self.is_compromised)
            .field("is_breached", &self.is_breached)
            .field("is_expired", &self.is_expired)
            .field("sections", &self.sections)
            .field("custom_fields", &self.custom_fields)
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
    /// Create a new KDBX4 vault at `path` using hardened default `Argon2id` parameters.
    /// Fails if the file already exists or if `master` is empty.
    pub fn create(path: impl AsRef<Path>, master: &str) -> Result<Self, VaultError> {
        Self::create_with_kdf(path, master, KdfParams::default())
    }

    /// Create a new KDBX4 vault at `path` with explicit validated `Argon2id` `KdfParams`.
    pub fn create_with_kdf(
        path: impl AsRef<Path>,
        master: &str,
        kdf: KdfParams,
    ) -> Result<Self, VaultError> {
        if master.is_empty() {
            return Err(VaultError::EmptyMasterPassword);
        }
        kdf.validate()?;
        let path = path.as_ref().to_path_buf();
        if path.exists() {
            return Err(VaultError::Io(std::io::Error::new(
                std::io::ErrorKind::AlreadyExists,
                "vault file already exists",
            )));
        }
        let mut db = Database::new_with_root_id(GroupId::from_uuid(Uuid::now_v7()));
        apply_kdf_config(&mut db.config, kdf)?;
        let vault = Self {
            db,
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

    /// Returns the vault's active `Argon2id` KDF parameters, or `None` if the vault uses a legacy KDF.
    pub fn kdf_params(&self) -> Option<KdfParams> {
        match self.db.config.kdf_config {
            KdfConfig::Argon2id {
                iterations,
                memory,
                parallelism,
                ..
            } => Some(KdfParams {
                iterations,
                memory_bytes: memory,
                parallelism,
            }),
            _ => None,
        }
    }

    /// Atomically rotates the master password (and upgrades KDF config to hardened `Argon2id` if needed).
    /// Verifies `current_master` in constant time, bumps `revision_date` (`last_modification`) across
    /// all entries and groups, and saves via atomic tempfile before committing the new in-memory state.
    pub fn change_master_password(
        &mut self,
        current_master: &str,
        new_master: &str,
    ) -> Result<(), VaultError> {
        if new_master.is_empty() {
            return Err(VaultError::EmptyMasterPassword);
        }
        if !constant_time_eq(self.master.as_bytes(), current_master.as_bytes()) {
            return Err(VaultError::InvalidMasterPassword);
        }

        let mut rotated_db = self.db.clone();
        let needs_kdf_upgrade = match rotated_db.config.kdf_config {
            KdfConfig::Argon2id {
                iterations,
                memory,
                parallelism,
                ..
            } => KdfParams {
                iterations,
                memory_bytes: memory,
                parallelism,
            }
            .validate()
            .is_err(),
            _ => true,
        };
        if needs_kdf_upgrade {
            apply_kdf_config(&mut rotated_db.config, KdfParams::default())?;
        }

        rotated_db.foreach_group_mut(|mut g| {
            let prev = g.times.clone();
            bump_modification_time(&prev, &mut g.times);
        });
        rotated_db.foreach_entry_mut(|mut e| {
            let prev = e.times.clone();
            bump_modification_time(&prev, &mut e.times);
        });

        save_db_to(&rotated_db, &self.path, new_master)?;
        self.db = rotated_db;
        self.master = Zeroizing::new(new_master.to_owned());
        Ok(())
    }

    /// Atomic save: write a temp file next to the vault, fsync, then rename.
    /// A crash mid-write can never corrupt the existing vault.
    pub fn save(&self) -> Result<(), VaultError> {
        self.save_to(&self.path, &self.master)
    }

    /// Atomic save to a specific destination path with a given master password.
    pub fn save_to(&self, dest_path: impl AsRef<Path>, master: &str) -> Result<(), VaultError> {
        save_db_to(&self.db, dest_path.as_ref(), master)
    }

    pub fn add(&mut self, input: &EntryInput) -> Result<Uuid, VaultError> {
        let new_id = EntryId::from_uuid(Uuid::now_v7());
        if let Some(gid) = input.group_id {
            let target = GroupId::from(gid);
            if self.db.group(target).is_none() {
                return Err(VaultError::GroupNotFound);
            }
            let mut grp = self.db.group_mut(target).unwrap();
            let mut entry = grp
                .add_entry_with_id(new_id)
                .expect("fresh UUIDv7 cannot collide with an existing entry identifier");
            apply_initial(&mut entry, input);
            return Ok(entry.id().uuid());
        }
        let mut root = self.db.root_mut();
        let mut entry = root
            .add_entry_with_id(new_id)
            .expect("fresh UUIDv7 cannot collide with an existing entry identifier");
        apply_initial(&mut entry, input);
        Ok(entry.id().uuid())
    }

    pub fn update(&mut self, id: Uuid, input: &EntryInput) -> Result<(), VaultError> {
        let eid = self.find(id)?;
        let target_group_id = match input.group_id {
            Some(gid) => {
                let target = GroupId::from(gid);
                if self.db.group(target).is_none() {
                    return Err(VaultError::GroupNotFound);
                }
                target
            }
            None => self.db.root().id(),
        };

        {
            let entry_ref = self.db.entry(eid).ok_or(VaultError::NotFound)?;
            check_revision(&entry_ref, input.last_known_revision_date)?;
        }

        let mut entry = self.db.entry_mut(eid).ok_or(VaultError::NotFound)?;
        let prev_times = entry.times.clone();
        let needs_move = entry.parent_mut().id() != target_group_id;

        entry.edit_tracking(|e| {
            apply_tracked(e, input);
            bump_modification_time(&prev_times, &mut e.times);
        });

        if needs_move {
            entry
                .move_to(target_group_id)
                .map_err(|_| VaultError::GroupNotFound)?;
            bump_location_time(&prev_times, &mut entry.times);
        }
        Ok(())
    }

    pub fn remove(&mut self, id: Uuid) -> Result<(), VaultError> {
        let eid = self.find(id)?;
        let prev_time = self
            .db
            .entry(eid)
            .and_then(|e| e.times.last_modification.max(e.times.location_changed));
        self.db
            .entry_mut(eid)
            .ok_or(VaultError::NotFound)?
            .track_changes()
            .remove();
        let now = Times::now();
        let del_time = match prev_time {
            Some(prev) if now <= prev => prev + Duration::from_secs(1),
            _ => now,
        };
        self.db.deleted_objects.insert(id, Some(del_time));
        Ok(())
    }

    /// Case-insensitive match on title, username, email, URL, phone, notes, group name, category, tags, or custom fields. Empty query lists all.
    pub fn search(&self, query: &str) -> Vec<EntrySummary> {
        let q = query.to_lowercase();
        let mut pw_digest_counts: std::collections::HashMap<[u8; 32], usize> =
            std::collections::HashMap::new();
        for e in self.db.iter_all_entries() {
            if !extract_bool(&e, VK_TRASHED) {
                let pw = e.get_password().unwrap_or_default();
                if !pw.is_empty() {
                    let digest = ring::digest::digest(&ring::digest::SHA256, pw.as_bytes());
                    let mut arr = [0u8; 32];
                    arr.copy_from_slice(digest.as_ref());
                    *pw_digest_counts.entry(arr).or_insert(0) += 1;
                }
            }
        }
        let mut out: Vec<EntrySummary> = self
            .db
            .iter_all_entries()
            .filter_map(|e| {
                let parent = e.parent();
                let group_name = if parent.name.is_empty() {
                    None
                } else {
                    Some(parent.name.clone())
                };
                let title = e.get_title().unwrap_or_default().to_owned();
                let username = e.get_username().unwrap_or_default().to_owned();
                let email = e.get(VK_EMAIL).unwrap_or_default().to_owned();
                let url = e.get_url().unwrap_or_default().to_owned();
                let phone = e.get(VK_PHONE).unwrap_or_default();
                let notes = e.get(fields::NOTES).unwrap_or_default();
                let sec_q = e.get(VK_SECURITY_QUESTION).unwrap_or_default();
                let custom_fields = extract_custom_fields(&e);
                let category = extract_category(&e, group_name.as_deref());
                let tags = extract_tags(&e);

                let matches_query = q.is_empty()
                    || title.to_lowercase().contains(&q)
                    || username.to_lowercase().contains(&q)
                    || email.to_lowercase().contains(&q)
                    || url.to_lowercase().contains(&q)
                    || phone.to_lowercase().contains(&q)
                    || notes.to_lowercase().contains(&q)
                    || sec_q.to_lowercase().contains(&q)
                    || category.to_lowercase().contains(&q)
                    || tags.iter().any(|t| t.to_lowercase().contains(&q))
                    || group_name
                        .as_deref()
                        .unwrap_or_default()
                        .to_lowercase()
                        .contains(&q)
                    || custom_fields.iter().any(|cf| {
                        cf.name.to_lowercase().contains(&q)
                            || (!cf.sensitive && cf.value.to_lowercase().contains(&q))
                    });

                if !matches_query {
                    return None;
                }

                let has_passkey = extract_passkey(&e).is_some();
                let passkey_supported = is_passkey_supported(&title, &url, has_passkey);
                let has_totp = e
                    .get_raw_otp_value()
                    .map(|s| !s.trim().is_empty())
                    .unwrap_or(false);
                let revision_date = entry_revision_date(&e);
                let is_favorite = extract_bool(&e, VK_FAVORITE);
                let is_archived = extract_bool(&e, VK_ARCHIVED);
                let is_trashed = extract_bool(&e, VK_TRASHED);
                let has_attachment = e.attachments_named().next().is_some();
                let two_fa_supported = is_two_fa_supported(&title, &url, has_totp);

                let pw = e.get_password().unwrap_or_default();
                let (strength_score, strength_label, auto_compromised) =
                    crate::generator::evaluate_password_strength(pw);
                let is_weak = strength_score < 50;
                let is_compromised = auto_compromised || extract_bool(&e, VK_COMPROMISED);
                let is_breached = is_compromised;
                let is_expired = extract_bool(&e, VK_EXPIRED) || is_entry_expired(&e);
                let is_identical = !is_trashed && !pw.is_empty() && {
                    let digest = ring::digest::digest(&ring::digest::SHA256, pw.as_bytes());
                    pw_digest_counts.get(digest.as_ref()).copied().unwrap_or(0) > 1
                };

                Some(EntrySummary {
                    id: e.id().uuid(),
                    title,
                    username,
                    email,
                    url,
                    group_name,
                    has_passkey,
                    passkey_supported,
                    has_totp,
                    revision_date,
                    category,
                    tags,
                    is_favorite,
                    is_archived,
                    is_trashed,
                    has_attachment,
                    two_fa_supported,
                    password_strength: strength_label.to_string(),
                    strength_score,
                    is_weak,
                    is_identical,
                    is_compromised,
                    is_breached,
                    is_expired,
                })
            })
            .collect();
        out.sort_by_key(|a| a.title.to_lowercase());
        out
    }

    /// Non-secret fields of one entry (passwords and sensitive custom fields are fetched separately).
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
        let has_otp = e
            .get_raw_otp_value()
            .map(|s| !s.trim().is_empty())
            .unwrap_or(false);
        let attachments = e
            .attachments_named()
            .map(|(name, att)| AttachmentSummary {
                name: name.to_string(),
                size: att.data.len(),
            })
            .collect();
        let title = field(fields::TITLE);
        let url = field(fields::URL);
        let email = field(VK_EMAIL);
        let phone = field(VK_PHONE);
        let security_question = field(VK_SECURITY_QUESTION);
        let has_security_answer = e
            .get(VK_SECURITY_ANSWER)
            .map(|s| !s.trim().is_empty())
            .unwrap_or(false);
        let sections = extract_sections(&e);
        let custom_fields = extract_custom_fields(&e);
        let passkey = extract_passkey(&e);
        let passkey_supported = is_passkey_supported(&title, &url, passkey.is_some());
        let revision_date = entry_revision_date(&e);
        let category = extract_category(&e, group_name.as_deref());
        let tags = extract_tags(&e);
        let is_favorite = extract_bool(&e, VK_FAVORITE);
        let is_archived = extract_bool(&e, VK_ARCHIVED);
        let is_trashed = extract_bool(&e, VK_TRASHED);
        let two_fa_supported = is_two_fa_supported(&title, &url, has_otp);

        let pw = e.get_password().unwrap_or_default();
        let (strength_score, strength_label, auto_compromised) =
            crate::generator::evaluate_password_strength(pw);
        let is_weak = strength_score < 50;
        let is_compromised = auto_compromised || extract_bool(&e, VK_COMPROMISED);
        let is_breached = is_compromised;
        let is_expired = extract_bool(&e, VK_EXPIRED) || is_entry_expired(&e);
        let is_identical = !is_trashed
            && !pw.is_empty()
            && self.db.iter_all_entries().any(|other| {
                other.id() != e.id() && !extract_bool(&other, VK_TRASHED) && {
                    let opw = other.get_password().unwrap_or_default();
                    !opw.is_empty() && constant_time_eq(pw.as_bytes(), opw.as_bytes())
                }
            });

        Ok(EntryDetails {
            id,
            title,
            username: field(fields::USERNAME),
            email,
            url,
            phone,
            security_question,
            has_security_answer,
            notes: field(fields::NOTES),
            group_id,
            group_name,
            has_otp,
            attachments,
            passkey,
            passkey_supported,
            revision_date,
            category,
            tags,
            is_favorite,
            is_archived,
            is_trashed,
            two_fa_supported,
            password_strength: strength_label.to_string(),
            strength_score,
            is_weak,
            is_identical,
            is_compromised,
            is_breached,
            is_expired,
            sections,
            custom_fields,
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

    /// Fetch the raw OTP seed URI only when explicitly requested.
    /// Treats the TOTP seed as a high-value secret, similar to the password.
    pub fn otp_uri(&self, id: Uuid) -> Result<Option<Zeroizing<String>>, VaultError> {
        let eid = self.find(id)?;
        let e = self.db.entry(eid).ok_or(VaultError::NotFound)?;
        Ok(e.get_raw_otp_value()
            .filter(|s| !s.trim().is_empty())
            .map(|s| Zeroizing::new(s.to_string())))
    }

    /// Fetch the protected Security Answer (`VK_SECURITY_ANSWER`) only when explicitly requested.
    pub fn security_answer(&self, id: Uuid) -> Result<Option<Zeroizing<String>>, VaultError> {
        let eid = self.find(id)?;
        let e = self.db.entry(eid).ok_or(VaultError::NotFound)?;
        Ok(e.get(VK_SECURITY_ANSWER)
            .filter(|s| !s.trim().is_empty())
            .map(|s| Zeroizing::new(s.to_owned())))
    }

    /// Fetch the value of a custom field at `index` (especially for `sensitive == true` fields).
    pub fn custom_field_value(
        &self,
        id: Uuid,
        index: usize,
    ) -> Result<Zeroizing<String>, VaultError> {
        let eid = self.find(id)?;
        let e = self.db.entry(eid).ok_or(VaultError::NotFound)?;
        let count = e
            .get(VK_CF_COUNT)
            .and_then(|s| s.trim().parse::<usize>().ok())
            .unwrap_or(0);
        if index >= count {
            return Err(VaultError::Policy("custom field index out of bounds"));
        }
        let key = format!("VK_CF_VAL_{index}");
        Ok(Zeroizing::new(e.get(&key).unwrap_or_default().to_owned()))
    }

    /// Returns non-secret container metadata and Argon2id KDF parameters for `Settings -> Vaults -> VAULT INFO`.
    pub fn vault_info(&self) -> VaultInfo {
        let kdf = self.kdf_params().unwrap_or_default();
        VaultInfo {
            path: self.path.to_string_lossy().into_owned(),
            entry_count: self.db.iter_all_entries().count(),
            group_count: self.list_groups().len(),
            kdf_iterations: kdf.iterations,
            kdf_memory_bytes: kdf.memory_bytes,
            kdf_parallelism: kdf.parallelism,
        }
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
        let new_id = GroupId::from_uuid(Uuid::now_v7());
        let mut root = self.db.root_mut();
        let mut grp = root
            .add_group_with_id(new_id)
            .expect("fresh UUIDv7 cannot collide with an existing group identifier");
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
        let prev_times = entry.times.clone();
        entry.edit_tracking(|e| {
            e.add_attachment(name.to_string(), Value::protected(data.to_vec()));
            bump_modification_time(&prev_times, &mut e.times);
        });
        self.save()?;
        Ok(())
    }

    /// Returns whether the named attachment is stored as `Value::Protected` in memory / KDBX4 inner header.
    pub fn is_attachment_protected(&self, entry_id: Uuid, name: &str) -> Result<bool, VaultError> {
        let eid = self.find(entry_id)?;
        let entry = self.db.entry(eid).ok_or(VaultError::NotFound)?;
        let att = entry
            .attachment_by_name(name)
            .ok_or(VaultError::AttachmentNotFound)?;
        Ok(att.is_protected())
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
        // Verify the attachment exists before modifying state.
        let entry_ref = self.db.entry(eid).ok_or(VaultError::NotFound)?;
        if entry_ref.attachment_by_name(name).is_none() {
            return Err(VaultError::AttachmentNotFound);
        }
        let mut entry = self.db.entry_mut(eid).ok_or(VaultError::NotFound)?;
        let prev_times = entry.times.clone();
        entry.remove_attachment_by_name(name);
        bump_modification_time(&prev_times, &mut entry.times);
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

    // --- Passkey (FIDO2 / WebAuthn KDBX4) API ---

    /// Generates and binds a KDBX4-compatible Passkey (`KPEX_PASSKEY_*` fields) to an entry.
    /// Generates a standards-compliant ECDSA P-256 (`ES256`, COSE alg `-7`) PKCS#8 v1 PEM private key
    /// via `ring`, wrapped in `Zeroizing`, and stores it in the protected KDBX4 field `KPEX_PASSKEY_PRIVATE_KEY_PEM`.
    pub fn generate_passkey(
        &mut self,
        entry_id: Uuid,
        rp_id: &str,
        username: &str,
    ) -> Result<PasskeySummary, VaultError> {
        self.generate_passkey_with_revision(entry_id, rp_id, username, None)
    }

    /// Generates and binds a KDBX4-compatible Passkey (`KPEX_PASSKEY_*` fields) with optional
    /// optimistic concurrency validation (`last_known_revision_date`).
    pub fn generate_passkey_with_revision(
        &mut self,
        entry_id: Uuid,
        rp_id: &str,
        username: &str,
        last_known_revision_date: Option<i64>,
    ) -> Result<PasskeySummary, VaultError> {
        let eid = self.find(entry_id)?;
        let (effective_rp_id, effective_username) = {
            let entry_ref = self.db.entry(eid).ok_or(VaultError::NotFound)?;
            check_revision(&entry_ref, last_known_revision_date)?;
            resolve_passkey_rp_and_user(&entry_ref, rp_id, username)?
        };

        let mut cred_bytes = [0u8; 24];
        let mut handle_bytes = [0u8; 24];
        let mut rng = rand::rngs::OsRng;
        rng.fill_bytes(&mut cred_bytes);
        rng.fill_bytes(&mut handle_bytes);

        let credential_id = encode_base64url(&cred_bytes);
        let user_handle = encode_base64url(&handle_bytes);
        let (private_key_pem, _uncompressed_pub) = crate::passkey::generate_p256_pkcs8_pem()?;

        let mut entry = self.db.entry_mut(eid).ok_or(VaultError::NotFound)?;
        let prev_times = entry.times.clone();
        entry.edit_tracking(|e| {
            e.set_unprotected(KPEX_PASSKEY_RELYING_PARTY, effective_rp_id.as_str());
            e.set_unprotected(KPEX_PASSKEY_USERNAME, effective_username.as_str());
            e.set_unprotected(KPEX_PASSKEY_DISPLAY_NAME, effective_username.as_str());
            e.set_unprotected(KPEX_PASSKEY_CREDENTIAL_ID, credential_id.as_str());
            e.set_unprotected(KPEX_PASSKEY_USER_HANDLE, user_handle.as_str());
            e.set_unprotected(KPEX_PASSKEY_FLAG_BE, "1");
            e.set_unprotected(KPEX_PASSKEY_FLAG_BS, "1");
            e.set_unprotected(KPEX_PASSKEY_SIGN_COUNT, "0");
            e.set_protected(KPEX_PASSKEY_PRIVATE_KEY_PEM, private_key_pem.as_str());
            bump_modification_time(&prev_times, &mut e.times);
        });

        let summary = PasskeySummary {
            rp_id: effective_rp_id,
            username: effective_username,
            credential_id,
            user_handle,
        };
        self.save()?;
        Ok(summary)
    }

    /// Removes the bound Passkey (`KPEX_PASSKEY_*` fields) from an entry and saves atomically.
    pub fn remove_passkey(&mut self, entry_id: Uuid) -> Result<(), VaultError> {
        self.remove_passkey_with_revision(entry_id, None)
    }

    /// Removes the bound Passkey (`KPEX_PASSKEY_*` fields) with optional optimistic concurrency check.
    pub fn remove_passkey_with_revision(
        &mut self,
        entry_id: Uuid,
        last_known_revision_date: Option<i64>,
    ) -> Result<(), VaultError> {
        let eid = self.find(entry_id)?;
        {
            let entry_ref = self.db.entry(eid).ok_or(VaultError::NotFound)?;
            check_revision(&entry_ref, last_known_revision_date)?;
        }
        let mut entry = self.db.entry_mut(eid).ok_or(VaultError::NotFound)?;
        let prev_times = entry.times.clone();
        entry.edit_tracking(|e| {
            clear_passkey_fields(e);
            bump_modification_time(&prev_times, &mut e.times);
        });
        self.save()?;
        Ok(())
    }

    /// Executes a full WebAuthn Level 3 `MakeCredential` (registration) ceremony for Windows or Android.
    ///
    /// Validates the factory-minted [`crate::PasskeyChallengeToken`], enforces RP ID / origin / ROR
    /// matching, enforces strict `UV` (`passkeys.dev` Known Issue compliance), checks `excludeCredentials`,
    /// sets `BE=1` & `BS=1` synced passkey flags, encodes the COSE ES256 (`-7`) public key and `"none"`
    /// CBOR `attestationObject`, and persists the credential atomically to KDBX4.
    #[allow(clippy::too_many_arguments)]
    pub fn register_webauthn_passkey(
        &mut self,
        entry_id: Uuid,
        platform: crate::PasskeyPlatform,
        rp_id: &str,
        username: &str,
        display_name: &str,
        origin: &str,
        challenge_token: &crate::PasskeyChallengeToken,
        challenge_factory: &crate::PasskeyChallengeFactory,
        now_unix: i64,
        uv_requirement: crate::UserVerificationRequirement,
        user_verified: bool,
        exclude_credential_ids: &[String],
        allowed_related_origins: &[String],
        android_package_name: Option<&str>,
        last_known_revision_date: Option<i64>,
    ) -> Result<crate::PasskeyRegistrationResponse, VaultError> {
        let eid = self.find(entry_id)?;
        let (effective_rp_id, effective_username) = {
            let entry_ref = self.db.entry(eid).ok_or(VaultError::NotFound)?;
            check_revision(&entry_ref, last_known_revision_date)?;
            resolve_passkey_rp_and_user(&entry_ref, rp_id, username)?
        };

        challenge_factory.verify_challenge(
            challenge_token,
            &effective_rp_id,
            crate::PasskeyCeremonyScope::Registration,
            now_unix,
        )?;
        crate::passkey::validate_rp_id_for_origin(
            &effective_rp_id,
            origin,
            allowed_related_origins,
        )?;
        let uv_flag = crate::passkey::resolve_uv_flag(uv_requirement, user_verified)?;

        // Enforce WebAuthn excludeCredentials (InvalidStateError if an excluded credential exists for this RP ID)
        if !exclude_credential_ids.is_empty() {
            for e in self.db.iter_all_entries() {
                if extract_bool(&e, VK_TRASHED) {
                    continue;
                }
                if let Some(pk) = extract_passkey(&e) {
                    if pk.rp_id.eq_ignore_ascii_case(&effective_rp_id)
                        && exclude_credential_ids
                            .iter()
                            .any(|ex| ex.trim() == pk.credential_id)
                    {
                        return Err(VaultError::Policy(
                            "credential excluded by relying party (InvalidStateError)",
                        ));
                    }
                }
            }
        }

        let effective_display_name = if display_name.trim().is_empty() {
            effective_username.clone()
        } else {
            display_name.trim().to_owned()
        };

        let mut cred_bytes = [0u8; 24];
        let mut handle_bytes = [0u8; 24];
        let mut rng = rand::rngs::OsRng;
        rng.fill_bytes(&mut cred_bytes);
        rng.fill_bytes(&mut handle_bytes);

        let credential_id = encode_base64url(&cred_bytes);
        let user_handle = encode_base64url(&handle_bytes);
        let (private_key_pem, uncompressed_pub) = crate::passkey::generate_p256_pkcs8_pem()?;

        let mut x = [0u8; 32];
        let mut y = [0u8; 32];
        x.copy_from_slice(&uncompressed_pub[1..33]);
        y.copy_from_slice(&uncompressed_pub[33..65]);
        let cose_pub = crate::passkey::encode_cose_p256_public_key(&x, &y);

        let backup_eligible = true;
        let backup_state = true;
        let sign_count = 0u32;
        let (auth_data, flag_byte) = crate::passkey::build_authenticator_data(
            &effective_rp_id,
            uv_flag,
            backup_eligible,
            backup_state,
            sign_count,
            Some((&cred_bytes, &cose_pub)),
        )?;
        let attestation_object = crate::passkey::encode_none_attestation_object(&auth_data);
        let pkg = match platform {
            crate::PasskeyPlatform::Android => android_package_name,
            crate::PasskeyPlatform::Windows => None,
        };
        let client_data_json = crate::passkey::build_client_data_json(
            crate::PasskeyCeremonyScope::Registration,
            challenge_token.challenge_b64url(),
            origin,
            pkg,
        );

        let mut entry = self.db.entry_mut(eid).ok_or(VaultError::NotFound)?;
        let prev_times = entry.times.clone();
        entry.edit_tracking(|e| {
            e.set_unprotected(KPEX_PASSKEY_RELYING_PARTY, effective_rp_id.as_str());
            e.set_unprotected(KPEX_PASSKEY_USERNAME, effective_username.as_str());
            e.set_unprotected(KPEX_PASSKEY_DISPLAY_NAME, effective_display_name.as_str());
            e.set_unprotected(KPEX_PASSKEY_CREDENTIAL_ID, credential_id.as_str());
            e.set_unprotected(KPEX_PASSKEY_USER_HANDLE, user_handle.as_str());
            e.set_unprotected(KPEX_PASSKEY_FLAG_BE, "1");
            e.set_unprotected(KPEX_PASSKEY_FLAG_BS, "1");
            e.set_unprotected(KPEX_PASSKEY_SIGN_COUNT, "0");
            e.set_protected(KPEX_PASSKEY_PRIVATE_KEY_PEM, private_key_pem.as_str());
            bump_modification_time(&prev_times, &mut e.times);
        });
        self.save()?;

        Ok(crate::PasskeyRegistrationResponse {
            credential_id,
            rp_id: effective_rp_id,
            username: effective_username,
            display_name: effective_display_name,
            user_handle,
            platform,
            authenticator_attachment: "platform".to_owned(),
            transports: vec!["hybrid".to_owned(), "internal".to_owned()],
            authenticator_data_b64url: encode_base64url(&auth_data),
            client_data_json_b64url: encode_base64url(&client_data_json),
            attestation_object_b64url: encode_base64url(&attestation_object),
            public_key_cose_b64url: encode_base64url(&cose_pub),
            flags: flag_byte,
            user_verified: uv_flag,
            backup_eligible,
            backup_state,
            sign_count,
            cose_algorithm: crate::COSE_ALG_ES256,
            cred_props_rk: true,
        })
    }

    /// Executes a full WebAuthn Level 3 `GetAssertion` (authentication) ceremony for Windows or Android.
    ///
    /// Validates the factory-minted [`crate::PasskeyChallengeToken`], enforces RP ID / origin / ROR
    /// matching, enforces strict `UV` (`passkeys.dev` Known Issue compliance), builds `authenticatorData`
    /// (`UP=1`, `UV`, `BE`, `BS`), and signs `authenticatorData || SHA-256(clientDataJSON)` using the
    /// entry's protected ECDSA P-256 PKCS#8 private key.
    #[allow(clippy::too_many_arguments)]
    pub fn authenticate_webauthn_passkey(
        &self,
        entry_id: Uuid,
        platform: crate::PasskeyPlatform,
        origin: &str,
        challenge_token: &crate::PasskeyChallengeToken,
        challenge_factory: &crate::PasskeyChallengeFactory,
        now_unix: i64,
        uv_requirement: crate::UserVerificationRequirement,
        user_verified: bool,
        allowed_related_origins: &[String],
        android_package_name: Option<&str>,
    ) -> Result<crate::PasskeyAssertionResponse, VaultError> {
        let eid = self.find(entry_id)?;
        let entry = self.db.entry(eid).ok_or(VaultError::NotFound)?;
        let pk = extract_passkey(&entry)
            .ok_or(VaultError::Policy("entry does not have a bound passkey"))?;

        challenge_factory.verify_challenge(
            challenge_token,
            &pk.rp_id,
            crate::PasskeyCeremonyScope::Authentication,
            now_unix,
        )?;
        crate::passkey::validate_rp_id_for_origin(&pk.rp_id, origin, allowed_related_origins)?;
        let uv_flag = crate::passkey::resolve_uv_flag(uv_requirement, user_verified)?;

        let pem = Zeroizing::new(
            entry
                .get(KPEX_PASSKEY_PRIVATE_KEY_PEM)
                .unwrap_or_default()
                .to_owned(),
        );
        if pem.trim().is_empty() {
            return Err(VaultError::Malformed(
                "passkey entry is missing KPEX_PASSKEY_PRIVATE_KEY_PEM",
            ));
        }

        let backup_eligible = entry
            .get(KPEX_PASSKEY_FLAG_BE)
            .map(|v| v.trim() != "0" && !v.trim().eq_ignore_ascii_case("false"))
            .unwrap_or(true);
        let backup_state = backup_eligible
            && entry
                .get(KPEX_PASSKEY_FLAG_BS)
                .map(|v| v.trim() != "0" && !v.trim().eq_ignore_ascii_case("false"))
                .unwrap_or(true);
        let sign_count = entry
            .get(KPEX_PASSKEY_SIGN_COUNT)
            .and_then(|v| v.trim().parse::<u32>().ok())
            .unwrap_or(0);

        let (auth_data, flag_byte) = crate::passkey::build_authenticator_data(
            &pk.rp_id,
            uv_flag,
            backup_eligible,
            backup_state,
            sign_count,
            None,
        )?;
        let pkg = match platform {
            crate::PasskeyPlatform::Android => android_package_name,
            crate::PasskeyPlatform::Windows => None,
        };
        let client_data_json = crate::passkey::build_client_data_json(
            crate::PasskeyCeremonyScope::Authentication,
            challenge_token.challenge_b64url(),
            origin,
            pkg,
        );
        let signature_der =
            crate::passkey::sign_webauthn_assertion(&pem, &auth_data, &client_data_json)?;

        Ok(crate::PasskeyAssertionResponse {
            credential_id: pk.credential_id,
            rp_id: pk.rp_id,
            username: pk.username,
            user_handle: pk.user_handle,
            platform,
            authenticator_attachment: "platform".to_owned(),
            authenticator_data_b64url: encode_base64url(&auth_data),
            client_data_json_b64url: encode_base64url(&client_data_json),
            signature_b64url: encode_base64url(&signature_der),
            flags: flag_byte,
            user_verified: uv_flag,
            backup_eligible,
            backup_state,
            sign_count,
        })
    }

    /// Discovers non-trashed passkeys matching `rp_id` (and optional `allow_credential_ids` filter)
    /// for Conditional UI (Autofill) and Windows/Android credential provider selection.
    pub fn find_passkeys_for_rp(
        &self,
        rp_id: &str,
        allow_credential_ids: &[String],
    ) -> Vec<(Uuid, PasskeySummary)> {
        let target_rp = clean_domain_or_host(rp_id);
        if target_rp.is_empty() {
            return Vec::new();
        }
        let mut results = Vec::new();
        for e in self.db.iter_all_entries() {
            if extract_bool(&e, VK_TRASHED) {
                continue;
            }
            if let Some(pk) = extract_passkey(&e) {
                let entry_rp = clean_domain_or_host(&pk.rp_id);
                if matches_host(&target_rp, &entry_rp)
                    && (allow_credential_ids.is_empty()
                        || allow_credential_ids
                            .iter()
                            .any(|allowed| allowed.trim() == pk.credential_id))
                {
                    results.push((e.id().uuid(), pk));
                }
            }
        }
        results
    }

    /// WebAuthn Level 3 Signal API (`PublicKeyCredential.signalUnknownCredential`):
    /// Removes a stale or server-deleted passkey matching `(rp_id, credential_id)`.
    pub fn signal_unknown_credential(
        &mut self,
        rp_id: &str,
        credential_id: &str,
    ) -> Result<bool, VaultError> {
        let clean_rp = crate::passkey::normalize_rp_id(rp_id)?;
        let target_cred = credential_id.trim();
        if target_cred.is_empty() {
            return Err(VaultError::Policy("credential_id must not be empty"));
        }

        let mut matched_ids = Vec::new();
        for e in self.db.iter_all_entries() {
            if let Some(pk) = extract_passkey(&e) {
                if pk.rp_id.eq_ignore_ascii_case(&clean_rp) && pk.credential_id == target_cred {
                    matched_ids.push(e.id());
                }
            }
        }
        if matched_ids.is_empty() {
            return Ok(false);
        }

        for eid in matched_ids {
            if let Some(mut entry) = self.db.entry_mut(eid) {
                let prev_times = entry.times.clone();
                entry.edit_tracking(|e| {
                    clear_passkey_fields(e);
                    bump_modification_time(&prev_times, &mut e.times);
                });
            }
        }
        self.save()?;
        Ok(true)
    }

    /// WebAuthn Level 3 Signal API (`PublicKeyCredential.signalAllAcceptedCredentials`):
    /// Prunes revoked passkeys for `(rp_id, user_handle)` that are not in `accepted_credential_ids`.
    pub fn signal_all_accepted_credentials(
        &mut self,
        rp_id: &str,
        user_handle: &str,
        accepted_credential_ids: &[String],
    ) -> Result<u32, VaultError> {
        let clean_rp = crate::passkey::normalize_rp_id(rp_id)?;
        let target_handle = user_handle.trim();
        if target_handle.is_empty() {
            return Err(VaultError::Policy("user_handle must not be empty"));
        }

        let mut to_prune = Vec::new();
        for e in self.db.iter_all_entries() {
            if let Some(pk) = extract_passkey(&e) {
                if pk.rp_id.eq_ignore_ascii_case(&clean_rp)
                    && pk.user_handle == target_handle
                    && !accepted_credential_ids
                        .iter()
                        .any(|acc| acc.trim() == pk.credential_id)
                {
                    to_prune.push(e.id());
                }
            }
        }
        if to_prune.is_empty() {
            return Ok(0);
        }

        let pruned_count = to_prune.len() as u32;
        for eid in to_prune {
            if let Some(mut entry) = self.db.entry_mut(eid) {
                let prev_times = entry.times.clone();
                entry.edit_tracking(|e| {
                    clear_passkey_fields(e);
                    bump_modification_time(&prev_times, &mut e.times);
                });
            }
        }
        self.save()?;
        Ok(pruned_count)
    }

    /// WebAuthn Level 3 Signal API (`PublicKeyCredential.signalCurrentUserDetails`):
    /// Updates the stored `username` and `display_name` for passkeys matching `(rp_id, user_handle)`.
    pub fn signal_current_user_details(
        &mut self,
        rp_id: &str,
        user_handle: &str,
        username: &str,
        display_name: &str,
    ) -> Result<u32, VaultError> {
        let clean_rp = crate::passkey::normalize_rp_id(rp_id)?;
        let target_handle = user_handle.trim();
        let clean_user = username.trim();
        if target_handle.is_empty() || clean_user.is_empty() {
            return Err(VaultError::Policy(
                "user_handle and username must not be empty",
            ));
        }
        let clean_display = if display_name.trim().is_empty() {
            clean_user
        } else {
            display_name.trim()
        };

        let mut to_update = Vec::new();
        for e in self.db.iter_all_entries() {
            if let Some(pk) = extract_passkey(&e) {
                if pk.rp_id.eq_ignore_ascii_case(&clean_rp) && pk.user_handle == target_handle {
                    to_update.push(e.id());
                }
            }
        }
        if to_update.is_empty() {
            return Ok(0);
        }

        let updated_count = to_update.len() as u32;
        for eid in to_update {
            if let Some(mut entry) = self.db.entry_mut(eid) {
                let prev_times = entry.times.clone();
                entry.edit_tracking(|e| {
                    e.set_unprotected(KPEX_PASSKEY_USERNAME, clean_user);
                    e.set_unprotected(KPEX_PASSKEY_DISPLAY_NAME, clean_display);
                    bump_modification_time(&prev_times, &mut e.times);
                });
            }
        }
        self.save()?;
        Ok(updated_count)
    }

    /// Updates Enpass-compatible category, tags, favorite, archive, trash, compromised, and expired
    /// metadata on an entry inside KDBX4 custom fields and bumps its modification timestamp.
    pub fn set_entry_metadata(
        &mut self,
        entry_id: Uuid,
        meta: &EntryMetadata,
    ) -> Result<(), VaultError> {
        let eid = self.find(entry_id)?;
        let mut entry = self.db.entry_mut(eid).ok_or(VaultError::NotFound)?;
        let prev_times = entry.times.clone();
        let cleaned_tags: Vec<String> = meta
            .tags
            .iter()
            .map(|t| t.trim().to_string())
            .filter(|t| !t.is_empty())
            .collect();
        let joined_tags = cleaned_tags.join(", ");
        let cat = if meta.category.trim().is_empty() {
            "Login"
        } else {
            meta.category.trim()
        };

        entry.edit_tracking(|e| {
            e.set_unprotected(VK_CATEGORY, cat);
            if joined_tags.is_empty() {
                e.fields.remove(VK_TAGS);
            } else {
                e.set_unprotected(VK_TAGS, joined_tags.as_str());
            }
            set_or_remove_bool(e, VK_FAVORITE, meta.is_favorite);
            set_or_remove_bool(e, VK_ARCHIVED, meta.is_archived);
            set_or_remove_bool(e, VK_TRASHED, meta.is_trashed);
            set_or_remove_bool(e, VK_COMPROMISED, meta.is_compromised);
            set_or_remove_bool(e, VK_EXPIRED, meta.is_expired);
            bump_modification_time(&prev_times, &mut e.times);
        });
        entry.tags = cleaned_tags;
        self.save()?;
        Ok(())
    }

    /// Creates an atomic encrypted KDBX4 backup in `backup_dir` and retains at most `max_backups`
    /// (default 60 in Enpass) rolling backup snapshots.
    pub fn create_backup(
        &self,
        backup_dir: impl AsRef<Path>,
        max_backups: usize,
    ) -> Result<PathBuf, VaultError> {
        let backup_dir = backup_dir.as_ref();
        fs::create_dir_all(backup_dir)?;

        let ts_secs = Times::now().and_utc().timestamp();
        let seq_id = Uuid::now_v7();
        let filename = format!("vaultkeep_backup_{ts_secs}_{seq_id}.kdbx");
        let backup_path = backup_dir.join(filename);
        save_db_to(&self.db, &backup_path, &self.master)?;

        let limit = max_backups.max(1);
        let mut backups: Vec<PathBuf> = fs::read_dir(backup_dir)?
            .filter_map(|res| res.ok())
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .and_then(|n| n.to_str())
                    .map(|s| s.starts_with("vaultkeep_backup_") && s.ends_with(".kdbx"))
                    .unwrap_or(false)
            })
            .collect();

        backups.sort();
        if backups.len() > limit {
            let to_remove = backups.len() - limit;
            for old_path in backups.into_iter().take(to_remove) {
                let _ = fs::remove_file(old_path);
            }
        }

        Ok(backup_path)
    }

    /// Lists existing encrypted KDBX4 backup snapshots in `backup_dir` (newest first).
    pub fn list_backups(backup_dir: impl AsRef<Path>) -> Result<Vec<PathBuf>, VaultError> {
        let backup_dir = backup_dir.as_ref();
        if !backup_dir.exists() {
            return Ok(Vec::new());
        }
        let mut backups: Vec<PathBuf> = fs::read_dir(backup_dir)?
            .filter_map(|res| res.ok())
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .and_then(|n| n.to_str())
                    .map(|s| s.starts_with("vaultkeep_backup_") && s.ends_with(".kdbx"))
                    .unwrap_or(false)
            })
            .collect();
        backups.sort_by(|a, b| b.cmp(a));
        Ok(backups)
    }

    /// Restores the active vault from an encrypted KDBX4 backup file (`backup_path`).
    /// If `backup_master` is empty, uses the active vault's master password.
    pub fn restore_backup(
        &mut self,
        backup_path: impl AsRef<Path>,
        backup_master: &str,
    ) -> Result<(), VaultError> {
        let effective_master = if backup_master.is_empty() {
            &self.master
        } else {
            backup_master
        };
        let restored = Vault::open(backup_path, effective_master)?;
        save_db_to(&restored.db, &self.path, &self.master)?;
        self.db = restored.db;
        Ok(())
    }

    /// Verifies `current_master` in constant time, overwrites the encrypted KDBX4 vault file
    /// with zeros (best-effort on-disk scrubbing), syncs to disk, and removes the file.
    pub fn erase_vault_file(&self, current_master: &str) -> Result<(), VaultError> {
        if !constant_time_eq(self.master.as_bytes(), current_master.as_bytes()) {
            return Err(VaultError::InvalidMasterPassword);
        }
        if self.path.exists() {
            if let Ok(len) = fs::metadata(&self.path).map(|m| m.len()) {
                if let Ok(mut f) = fs::OpenOptions::new().write(true).open(&self.path) {
                    let zeros = [0u8; 8192];
                    let mut remaining = len.min(MAX_VAULT_BYTES);
                    while remaining > 0 {
                        let chunk = (remaining as usize).min(zeros.len());
                        if f.write_all(&zeros[..chunk]).is_err() {
                            break;
                        }
                        remaining -= chunk as u64;
                    }
                    let _ = f.sync_all();
                }
            }
            fs::remove_file(&self.path)?;
        }
        Ok(())
    }

    /// Duplicates an existing entry (`id`) inside the vault using a sequential `Uuid::now_v7()`,
    /// copying all fields, protected secrets (`password`, `otp`, `security_answer`, sensitive custom fields),
    /// metadata (`category`, `tags`, `is_favorite`), group assignment, and protected attachments
    /// without exposing decrypted secrets across the FFI boundary.
    pub fn duplicate_entry(&mut self, id: Uuid) -> Result<Uuid, VaultError> {
        let details = self.details(id)?;
        let password = self.password(id)?;
        let otp = self.otp_uri(id)?;
        let security_answer = self.security_answer(id)?;

        let mut custom_fields = Vec::with_capacity(details.custom_fields.len());
        for (idx, cf) in details.custom_fields.iter().enumerate() {
            let val = if cf.sensitive {
                self.custom_field_value(id, idx)?
            } else {
                Zeroizing::new(cf.value.clone())
            };
            custom_fields.push(CustomFieldInput {
                name: cf.name.clone(),
                field_type: cf.field_type.clone(),
                section: cf.section.clone(),
                sensitive: cf.sensitive,
                value: val,
            });
        }

        let mut copied_attachments = Vec::with_capacity(details.attachments.len());
        for att in &details.attachments {
            let bytes = self.get_attachment(id, &att.name)?;
            copied_attachments.push((att.name.clone(), Zeroizing::new(bytes)));
        }

        let copy_title = if details.title.trim().is_empty() {
            "Copy".to_owned()
        } else {
            format!("{} - Copy", details.title)
        };

        let input = EntryInput {
            title: copy_title,
            username: details.username,
            password,
            url: details.url,
            notes: details.notes,
            group_id: details.group_id,
            otp,
            last_known_revision_date: None,
            email: details.email,
            phone: details.phone,
            security_question: details.security_question,
            security_answer,
            sections: details.sections,
            custom_fields,
        };

        let new_id = self.add(&input)?;
        let meta = EntryMetadata {
            category: details.category,
            tags: details.tags,
            is_favorite: details.is_favorite,
            is_archived: false,
            is_trashed: false,
            is_compromised: details.is_compromised,
            is_expired: details.is_expired,
        };
        self.set_entry_metadata(new_id, &meta)?;
        for (att_name, att_bytes) in copied_attachments {
            self.add_attachment(new_id, &att_name, &att_bytes)?;
        }
        self.save()?;
        Ok(new_id)
    }

    /// Exports the vault to `dest_path` after verifying `current_master` in constant time.
    /// Supported `format` values: `"kdbx"` (encrypted KDBX4 copy) or `"csv"` (UTF-8 CSV export).
    /// Returns the number of exported entries.
    pub fn export_vault_file(
        &self,
        dest_path: impl AsRef<Path>,
        current_master: &str,
        format: &str,
    ) -> Result<usize, VaultError> {
        if !constant_time_eq(self.master.as_bytes(), current_master.as_bytes()) {
            return Err(VaultError::InvalidMasterPassword);
        }
        let dest_path = dest_path.as_ref();
        if self.is_same_path(dest_path) {
            return Err(VaultError::SelfMerge);
        }
        if let Some(parent) = dest_path.parent() {
            if !parent.as_os_str().is_empty() {
                fs::create_dir_all(parent)?;
            }
        }

        let fmt_norm = format.trim().to_ascii_lowercase();
        if fmt_norm == "csv" {
            let mut buf = Zeroizing::new(String::from(
                "title,username,password,url,notes,category,email\n",
            ));
            let mut count = 0usize;
            for e in self.db.iter_all_entries() {
                if extract_bool(&e, VK_TRASHED) {
                    continue;
                }
                let parent = e.parent();
                let group_name = if parent.name.is_empty() {
                    None
                } else {
                    Some(parent.name.as_str())
                };
                let title = e.get_title().unwrap_or_default();
                let username = e.get_username().unwrap_or_default();
                let password = e.get_password().unwrap_or_default();
                let url = e.get_url().unwrap_or_default();
                let notes = e.get(fields::NOTES).unwrap_or_default();
                let category = extract_category(&e, group_name);
                let email = e.get(VK_EMAIL).unwrap_or_default();

                buf.push_str(&escape_csv_field(title));
                buf.push(',');
                buf.push_str(&escape_csv_field(username));
                buf.push(',');
                buf.push_str(&escape_csv_field(password));
                buf.push(',');
                buf.push_str(&escape_csv_field(url));
                buf.push(',');
                buf.push_str(&escape_csv_field(notes));
                buf.push(',');
                buf.push_str(&escape_csv_field(&category));
                buf.push(',');
                buf.push_str(&escape_csv_field(email));
                buf.push('\n');
                count += 1;
            }

            let parent = dest_path.parent().unwrap_or_else(|| Path::new("."));
            let mut tmp_file = tempfile::Builder::new()
                .prefix(".vaultkeep_export_")
                .suffix(".tmp")
                .tempfile_in(parent)?;
            tmp_file.write_all(buf.as_bytes())?;
            tmp_file.as_file().sync_all()?;
            tmp_file.persist(dest_path).map_err(|e| e.error)?;
            Ok(count)
        } else {
            save_db_to(&self.db, dest_path, &self.master)?;
            Ok(self.db.iter_all_entries().count())
        }
    }

    /// Imports credentials from CSV text (`title,username,password,url,notes,category,email,otp`).
    /// Assigns sequential `Uuid::now_v7()` identifiers and persists atomically to KDBX4.
    pub fn import_csv(&mut self, csv_content: &str) -> Result<usize, VaultError> {
        let mut imported = 0usize;
        for (line_idx, raw_line) in csv_content.lines().enumerate() {
            let trimmed = raw_line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let cols = parse_csv_row(trimmed);
            if cols.is_empty() {
                continue;
            }
            // Skip standard header row if present on first non-empty line
            if line_idx == 0 {
                let first_lower = cols[0].trim().to_ascii_lowercase();
                if first_lower == "title" || first_lower == "name" {
                    continue;
                }
            }
            let title = cols.first().map(|s| s.trim()).unwrap_or_default();
            let username = cols.get(1).map(|s| s.trim()).unwrap_or_default();
            let password = cols.get(2).map(|s| s.as_str()).unwrap_or_default();
            let url = cols.get(3).map(|s| s.trim()).unwrap_or_default();
            let notes = cols.get(4).map(|s| s.trim()).unwrap_or_default();
            let category = cols.get(5).map(|s| s.trim()).unwrap_or_default();
            let email = cols.get(6).map(|s| s.trim()).unwrap_or_default();
            let otp = cols
                .get(7)
                .map(|s| s.trim())
                .filter(|s| !s.is_empty())
                .map(|s| Zeroizing::new(s.to_owned()));

            if title.is_empty() && username.is_empty() && password.is_empty() && url.is_empty() {
                continue;
            }

            let input = EntryInput {
                title: if title.is_empty() {
                    "Imported Item".to_owned()
                } else {
                    title.to_owned()
                },
                username: username.to_owned(),
                password: Zeroizing::new(password.to_owned()),
                url: url.to_owned(),
                notes: notes.to_owned(),
                group_id: None,
                otp,
                last_known_revision_date: None,
                email: email.to_owned(),
                phone: String::new(),
                security_question: String::new(),
                security_answer: None,
                sections: Vec::new(),
                custom_fields: Vec::new(),
            };
            let new_id = self.add(&input)?;
            if !category.is_empty() {
                let meta = EntryMetadata {
                    category: category.to_owned(),
                    ..Default::default()
                };
                self.set_entry_metadata(new_id, &meta)?;
            }
            imported += 1;
        }
        if imported > 0 {
            self.save()?;
        }
        Ok(imported)
    }

    fn find(&self, id: Uuid) -> Result<EntryId, VaultError> {
        self.db
            .iter_all_entries()
            .find(|e| e.id().uuid() == id)
            .map(|e| e.id())
            .ok_or(VaultError::NotFound)
    }
}

fn escape_csv_field(field: &str) -> String {
    if field.contains([',', '"', '\n', '\r']) {
        format!("\"{}\"", field.replace('"', "\"\""))
    } else {
        field.to_owned()
    }
}

fn parse_csv_row(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    let mut chars = line.chars().peekable();
    while let Some(ch) = chars.next() {
        if in_quotes {
            if ch == '"' {
                if chars.peek() == Some(&'"') {
                    current.push('"');
                    let _ = chars.next();
                } else {
                    in_quotes = false;
                }
            } else {
                current.push(ch);
            }
        } else if ch == '"' {
            in_quotes = true;
        } else if ch == ',' {
            fields.push(std::mem::take(&mut current));
        } else {
            current.push(ch);
        }
    }
    fields.push(current);
    fields
}

fn set_or_remove_bool(entry: &mut keepass::db::EntryTrack<'_>, key: &str, value: bool) {
    if value {
        entry.set_unprotected(key, "true");
    } else {
        entry.fields.remove(key);
    }
}

fn extract_bool(entry: &keepass::db::EntryRef<'_>, key: &str) -> bool {
    matches!(
        entry
            .get(key)
            .unwrap_or_default()
            .trim()
            .to_ascii_lowercase()
            .as_str(),
        "true" | "1" | "yes"
    )
}

fn extract_category(entry: &keepass::db::EntryRef<'_>, group_name: Option<&str>) -> String {
    let explicit = entry.get(VK_CATEGORY).unwrap_or_default().trim();
    if !explicit.is_empty() {
        return explicit.to_owned();
    }
    if let Some(g) = group_name {
        let gl = g.to_ascii_lowercase();
        for &(kw, cat) in &[
            ("card", "Credit Card"),
            ("credit", "Credit Card"),
            ("identity", "Identity"),
            ("note", "Note"),
            ("password", "Password"),
            ("finance", "Finance"),
            ("bank", "Finance"),
            ("crypto", "Finance"),
            ("license", "License"),
            ("travel", "Travel"),
            ("computer", "Computer"),
            ("server", "Computer"),
            ("ssh", "Computer"),
            ("misc", "Miscellaneous"),
        ] {
            if gl.contains(kw) {
                return cat.to_owned();
            }
        }
    }
    "Login".to_owned()
}

fn extract_tags(entry: &keepass::db::EntryRef<'_>) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for t in &entry.tags {
        let trimmed = t.trim();
        if !trimmed.is_empty() && !out.iter().any(|x| x.eq_ignore_ascii_case(trimmed)) {
            out.push(trimmed.to_owned());
        }
    }
    let raw = entry.get(VK_TAGS).unwrap_or_default();
    for part in raw.split(',') {
        let trimmed = part.trim();
        if !trimmed.is_empty() && !out.iter().any(|x| x.eq_ignore_ascii_case(trimmed)) {
            out.push(trimmed.to_owned());
        }
    }
    out
}

fn is_entry_expired(entry: &keepass::db::EntryRef<'_>) -> bool {
    if entry.times.expires != Some(true) {
        return false;
    }
    match entry.times.expiry {
        Some(exp) => exp <= Times::now(),
        None => false,
    }
}

fn extract_passkey(entry: &keepass::db::EntryRef<'_>) -> Option<PasskeySummary> {
    let cred_id = entry
        .get(KPEX_PASSKEY_CREDENTIAL_ID)
        .unwrap_or_default()
        .trim();
    if cred_id.is_empty() {
        return None;
    }
    Some(PasskeySummary {
        rp_id: entry
            .get(KPEX_PASSKEY_RELYING_PARTY)
            .unwrap_or_default()
            .to_owned(),
        username: entry
            .get(KPEX_PASSKEY_USERNAME)
            .unwrap_or_default()
            .to_owned(),
        credential_id: cred_id.to_owned(),
        user_handle: entry
            .get(KPEX_PASSKEY_USER_HANDLE)
            .unwrap_or_default()
            .to_owned(),
    })
}

fn resolve_passkey_rp_and_user(
    entry: &keepass::db::EntryRef<'_>,
    rp_id: &str,
    username: &str,
) -> Result<(String, String), VaultError> {
    let effective_rp_id = {
        let cleaned = clean_domain_or_host(rp_id);
        if !cleaned.is_empty() {
            cleaned
        } else {
            let from_url = clean_domain_or_host(entry.get_url().unwrap_or_default());
            if !from_url.is_empty() {
                from_url
            } else {
                let from_title: String = entry
                    .get_title()
                    .unwrap_or_default()
                    .trim()
                    .to_lowercase()
                    .chars()
                    .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '.')
                    .collect();
                if from_title.is_empty() {
                    return Err(VaultError::Policy(
                        "relying party ID or entry URL/title is required for passkey",
                    ));
                }
                if from_title.contains('.') {
                    from_title
                } else {
                    format!("{from_title}.local")
                }
            }
        }
    };

    let effective_username = {
        let trimmed = username.trim();
        if !trimmed.is_empty() {
            trimmed.to_owned()
        } else {
            let entry_user = entry.get_username().unwrap_or_default().trim();
            if !entry_user.is_empty() {
                entry_user.to_owned()
            } else {
                "user".to_owned()
            }
        }
    };

    Ok((effective_rp_id, effective_username))
}

fn clear_passkey_fields(entry: &mut keepass::db::EntryTrack<'_>) {
    entry.fields.remove(KPEX_PASSKEY_RELYING_PARTY);
    entry.fields.remove(KPEX_PASSKEY_USERNAME);
    entry.fields.remove(KPEX_PASSKEY_DISPLAY_NAME);
    entry.fields.remove(KPEX_PASSKEY_CREDENTIAL_ID);
    entry.fields.remove(KPEX_PASSKEY_USER_HANDLE);
    entry.fields.remove(KPEX_PASSKEY_FLAG_BE);
    entry.fields.remove(KPEX_PASSKEY_FLAG_BS);
    entry.fields.remove(KPEX_PASSKEY_SIGN_COUNT);
    entry.fields.remove(KPEX_PASSKEY_PRIVATE_KEY_PEM);
}

const PASSKEY_SUPPORTED_DOMAINS: &[&str] = &[
    "google.com",
    "gmail.com",
    "github.com",
    "gitlab.com",
    "amazon.com",
    "aws.amazon.com",
    "microsoft.com",
    "live.com",
    "outlook.com",
    "apple.com",
    "icloud.com",
    "cloudflare.com",
    "binance.com",
    "coinbase.com",
    "paypal.com",
    "stripe.com",
    "discord.com",
    "adobe.com",
    "twitter.com",
    "x.com",
    "proton.me",
    "dropbox.com",
    "linkedin.com",
    "shopify.com",
    "ebay.com",
    "sony.com",
    "playstation.com",
    "nintendo.com",
    "kayak.com",
    "bestbuy.com",
    "uber.com",
    "whatsapp.com",
    "tiktok.com",
    "1password.com",
    "bitwarden.com",
];

const PASSKEY_SUPPORTED_KEYWORDS: &[&str] = &[
    "google",
    "gmail",
    "github",
    "gitlab",
    "amazon",
    "aws",
    "microsoft",
    "outlook",
    "apple",
    "icloud",
    "cloudflare",
    "binance",
    "coinbase",
    "paypal",
    "stripe",
    "discord",
    "adobe",
    "twitter",
    "proton",
    "dropbox",
    "linkedin",
    "shopify",
    "ebay",
    "sony",
    "playstation",
    "nintendo",
    "kayak",
    "bestbuy",
    "uber",
    "whatsapp",
    "tiktok",
];

const TWO_FA_SUPPORTED_DOMAINS: &[&str] = &[
    "google.com",
    "gmail.com",
    "github.com",
    "gitlab.com",
    "amazon.com",
    "aws.amazon.com",
    "microsoft.com",
    "live.com",
    "outlook.com",
    "apple.com",
    "icloud.com",
    "cloudflare.com",
    "binance.com",
    "coinbase.com",
    "paypal.com",
    "stripe.com",
    "discord.com",
    "adobe.com",
    "twitter.com",
    "x.com",
    "proton.me",
    "dropbox.com",
    "linkedin.com",
    "shopify.com",
    "ebay.com",
    "sony.com",
    "playstation.com",
    "nintendo.com",
    "reddit.com",
    "facebook.com",
    "instagram.com",
    "slack.com",
    "notion.so",
    "figma.com",
    "digitalocean.com",
    "heroku.com",
    "vercel.com",
    "npmjs.com",
    "pypi.org",
    "crates.io",
    "steam.com",
    "steampowered.com",
    "epicgames.com",
    "ea.com",
    "ubisoft.com",
    "bethesda.net",
];

const TWO_FA_SUPPORTED_KEYWORDS: &[&str] = &[
    "google",
    "gmail",
    "github",
    "gitlab",
    "amazon",
    "aws",
    "microsoft",
    "outlook",
    "apple",
    "icloud",
    "cloudflare",
    "binance",
    "coinbase",
    "paypal",
    "stripe",
    "discord",
    "adobe",
    "twitter",
    "proton",
    "dropbox",
    "linkedin",
    "shopify",
    "ebay",
    "sony",
    "playstation",
    "nintendo",
    "reddit",
    "facebook",
    "instagram",
    "slack",
    "notion",
    "figma",
    "digitalocean",
    "steam",
    "epic",
    "bethesda",
    "deviantart",
    "blockchain",
    "coindcx",
    "coinspot",
    "dynu",
    "avast",
];

/// Checks whether an entry already has a Passkey or belongs to a Relying Party known to support Passkeys.
pub fn is_passkey_supported(title: &str, url: &str, has_passkey: bool) -> bool {
    if has_passkey {
        return true;
    }
    let host = clean_domain_or_host(url);
    if !host.is_empty()
        && PASSKEY_SUPPORTED_DOMAINS
            .iter()
            .any(|d| matches_host(&host, d))
    {
        return true;
    }
    let title_lower = title.to_lowercase();
    title_lower
        .split(|c: char| !c.is_alphanumeric())
        .any(|word| !word.is_empty() && PASSKEY_SUPPORTED_KEYWORDS.contains(&word))
}

/// Checks whether an entry has TOTP configured or belongs to a website known to support 2FA/TOTP.
pub fn is_two_fa_supported(title: &str, url: &str, has_totp: bool) -> bool {
    if has_totp {
        return true;
    }
    let host = clean_domain_or_host(url);
    if !host.is_empty()
        && TWO_FA_SUPPORTED_DOMAINS
            .iter()
            .any(|d| matches_host(&host, d))
    {
        return true;
    }
    let title_lower = title.to_lowercase();
    title_lower
        .split(|c: char| !c.is_alphanumeric())
        .any(|word| !word.is_empty() && TWO_FA_SUPPORTED_KEYWORDS.contains(&word))
}

fn encode_base64url(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::with_capacity((bytes.len() * 4).div_ceil(3));
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(ALPHABET[((triple >> 18) & 0x3F) as usize] as char);
        out.push(ALPHABET[((triple >> 12) & 0x3F) as usize] as char);
        if chunk.len() > 1 {
            out.push(ALPHABET[((triple >> 6) & 0x3F) as usize] as char);
        }
        if chunk.len() > 2 {
            out.push(ALPHABET[(triple & 0x3F) as usize] as char);
        }
    }
    out
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
    // Entry is a subdomain of target — e.g. entry "mail.google.com" matches target "google.com".
    // We intentionally do NOT match the reverse direction (target being a subdomain of entry)
    // without eTLD+1 validation, as it would allow overly broad credential matching.
    entry_host.ends_with(&format!(".{target_host}"))
}

fn key(master: &str) -> DatabaseKey {
    DatabaseKey::new().with_password(master)
}

fn apply_kdf_config(config: &mut DatabaseConfig, kdf: KdfParams) -> Result<(), VaultError> {
    kdf.validate()?;
    let version = match DatabaseConfig::default().kdf_config {
        KdfConfig::Argon2 { version, .. } | KdfConfig::Argon2id { version, .. } => version,
        _ => unreachable!("DatabaseConfig::default() uses Argon2 Version13"),
    };
    config.kdf_config = KdfConfig::Argon2id {
        iterations: kdf.iterations,
        memory: kdf.memory_bytes,
        parallelism: kdf.parallelism,
        version,
    };
    Ok(())
}

fn save_db_to(db: &Database, dest: &Path, master: &str) -> Result<(), VaultError> {
    let parent = dest.parent().unwrap_or_else(|| Path::new("."));
    let mut tmp_file = tempfile::Builder::new()
        .prefix(".vaultkeep_tmp_")
        .suffix(".kdbx")
        .tempfile_in(parent)?;

    let write_res = (|| -> Result<(), VaultError> {
        {
            let mut w = BufWriter::new(&mut tmp_file);
            db.save(&mut w, key(master))?;
            w.flush()?;
        }
        tmp_file.as_file().sync_all()?;
        Ok(())
    })();

    write_res?;

    tmp_file.persist(dest).map_err(|e| e.error)?;
    Ok(())
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    let key = ring::hmac::Key::new(ring::hmac::HMAC_SHA256, b"VAULTKEEP_CT_EQ_V1");
    let tag_a = ring::hmac::sign(&key, a);
    ring::hmac::verify(&key, b, tag_a.as_ref()).is_ok() && a.len() == b.len()
}

fn entry_revision_date(entry: &keepass::db::EntryRef<'_>) -> Option<i64> {
    entry
        .times
        .last_modification
        .map(|dt| dt.and_utc().timestamp())
}

fn check_revision(
    entry: &keepass::db::EntryRef<'_>,
    expected: Option<i64>,
) -> Result<(), VaultError> {
    if let Some(expected_rev) = expected {
        if let Some(actual_rev) = entry_revision_date(entry) {
            if (actual_rev - expected_rev).abs() > 1 {
                return Err(VaultError::StaleRevision {
                    expected: expected_rev,
                    actual: actual_rev,
                });
            }
        }
    }
    Ok(())
}

fn bump_modification_time(prev: &Times, current: &mut Times) {
    let now = Times::now();
    let next = match prev.last_modification {
        Some(p) if now <= p => p + Duration::from_secs(1),
        _ => now,
    };
    current.last_modification = Some(next);
}

fn bump_location_time(prev: &Times, current: &mut Times) {
    let now = Times::now();
    let next = match prev.location_changed {
        Some(p) if now <= p => p + Duration::from_secs(1),
        _ => now,
    };
    current.location_changed = Some(next);
}

fn extract_sections(entry: &keepass::db::EntryRef<'_>) -> Vec<String> {
    let raw = entry.get(VK_SECTIONS).unwrap_or_default();
    let parsed: Vec<String> = raw
        .lines()
        .map(|s| s.trim().to_owned())
        .filter(|s| !s.is_empty())
        .collect();
    if parsed.is_empty() {
        vec!["ADDITIONAL DETAILS".to_owned(), "Section".to_owned()]
    } else {
        parsed
    }
}

fn extract_custom_fields(entry: &keepass::db::EntryRef<'_>) -> Vec<CustomFieldSummary> {
    let count = entry
        .get(VK_CF_COUNT)
        .and_then(|s| s.trim().parse::<usize>().ok())
        .unwrap_or(0)
        .min(128);
    let mut out = Vec::with_capacity(count);
    for idx in 0..count {
        let meta_key = format!("VK_CF_META_{idx}");
        let val_key = format!("VK_CF_VAL_{idx}");
        let Some(meta_raw) = entry.get(&meta_key) else {
            continue;
        };
        let mut parts = meta_raw.splitn(4, '\t');
        let name = parts.next().unwrap_or("Custom Field").to_owned();
        let field_type = parts.next().unwrap_or("Text").to_owned();
        let section = parts.next().unwrap_or("Section").to_owned();
        let sensitive = matches!(parts.next().unwrap_or("0"), "1" | "true");
        let value = if sensitive {
            String::new()
        } else {
            entry.get(&val_key).unwrap_or_default().to_owned()
        };
        out.push(CustomFieldSummary {
            name,
            field_type,
            section,
            sensitive,
            value,
        });
    }
    out
}

fn apply_initial(entry: &mut keepass::db::EntryMut<'_>, input: &EntryInput) {
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
    if input.email.trim().is_empty() {
        entry.fields.remove(VK_EMAIL);
    } else {
        entry.set_unprotected(VK_EMAIL, input.email.trim());
    }
    if input.phone.trim().is_empty() {
        entry.fields.remove(VK_PHONE);
    } else {
        entry.set_unprotected(VK_PHONE, input.phone.trim());
    }
    if input.security_question.trim().is_empty() {
        entry.fields.remove(VK_SECURITY_QUESTION);
    } else {
        entry.set_unprotected(VK_SECURITY_QUESTION, input.security_question.trim());
    }
    if let Some(ref ans) = input.security_answer {
        if ans.trim().is_empty() {
            entry.fields.remove(VK_SECURITY_ANSWER);
        } else {
            entry.set_protected(VK_SECURITY_ANSWER, ans.as_str());
        }
    }
    let cleaned_sections: Vec<String> = input
        .sections
        .iter()
        .map(|s| s.trim().replace('\n', " "))
        .filter(|s| !s.is_empty())
        .collect();
    if cleaned_sections.is_empty() {
        entry.fields.remove(VK_SECTIONS);
    } else {
        entry.set_unprotected(VK_SECTIONS, cleaned_sections.join("\n").as_str());
    }
    if input.custom_fields.is_empty() {
        entry.fields.remove(VK_CF_COUNT);
    } else {
        let count = input.custom_fields.len().min(128);
        entry.set_unprotected(VK_CF_COUNT, count.to_string().as_str());
        for (idx, cf) in input.custom_fields.iter().take(count).enumerate() {
            let meta_key = format!("VK_CF_META_{idx}");
            let val_key = format!("VK_CF_VAL_{idx}");
            let meta_val = format!(
                "{}\t{}\t{}\t{}",
                cf.name.replace(['\t', '\n'], " "),
                cf.field_type.replace(['\t', '\n'], " "),
                cf.section.replace(['\t', '\n'], " "),
                if cf.sensitive { "1" } else { "0" }
            );
            entry.set_unprotected(&meta_key, meta_val.as_str());
            if cf.sensitive {
                entry.set_protected(&val_key, cf.value.as_str());
            } else {
                entry.set_unprotected(&val_key, cf.value.as_str());
            }
        }
    }
}

fn apply_tracked(entry: &mut keepass::db::EntryTrack<'_>, input: &EntryInput) {
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
    if input.email.trim().is_empty() {
        entry.fields.remove(VK_EMAIL);
    } else {
        entry.set_unprotected(VK_EMAIL, input.email.trim());
    }
    if input.phone.trim().is_empty() {
        entry.fields.remove(VK_PHONE);
    } else {
        entry.set_unprotected(VK_PHONE, input.phone.trim());
    }
    if input.security_question.trim().is_empty() {
        entry.fields.remove(VK_SECURITY_QUESTION);
    } else {
        entry.set_unprotected(VK_SECURITY_QUESTION, input.security_question.trim());
    }
    if let Some(ref ans) = input.security_answer {
        if ans.trim().is_empty() {
            entry.fields.remove(VK_SECURITY_ANSWER);
        } else {
            entry.set_protected(VK_SECURITY_ANSWER, ans.as_str());
        }
    }
    let cleaned_sections: Vec<String> = input
        .sections
        .iter()
        .map(|s| s.trim().replace('\n', " "))
        .filter(|s| !s.is_empty())
        .collect();
    if cleaned_sections.is_empty() {
        entry.fields.remove(VK_SECTIONS);
    } else {
        entry.set_unprotected(VK_SECTIONS, cleaned_sections.join("\n").as_str());
    }

    for idx in 0..128 {
        entry.fields.remove(&format!("VK_CF_META_{idx}"));
        entry.fields.remove(&format!("VK_CF_VAL_{idx}"));
    }
    if input.custom_fields.is_empty() {
        entry.fields.remove(VK_CF_COUNT);
    } else {
        let count = input.custom_fields.len().min(128);
        entry.set_unprotected(VK_CF_COUNT, count.to_string().as_str());
        for (idx, cf) in input.custom_fields.iter().take(count).enumerate() {
            let meta_key = format!("VK_CF_META_{idx}");
            let val_key = format!("VK_CF_VAL_{idx}");
            let meta_val = format!(
                "{}\t{}\t{}\t{}",
                cf.name.replace(['\t', '\n'], " "),
                cf.field_type.replace(['\t', '\n'], " "),
                cf.section.replace(['\t', '\n'], " "),
                if cf.sensitive { "1" } else { "0" }
            );
            entry.set_unprotected(&meta_key, meta_val.as_str());
            if cf.sensitive {
                entry.set_protected(&val_key, cf.value.as_str());
            } else {
                entry.set_unprotected(&val_key, cf.value.as_str());
            }
        }
    }
}
