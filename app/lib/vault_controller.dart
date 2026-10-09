import 'dart:async';

import 'package:flutter/foundation.dart';

import 'backend.dart';

enum VaultStatus { locked, unlocked }

/// UI state for one vault session: lock state, entry list, search and the
/// idle auto-lock timer. All crypto and file work happens in the Rust backend.
class VaultController extends ChangeNotifier {
  VaultController(
    this._backend, {
    this.autoLockAfter = const Duration(minutes: 2),
  });

  final VaultBackend _backend;
  final Duration autoLockAfter;

  VaultStatus status = VaultStatus.locked;
  List<VaultItem> items = const [];
  List<VaultGroup> groups = const [];
  String? selectedGroupId;
  String query = '';
  String? error;
  bool busy = false;

  Timer? _idle;
  int _searchSeq = 0;
  bool _disposed = false;

  static String describe(Object e) => e is String ? e : e.toString();

  Future<bool> unlock(String path, String master) =>
      _open(() => _backend.unlock(path, master));

  Future<bool> create(String path, String master) =>
      _open(() => _backend.create(path, master));

  Future<bool> _open(Future<void> Function() action) async {
    busy = true;
    error = null;
    _notify();
    try {
      await action();
      query = '';
      selectedGroupId = null;
      items = await _backend.list('');
      try {
        groups = await _backend.listGroups();
      } catch (_) {
        groups = const [];
      }
      status = VaultStatus.unlocked;
      _restartIdleTimer();
      return true;
    } catch (e) {
      error = describe(e);
      status = VaultStatus.locked;
      items = const [];
      groups = const [];
      await _lockBackend();
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Locks immediately: UI state first, then the backend drops the vault.
  Future<void> lock() async {
    _idle?.cancel();
    _idle = null;
    status = VaultStatus.locked;
    items = const [];
    groups = const [];
    selectedGroupId = null;
    query = '';
    _notify();
    await _lockBackend();
  }

  /// Call on user activity; restarts the idle auto-lock countdown.
  void touch() {
    if (status == VaultStatus.unlocked) _restartIdleTimer();
  }

  Future<void> search(String q) async {
    query = q;
    final seq = ++_searchSeq;
    try {
      final found = await _backend.list(q);
      // Ignore results that arrive late, or after the vault was locked.
      if (seq != _searchSeq || status != VaultStatus.unlocked) return;
      items = found;
      error = null;
    } catch (e) {
      error = describe(e);
    }
    touch();
    _notify();
  }

  Future<VaultEntry> loadEntry(String id) {
    touch();
    return _backend.get(id);
  }

  Future<String> revealPassword(String id) {
    touch();
    return _backend.revealPassword(id);
  }

  Future<String> generatePassword({int length = 24, bool symbols = true}) {
    touch();
    return _backend.generate(length: length, symbols: symbols);
  }

  Future<String> save(String? id, EntryDraft draft) async {
    final savedId = await _backend.save(id, draft);
    await _refresh();
    touch();
    return savedId;
  }

  Future<void> delete(String id) async {
    await _backend.delete(id);
    await _refresh();
    touch();
  }

  Future<void> refreshGroups() async {
    if (status != VaultStatus.unlocked) return;
    try {
      groups = await _backend.listGroups();
      _notify();
    } catch (_) {}
  }

  Future<String> createGroup(String name) async {
    touch();
    final gid = await _backend.createGroup(name);
    await refreshGroups();
    return gid;
  }

  void selectGroup(String? groupId) {
    selectedGroupId = groupId;
    _notify();
  }

  Future<VaultTotp?> getTotp(String id) {
    touch();
    return _backend.getTotp(id);
  }

  Future<void> addAttachment(String entryId, String name, Uint8List data) async {
    touch();
    await _backend.addAttachment(entryId, name, data);
  }

  Future<Uint8List> getAttachment(String entryId, String name) {
    touch();
    return _backend.getAttachment(entryId, name);
  }

  Future<void> removeAttachment(String entryId, String name) async {
    touch();
    await _backend.removeAttachment(entryId, name);
  }

  Future<List<VaultAttachment>> listAttachments(String entryId) {
    touch();
    return _backend.listAttachments(entryId);
  }

  Future<int> mergeVault(String otherPath, String otherMaster) async {
    touch();
    final count = await _backend.mergeVault(otherPath, otherMaster);
    await _refresh();
    await refreshGroups();
    return count;
  }

  Future<List<VaultItem>> findEntriesForDomain(String domain) {
    touch();
    return _backend.findEntriesForDomain(domain);
  }

  Future<void> _refresh() async {
    if (status != VaultStatus.unlocked) return;
    items = await _backend.list(query);
    _notify();
  }

  void _restartIdleTimer() {
    _idle?.cancel();
    _idle = Timer(autoLockAfter, () => unawaited(lock()));
  }

  Future<void> _lockBackend() async {
    try {
      await _backend.lock();
    } catch (_) {
      // Locking is best effort; the UI is already locked.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _idle?.cancel();
    super.dispose();
  }
}
