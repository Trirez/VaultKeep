/// Plain Dart models and the interface the UI depends on.
///
/// Nothing in this file imports generated Rust bindings, so the controller and
/// screens can be tested with a fake backend and no native library.
library;

import 'dart:typed_data';

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

class VaultItem {
  const VaultItem({
    required this.id,
    required this.title,
    required this.username,
    required this.url,
    this.groupName,
  });

  final String id;
  final String title;
  final String username;
  final String url;
  final String? groupName;
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
    this.otpUri,
    this.attachments = const [],
  });

  final String id;
  final String title;
  final String username;
  final String url;
  final String notes;
  final String? groupId;
  final String? groupName;
  final String? otpUri;
  final List<VaultAttachment> attachments;
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
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final String? groupId;
  final String? otp;
}

abstract class VaultBackend {
  Future<void> create(String path, String master);
  Future<void> unlock(String path, String master);
  Future<void> lock();
  Future<List<VaultItem>> list(String query);
  Future<VaultEntry> get(String id);
  Future<String> revealPassword(String id);

  /// Adds (`id == null`) or updates an entry and returns its id.
  Future<String> save(String? id, EntryDraft draft);
  Future<void> delete(String id);
  Future<String> generate({int length = 24, bool symbols = true});

  Future<List<VaultGroup>> listGroups();
  Future<String> createGroup(String name);
  Future<VaultTotp?> getTotp(String id);
  Future<void> addAttachment(String entryId, String name, Uint8List data);
  Future<Uint8List> getAttachment(String entryId, String name);
  Future<void> removeAttachment(String entryId, String name);
  Future<List<VaultAttachment>> listAttachments(String entryId);
  Future<int> mergeVault(String otherPath, String otherMaster);
  Future<List<VaultItem>> findEntriesForDomain(String domain);
}
