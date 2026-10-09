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
  final _groups = <VaultGroup>[
    const VaultGroup(id: 'root', name: 'Root', entryCount: 0),
  ];
  final _attachments = <String, Map<String, Uint8List>>{};
  int _next = 0;
  int _nextGroup = 1;
  bool unlocked = false;

  void _check() {
    if (!unlocked) throw 'vault is locked';
  }

  @override
  Future<void> create(String path, String master) async {
    unlocked = true;
  }

  @override
  Future<void> unlock(String path, String master) async {
    if (master != _master) {
      throw 'could not open vault (wrong password/keyfile, or corrupt file)';
    }
    unlocked = true;
  }

  @override
  Future<void> lock() async {
    unlocked = false;
  }

  @override
  Future<List<VaultItem>> list(String query) async {
    _check();
    final q = query.toLowerCase();
    return [
      for (final e in _store.entries)
        if (q.isEmpty || e.value.title.toLowerCase().contains(q))
          VaultItem(
            id: e.key,
            title: e.value.title,
            username: e.value.username,
            url: e.value.url,
            groupName: e.value.groupId,
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
    return VaultEntry(
      id: id,
      title: d.title,
      username: d.username,
      url: d.url,
      notes: d.notes,
      groupId: d.groupId,
      otpUri: d.otp,
      attachments: atts,
    );
  }

  @override
  Future<String> revealPassword(String id) async {
    _check();
    return _store[id]!.password;
  }

  @override
  Future<String> save(String? id, EntryDraft draft) async {
    _check();
    final key = id ?? 'id${_next++}';
    _store[key] = draft;
    return key;
  }

  @override
  Future<void> delete(String id) async {
    _check();
    _store.remove(id);
    _attachments.remove(id);
  }

  @override
  Future<String> generate({int length = 24, bool symbols = true}) async =>
      'x' * length;

  @override
  Future<List<VaultGroup>> listGroups() async {
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
          ),
    ];
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
}
