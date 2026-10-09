use thiserror::Error;

#[derive(Debug, Error)]
pub enum VaultError {
    #[error("could not open vault (wrong password/keyfile, or corrupt file)")]
    Open(#[from] keepass::db::DatabaseOpenError),
    #[error("could not save vault")]
    Save(#[from] keepass::db::DatabaseSaveError),
    #[error("i/o error: {0}")]
    Io(#[from] std::io::Error),
    #[error("entry not found")]
    NotFound,
    #[error("vault is locked")]
    Locked,
    #[error("master password must not be empty")]
    EmptyMasterPassword,
    #[error("invalid password policy: {0}")]
    Policy(&'static str),
    #[error("totp error: {0}")]
    Totp(#[from] keepass::db::TOTPError),
    #[error("merge error: {0}")]
    Merge(#[from] keepass::db::merge::MergeError),
    #[error("attachment not found")]
    AttachmentNotFound,
    #[error("group not found")]
    GroupNotFound,
    #[error("vault file too large ({0} bytes, maximum allowed is {1} bytes)")]
    FileTooLarge(u64, u64),
    #[error("attachment too large ({0} bytes, maximum allowed is {1} bytes)")]
    AttachmentTooLarge(usize, usize),
    #[error("malformed vault envelope: {0}")]
    Malformed(&'static str),
    #[error("cannot merge unrelated vaults: root group UUID mismatch")]
    IncompatibleVaultRoots,
    #[error("cannot merge vault with itself")]
    SelfMerge,
}
