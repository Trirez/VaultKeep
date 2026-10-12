import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkeep/backend.dart';
import 'package:vaultkeep/clipboard_guard.dart';
import 'package:vaultkeep/theme.dart';
import 'package:vaultkeep/vault_controller.dart';

const _master = 'correct-horse-battery';

EntryDraft _draft(String title, {String password = 'pw', String? groupId, String? otp}) => EntryDraft(
      title: title,
      username: 'user',
      password: password,
      url: 'https://$title.example',
      notes: '',
      groupId: groupId,
      otp: otp,
    );

/// In-memory stand-in for the Rust backend.
class FakeBackend implements VaultBackend {
  final _store = <String, EntryDraft>{};
  final _revisions = <String, int>{};
  final _groups = <VaultGroup>[
    const VaultGroup(id: 'root', name: 'Root', entryCount: 0),
  ];
  final _attachments = <String, Map<String, Uint8List>>{};
  final _passkeys = <String, VaultPasskey>{};
  final _backups = <String, Map<String, EntryDraft>>{};
  int _next = 0;
  int _nextGroup = 1;
  int _clock = 1700000000;
  bool unlocked = false;
  String activePath = 'v.kdbx';
  String activeMaster = _master;
  Duration? listDelay;

  void _check() {
    if (!unlocked) throw 'vault is locked';
  }

  static bool _isSupported(String title, String url, bool hasPasskey) {
    if (hasPasskey) return false;
    final t = title.toLowerCase();
    final u = url.toLowerCase();
    for (final p in ['google', 'github', 'cloudflare', 'microsoft', 'apple']) {
      if (t.contains(p) || u.contains(p)) return true;
    }
    return false;
  }

  @override
  Future<void> create(String path, String master) async {
    activePath = path;
    activeMaster = master;
    unlocked = true;
  }

  @override
  Future<void> unlock(String path, String master) async {
    if (master != activeMaster) {
      throw 'could not open vault (wrong password/keyfile, or corrupt file)';
    }
    activePath = path;
    unlocked = true;
  }

  @override
  Future<void> lock() async {
    unlocked = false;
  }

  @override
  Future<void> changeMasterPassword(
    String currentMaster,
    String newMaster,
  ) async {
    _check();
    if (currentMaster != activeMaster) {
      throw 'current master password does not match the unlocked vault';
    }
    if (newMaster.isEmpty) {
      throw 'master password cannot be empty';
    }
    activeMaster = newMaster;
    _clock += 10;
    for (final key in _revisions.keys.toList()) {
      _revisions[key] = _clock;
    }
  }

  @override
  Future<List<VaultItem>> list(String query) async {
    if (listDelay != null) {
      await Future<void>.delayed(listDelay!);
    }
    _check();
    final q = query.toLowerCase();
    final pwCounts = <String, int>{};
    for (final e in _store.values) {
      if (e.password.isNotEmpty) {
        pwCounts[e.password] = (pwCounts[e.password] ?? 0) + 1;
      }
    }
    return [
      for (final e in _store.entries)
        if (q.isEmpty ||
            e.value.title.toLowerCase().contains(q) ||
            e.value.username.toLowerCase().contains(q) ||
            e.value.email.toLowerCase().contains(q) ||
            e.value.phone.toLowerCase().contains(q) ||
            e.value.tags.any((t) => t.toLowerCase().contains(q)))
          VaultItem(
            id: e.key,
            title: e.value.title,
            username: e.value.username,
            url: e.value.url,
            groupName: e.value.groupId,
            hasPasskey: _passkeys.containsKey(e.key),
            passkeySupported: _isSupported(
              e.value.title,
              e.value.url,
              _passkeys.containsKey(e.key),
            ),
            hasTotp: e.value.otp != null && e.value.otp!.isNotEmpty,
            revisionDate: _revisions[e.key],
            category: e.value.category ?? 'Login',
            tags: e.value.tags,
            isFavorite: e.value.isFavorite,
            isArchived: e.value.isArchived,
            isTrashed: e.value.isTrashed,
            hasAttachment: (_attachments[e.key]?.isNotEmpty ?? false),
            twoFaSupported: _isSupported(e.value.title, e.value.url, false),
            passwordStrength:
                e.value.password.length >= 12 ? 'Excellent' : 'Weak',
            strengthScore: e.value.password.length >= 12 ? 95 : 35,
            isWeak: e.value.password.length < 8,
            isIdentical: (pwCounts[e.value.password] ?? 0) > 1,
            isBreached: e.value.password == 'password123',
            email: e.value.email,
          ),
    ];
  }

  @override
  Future<VaultEntry> get(String id) async {
    _check();
    final d = _store[id]!;
    final atts = [
      for (final a in (_attachments[id] ?? {}).entries)
        VaultAttachment(name: a.key, size: a.value.length),
    ];
    final pk = _passkeys[id];
    return VaultEntry(
      id: id,
      title: d.title,
      username: d.username,
      url: d.url,
      notes: d.notes,
      groupId: d.groupId,
      hasOtp: d.otp != null && d.otp!.isNotEmpty,
      attachments: atts,
      passkey: pk,
      passkeySupported: _isSupported(d.title, d.url, pk != null),
      revisionDate: _revisions[id],
      category: d.category ?? 'Login',
      tags: d.tags,
      isFavorite: d.isFavorite,
      isArchived: d.isArchived,
      isTrashed: d.isTrashed,
      twoFaSupported: _isSupported(d.title, d.url, false),
      passwordStrength: d.password.length >= 12 ? 'Excellent' : 'Weak',
      strengthScore: d.password.length >= 12 ? 95 : 35,
      isWeak: d.password.length < 8,
      isBreached: d.password == 'password123',
      email: d.email,
      phone: d.phone,
      securityQuestion: d.securityQuestion,
      hasSecurityAnswer:
          d.securityAnswer != null && d.securityAnswer!.isNotEmpty,
      sections: d.sections,
      customFields: [
        for (final cf in d.customFields)
          VaultCustomField(
            name: cf.name,
            value: cf.sensitive ? '' : cf.value,
            fieldType: cf.fieldType,
            sensitive: cf.sensitive,
            section: cf.section,
          ),
      ],
    );
  }

  @override
  Future<String> revealPassword(String id) async {
    _check();
    return _store[id]!.password;
  }

  @override
  Future<String?> revealOtpUri(String id) async {
    _check();
    return _store[id]!.otp;
  }

  @override
  Future<String?> revealSecurityAnswer(String id) async {
    _check();
    final ans = _store[id]?.securityAnswer;
    return (ans == null || ans.isEmpty) ? null : ans;
  }

  @override
  Future<String> revealCustomField(String id, int index) async {
    _check();
    final fields = _store[id]!.customFields;
    if (index < 0 || index >= fields.length) {
      throw 'custom field index out of range';
    }
    return fields[index].value;
  }

  @override
  Future<String> save(String? id, EntryDraft draft) async {
    _check();
    final key = id ?? 'id${_next++}';
    if (id != null && draft.lastKnownRevisionDate != null) {
      final currentRev = _revisions[id];
      if (currentRev != null &&
          draft.lastKnownRevisionDate! + 1 < currentRev) {
        throw 'stale revision: entry was modified since last loaded';
      }
    }
    final prev = _store[key];
    final effectiveOtp = draft.otp ?? prev?.otp;
    final effectiveSecAns = draft.securityAnswer ?? prev?.securityAnswer;
    _store[key] = EntryDraft(
      title: draft.title,
      username: draft.username,
      password: draft.password,
      url: draft.url,
      notes: draft.notes,
      groupId: draft.groupId,
      otp: effectiveOtp,
      lastKnownRevisionDate: draft.lastKnownRevisionDate,
      category: draft.category,
      tags: draft.tags,
      isFavorite: draft.isFavorite,
      isArchived: draft.isArchived,
      isTrashed: draft.isTrashed,
      email: draft.email,
      phone: draft.phone,
      securityQuestion: draft.securityQuestion,
      securityAnswer: effectiveSecAns,
      sections: draft.sections,
      customFields: draft.customFields,
    );
    _revisions[key] = ++_clock;
    return key;
  }

  @override
  Future<void> setEntryMetadata(
    String id, {
    required String category,
    required List<String> tags,
    required bool isFavorite,
    required bool isArchived,
    required bool isTrashed,
  }) async {
    _check();
    final old = _store[id]!;
    _store[id] = EntryDraft(
      title: old.title,
      username: old.username,
      password: old.password,
      url: old.url,
      notes: old.notes,
      groupId: old.groupId,
      otp: old.otp,
      category: category,
      tags: tags,
      isFavorite: isFavorite,
      isArchived: isArchived,
      isTrashed: isTrashed,
      email: old.email,
      phone: old.phone,
      securityQuestion: old.securityQuestion,
      securityAnswer: old.securityAnswer,
      sections: old.sections,
      customFields: old.customFields,
    );
    _revisions[id] = ++_clock;
  }

  @override
  Future<void> delete(String id) async {
    _check();
    _store.remove(id);
    _revisions.remove(id);
    _attachments.remove(id);
    _passkeys.remove(id);
  }

  @override
  Future<String> generate({int length = 24, bool symbols = true}) async =>
      'x' * length;

  @override
  Future<String> generateCustom(PasswordGenConfig config) async {
    if (config.pronounceable && config.separator.isNotEmpty) {
      final base = 'kora${config.separator}vela${config.separator}99';
      if (base.length >= config.length) {
        return base.substring(0, config.length);
      }
      return base + ('a' * (config.length - base.length));
    }
    return 'A9!${'x' * (config.length > 3 ? config.length - 3 : 0)}';
  }

  @override
  Future<PasswordEvaluation> evaluatePassword(String password) async {
    final isComp = password == 'password123' || password == '123456';
    final score = isComp ? 10 : (password.length >= 16 ? 92 : 65);
    final label = isComp
        ? 'Weak'
        : (password.length >= 16 ? 'Excellent' : 'Good');
    return PasswordEvaluation(
      score: score,
      label: label,
      isCompromised: isComp,
    );
  }

  @override
  Future<VaultInfo> getVaultInfo() async {
    _check();
    return VaultInfo(
      path: activePath,
      entryCount: _store.length,
      groupCount: _groups.length,
      kdfIterations: 6,
      kdfMemoryMib: 32,
      kdfParallelism: 4,
    );
  }

  @override
  Future<String> createBackup(String backupDir, {int maxBackups = 60}) async {
    _check();
    final bpath = '$backupDir/backup_${++_clock}.kdbx';
    _backups[bpath] = Map.of(_store);
    return bpath;
  }

  @override
  Future<List<String>> listBackups(String backupDir) async {
    _check();
    final keys = _backups.keys
        .where((k) => k.startsWith(backupDir))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return keys;
  }

  @override
  Future<void> restoreBackup(String backupPath, String backupMaster) async {
    _check();
    if (backupMaster.isNotEmpty && backupMaster != activeMaster) {
      throw 'could not open backup (wrong password)';
    }
    final snap = _backups[backupPath];
    if (snap == null) throw 'backup file not found';
    _store
      ..clear()
      ..addAll(snap);
  }

  @override
  Future<void> eraseVault(String currentMaster) async {
    _check();
    if (currentMaster != activeMaster) {
      throw 'current master password is incorrect';
    }
    _store.clear();
    _revisions.clear();
    _attachments.clear();
    _passkeys.clear();
    unlocked = false;
  }

  @override
  Future<List<VaultGroup>> listGroups() async {
    if (listDelay != null) {
      await Future<void>.delayed(listDelay!);
    }
    _check();
    return List.unmodifiable(_groups);
  }


  @override
  Future<String> createGroup(String name) async {
    _check();
    final id = 'grp_${_nextGroup++}';
    _groups.add(VaultGroup(id: id, name: name, entryCount: 0));
    return id;
  }

  @override
  Future<VaultTotp?> getTotp(String id) async {
    _check();
    final d = _store[id];
    if (d?.otp == null || d!.otp!.isEmpty) return null;
    return const VaultTotp(code: '123456', secondsRemaining: 25, period: 30);
  }

  @override
  Future<void> addAttachment(String entryId, String name, Uint8List data) async {
    _check();
    _attachments.putIfAbsent(entryId, () => {})[name] = data;
    _revisions[entryId] = ++_clock;
  }

  @override
  Future<Uint8List> getAttachment(String entryId, String name) async {
    _check();
    final map = _attachments[entryId];
    if (map == null || !map.containsKey(name)) throw 'attachment not found';
    return map[name]!;
  }

  @override
  Future<void> removeAttachment(String entryId, String name) async {
    _check();
    _attachments[entryId]?.remove(name);
    _revisions[entryId] = ++_clock;
  }

  @override
  Future<List<VaultAttachment>> listAttachments(String entryId) async {
    _check();
    final map = _attachments[entryId] ?? {};
    return [
      for (final e in map.entries)
        VaultAttachment(name: e.key, size: e.value.length),
    ];
  }

  @override
  Future<int> mergeVault(String otherPath, String otherMaster) async {
    _check();
    return 1;
  }

  @override
  Future<List<VaultItem>> findEntriesForDomain(String domain) async {
    _check();
    final q = domain.toLowerCase();
    return [
      for (final e in _store.entries)
        if (e.value.url.toLowerCase().contains(q) ||
            e.value.title.toLowerCase().contains(q))
          VaultItem(
            id: e.key,
            title: e.value.title,
            username: e.value.username,
            url: e.value.url,
            groupName: e.value.groupId,
            hasPasskey: _passkeys.containsKey(e.key),
            passkeySupported: _isSupported(
              e.value.title,
              e.value.url,
              _passkeys.containsKey(e.key),
            ),
            hasTotp: e.value.otp != null && e.value.otp!.isNotEmpty,
          ),
    ];
  }

  @override
  Future<VaultPasskey> generatePasskey(
    String entryId, {
    String rpId = '',
    String username = '',
  }) async {
    _check();
    final d = _store[entryId]!;
    final pk = VaultPasskey(
      rpId: rpId.isEmpty ? d.url : rpId,
      username: username.isEmpty ? d.username : username,
      credentialId: 'cred_$entryId',
      userHandle: 'uh_$entryId',
    );
    _passkeys[entryId] = pk;
    _revisions[entryId] = ++_clock;
    return pk;
  }

  @override
  Future<VaultPasskeyAssertion> authenticatePasskey(
    String entryId, {
    required String platform,
    String origin = '',
    bool userVerified = true,
    String? androidPackageName,
  }) async {
    _check();
    final normPlatform = platform.trim().toLowerCase();
    if (normPlatform != 'windows' && normPlatform != 'android') {
      throw StateError(
        'passkeys are currently enabled only for Windows and Android targets',
      );
    }
    final pk = _passkeys[entryId];
    if (pk == null) {
      throw StateError('entry does not have a bound passkey');
    }
    final flags = 0x01 | (userVerified ? 0x04 : 0) | 0x08 | 0x10;
    return VaultPasskeyAssertion(
      credentialId: pk.credentialId,
      rpId: pk.rpId,
      username: pk.username,
      userHandle: pk.userHandle,
      platform: normPlatform,
      authenticatorAttachment: 'platform',
      authenticatorDataB64url: 'authdata_${pk.credentialId}',
      clientDataJsonB64url: 'clientdata_${pk.rpId}',
      signatureB64url: 'sig_es256_${pk.credentialId}',
      flags: flags,
      userVerified: userVerified,
      backupEligible: true,
      backupState: true,
      signCount: 0,
    );
  }

  @override
  Future<void> removePasskey(String entryId) async {
    _check();
    _passkeys.remove(entryId);
    _revisions[entryId] = ++_clock;
  }

  @override
  Future<String> duplicateEntry(String id) async {
    _check();
    final d = _store[id];
    if (d == null) throw 'entry not found';
    final copyDraft = EntryDraft(
      title: d.title.isEmpty ? 'Untitled (Copy)' : '${d.title} (Copy)',
      username: d.username,
      password: d.password,
      url: d.url,
      notes: d.notes,
      groupId: d.groupId,
      otp: d.otp,
      category: d.category,
      tags: d.tags,
      isFavorite: d.isFavorite,
      isArchived: false,
      isTrashed: false,
      email: d.email,
      phone: d.phone,
      securityQuestion: d.securityQuestion,
      securityAnswer: d.securityAnswer,
      sections: d.sections,
      customFields: d.customFields,
    );
    final newId = await save(null, copyDraft);
    if (_attachments[id] != null) {
      _attachments[newId] = Map.of(_attachments[id]!);
    }
    return newId;
  }

  @override
  Future<int> exportVault(
    String destPath,
    String currentMaster, {
    String format = 'kdbx',
  }) async {
    _check();
    if (currentMaster != activeMaster) {
      throw 'current master password is incorrect';
    }
    if (destPath == activePath) {
      throw 'cannot export over the live vault path';
    }
    return _store.values.where((e) => !e.isTrashed).length;
  }

  @override
  Future<int> importCsv(String csvContent) async {
    _check();
    var count = 0;
    final lines = csvContent.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = line.split(',');
      if (i == 0 && parts.first.trim().toLowerCase() == 'title') continue;
      final title = parts.isNotEmpty ? parts[0].trim() : 'Imported';
      final username = parts.length > 1 ? parts[1].trim() : '';
      final password = parts.length > 2 ? parts[2].trim() : '';
      final url = parts.length > 3 ? parts[3].trim() : '';
      final notes = parts.length > 4 ? parts[4].trim() : '';
      final category =
          parts.length > 5 && parts[5].trim().isNotEmpty ? parts[5].trim() : 'Login';
      final email = parts.length > 6 ? parts[6].trim() : '';
      await save(
        null,
        EntryDraft(
          title: title.isEmpty ? 'Imported Item' : title,
          username: username,
          password: password,
          url: url,
          notes: notes,
          category: category,
          email: email,
        ),
      );
      count++;
    }
    return count;
  }
}


void main() {
  test('unlock succeeds and loads the list', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await backend.unlock('v.kdbx', _master);
    await backend.save(null, _draft('GitHub'));
    await backend.lock();

    expect(await c.unlock('v.kdbx', _master), isTrue);
    expect(c.status, VaultStatus.unlocked);
    expect(c.items.single.title, 'GitHub');
    expect(c.error, isNull);
    c.dispose();
  });

  test('wrong password keeps the vault locked and reports the error', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);

    expect(await c.unlock('v.kdbx', 'nope'), isFalse);
    expect(c.status, VaultStatus.locked);
    expect(c.error, contains('could not open vault'));
    expect(backend.unlocked, isFalse);
    c.dispose();
  });

  test('save, search and delete update the list', () async {
    final c = VaultController(FakeBackend());
    await c.create('v.kdbx', _master);

    final a = await c.save(null, _draft('GitHub'));
    await c.save(null, _draft('Bank'));
    expect(c.items.length, 2);

    await c.search('git');
    expect(c.items.map((i) => i.title), ['GitHub']);

    await c.delete(a);
    await c.search('');
    expect(c.items.map((i) => i.title), ['Bank']);
    c.dispose();
  });

  test('lock clears state, clipboard, generator history, and locks the backend', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);
    await c.save(null, _draft('GitHub'));

    await ClipboardGuard.copySecret('top-secret-clipboard-pw');
    expect(ClipboardGuard.hasActiveSecret, isTrue);
    c.recordGeneratedPassword('generated-pw-123', domainOrTitle: 'GitHub');
    expect(c.generatorHistory, isNotEmpty);
    c.windowsHelloEnabled = true;
    c.quickPinEnabled = true;
    c.wifiSyncServerRunning = true;

    await c.lock();
    expect(c.status, VaultStatus.locked);
    expect(c.items, isEmpty);
    expect(c.query, isEmpty);
    expect(ClipboardGuard.hasActiveSecret, isFalse);
    expect(c.generatorHistory, isEmpty);
    expect(c.windowsHelloEnabled, isFalse);
    expect(c.quickPinEnabled, isFalse);
    expect(c.wifiSyncServerRunning, isFalse);
    expect(backend.unlocked, isFalse);
    c.dispose();
  });

  test('auto-locks after the idle timeout', () async {
    final backend = FakeBackend();
    final c = VaultController(
      backend,
      autoLockAfter: const Duration(milliseconds: 40),
    );
    await c.create('v.kdbx', _master);
    expect(c.status, VaultStatus.unlocked);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.status, VaultStatus.locked);
    expect(backend.unlocked, isFalse);
    c.dispose();
  });

  test('groups management: creation, listing, selection', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);

    final gid = await c.createGroup('Finance');
    expect(c.groups.any((g) => g.id == gid && g.name == 'Finance'), isTrue);

    c.selectGroup(gid);
    expect(c.selectedGroupId, gid);

    await c.save(null, _draft('Bank Account', groupId: gid));
    expect(c.items.single.title, 'Bank Account');
    expect(c.items.single.groupName, gid);
    c.dispose();
  });

  test('TOTP retrieval and display', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);

    final id = await c.save(
      null,
      _draft('Cloudflare', otp: 'otpauth://totp/Cloudflare:me?secret=JBSWY3DPEHPK3PXP'),
    );

    final entry = await c.loadEntry(id);
    expect(entry.hasOtp, isTrue);
    expect(
      await c.revealOtpUri(id),
      'otpauth://totp/Cloudflare:me?secret=JBSWY3DPEHPK3PXP',
    );

    final totp = await c.getTotp(id);
    expect(totp, isNotNull);
    expect(totp!.code, '123456');
    expect(totp.period, 30);
    expect(totp.secondsRemaining, 25);
    c.dispose();
  });

  test('attachments crud operations', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);

    final id = await c.save(null, _draft('Passport Entry'));
    final data = Uint8List.fromList([1, 2, 3, 4, 5]);

    await c.addAttachment(id, 'scan.pdf', data);
    final atts = await c.listAttachments(id);
    expect(atts.length, 1);
    expect(atts.first.name, 'scan.pdf');
    expect(atts.first.size, 5);

    final read = await c.getAttachment(id, 'scan.pdf');
    expect(read, data);

    await c.removeAttachment(id, 'scan.pdf');
    final after = await c.listAttachments(id);
    expect(after, isEmpty);
    c.dispose();
  });

  test('3-way merge and domain query', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);

    await c.save(null, _draft('Google'));
    final mergedCount = await c.mergeVault('remote.kdbx', _master);
    expect(mergedCount, 1);

    final domainResults = await c.findEntriesForDomain('google');
    expect(domainResults.length, 1);
    expect(domainResults.first.title, 'Google');
    c.dispose();
  });

  test('passkey generation, removal, and category filtering', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);

    final githubId = await c.save(null, _draft('GitHub'));
    await c.save(null, _draft('CustomLocalApp'));

    // Before generating passkey: GitHub is Passkey Supported
    expect(c.passkeyCount, 0);
    expect(c.passkeySupportedCount, 1);

    final pk = await c.generatePasskey(
      githubId,
      rpId: 'github.com',
      username: 'octocat',
    );
    expect(pk.rpId, 'github.com');
    expect(pk.username, 'octocat');
    expect(c.passkeyCount, 1);
    expect(c.passkeySupportedCount, 0);

    c.selectCategory(VaultCategoryFilter.passkeys);
    expect(c.selectedCategory, VaultCategoryFilter.passkeys);

    // Windows assertion (Flags 0x1d: UP=1, UV=1, BE=1, BS=1)
    final winAssert = await c.authenticatePasskey(
      githubId,
      platform: 'windows',
      origin: 'https://github.com',
      userVerified: true,
    );
    expect(winAssert.platform, 'windows');
    expect(winAssert.flags, 0x1d);
    expect(winAssert.userVerified, isTrue);
    expect(winAssert.backupEligible, isTrue);
    expect(winAssert.backupState, isTrue);

    // Android assertion with unverified preferred ceremony (Flags 0x19: UP=1, UV=0, BE=1, BS=1)
    final androidAssert = await c.authenticatePasskey(
      githubId,
      platform: 'android',
      origin: 'https://github.com',
      userVerified: false,
      androidPackageName: 'com.github.android',
    );
    expect(androidAssert.platform, 'android');
    expect(androidAssert.flags, 0x19);
    expect(androidAssert.userVerified, isFalse);

    // Unsupported platform is rejected
    await expectLater(
      c.authenticatePasskey(githubId, platform: 'ios'),
      throwsStateError,
    );

    await c.removePasskey(githubId);
    expect(c.passkeyCount, 0);
    expect(c.passkeySupportedCount, 1);
    c.dispose();
  });


  test('changeMasterPassword rotates master password and bumps revisions', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);
    final id = await c.save(null, _draft('AWS'));
    final revBefore = (await c.loadEntry(id)).revisionDate!;

    // Wrong current password fails
    await expectLater(
      c.changeMasterPassword('wrong-password', 'new-horse-battery'),
      throwsA(contains('current master password does not match')),
    );

    // Valid rotation succeeds and bumps revisionDate
    await c.changeMasterPassword(_master, 'new-horse-battery');
    final revAfter = (await c.loadEntry(id)).revisionDate!;
    expect(revAfter, greaterThan(revBefore));

    await c.lock();
    expect(await c.unlock('v.kdbx', _master), isFalse);
    expect(await c.unlock('v.kdbx', 'new-horse-battery'), isTrue);
    c.dispose();
  });

  test('optimistic concurrency rejects stale lastKnownRevisionDate', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);

    final id = await c.save(null, _draft('Stripe'));
    final loaded = await c.loadEntry(id);
    expect(loaded.revisionDate, isNotNull);

    // Concurrent update advances revision twice
    await c.save(id, _draft('Stripe', password: 'v2'));
    await c.save(id, _draft('Stripe', password: 'v3'));

    // Attempting to save with the old revisionDate is rejected
    await expectLater(
      c.save(
        id,
        EntryDraft(
          title: 'Stripe',
          username: 'user',
          password: 'stale',
          url: 'https://Stripe.example',
          notes: '',
          lastKnownRevisionDate: loaded.revisionDate,
        ),
      ),
      throwsA(contains('stale revision')),
    );
    expect(await c.revealPassword(id), 'v3');
    c.dispose();
  });

  test('Enpass security score, audit counters, categories, tags, and backup', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);

    expect(c.overallSecurityScore, 100);
    expect(c.overallSecurityLabel, 'Excellent');

    final id1 = await c.save(
      null,
      const EntryDraft(
        title: 'GitHub',
        username: 'octo',
        password: 'VeryStrongUniquePassword!2026',
        url: 'https://github.com',
        notes: '',
        category: 'Login',
        tags: ['Dev', 'Cloud'],
        isFavorite: true,
      ),
    );
    expect(c.excellentCount, 1);
    expect(c.favoritesCount, 1);
    expect(c.categoryCount('Login'), 1);
    expect(c.allTags, ['Cloud', 'Dev']);
    expect(c.overallSecurityScore, 100);

    await c.setEntryMetadata(
      id1,
      category: 'Finance',
      tags: ['Banking'],
      isFavorite: false,
      isArchived: false,
      isTrashed: false,
    );
    expect(c.categoryCount('Finance'), 1);
    expect(c.favoritesCount, 0);

    final customPw = await c.generateCustomPassword(
      const PasswordGenConfig(length: 18, pronounceable: true),
    );
    expect(customPw.length, 18);

    final backupPath = await c.createBackup('/tmp/backups');
    expect(backupPath, contains('backup_'));
    c.dispose();
  });

  test('structured Enpass fields, custom fields, security answer, backup restore, and eraseVault', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);

    final id = await c.save(
      null,
      const EntryDraft(
        title: 'Chase Bank',
        username: 'alice_b',
        password: 'StrongPassword#2026!',
        url: 'https://chase.com',
        notes: 'Checking account',
        email: 'alice@chase.example',
        phone: '+1-800-555-0199',
        securityQuestion: 'First school?',
        securityAnswer: 'Oakridge',
        sections: ['WIRE DETAILS', 'RECOVERY'],
        customFields: [
          VaultCustomField(
            name: 'Routing',
            value: '021000021',
            fieldType: 'Text',
            sensitive: false,
            section: 'WIRE DETAILS',
          ),
          VaultCustomField(
            name: 'Wire PIN',
            value: '9942',
            fieldType: 'PIN',
            sensitive: true,
            section: 'RECOVERY',
          ),
        ],
      ),
    );

    final loaded = await c.loadEntry(id);
    expect(loaded.email, 'alice@chase.example');
    expect(loaded.phone, '+1-800-555-0199');
    expect(loaded.securityQuestion, 'First school?');
    expect(loaded.hasSecurityAnswer, isTrue);
    expect(loaded.sections, ['WIRE DETAILS', 'RECOVERY']);
    expect(loaded.customFields.length, 2);
    expect(loaded.customFields[0].value, '021000021');
    expect(loaded.customFields[1].value, ''); // redacted in summary because sensitive
    expect(await c.revealSecurityAnswer(id), 'Oakridge');
    expect(await c.revealCustomField(id, 0), '021000021');
    expect(await c.revealCustomField(id, 1), '9942');

    // Vault info & password evaluation
    final info = await c.getVaultInfo();
    expect(info.entryCount, 1);
    expect(info.kdfMemoryMib, 32);

    final eval = await c.evaluatePassword('password123');
    expect(eval.isCompromised, isTrue);
    expect(eval.label, 'Weak');

    // Backup snapshot creation, listing, and restore
    final bpath = await c.createBackup('/tmp/backups');
    final backups = await c.listBackups('/tmp/backups');
    expect(backups, [bpath]);

    await c.delete(id);
    expect(c.items, isEmpty);

    await c.restoreBackup(bpath, '');
    expect(c.items.length, 1);
    expect(c.items.single.title, 'Chase Bank');

    // Erase vault rejects wrong master password and locks on right master password
    await expectLater(
      c.eraseVault('wrong-master'),
      throwsA(contains('incorrect')),
    );
    expect(c.status, VaultStatus.unlocked);

    await c.eraseVault(_master);
    expect(c.status, VaultStatus.locked);
    c.dispose();
  });

  test('Quick PIN unlock supports numeric and character PINs and enforces 3-attempt lockout', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);

    // 1. Numeric PIN ("482910")
    c.configureQuickPin('482910');
    expect(c.quickPinEnabled, isTrue);
    expect(c.hasQuickPinConfigured, isTrue);

    await c.lock();
    expect(c.status, VaultStatus.locked);
    expect(c.quickPinEnabled, isTrue);
    expect(c.hasQuickPinConfigured, isTrue);

    expect(await c.unlockWithPin('v.kdbx', '482910'), isTrue);
    expect(c.status, VaultStatus.unlocked);

    // 2. Character/alphanumeric PIN ("Vault#99")
    c.configureQuickPin('Vault#99');
    await c.lock();
    expect(await c.unlockWithPin('v.kdbx', 'Vault#99'), isTrue);
    expect(c.status, VaultStatus.unlocked);

    // 3. Adversarial test: 3 wrong PIN attempts clear PIN and require master password
    await c.lock();
    expect(await c.unlockWithPin('v.kdbx', 'wrong-1'), isFalse);
    expect(c.error, contains('2 attempts remaining'));
    expect(c.hasQuickPinConfigured, isTrue);

    expect(await c.unlockWithPin('v.kdbx', 'wrong-2'), isFalse);
    expect(c.error, contains('1 attempt remaining'));
    expect(c.hasQuickPinConfigured, isTrue);

    expect(await c.unlockWithPin('v.kdbx', 'wrong-3'), isFalse);
    expect(c.error, contains('Too many failed PIN attempts'));
    expect(c.hasQuickPinConfigured, isFalse);

    // Subsequent PIN attempt with the old valid PIN is rejected until Master Password unlock
    expect(await c.unlockWithPin('v.kdbx', 'Vault#99'), isFalse);
    c.dispose();
  });

  test('Windows Hello Quick Unlock succeeds when verified and rejects when unverified', () async {
    final backend = FakeBackend();
    var mockVerified = true;
    final c = VaultController(
      backend,
      windowsHelloAuthenticator: () async => mockVerified,
    );
    await c.create('v.kdbx', _master);

    expect(await c.enableWindowsHello(), isTrue);
    expect(c.windowsHelloEnabled, isTrue);
    expect(c.hasWindowsHelloCredential, isTrue);

    await c.lock();
    expect(c.status, VaultStatus.locked);
    expect(c.windowsHelloEnabled, isTrue);

    // Adversarial: Windows Hello canceled / rejected
    mockVerified = false;
    expect(await c.unlockWithWindowsHello('v.kdbx'), isFalse);
    expect(c.status, VaultStatus.locked);
    expect(c.error, contains('cancelled or failed'));

    // Happy path: Windows Hello verified
    mockVerified = true;
    expect(await c.unlockWithWindowsHello('v.kdbx'), isTrue);
    expect(c.status, VaultStatus.unlocked);
    c.dispose();
  });

  test('Theme Mode (Light / Dark / Follow System), System Accent Color, and Startup/Tray settings persist across restarts', () async {
    final tempDir = await Directory.systemTemp.createTemp('vk_settings_test_');
    final settingsPath = '${tempDir.path}${Platform.pathSeparator}settings.json';
    addTearDown(() async {
      TacticalTheme.configure(light: false, accent: null);
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final backend = FakeBackend();
    final c1 = VaultController(backend, settingsFilePath: settingsPath);
    await c1.initializePlatformSettings();

    // Switch to Light mode and enable Startup + Minimize to Tray + Hide Dock Icon
    c1.updateSettings(
      themeModeSetting: 'Light',
      openAtStartup: true,
      minimizeToTray: true,
      hideDockIcon: true,
    );
    expect(c1.effectiveIsLight, isTrue);
    TacticalTheme.configure(light: c1.effectiveIsLight);
    expect(TacticalTheme.bgDeepCarbon, const Color(0xFFF1F5F9));

    // Switch to Follow System and verify it tracks OS brightness & accent color
    c1.updateSystemBrightness(true, accentColorValue: 0xFF2563EB);
    c1.updateSettings(themeModeSetting: 'Follow System');
    expect(c1.effectiveIsLight, isTrue);
    expect(c1.systemAccentColorValue, 0xFF2563EB);
    TacticalTheme.configure(
      light: c1.effectiveIsLight,
      accent: Color(c1.systemAccentColorValue!),
    );
    expect(TacticalTheme.amberPrimary, const Color(0xFF2563EB));

    c1.updateSystemBrightness(false, accentColorValue: 0xFF10B981);
    expect(c1.effectiveIsLight, isFalse);

    // Persist Light Mode and verify reload in a new VaultController instance
    c1.updateSettings(themeModeSetting: 'Light');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c1.dispose();

    final c2 = VaultController(backend, settingsFilePath: settingsPath);
    await c2.initializePlatformSettings();
    expect(c2.themeModeSetting, 'Light');
    expect(c2.openAtStartup, isTrue);
    expect(c2.minimizeToTray, isTrue);
    expect(c2.hideDockIcon, isTrue);
    c2.dispose();
  });

  test('Top Menu controller actions: duplicate, archive, trash, changeCategory, moveEntryToGroup, export/import CSV, group cycling, and recent items', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);

    final g1 = await c.createGroup('Work');
    final g2 = await c.createGroup('Personal');

    // Group cycling (Ctrl+Down / Ctrl+Up)
    expect(c.selectedGroupId, isNull);
    c.selectNextGroup();
    expect(c.selectedGroupId, 'root');
    c.selectNextGroup();
    expect(c.selectedGroupId, g1);
    c.selectNextGroup();
    expect(c.selectedGroupId, g2);
    c.selectNextGroup();
    expect(c.selectedGroupId, isNull);
    c.selectPreviousGroup();
    expect(c.selectedGroupId, g2);
    c.selectGroup(null);

    // Save an entry and duplicate it
    final origId = await c.save(
      null,
      const EntryDraft(
        title: 'GitHub',
        username: 'octocat',
        password: 'SecretPassword!123',
        url: 'https://github.com',
        notes: 'Dev account',
        email: 'octo@github.com',
        category: 'Login',
        tags: ['dev'],
      ),
    );
    c.recordRecentItem(origId);
    expect(c.recentEntryIds, [origId]);

    final dupId = await c.duplicateEntry(origId);
    expect(dupId, isNot(origId));
    final dupEntry = await c.loadEntry(dupId);
    expect(dupEntry.title, 'GitHub (Copy)');
    expect(await c.revealPassword(dupId), 'SecretPassword!123');

    // Change Category & Add to Vault Group
    await c.changeEntryCategory(dupId, 'Computer');
    expect((await c.loadEntry(dupId)).category, 'Computer');
    await c.moveEntryToGroup(dupId, g1);
    expect((await c.loadEntry(dupId)).groupId, g1);

    // Archive and Move to Trash
    await c.archiveEntry(dupId, archived: true);
    expect((await c.loadEntry(dupId)).isArchived, isTrue);
    await c.moveEntryToTrash(dupId, trashed: true);
    expect((await c.loadEntry(dupId)).isTrashed, isTrue);

    // Import CSV
    final imported = await c.importCsv(
      'Title,Username,Email,Password,URL,Notes,Category,Tags\n'
      'Cloudflare,ops,ops@cf.com,CfPass!99,https://cloudflare.com,Edge,Login,infra',
    );
    expect(imported, 1);
    expect(c.items.any((i) => i.title == 'Cloudflare'), isTrue);

    // Export Vault: adversarial wrong password rejected, happy path succeeds
    await expectLater(
      () => c.exportVault('export.kdbx', 'wrong-master-password', 'kdbx'),
      throwsA(anything),
    );
    final exportedCount = await c.exportVault('export.kdbx', _master, 'kdbx');
    expect(exportedCount, greaterThanOrEqualTo(2));

    // Clear recent items and verify lock resets hideSensitive and recentEntryIds
    c.updateSettings(hideSensitive: false);
    expect(c.hideSensitive, isFalse);
    c.clearRecentItems();
    expect(c.recentEntryIds, isEmpty);
    c.recordRecentItem(origId);
    await c.lock();
    expect(c.recentEntryIds, isEmpty);
    expect(c.hideSensitive, isTrue);
    c.dispose();
  });

  test('Wi-Fi Sync: Same-Account auto-sync and 6-digit Pairing Code sync (happy path + adversarial rejections)', () async {
    final deviceA = VaultController(FakeBackend(), deviceName: 'LAPTOP-ALPHA');
    final deviceB = VaultController(FakeBackend(), deviceName: 'PHONE-BETA');
    final intruder = VaultController(FakeBackend(), deviceName: 'INTRUDER-NODE');

    await deviceA.create('a.kdbx', _master);
    await deviceB.create('b.kdbx', _master);
    await intruder.create('c.kdbx', _master);

    await deviceA.save(
      null,
      const EntryDraft(
        title: 'GitHub',
        username: 'octocat',
        password: 'OctoPassword!2026',
        url: 'https://github.com',
        notes: 'Alpha item',
      ),
    );
    await deviceB.save(
      null,
      const EntryDraft(
        title: 'AWS Console',
        username: 'cloud-admin',
        password: 'AwsPassword!2026',
        url: 'https://aws.amazon.com',
        notes: 'Beta item',
      ),
    );

    // 1. Mode 1: Same-Account Wi-Fi Sync
    deviceA.completeOnboardingActivation(
      usageType: 'Personal',
      email: 'killfury212@gmail.com',
    );
    deviceB.completeOnboardingActivation(
      usageType: 'Personal',
      email: 'KILLFURY212@GMAIL.COM', // case-insensitive normalization check
    );
    intruder.completeOnboardingActivation(
      usageType: 'Personal',
      email: 'attacker@evil.org',
    );

    deviceA.startWifiSyncServer(
      customAddress: '192.168.1.10:52138',
      fixedCodeForTesting: '861303',
    );

    expect(deviceB.discoverSameAccountWifiPeers().length, 1);
    expect(intruder.discoverSameAccountWifiPeers(), isEmpty);

    // Adversarial: different account is rejected from Same-Account sync
    await expectLater(
      () => intruder.syncWithSameAccountPeer(),
      throwsA(isA<StateError>()),
    );
    expect(intruder.items, isEmpty);

    // Happy path: Same-Account sync bidirectionally merges passwords between deviceA & deviceB
    final mergedSameAccount = await deviceB.syncWithSameAccountPeer();
    expect(mergedSameAccount, greaterThanOrEqualTo(2));
    expect(deviceA.items.map((i) => i.title).toSet(), {'GitHub', 'AWS Console'});
    expect(deviceB.items.map((i) => i.title).toSet(), {'GitHub', 'AWS Console'});

    // 2. Mode 2: 6-Digit Pairing Code Wi-Fi Sync on the Same Wi-Fi
    final deviceD = VaultController(FakeBackend(), deviceName: 'TABLET-DELTA');
    await deviceD.create('d.kdbx', _master);
    await deviceD.save(
      null,
      const EntryDraft(
        title: 'ProtonMail',
        username: 'vaultuser',
        password: 'ProtonPassword!2026',
        url: 'https://proton.me',
        notes: 'Delta item',
      ),
    );

    // Adversarial: Wrong 6-digit pairing code is rejected
    await expectLater(
      () => deviceD.syncWithWifiCode('000000'),
      throwsA(isA<StateError>()),
    );
    expect(deviceD.items.map((i) => i.title).toList(), ['ProtonMail']);

    // Adversarial: Expired 6-digit pairing code is rejected
    deviceA.regenerateWifiSyncPairingCode(
      fixedCodeForTesting: '123456',
      lifetime: const Duration(seconds: -5),
    );
    await expectLater(
      () => deviceD.syncWithWifiCode('123456'),
      throwsA(isA<StateError>()),
    );

    // Happy path: Valid 6-digit pairing code (with space formatting '861 303') syncs bidirectionally
    deviceA.regenerateWifiSyncPairingCode(fixedCodeForTesting: '861303');
    final mergedByCode = await deviceD.syncWithWifiCode('861 303');
    expect(mergedByCode, greaterThanOrEqualTo(3));
    expect(
      deviceD.items.map((i) => i.title).toSet(),
      {'GitHub', 'AWS Console', 'ProtonMail'},
    );
    expect(
      deviceA.items.map((i) => i.title).toSet(),
      {'GitHub', 'AWS Console', 'ProtonMail'},
    );
    expect(deviceD.wifiSyncPairedDevices, isNotEmpty);

    deviceA.dispose();
    deviceB.dispose();
    intruder.dispose();
    deviceD.dispose();
  });
}


