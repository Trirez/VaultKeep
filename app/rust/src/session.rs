use uuid::Uuid;
use vaultkeep_core::{EntryDetails, EntryInput, EntrySummary, Vault, VaultError};
use zeroize::Zeroizing;

/// Holds the single open vault and its session-scoped WebAuthn challenge factory.
/// Dropping the vault zeroizes its master password.
pub(crate) struct Session {
    vault: Option<Vault>,
    challenge_factory: Option<vaultkeep_core::PasskeyChallengeFactory>,
}

impl Session {
    pub(crate) const fn new() -> Self {
        Self {
            vault: None,
            challenge_factory: None,
        }
    }

    pub(crate) fn create(&mut self, path: &str, master: &str) -> Result<(), VaultError> {
        self.lock();
        let v = Vault::create(path, master)?;
        let factory = vaultkeep_core::PasskeyChallengeFactory::new(
            vaultkeep_core::PasskeyTokenConfig::default(),
        )?;
        self.vault = Some(v);
        self.challenge_factory = Some(factory);
        Ok(())
    }

    pub(crate) fn unlock(&mut self, path: &str, master: &str) -> Result<(), VaultError> {
        self.lock();
        let v = Vault::open(path, master)?;
        let factory = vaultkeep_core::PasskeyChallengeFactory::new(
            vaultkeep_core::PasskeyTokenConfig::default(),
        )?;
        self.vault = Some(v);
        self.challenge_factory = Some(factory);
        Ok(())
    }

    pub(crate) fn lock(&mut self) {
        self.vault = None;
        self.challenge_factory = None;
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

    pub(crate) fn otp_uri(
        &self,
        id: Uuid,
    ) -> Result<Option<zeroize::Zeroizing<String>>, VaultError> {
        self.vault()?.otp_uri(id)
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
            None => vault.add(input)?,
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

    pub(crate) fn generate_passkey(
        &mut self,
        entry_id: Uuid,
        rp_id: &str,
        username: &str,
    ) -> Result<vaultkeep_core::PasskeySummary, VaultError> {
        self.vault_mut()?
            .generate_passkey(entry_id, rp_id, username)
    }

    pub(crate) fn remove_passkey(&mut self, entry_id: Uuid) -> Result<(), VaultError> {
        self.vault_mut()?.remove_passkey(entry_id)
    }

    pub(crate) fn authenticate_passkey(
        &self,
        entry_id: Uuid,
        platform: vaultkeep_core::PasskeyPlatform,
        origin: &str,
        user_verified: bool,
        android_package_name: Option<&str>,
    ) -> Result<vaultkeep_core::PasskeyAssertionResponse, VaultError> {
        let vault = self.vault()?;
        let details = vault.details(entry_id)?;
        let pk = details
            .passkey
            .ok_or(VaultError::Policy("entry does not have a bound passkey"))?;
        let effective_origin = if origin.trim().is_empty() {
            format!("https://{}", pk.rp_id)
        } else {
            origin.to_owned()
        };
        let factory = self.challenge_factory.as_ref().ok_or(VaultError::Locked)?;
        let now_unix = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let token = factory.mint_challenge(
            &pk.rp_id,
            vaultkeep_core::PasskeyCeremonyScope::Authentication,
            now_unix,
        )?;
        vault.authenticate_webauthn_passkey(
            entry_id,
            platform,
            &effective_origin,
            &token,
            factory,
            now_unix,
            vaultkeep_core::UserVerificationRequirement::Preferred,
            user_verified,
            &[],
            android_package_name,
        )
    }

    pub(crate) fn signal_unknown_credential(
        &mut self,
        rp_id: &str,
        credential_id: &str,
    ) -> Result<bool, VaultError> {
        self.vault_mut()?
            .signal_unknown_credential(rp_id, credential_id)
    }

    pub(crate) fn change_master_password(
        &mut self,
        current_master: &str,
        new_master: &str,
    ) -> Result<(), VaultError> {
        self.vault_mut()?
            .change_master_password(current_master, new_master)
    }

    pub(crate) fn set_metadata(
        &mut self,
        entry_id: Uuid,
        meta: &vaultkeep_core::EntryMetadata,
    ) -> Result<(), VaultError> {
        self.vault_mut()?.set_entry_metadata(entry_id, meta)
    }

    pub(crate) fn create_backup(
        &self,
        backup_dir: &str,
        max_backups: usize,
    ) -> Result<String, VaultError> {
        let p = self.vault()?.create_backup(backup_dir, max_backups)?;
        Ok(p.to_string_lossy().into_owned())
    }

    pub(crate) fn list_backups(&self, backup_dir: &str) -> Result<Vec<String>, VaultError> {
        let _ = self.vault()?;
        let list = Vault::list_backups(backup_dir)?;
        Ok(list
            .into_iter()
            .map(|p| p.to_string_lossy().into_owned())
            .collect())
    }

    pub(crate) fn restore_backup(
        &mut self,
        backup_path: &str,
        backup_master: &str,
    ) -> Result<(), VaultError> {
        self.vault_mut()?.restore_backup(backup_path, backup_master)
    }

    pub(crate) fn erase_vault(&mut self, current_master: &str) -> Result<(), VaultError> {
        self.vault()?.erase_vault_file(current_master)?;
        self.lock();
        Ok(())
    }

    pub(crate) fn security_answer(
        &self,
        id: Uuid,
    ) -> Result<Option<Zeroizing<String>>, VaultError> {
        self.vault()?.security_answer(id)
    }

    pub(crate) fn custom_field_value(
        &self,
        id: Uuid,
        index: usize,
    ) -> Result<Zeroizing<String>, VaultError> {
        self.vault()?.custom_field_value(id, index)
    }

    pub(crate) fn vault_info(&self) -> Result<vaultkeep_core::VaultInfo, VaultError> {
        Ok(self.vault()?.vault_info())
    }

    pub(crate) fn duplicate_entry(&mut self, id: Uuid) -> Result<Uuid, VaultError> {
        self.vault_mut()?.duplicate_entry(id)
    }

    pub(crate) fn export_vault(
        &self,
        dest_path: &str,
        current_master: &str,
        format: &str,
    ) -> Result<usize, VaultError> {
        self.vault()?
            .export_vault_file(dest_path, current_master, format)
    }

    pub(crate) fn import_csv(&mut self, csv_content: &str) -> Result<usize, VaultError> {
        self.vault_mut()?.import_csv(csv_content)
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
