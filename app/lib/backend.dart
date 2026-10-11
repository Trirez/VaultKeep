/// Plain Dart models and the interface the UI depends on.
///
/// Nothing in this file imports generated Rust bindings, so the controller and
/// screens can be tested with a fake backend and no native library.
library;

import 'dart:typed_data';

/// Enpass 10 built-in item categories.
const List<String> kEnpassCategories = [
  'Login',
  'Credit Card',
  'Identity',
  'Note',
  'Password',
  'Finance',
  'License',
  'Travel',
  'Computer',
  'Miscellaneous',
];

class VaultGroup {
  const VaultGroup({
    required this.id,
    required this.name,
    required this.entryCount,
  });

  final String id;
  final String name;
  final int entryCount;
}

class VaultAttachment {
  const VaultAttachment({
    required this.name,
    required this.size,
  });

  final String name;
  final int size;
}

class VaultPasskey {
  const VaultPasskey({
    required this.rpId,
    required this.username,
    required this.credentialId,
    required this.userHandle,
  });

  final String rpId;
  final String username;
  final String credentialId;
  final String userHandle;
}

class VaultPasskeyAssertion {
  const VaultPasskeyAssertion({
    required this.credentialId,
    required this.rpId,
    required this.username,
    required this.userHandle,
    required this.platform,
    required this.authenticatorAttachment,
    required this.authenticatorDataB64url,
    required this.clientDataJsonB64url,
    required this.signatureB64url,
    required this.flags,
    required this.userVerified,
    required this.backupEligible,
    required this.backupState,
    required this.signCount,
  });

  final String credentialId;
  final String rpId;
  final String username;
  final String userHandle;
  final String platform;
  final String authenticatorAttachment;
  final String authenticatorDataB64url;
  final String clientDataJsonB64url;
  final String signatureB64url;
  final int flags;
  final bool userVerified;
  final bool backupEligible;
  final bool backupState;
  final int signCount;
}


class VaultTotp {
  const VaultTotp({
    required this.code,
    required this.secondsRemaining,
    required this.period,
  });

  final String code;
  final int secondsRemaining;
  final int period;
}

class PasswordGenConfig {
  const PasswordGenConfig({
    this.length = 24,
    this.uppercase = true,
    this.digits = true,
    this.symbols = true,
    this.pronounceable = false,
    this.allowAmbiguous = false,
    this.exactMode = false,
    this.minUpper = 1,
    this.minDigits = 1,
    this.minSymbols = 1,
    this.excludeChars = '',
    this.includeChars = '',
  });

  final int length;
  final bool uppercase;
  final bool digits;
  final bool symbols;
  final bool pronounceable;
  final bool allowAmbiguous;
  final bool exactMode;
  final int minUpper;
  final int minDigits;
  final int minSymbols;
  final String excludeChars;
  final String includeChars;
}

class VaultItem {
  const VaultItem({
    required this.id,
    required this.title,
    required this.username,
    required this.url,
    this.groupName,
    this.hasPasskey = false,
    this.passkeySupported = false,
    this.hasTotp = false,
    this.revisionDate,
    this.category = 'Login',
    this.tags = const [],
    this.isFavorite = false,
    this.isArchived = false,
    this.isTrashed = false,
    this.hasAttachment = false,
    this.twoFaSupported = false,
    this.passwordStrength = 'Strong',
    this.strengthScore = 80,
    this.isWeak = false,
    this.isIdentical = false,
    this.isCompromised = false,
    this.isBreached = false,
    this.isExpired = false,
  });

  final String id;
  final String title;
  final String username;
  final String url;
  final String? groupName;
  final bool hasPasskey;
  final bool passkeySupported;
  final bool hasTotp;
  final int? revisionDate;
  final String category;
  final List<String> tags;
  final bool isFavorite;
  final bool isArchived;
  final bool isTrashed;
  final bool hasAttachment;
  final bool twoFaSupported;
  final String passwordStrength;
  final int strengthScore;
  final bool isWeak;
  final bool isIdentical;
  final bool isCompromised;
  final bool isBreached;
  final bool isExpired;
}

class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.title,
    required this.username,
    required this.url,
    required this.notes,
    this.groupId,
    this.groupName,
    this.hasOtp = false,
    this.attachments = const [],
    this.passkey,
    this.passkeySupported = false,
    this.revisionDate,
    this.category = 'Login',
    this.tags = const [],
    this.isFavorite = false,
    this.isArchived = false,
    this.isTrashed = false,
    this.twoFaSupported = false,
    this.passwordStrength = 'Strong',
    this.strengthScore = 80,
    this.isWeak = false,
    this.isIdentical = false,
    this.isCompromised = false,
    this.isBreached = false,
    this.isExpired = false,
  });

  final String id;
  final String title;
  final String username;
  final String url;
  final String notes;
  final String? groupId;
  final String? groupName;
  final bool hasOtp;
  final List<VaultAttachment> attachments;
  final VaultPasskey? passkey;
  final bool passkeySupported;
  final int? revisionDate;
  final String category;
  final List<String> tags;
  final bool isFavorite;
  final bool isArchived;
  final bool isTrashed;
  final bool twoFaSupported;
  final String passwordStrength;
  final int strengthScore;
  final bool isWeak;
  final bool isIdentical;
  final bool isCompromised;
  final bool isBreached;
  final bool isExpired;
}

/// What the edit screen submits. Deliberately has no toString, so a stray log
/// line cannot print the password.
class EntryDraft {
  const EntryDraft({
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    this.groupId,
    this.otp,
    this.lastKnownRevisionDate,
    this.category,
    this.tags = const [],
    this.isFavorite = false,
    this.isArchived = false,
    this.isTrashed = false,
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final String? groupId;
  final String? otp;
  final int? lastKnownRevisionDate;
  final String? category;
  final List<String> tags;
  final bool isFavorite;
  final bool isArchived;
  final bool isTrashed;
}

abstract class VaultBackend {
  Future<void> create(String path, String master);
  Future<void> unlock(String path, String master);
  Future<void> lock();
  Future<List<VaultItem>> list(String query);
  Future<VaultEntry> get(String id);
  Future<String> revealPassword(String id);
  Future<String?> revealOtpUri(String id);

  /// Adds (`id == null`) or updates an entry and returns its id.
  Future<String> save(String? id, EntryDraft draft);
  Future<void> setEntryMetadata(
    String id, {
    required String category,
    required List<String> tags,
    required bool isFavorite,
    required bool isArchived,
    required bool isTrashed,
  });
  Future<void> delete(String id);
  Future<String> generate({int length = 24, bool symbols = true});
  Future<String> generateCustom(PasswordGenConfig config);
  Future<String> createBackup(String backupDir, {int maxBackups = 60});

  Future<List<VaultGroup>> listGroups();
  Future<String> createGroup(String name);
  Future<VaultTotp?> getTotp(String id);
  Future<void> addAttachment(String entryId, String name, Uint8List data);
  Future<Uint8List> getAttachment(String entryId, String name);
  Future<void> removeAttachment(String entryId, String name);
  Future<List<VaultAttachment>> listAttachments(String entryId);
  Future<int> mergeVault(String otherPath, String otherMaster);
  Future<List<VaultItem>> findEntriesForDomain(String domain);
  Future<VaultPasskey> generatePasskey(
    String entryId, {
    String rpId = '',
    String username = '',
  });
  Future<VaultPasskeyAssertion> authenticatePasskey(
    String entryId, {
    required String platform,
    String origin = '',
    bool userVerified = true,
    String? androidPackageName,
  });
  Future<void> removePasskey(String entryId);
  Future<void> changeMasterPassword(String currentMaster, String newMaster);
}

