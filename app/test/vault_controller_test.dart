import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkeep/backend.dart';
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
  int _next = 0;
  int _nextGroup = 1;
  int _clock = 1700000000;
  bool unlocked = false;
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
    activeMaster = master;
    unlocked = true;
  }

  @override
  Future<void> unlock(String path, String master) async {
    if (master != activeMaster) {
      throw 'could not open vault (wrong password/keyfile, or corrupt file)';
    }
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
        if (q.isEmpty || e.value.title.toLowerCase().contains(q))
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
    _store[key] = draft;
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
  Future<String> generateCustom(PasswordGenConfig config) async =>
      'A9!${'x' * (config.length > 3 ? config.length - 3 : 0)}';

  @override
  Future<String> createBackup(String backupDir, {int maxBackups = 60}) async {
    _check();
    return '$backupDir/backup_$_clock.kdbx';
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

  test('lock clears state and locks the backend', () async {
    final backend = FakeBackend();
    final c = VaultController(backend);
    await c.create('v.kdbx', _master);
    await c.save(null, _draft('GitHub'));

    await c.lock();
    expect(c.status, VaultStatus.locked);
    expect(c.items, isEmpty);
    expect(c.query, isEmpty);
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
}
