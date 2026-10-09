import 'dart:typed_data';

import 'backend.dart';
import 'src/rust/api/vault.dart' as rust;

class RustBackend implements VaultBackend {
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
    return [
      for (final e in items)
        VaultItem(
          id: e.id,
          title: e.title,
          username: e.username,
          url: e.url,
          groupName: e.groupName,
        ),
    ];
  }

  @override
  Future<VaultEntry> get(String id) async {
    final e = await rust.getEntry(id: id);
    return VaultEntry(
      id: e.id,
      title: e.title,
      username: e.username,
      url: e.url,
      notes: e.notes,
      groupId: e.groupId,
      groupName: e.groupName,
      otpUri: e.otpUri,
      attachments: [
        for (final a in e.attachments)
          VaultAttachment(name: a.name, size: a.size),
      ],
    );
  }

  @override
  Future<String> revealPassword(String id) => rust.revealPassword(id: id);

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
        ),
      );

  @override
  Future<void> delete(String id) => rust.deleteEntry(id: id);

  @override
  Future<String> generate({int length = 24, bool symbols = true}) =>
      rust.generateNewPassword(length: length, symbols: symbols);

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
    return [
      for (final e in items)
        VaultItem(
          id: e.id,
          title: e.title,
          username: e.username,
          url: e.url,
          groupName: e.groupName,
        ),
    ];
  }
}
