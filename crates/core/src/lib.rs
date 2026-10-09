//! VaultKeep core: a thin, UI-free wrapper around KDBX4 vaults.
//!
//! Every frontend (desktop, Android, iOS) talks only to this crate, so all
//! cryptography and file-format handling stays in one audited place.
//! Vaults are standard KDBX files and open in KeePassXC.

mod error;
mod generator;
mod vault;

pub use error::VaultError;
pub use generator::{generate_password, PasswordPolicy};
pub use vault::{
    AttachmentSummary, EntryDetails, EntryInput, EntrySummary, GroupSummary, TotpToken, Vault,
    MAX_ATTACHMENT_BYTES, MAX_VAULT_BYTES,
};
