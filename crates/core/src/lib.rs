#![deny(unsafe_code)]
//! VaultKeep core: a thin, UI-free wrapper around KDBX4 vaults.
//!
//! Every frontend (desktop, Android, iOS) talks only to this crate, so all
//! cryptography and file-format handling stays in one audited place.
//! Vaults are standard KDBX files and open in KeePassXC.

mod error;
mod generator;
pub mod passkey;
mod vault;

pub use error::VaultError;
pub use generator::{
    evaluate_password_strength, generate_password, generate_password_advanced,
    AdvancedPasswordPolicy, PasswordPolicy,
};
pub use passkey::{
    PasskeyAssertionResponse, PasskeyCeremonyScope, PasskeyChallengeFactory, PasskeyChallengeToken,
    PasskeyPlatform, PasskeyRegistrationResponse, PasskeyTokenConfig, UserVerificationRequirement,
    COSE_ALG_ES256, MAX_ROR_UNIQUE_LABELS, VAULTKEEP_AAGUID,
};
pub use vault::{
    is_passkey_supported, is_two_fa_supported, AttachmentSummary, EntryDetails, EntryInput,
    EntryMetadata, EntrySummary, GroupSummary, KdfParams, PasskeySummary, TotpToken, Vault,
    MAX_ATTACHMENT_BYTES, MAX_VAULT_BYTES,
};
