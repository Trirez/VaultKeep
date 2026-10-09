use uuid::Uuid;
use vaultkeep_core::{EntryDetails, EntryInput, EntrySummary, Vault, VaultError};
use zeroize::Zeroizing;

/// Holds the single open vault. Dropping the vault zeroizes its master password.
pub(crate) struct Session {
    vault: Option<Vault>,
}

impl Session {
    pub(crate) const fn new() -> Self {
        Self { vault: None }
    }

    pub(crate) fn create(&mut self, path: &str, master: &str) -> Result<(), VaultError> {
        self.vault = None;
        self.vault = Some(Vault::create(path, master)?);
        Ok(())
    }

    pub(crate) fn unlock(&mut self, path: &str, master: &str) -> Result<(), VaultError> {
        self.vault = None;
        self.vault = Some(Vault::open(path, master)?);
        Ok(())
    }

    pub(crate) fn lock(&mut self) {
        self.vault = None;
    }

    pub(crate) fn is_unlocked(&self) -> bool {
        self.vault.is_some()
    }

    fn vault(&self) -> Result<&Vault, VaultError> {
        self.vault.as_ref().ok_or(VaultError::Locked)
    }

    fn vault_mut(&mut self) -> Result<&mut Vault, VaultError> {
        self.vault.as_mut().ok_or(VaultError::Locked)
    }

    pub(crate) fn search(&self, query: &str) -> Result<Vec<EntrySummary>, VaultError> {
        Ok(self.vault()?.search(query))
    }

    pub(crate) fn details(&self, id: Uuid) -> Result<EntryDetails, VaultError> {
        self.vault()?.details(id)
    }

    pub(crate) fn password(&self, id: Uuid) -> Result<Zeroizing<String>, VaultError> {
        self.vault()?.password(id)
    }

    /// Add (`id == None`) or update an entry, then persist atomically.
    pub(crate) fn save_entry(
        &mut self,
        id: Option<Uuid>,
        input: &EntryInput,
    ) -> Result<Uuid, VaultError> {
        let vault = self.vault_mut()?;
        let id = match id {
            Some(id) => {
                vault.update(id, input)?;
                id
            }
            None => vault.add(input),
        };
        vault.save()?;
        Ok(id)
    }

    pub(crate) fn delete(&mut self, id: Uuid) -> Result<(), VaultError> {
        let vault = self.vault_mut()?;
        vault.remove(id)?;
        vault.save()
    }

    pub(crate) fn list_groups(&self) -> Result<Vec<vaultkeep_core::GroupSummary>, VaultError> {
        Ok(self.vault()?.list_groups())
    }

    pub(crate) fn create_group(&mut self, name: &str) -> Result<Uuid, VaultError> {
        self.vault_mut()?.create_group(name)
    }

    pub(crate) fn totp(&self, id: Uuid) -> Result<Option<vaultkeep_core::TotpToken>, VaultError> {
        self.vault()?.totp(id)
    }

    pub(crate) fn add_attachment(
        &mut self,
        entry_id: Uuid,
        name: &str,
        data: &[u8],
    ) -> Result<(), VaultError> {
        self.vault_mut()?.add_attachment(entry_id, name, data)
    }

    pub(crate) fn get_attachment(&self, entry_id: Uuid, name: &str) -> Result<Vec<u8>, VaultError> {
        self.vault()?.get_attachment(entry_id, name)
    }

    pub(crate) fn remove_attachment(
        &mut self,
        entry_id: Uuid,
        name: &str,
    ) -> Result<(), VaultError> {
        self.vault_mut()?.remove_attachment(entry_id, name)
    }

    pub(crate) fn list_attachments(
        &self,
        entry_id: Uuid,
    ) -> Result<Vec<vaultkeep_core::AttachmentSummary>, VaultError> {
        self.vault()?.list_attachments(entry_id)
    }

    pub(crate) fn merge(
        &mut self,
        other_path: &str,
        other_master: &str,
    ) -> Result<usize, VaultError> {
        self.vault_mut()?.sync_with_file(other_path, other_master)
    }

    pub(crate) fn find_for_domain(
        &self,
        domain: &str,
    ) -> Result<Vec<vaultkeep_core::EntrySummary>, VaultError> {
        Ok(self.vault()?.find_for_domain(domain))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locked_session_refuses_everything() {
        let mut s = Session::new();
        assert!(!s.is_unlocked());
        assert!(matches!(s.search(""), Err(VaultError::Locked)));
        assert!(matches!(s.password(Uuid::nil()), Err(VaultError::Locked)));
        assert!(matches!(s.delete(Uuid::nil()), Err(VaultError::Locked)));
    }

    #[test]
    fn lock_drops_the_vault_and_failed_unlock_stays_locked() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("v.kdbx");
        let path = path.to_str().unwrap();

        let mut s = Session::new();
        s.create(path, "master-pass").unwrap();
        assert!(s.is_unlocked());

        s.lock();
        assert!(!s.is_unlocked());
        assert!(s.unlock(path, "wrong").is_err());
        assert!(!s.is_unlocked());
        s.unlock(path, "master-pass").unwrap();
        assert!(s.is_unlocked());
    }
}
