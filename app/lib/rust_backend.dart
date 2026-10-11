import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'backend.dart';
import 'src/rust/api/vault.dart' as rust;

class RustBackend implements VaultBackend {
  static VaultItem _mapItem(rust.EntryItem e) => VaultItem(
        id: e.id,
        title: e.title,
        username: e.username,
        url: e.url,
        groupName: e.groupName,
        hasPasskey: e.hasPasskey,
        passkeySupported: e.passkeySupported,
        hasTotp: e.hasTotp,
        revisionDate: e.revisionDate?.toInt(),
        category: e.category,
        tags: List.unmodifiable(e.tags),
        isFavorite: e.isFavorite,
        isArchived: e.isArchived,
        isTrashed: e.isTrashed,
        hasAttachment: e.hasAttachment,
        twoFaSupported: e.twoFaSupported,
        passwordStrength: e.passwordStrength,
        strengthScore: e.strengthScore,
        isWeak: e.isWeak,
        isIdentical: e.isIdentical,
        isCompromised: e.isCompromised,
        isBreached: e.isBreached,
        isExpired: e.isExpired,
        email: e.email,
      );

  @override
  Future<void> create(String path, String master) =>
      rust.createVault(path: path, master: master);

  @override
  Future<void> unlock(String path, String master) =>
      rust.unlockVault(path: path, master: master);

  @override
  Future<void> lock() async => rust.lockVault();

  @override
  Future<List<VaultItem>> list(String query) async {
    final items = await rust.listEntries(query: query);
    return [for (final e in items) _mapItem(e)];
  }

  @override
  Future<VaultEntry> get(String id) async {
    final e = await rust.getEntry(id: id);
    final pk = e.passkey;
    return VaultEntry(
      id: e.id,
      title: e.title,
      username: e.username,
      url: e.url,
      notes: e.notes,
      groupId: e.groupId,
      groupName: e.groupName,
      hasOtp: e.hasOtp,
      attachments: [
        for (final a in e.attachments)
          VaultAttachment(name: a.name, size: a.size),
      ],
      passkey: pk == null
          ? null
          : VaultPasskey(
              rpId: pk.rpId,
              username: pk.username,
              credentialId: pk.credentialId,
              userHandle: pk.userHandle,
            ),
      passkeySupported: e.passkeySupported,
      revisionDate: e.revisionDate?.toInt(),
      category: e.category,
      tags: List.unmodifiable(e.tags),
      isFavorite: e.isFavorite,
      isArchived: e.isArchived,
      isTrashed: e.isTrashed,
      twoFaSupported: e.twoFaSupported,
      passwordStrength: e.passwordStrength,
      strengthScore: e.strengthScore,
      isWeak: e.isWeak,
      isIdentical: e.isIdentical,
      isCompromised: e.isCompromised,
      isBreached: e.isBreached,
      isExpired: e.isExpired,
      email: e.email,
      phone: e.phone,
      securityQuestion: e.securityQuestion,
      hasSecurityAnswer: e.hasSecurityAnswer,
      sections: List.unmodifiable(e.sections),
      customFields: [
        for (final cf in e.customFields)
          VaultCustomField(
            name: cf.name,
            value: cf.value,
            fieldType: cf.fieldType,
            sensitive: cf.sensitive,
            section: cf.section,
          ),
      ],
    );
  }

  @override
  Future<String> revealPassword(String id) => rust.revealPassword(id: id);

  @override
  Future<String?> revealOtpUri(String id) => rust.revealOtpUri(id: id);

  @override
  Future<String?> revealSecurityAnswer(String id) =>
      rust.revealSecurityAnswer(id: id);

  @override
  Future<String> revealCustomField(String id, int index) =>
      rust.revealCustomField(id: id, index: index);

  @override
  Future<String> save(String? id, EntryDraft draft) => rust.saveEntry(
        id: id,
        data: rust.EntryData(
          title: draft.title,
          username: draft.username,
          password: draft.password,
          url: draft.url,
          notes: draft.notes,
          groupId: draft.groupId,
          otp: draft.otp,
          lastKnownRevisionDate: draft.lastKnownRevisionDate == null
              ? null
              : PlatformInt64Util.from(draft.lastKnownRevisionDate!),
          category: draft.category,
          tags: draft.tags,
          isFavorite: draft.isFavorite,
          isArchived: draft.isArchived,
          isTrashed: draft.isTrashed,
          email: draft.email,
          phone: draft.phone,
          securityQuestion: draft.securityQuestion,
          securityAnswer: draft.securityAnswer,
          sections: draft.sections,
          customFields: [
            for (final cf in draft.customFields)
              rust.CustomFieldData(
                name: cf.name,
                value: cf.value,
                fieldType: cf.fieldType,
                sensitive: cf.sensitive,
                section: cf.section,
              ),
          ],
        ),
      );

  @override
  Future<void> setEntryMetadata(
    String id, {
    required String category,
    required List<String> tags,
    required bool isFavorite,
    required bool isArchived,
    required bool isTrashed,
  }) =>
      rust.setEntryMetadata(
        id: id,
        category: category,
        tags: tags,
        isFavorite: isFavorite,
        isArchived: isArchived,
        isTrashed: isTrashed,
      );

  @override
  Future<void> delete(String id) => rust.deleteEntry(id: id);

  @override
  Future<String> generate({int length = 24, bool symbols = true}) =>
      rust.generateNewPassword(length: length, symbols: symbols);

  @override
  Future<String> generateCustom(PasswordGenConfig config) =>
      rust.generateCustomPassword(
        policy: rust.CustomPasswordPolicy(
          length: config.length,
          uppercase: config.uppercase,
          digits: config.digits,
          symbols: config.symbols,
          pronounceable: config.pronounceable,
          allowAmbiguous: config.allowAmbiguous,
          exactMode: config.exactMode,
          minUpper: config.minUpper,
          minDigits: config.minDigits,
          minSymbols: config.minSymbols,
          excludeChars: config.excludeChars,
          includeChars: config.includeChars,
          separator: config.separator,
        ),
      );

  @override
  Future<PasswordEvaluation> evaluatePassword(String password) async {
    final res = await rust.evaluatePassword(password: password);
    return PasswordEvaluation(
      score: res.score,
      label: res.label,
      isCompromised: res.isCompromised,
    );
  }

  @override
  Future<VaultInfo> getVaultInfo() async {
    final info = await rust.getVaultInfo();
    return VaultInfo(
      path: info.path,
      entryCount: info.entryCount,
      groupCount: info.groupCount,
      kdfIterations: info.kdfIterations,
      kdfMemoryMib: info.kdfMemoryMib,
      kdfParallelism: info.kdfParallelism,
    );
  }

  @override
  Future<String> createBackup(String backupDir, {int maxBackups = 60}) =>
      rust.createVaultBackup(backupDir: backupDir, maxBackups: maxBackups);

  @override
  Future<List<String>> listBackups(String backupDir) =>
      rust.listVaultBackups(backupDir: backupDir);

  @override
  Future<void> restoreBackup(String backupPath, String backupMaster) =>
      rust.restoreVaultBackup(
        backupPath: backupPath,
        backupMaster: backupMaster,
      );

  @override
  Future<void> eraseVault(String currentMaster) =>
      rust.eraseVault(currentMaster: currentMaster);

  @override
  Future<List<VaultGroup>> listGroups() async {
    final list = await rust.listGroups();
    return [
      for (final g in list)
        VaultGroup(
          id: g.id,
          name: g.name,
          entryCount: g.entryCount,
        ),
    ];
  }

  @override
  Future<String> createGroup(String name) => rust.createGroup(name: name);

  @override
  Future<VaultTotp?> getTotp(String id) async {
    final t = await rust.getTotp(id: id);
    if (t == null) return null;
    return VaultTotp(
      code: t.code,
      secondsRemaining: t.secondsRemaining,
      period: t.period,
    );
  }

  @override
  Future<void> addAttachment(String entryId, String name, Uint8List data) =>
      rust.addAttachment(entryId: entryId, name: name, data: data);

  @override
  Future<Uint8List> getAttachment(String entryId, String name) =>
      rust.getAttachment(entryId: entryId, name: name);

  @override
  Future<void> removeAttachment(String entryId, String name) =>
      rust.removeAttachment(entryId: entryId, name: name);

  @override
  Future<List<VaultAttachment>> listAttachments(String entryId) async {
    final list = await rust.listAttachments(entryId: entryId);
    return [
      for (final a in list) VaultAttachment(name: a.name, size: a.size),
    ];
  }

  @override
  Future<int> mergeVault(String otherPath, String otherMaster) =>
      rust.mergeVault(otherPath: otherPath, otherMaster: otherMaster);

  @override
  Future<List<VaultItem>> findEntriesForDomain(String domain) async {
    final items = await rust.findEntriesForDomain(domain: domain);
    return [for (final e in items) _mapItem(e)];
  }

  @override
  Future<VaultPasskey> generatePasskey(
    String entryId, {
    String rpId = '',
    String username = '',
  }) async {
    final pk = await rust.generateEntryPasskey(
      entryId: entryId,
      rpId: rpId,
      username: username,
    );
    return VaultPasskey(
      rpId: pk.rpId,
      username: pk.username,
      credentialId: pk.credentialId,
      userHandle: pk.userHandle,
    );
  }

  @override
  Future<VaultPasskeyAssertion> authenticatePasskey(
    String entryId, {
    required String platform,
    String origin = '',
    bool userVerified = true,
    String? androidPackageName,
  }) async {
    final resp = await rust.authenticateEntryPasskey(
      entryId: entryId,
      platform: platform,
      origin: origin,
      userVerified: userVerified,
      androidPackageName: androidPackageName,
    );
    return VaultPasskeyAssertion(
      credentialId: resp.credentialId,
      rpId: resp.rpId,
      username: resp.username,
      userHandle: resp.userHandle,
      platform: resp.platform,
      authenticatorAttachment: resp.authenticatorAttachment,
      authenticatorDataB64url: resp.authenticatorDataB64Url,
      clientDataJsonB64url: resp.clientDataJsonB64Url,
      signatureB64url: resp.signatureB64Url,
      flags: resp.flags,
      userVerified: resp.userVerified,
      backupEligible: resp.backupEligible,
      backupState: resp.backupState,
      signCount: resp.signCount,
    );
  }

  @override
  Future<void> removePasskey(String entryId) =>
      rust.removeEntryPasskey(entryId: entryId);

  @override
  Future<void> changeMasterPassword(
    String currentMaster,
    String newMaster,
  ) =>
      rust.changeMasterPassword(
        currentMaster: currentMaster,
        newMaster: newMaster,
      );

  @override
  Future<String> duplicateEntry(String id) => rust.duplicateEntry(id: id);

  @override
  Future<int> exportVault(
    String destPath,
    String currentMaster, {
    String format = 'kdbx',
  }) =>
      rust.exportVault(
        destPath: destPath,
        currentMaster: currentMaster,
        format: format,
      );

  @override
  Future<int> importCsv(String csvContent) =>
      rust.importCsvEntries(csvContent: csvContent);
}

