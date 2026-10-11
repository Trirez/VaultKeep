//! Public API surface scanned by `flutter_rust_bridge_codegen`.
//!
//! Every `pub` item here becomes a Dart function or class. Rules:
//! - use `u32`/`i32`, never `usize` (it becomes `BigInt` in Dart);
//! - errors are plain strings that never contain secrets;
//! - list/detail types carry no password; it is fetched only by `reveal_password`.

use std::sync::{Mutex, MutexGuard};

use uuid::Uuid;
use vaultkeep_core::{
    evaluate_password_strength, generate_password, generate_password_advanced,
    AdvancedPasswordPolicy, CustomFieldInput, EntryInput, EntryMetadata, PasswordPolicy,
};
use zeroize::Zeroizing;

use crate::session::Session;

static SESSION: Mutex<Session> = Mutex::new(Session::new());

fn session() -> MutexGuard<'static, Session> {
    match SESSION.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            // Fail closed: if a panic occurred while holding the session lock,
            // drop any potentially half-mutated open vault and return a locked session.
            let mut guard = poisoned.into_inner();
            guard.lock();
            SESSION.clear_poison();
            guard
        }
    }
}

fn parse_id(id: &str) -> Result<Uuid, String> {
    Uuid::parse_str(id).map_err(|_| "invalid entry id".to_string())
}

fn map_summary(s: vaultkeep_core::EntrySummary) -> EntryItem {
    EntryItem {
        id: s.id.to_string(),
        title: s.title,
        username: s.username,
        email: s.email,
        url: s.url,
        group_name: s.group_name,
        has_passkey: s.has_passkey,
        passkey_supported: s.passkey_supported,
        has_totp: s.has_totp,
        revision_date: s.revision_date,
        category: s.category,
        tags: s.tags,
        is_favorite: s.is_favorite,
        is_archived: s.is_archived,
        is_trashed: s.is_trashed,
        has_attachment: s.has_attachment,
        two_fa_supported: s.two_fa_supported,
        password_strength: s.password_strength,
        strength_score: u32::from(s.strength_score),
        is_weak: s.is_weak,
        is_identical: s.is_identical,
        is_compromised: s.is_compromised,
        is_breached: s.is_breached,
        is_expired: s.is_expired,
    }
}

/// One row in the entry list. No secrets.
#[derive(Debug, Clone)]
pub struct EntryItem {
    pub id: String,
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
    pub strength_score: u32,
    pub is_weak: bool,
    pub is_identical: bool,
    pub is_compromised: bool,
    pub is_breached: bool,
    pub is_expired: bool,
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

/// Non-secret metadata + non-sensitive value for a custom field in `EntryDetails`.
/// Sensitive values are empty here and fetched via `reveal_custom_field`.
#[derive(Debug, Clone)]
pub struct CustomFieldItem {
    pub name: String,
    pub field_type: String,
    pub section: String,
    pub sensitive: bool,
    pub value: String,
}

/// Custom field input from the edit screen. Deliberately no `Debug` (it may hold a sensitive value).
pub struct CustomFieldData {
    pub name: String,
    pub field_type: String,
    pub section: String,
    pub sensitive: bool,
    pub value: String,
}

/// Non-secret container and Argon2id KDF summary for `Settings -> Vaults -> VAULT INFO`.
#[derive(Debug, Clone)]
pub struct VaultInfoItem {
    pub path: String,
    pub entry_count: u32,
    pub group_count: u32,
    pub kdf_iterations: u32,
    pub kdf_memory_mib: u32,
    pub kdf_parallelism: u32,
}

/// Authoritative Rust password strength evaluation result.
#[derive(Debug, Clone)]
pub struct PasswordEvaluationItem {
    pub score: u32,
    pub label: String,
    pub is_compromised: bool,
    pub is_weak: bool,
}

/// Non-secret metadata for a KDBX4 Passkey (`KPEX_PASSKEY_*`).
#[derive(Debug, Clone)]
pub struct PasskeyItem {
    pub rp_id: String,
    pub username: String,
    pub credential_id: String,
    pub user_handle: String,
}

/// WebAuthn `GetAssertion` ceremony response for Windows (`webauthn.dll`) and Android (`CredentialManager`).
#[derive(Debug, Clone)]
pub struct PasskeyAssertionItem {
    pub credential_id: String,
    pub rp_id: String,
    pub username: String,
    pub user_handle: String,
    pub platform: String,
    pub authenticator_attachment: String,
    pub authenticator_data_b64url: String,
    pub client_data_json_b64url: String,
    pub signature_b64url: String,
    pub flags: u32,
    pub user_verified: bool,
    pub backup_eligible: bool,
    pub backup_state: bool,
    pub sign_count: u32,
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

/// Everything about an entry except its password and sensitive custom field values.
#[derive(Clone)]
pub struct EntryDetails {
    pub id: String,
    pub title: String,
    pub username: String,
    pub email: String,
    pub url: String,
    pub phone: String,
    pub security_question: String,
    pub has_security_answer: bool,
    pub notes: String,
    pub group_id: Option<String>,
    pub group_name: Option<String>,
    pub has_otp: bool,
    pub attachments: Vec<AttachmentItem>,
    pub passkey: Option<PasskeyItem>,
    pub passkey_supported: bool,
    pub revision_date: Option<i64>,
    pub category: String,
    pub tags: Vec<String>,
    pub is_favorite: bool,
    pub is_archived: bool,
    pub is_trashed: bool,
    pub two_fa_supported: bool,
    pub password_strength: String,
    pub strength_score: u32,
    pub is_weak: bool,
    pub is_identical: bool,
    pub is_compromised: bool,
    pub is_breached: bool,
    pub is_expired: bool,
    pub sections: Vec<String>,
    pub custom_fields: Vec<CustomFieldItem>,
}

impl std::fmt::Debug for EntryDetails {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
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

/// Data from the edit screen. Deliberately no `Debug` (it holds a password and sensitive answers).
pub struct EntryData {
    pub title: String,
    pub username: String,
    pub password: String,
    pub url: String,
    pub notes: String,
    pub group_id: Option<String>,
    pub otp: Option<String>,
    pub last_known_revision_date: Option<i64>,
    pub category: Option<String>,
    pub tags: Vec<String>,
    pub is_favorite: bool,
    pub is_archived: bool,
    pub is_trashed: bool,
    pub email: String,
    pub phone: String,
    pub security_question: String,
    pub security_answer: Option<String>,
    pub sections: Vec<String>,
    pub custom_fields: Vec<CustomFieldData>,
}

/// Advanced password generator policy exposed over FFI.
#[derive(Debug, Clone)]
pub struct CustomPasswordPolicy {
    pub length: u32,
    pub uppercase: bool,
    pub digits: bool,
    pub symbols: bool,
    pub pronounceable: bool,
    pub separator: String,
    pub allow_ambiguous: bool,
    pub exact_mode: bool,
    pub min_upper: u32,
    pub min_digits: u32,
    pub min_symbols: u32,
    pub exclude_chars: String,
    pub include_chars: String,
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
    Ok(found.into_iter().map(map_summary).collect())
}

pub fn get_entry(id: String) -> Result<EntryDetails, String> {
    let d = session()
        .details(parse_id(&id)?)
        .map_err(|e| e.to_string())?;
    Ok(EntryDetails {
        id: d.id.to_string(),
        title: d.title,
        username: d.username,
        email: d.email,
        url: d.url,
        phone: d.phone,
        security_question: d.security_question,
        has_security_answer: d.has_security_answer,
        notes: d.notes,
        group_id: d.group_id.map(|g| g.to_string()),
        group_name: d.group_name,
        has_otp: d.has_otp,
        attachments: d
            .attachments
            .into_iter()
            .map(|a| AttachmentItem {
                name: a.name,
                size: a.size as u32,
            })
            .collect(),
        passkey: d.passkey.map(|p| PasskeyItem {
            rp_id: p.rp_id,
            username: p.username,
            credential_id: p.credential_id,
            user_handle: p.user_handle,
        }),
        passkey_supported: d.passkey_supported,
        revision_date: d.revision_date,
        category: d.category,
        tags: d.tags,
        is_favorite: d.is_favorite,
        is_archived: d.is_archived,
        is_trashed: d.is_trashed,
        two_fa_supported: d.two_fa_supported,
        password_strength: d.password_strength,
        strength_score: u32::from(d.strength_score),
        is_weak: d.is_weak,
        is_identical: d.is_identical,
        is_compromised: d.is_compromised,
        is_breached: d.is_breached,
        is_expired: d.is_expired,
        sections: d.sections,
        custom_fields: d
            .custom_fields
            .into_iter()
            .map(|cf| CustomFieldItem {
                name: cf.name,
                field_type: cf.field_type,
                section: cf.section,
                sensitive: cf.sensitive,
                value: cf.value,
            })
            .collect(),
    })
}

/// The only call that returns a password. Use for copy/reveal.
/// Note: `Zeroizing<String>` from core is converted to a plain `String` at the FFI
/// boundary because `flutter_rust_bridge` does not support custom drop semantics.
/// The Dart VM's immutable strings cannot be wiped. This is an accepted limitation
/// documented in the threat model (§1 — Trust Boundary Details).
pub fn reveal_password(id: String) -> Result<String, String> {
    let pw = session()
        .password(parse_id(&id)?)
        .map_err(|e| e.to_string())?;
    Ok(pw.to_string())
}

/// The only call that returns a TOTP seed URI. Use for edit/reveal.
pub fn reveal_otp_uri(id: String) -> Result<Option<String>, String> {
    let uri = session()
        .otp_uri(parse_id(&id)?)
        .map_err(|e| e.to_string())?;
    // Note: Zeroizing<String> → plain String at FFI boundary (accepted limitation).
    Ok(uri.map(|z| z.to_string()))
}

/// The only call that returns the protected Security Answer (`VK_SECURITY_ANSWER`).
pub fn reveal_security_answer(id: String) -> Result<Option<String>, String> {
    let ans = session()
        .security_answer(parse_id(&id)?)
        .map_err(|e| e.to_string())?;
    Ok(ans.map(|z| z.to_string()))
}

/// The only call that returns a protected Custom Field value (`VK_CF_VAL_{index}`).
pub fn reveal_custom_field(id: String, index: u32) -> Result<String, String> {
    let val = session()
        .custom_field_value(parse_id(&id)?, index as usize)
        .map_err(|e| e.to_string())?;
    Ok(val.to_string())
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
        last_known_revision_date: data.last_known_revision_date,
        email: data.email,
        phone: data.phone,
        security_question: data.security_question,
        security_answer: data.security_answer.map(Zeroizing::new),
        sections: data.sections,
        custom_fields: data
            .custom_fields
            .into_iter()
            .map(|cf| CustomFieldInput {
                name: cf.name,
                field_type: cf.field_type,
                section: cf.section,
                sensitive: cf.sensitive,
                value: Zeroizing::new(cf.value),
            })
            .collect(),
    };
    let mut sess = session();
    let saved_id = sess.save_entry(id, &input).map_err(|e| e.to_string())?;
    if data.category.is_some()
        || !data.tags.is_empty()
        || data.is_favorite
        || data.is_archived
        || data.is_trashed
    {
        let meta = EntryMetadata {
            category: data.category.unwrap_or_else(|| "Login".to_string()),
            tags: data.tags,
            is_favorite: data.is_favorite,
            is_archived: data.is_archived,
            is_trashed: data.is_trashed,
            is_compromised: false,
            is_expired: false,
        };
        sess.set_metadata(saved_id, &meta)
            .map_err(|e| e.to_string())?;
    }
    Ok(saved_id.to_string())
}

/// Update non-secret Enpass metadata (category, tags, favorite, archive, trash) without touching the password.
pub fn set_entry_metadata(
    id: String,
    category: String,
    tags: Vec<String>,
    is_favorite: bool,
    is_archived: bool,
    is_trashed: bool,
) -> Result<(), String> {
    let entry_id = parse_id(&id)?;
    let mut sess = session();
    let existing = sess.details(entry_id).map_err(|e| e.to_string())?;
    let meta = EntryMetadata {
        category,
        tags,
        is_favorite,
        is_archived,
        is_trashed,
        is_compromised: existing.is_compromised,
        is_expired: existing.is_expired,
    };
    sess.set_metadata(entry_id, &meta)
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

/// Enpass-grade advanced password generator from OS CSPRNG.
pub fn generate_custom_password(policy: CustomPasswordPolicy) -> Result<String, String> {
    let adv = AdvancedPasswordPolicy {
        length: policy.length as usize,
        lower: true,
        upper: policy.uppercase,
        digits: policy.digits,
        symbols: policy.symbols,
        pronounceable: policy.pronounceable,
        separator: policy.separator,
        allow_ambiguous: policy.allow_ambiguous,
        exact_mode: policy.exact_mode,
        min_upper: policy.min_upper as usize,
        min_digits: policy.min_digits as usize,
        min_symbols: policy.min_symbols as usize,
        exclude_chars: policy.exclude_chars,
        include_chars: policy.include_chars,
    };
    generate_password_advanced(&adv).map_err(|e| e.to_string())
}

/// Evaluates password strength and compromised advisory status inside Rust (`Zeroizing` the input).
pub fn evaluate_password(password: String) -> PasswordEvaluationItem {
    let pw = Zeroizing::new(password);
    let (score, label, is_compromised) = evaluate_password_strength(&pw);
    PasswordEvaluationItem {
        score: u32::from(score),
        label: label.to_string(),
        is_compromised,
        is_weak: score < 50,
    }
}

/// Returns non-secret container metadata and Argon2id KDF parameters for the open vault.
pub fn get_vault_info() -> Result<VaultInfoItem, String> {
    let info = session().vault_info().map_err(|e| e.to_string())?;
    Ok(VaultInfoItem {
        path: info.path,
        entry_count: info.entry_count as u32,
        group_count: info.group_count as u32,
        kdf_iterations: info.kdf_iterations as u32,
        kdf_memory_mib: (info.kdf_memory_bytes / (1024 * 1024)) as u32,
        kdf_parallelism: info.kdf_parallelism,
    })
}

/// Create a timestamped encrypted backup of the unlocked vault and prune backups beyond `max_backups`.
pub fn create_vault_backup(backup_dir: String, max_backups: u32) -> Result<String, String> {
    session()
        .create_backup(&backup_dir, max_backups as usize)
        .map_err(|e| e.to_string())
}

/// Lists existing encrypted KDBX4 backup snapshots in `backup_dir` (newest first).
pub fn list_vault_backups(backup_dir: String) -> Result<Vec<String>, String> {
    session()
        .list_backups(&backup_dir)
        .map_err(|e| e.to_string())
}

/// Restores the unlocked vault from an encrypted KDBX4 backup file (`backup_path`).
pub fn restore_vault_backup(backup_path: String, backup_master: String) -> Result<(), String> {
    let backup_master = Zeroizing::new(backup_master);
    session()
        .restore_backup(&backup_path, &backup_master)
        .map_err(|e| e.to_string())
}

/// Verifies `current_master` in constant time, deletes the vault file on disk, and locks the session.
pub fn erase_vault(current_master: String) -> Result<(), String> {
    let current_master = Zeroizing::new(current_master);
    session()
        .erase_vault(&current_master)
        .map_err(|e| e.to_string())
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
    Ok(list.into_iter().map(map_summary).collect())
}

pub fn generate_entry_passkey(
    entry_id: String,
    rp_id: String,
    username: String,
) -> Result<PasskeyItem, String> {
    let summary = session()
        .generate_passkey(parse_id(&entry_id)?, &rp_id, &username)
        .map_err(|e| e.to_string())?;
    Ok(PasskeyItem {
        rp_id: summary.rp_id,
        username: summary.username,
        credential_id: summary.credential_id,
        user_handle: summary.user_handle,
    })
}

pub fn remove_entry_passkey(entry_id: String) -> Result<(), String> {
    session()
        .remove_passkey(parse_id(&entry_id)?)
        .map_err(|e| e.to_string())
}

pub fn authenticate_entry_passkey(
    entry_id: String,
    platform: String,
    origin: String,
    user_verified: bool,
    android_package_name: Option<String>,
) -> Result<PasskeyAssertionItem, String> {
    let target_platform =
        vaultkeep_core::PasskeyPlatform::parse(&platform).map_err(|e| e.to_string())?;
    let resp = session()
        .authenticate_passkey(
            parse_id(&entry_id)?,
            target_platform,
            &origin,
            user_verified,
            android_package_name.as_deref(),
        )
        .map_err(|e| e.to_string())?;
    Ok(PasskeyAssertionItem {
        credential_id: resp.credential_id,
        rp_id: resp.rp_id,
        username: resp.username,
        user_handle: resp.user_handle,
        platform: resp.platform.as_str().to_owned(),
        authenticator_attachment: resp.authenticator_attachment,
        authenticator_data_b64url: resp.authenticator_data_b64url,
        client_data_json_b64url: resp.client_data_json_b64url,
        signature_b64url: resp.signature_b64url,
        flags: resp.flags as u32,
        user_verified: resp.user_verified,
        backup_eligible: resp.backup_eligible,
        backup_state: resp.backup_state,
        sign_count: resp.sign_count,
    })
}

pub fn signal_unknown_passkey(rp_id: String, credential_id: String) -> Result<bool, String> {
    session()
        .signal_unknown_credential(&rp_id, &credential_id)
        .map_err(|e| e.to_string())
}

pub fn change_master_password(current_master: String, new_master: String) -> Result<(), String> {
    let current_master = Zeroizing::new(current_master);
    let new_master = Zeroizing::new(new_master);
    session()
        .change_master_password(&current_master, &new_master)
        .map_err(|e| e.to_string())
}

/// Duplicates entry `id` inside the open vault without exposing decrypted secrets to Dart.
pub fn duplicate_entry(id: String) -> Result<String, String> {
    let new_id = session()
        .duplicate_entry(parse_id(&id)?)
        .map_err(|e| e.to_string())?;
    Ok(new_id.to_string())
}

/// Exports the open vault to `dest_path` (`"kdbx"` or `"csv"`) after verifying `current_master`.
pub fn export_vault(
    dest_path: String,
    current_master: String,
    format: String,
) -> Result<u32, String> {
    let current_master = Zeroizing::new(current_master);
    let count = session()
        .export_vault(&dest_path, &current_master, &format)
        .map_err(|e| e.to_string())?;
    Ok(count as u32)
}

/// Imports credentials from CSV text (`title,username,password,url,notes,category,email,otp`).
pub fn import_csv_entries(csv_content: String) -> Result<u32, String> {
    let csv_content = Zeroizing::new(csv_content);
    let count = session()
        .import_csv(&csv_content)
        .map_err(|e| e.to_string())?;
    Ok(count as u32)
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
            last_known_revision_date: None,
            category: None,
            tags: Vec::new(),
            is_favorite: false,
            is_archived: false,
            is_trashed: false,
            email: "kingshuk@example.com".into(),
            phone: "+1-555-0100".into(),
            security_question: "First pet?".into(),
            security_answer: Some("Fluffy".into()),
            sections: vec!["ADDITIONAL DETAILS".into()],
            custom_fields: vec![
                CustomFieldData {
                    name: "Department".into(),
                    value: "Platform".into(),
                    field_type: "text".into(),
                    sensitive: false,
                    section: String::new(),
                },
                CustomFieldData {
                    name: "Recovery PIN".into(),
                    value: "9942".into(),
                    field_type: "password".into(),
                    sensitive: true,
                    section: "ADDITIONAL DETAILS".into(),
                },
            ],
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
        let found = list_entries("git".into()).unwrap();
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].email, "kingshuk@example.com");
        assert!(found[0].passkey_supported);
        assert!(!found[0].has_passkey);
        assert!(found[0].has_totp);
        assert!(found[0].two_fa_supported);
        assert!(found[0].revision_date.is_some());
        assert_eq!(found[0].category, "Login");

        // Update Enpass metadata without touching password
        set_entry_metadata(
            id.clone(),
            "Finance".into(),
            vec!["work".into(), "cloud".into()],
            true,
            false,
            false,
        )
        .unwrap();

        let details = get_entry(id.clone()).unwrap();
        assert_eq!(details.notes, "n");
        assert_eq!(details.email, "kingshuk@example.com");
        assert_eq!(details.phone, "+1-555-0100");
        assert_eq!(details.security_question, "First pet?");
        assert!(details.has_security_answer);
        assert_eq!(details.sections, vec!["ADDITIONAL DETAILS".to_string()]);
        assert_eq!(details.custom_fields.len(), 2);
        assert_eq!(details.custom_fields[0].name, "Department");
        assert_eq!(details.custom_fields[0].value, "Platform");
        assert!(!details.custom_fields[0].sensitive);
        assert_eq!(details.custom_fields[1].name, "Recovery PIN");
        assert_eq!(details.custom_fields[1].value, ""); // omitted when sensitive!
        assert!(details.custom_fields[1].sensitive);
        assert_eq!(details.group_id, Some(gid));
        assert_eq!(details.group_name.as_deref(), Some("Engineering"));
        assert!(details.has_otp);
        assert!(details.passkey.is_none());
        assert!(details.passkey_supported);
        assert!(details.revision_date.is_some());
        assert_eq!(details.category, "Finance");
        assert_eq!(details.tags, vec!["work".to_string(), "cloud".to_string()]);
        assert!(details.is_favorite);
        assert_eq!(reveal_password(id.clone()).unwrap(), "pw-1");
        assert_eq!(
            reveal_security_answer(id.clone()).unwrap().as_deref(),
            Some("Fluffy")
        );
        assert_eq!(reveal_custom_field(id.clone(), 0).unwrap(), "Platform");
        assert_eq!(reveal_custom_field(id.clone(), 1).unwrap(), "9942");
        assert!(reveal_otp_uri(id.clone()).unwrap().is_some());

        // Vault info check
        let vinfo = get_vault_info().unwrap();
        assert_eq!(vinfo.entry_count, 1);
        assert!(vinfo.kdf_iterations > 0);
        assert!(vinfo.kdf_memory_mib > 0);

        // Generate & authenticate passkey on Windows and Android through the bridge API
        let pk = generate_entry_passkey(id.clone(), String::new(), String::new()).unwrap();
        assert_eq!(pk.rp_id, "github.com");
        assert_eq!(pk.username, "kingshuk");
        assert!(!pk.credential_id.is_empty());
        assert!(get_entry(id.clone()).unwrap().passkey.is_some());
        assert!(list_entries("git".into()).unwrap()[0].has_passkey);

        let win_assert = authenticate_entry_passkey(
            id.clone(),
            "windows".into(),
            "https://github.com".into(),
            true,
            None,
        )
        .unwrap();
        assert_eq!(win_assert.platform, "windows");
        assert_eq!(win_assert.flags, 0x1d);
        assert!(win_assert.user_verified);
        assert!(win_assert.backup_eligible);
        assert!(win_assert.backup_state);
        assert!(!win_assert.signature_b64url.is_empty());

        let android_assert = authenticate_entry_passkey(
            id.clone(),
            "android".into(),
            "https://github.com".into(),
            true,
            Some("com.github.android".into()),
        )
        .unwrap();
        assert_eq!(android_assert.platform, "android");
        assert_eq!(android_assert.flags, 0x1d);

        // Non-Windows/Android platform must be rejected for now
        assert!(authenticate_entry_passkey(
            id.clone(),
            "ios".into(),
            "https://github.com".into(),
            true,
            None,
        )
        .is_err());

        remove_entry_passkey(id.clone()).unwrap();
        assert!(get_entry(id.clone()).unwrap().passkey.is_none());

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

        let current_rev = get_entry(id.clone()).unwrap().revision_date;
        let mut stale = data("pw-stale");
        stale.last_known_revision_date = current_rev.map(|r| r - 10);
        assert!(save_entry(Some(id.clone()), stale).is_err());

        let mut fresh = data("pw-2");
        fresh.last_known_revision_date = current_rev;
        save_entry(Some(id.clone()), fresh).unwrap();
        assert_eq!(reveal_password(id.clone()).unwrap(), "pw-2");

        // Test backup, list, and restore through bridge API
        let bdir = dir.path().join("backups").to_string_lossy().into_owned();
        let bfile = create_vault_backup(bdir.clone(), 5).unwrap();
        assert!(std::path::Path::new(&bfile).exists());
        let backups = list_vault_backups(bdir).unwrap();
        assert_eq!(backups.len(), 1);

        // Rotate master password
        assert!(change_master_password("wrong-current".into(), "new-master".into()).is_err());
        let new_master = "new-horse-battery-staple".to_string();
        change_master_password(master.clone(), new_master.clone()).unwrap();

        lock_vault();
        assert!(!is_unlocked());
        assert_eq!(list_entries(String::new()).unwrap_err(), "vault is locked");
        assert!(unlock_vault(path.clone(), master.clone()).is_err());
        assert!(!is_unlocked());

        unlock_vault(path.clone(), new_master.clone()).unwrap();
        assert_eq!(reveal_password(id.clone()).unwrap(), "pw-2");
        delete_entry(id.clone()).unwrap();
        assert!(list_entries(String::new()).unwrap().is_empty());

        // Restore from backup (which was encrypted with the original master password)
        restore_vault_backup(bfile, master.clone()).unwrap();
        assert_eq!(list_entries(String::new()).unwrap().len(), 1);
        assert_eq!(reveal_password(id.clone()).unwrap(), "pw-2");

        // Test duplicate_entry, export_vault, and import_csv_entries through bridge API
        let dup_id = duplicate_entry(id).unwrap();
        assert_eq!(get_entry(dup_id.clone()).unwrap().title, "GitHub - Copy");
        assert_eq!(reveal_password(dup_id).unwrap(), "pw-2");

        let export_csv_path = dir.path().join("export.csv").to_string_lossy().into_owned();
        assert!(export_vault(export_csv_path.clone(), "wrong-master".into(), "csv".into()).is_err());
        let exp_count = export_vault(export_csv_path, new_master.clone(), "csv".into()).unwrap();
        assert_eq!(exp_count, 2);

        let imp_count = import_csv_entries(
            "title,username,password,url,notes,category,email\nProtonMail,pm_user,pm_pass_123,https://proton.me,note,Login,pm@proton.me\n".into(),
        )
        .unwrap();
        assert_eq!(imp_count, 1);
        assert_eq!(list_entries("ProtonMail".into()).unwrap().len(), 1);

        // Test erase_vault (rejects wrong master password, succeeds on right master password)
        assert!(erase_vault("wrong-master".into()).is_err());
        assert!(erase_vault(master).is_err());
        assert!(is_unlocked());
        erase_vault(new_master).unwrap();
        assert!(!is_unlocked());
        assert!(!std::path::Path::new(&path).exists());

        assert_eq!(
            get_entry("not-a-uuid".into()).unwrap_err(),
            "invalid entry id"
        );
        assert_eq!(generate_new_password(20, false).unwrap().len(), 20);
        let custom_pw = generate_custom_password(CustomPasswordPolicy {
            length: 16,
            uppercase: true,
            digits: true,
            symbols: true,
            pronounceable: false,
            allow_ambiguous: false,
            exact_mode: false,
            min_upper: 2,
            min_digits: 2,
            min_symbols: 2,
            exclude_chars: String::new(),
            include_chars: String::new(),
            separator: "-".into(),
        })
        .unwrap();
        assert_eq!(custom_pw.len(), 16);

        let pron_pw = generate_custom_password(CustomPasswordPolicy {
            length: 15,
            uppercase: true,
            digits: true,
            symbols: false,
            pronounceable: true,
            allow_ambiguous: false,
            exact_mode: false,
            min_upper: 0,
            min_digits: 0,
            min_symbols: 0,
            exclude_chars: String::new(),
            include_chars: String::new(),
            separator: ".".into(),
        })
        .unwrap();
        assert!(pron_pw.contains('.'));

        let eval = evaluate_password(custom_pw);
        assert!(eval.score >= 3);
        assert!(!eval.label.is_empty());

        // SEC-004 regression check: poisoning SESSION while unlocked fails closed (locks the vault)
        let poison_path = dir.path().join("poison.kdbx").to_str().unwrap().to_string();
        create_vault(poison_path, "poison-master-password".into()).unwrap();
        assert!(is_unlocked());
        let _ = std::panic::catch_unwind(|| {
            let _guard = SESSION.lock().unwrap();
            panic!("simulated panic while holding SESSION lock");
        });
        assert!(SESSION.is_poisoned());
        assert!(
            !is_unlocked(),
            "poisoned SESSION must fail closed and drop the open vault"
        );
        assert!(
            !SESSION.is_poisoned(),
            "poison flag must be cleared after fail-closed lock"
        );
    }
}
