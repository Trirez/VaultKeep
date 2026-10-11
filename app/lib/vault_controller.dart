import 'dart:async';

import 'package:flutter/foundation.dart';

import 'backend.dart';

enum VaultStatus { locked, unlocked }

enum VaultCategoryFilter {
  all,
  favorites,
  passkeys,
  passkeySupported,
  totp2fa,
  auditExcellent,
  auditCompromised,
  auditWeak,
  auditIdentical,
  auditBreached,
  auditTwoFaSupported,
  auditExpired,
  attachments,
  archived,
  trashed,
}

enum VaultSortField {
  title,
  username,
  url,
  revisionDate,
}

/// UI state for one vault session: lock state, entry list, search, Enpass audit
/// dashboard metrics, categories/tags, and the idle auto-lock timer.
/// All crypto and file work happens in the Rust backend.
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
  VaultCategoryFilter selectedCategory = VaultCategoryFilter.all;
  String? selectedItemCategory;
  String? selectedTag;
  bool showHomeDashboard = false;
  VaultSortField sortField = VaultSortField.title;
  bool sortAscending = true;
  String query = '';
  String? error;
  bool busy = false;

  // Enpass Settings State
  bool showSidebarCounts = true;
  bool showSubtitles = true;
  bool showWebsiteIcons = true;
  bool includeOldPasswordsInAudit = true;
  bool windowsHelloEnabled = false;
  bool quickPinEnabled = false;
  bool autoBackupEnabled = true;
  int maxBackupCount = 60;
  bool wifiSyncServerRunning = false;
  String wifiSyncVaultName = 'Primary';
  bool checkCompromisedPasswords = true;
  bool verifyBrowserSignature = true;
  String connectedStorageProvider = 'This PC (Local KDBX4)';
  String? lastBackupPath;

  Timer? _idle;
  int _searchSeq = 0;
  bool _disposed = false;

  List<VaultItem> get activeItems =>
      items.where((i) => !i.isTrashed && !i.isArchived).toList();

  int get passkeyCount => activeItems.where((i) => i.hasPasskey).length;
  int get passkeySupportedCount =>
      activeItems.where((i) => i.passkeySupported).length;
  int get totpCount => activeItems.where((i) => i.hasTotp).length;

  int get favoritesCount => activeItems.where((i) => i.isFavorite).length;
  int get attachmentsCount => activeItems.where((i) => i.hasAttachment).length;
  int get archivedCount =>
      items.where((i) => !i.isTrashed && i.isArchived).length;
  int get trashedCount => items.where((i) => i.isTrashed).length;

  int get excellentCount => activeItems
      .where(
        (i) =>
            !i.isWeak &&
            !i.isIdentical &&
            !i.isCompromised &&
            !i.isBreached &&
            i.strengthScore >= 75,
      )
      .length;
  int get compromisedCount => activeItems.where((i) => i.isCompromised).length;
  int get weakCount => activeItems.where((i) => i.isWeak).length;
  int get identicalCount => activeItems.where((i) => i.isIdentical).length;
  int get breachedCount => activeItems.where((i) => i.isBreached).length;
  int get twoFaSupportedCount =>
      activeItems.where((i) => i.twoFaSupported).length;
  int get expiredCount => activeItems.where((i) => i.isExpired).length;

  int get overallSecurityScore {
    final active = activeItems;
    if (active.isEmpty) return 100;
    var sum = 0;
    for (final item in active) {
      var s = item.strengthScore;
      if (!item.isWeak &&
          !item.isIdentical &&
          !item.isCompromised &&
          !item.isBreached &&
          !item.isExpired &&
          s >= 75) {
        s = 100;
      } else {
        if (item.isCompromised || item.isBreached) {
          if (s > 20) s = 20;
        }
        if (item.isIdentical && s > 55) {
          s = 55;
        }
        if (item.isExpired) {
          s = (s - 15).clamp(0, 100);
        }
      }
      sum += s;
    }
    return (sum / active.length).round().clamp(0, 100);
  }

  String get overallSecurityLabel {
    final score = overallSecurityScore;
    if (score >= 85) return 'Excellent';
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Moderate';
    return 'Weak';
  }

  int categoryCount(String category) {
    final target = category.toLowerCase();
    return activeItems
        .where((i) => i.category.toLowerCase() == target)
        .length;
  }

  List<String> get allTags {
    final seen = <String>{};
    final out = <String>[];
    for (final item in activeItems) {
      for (final t in item.tags) {
        final trimmed = t.trim();
        if (trimmed.isNotEmpty && seen.add(trimmed.toLowerCase())) {
          out.add(trimmed);
        }
      }
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

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
      selectedCategory = VaultCategoryFilter.all;
      selectedItemCategory = null;
      selectedTag = null;
      showHomeDashboard = false;
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
    selectedCategory = VaultCategoryFilter.all;
    selectedItemCategory = null;
    selectedTag = null;
    showHomeDashboard = false;
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

  Future<String?> revealOtpUri(String id) {
    touch();
    return _backend.revealOtpUri(id);
  }

  Future<String> generatePassword({int length = 24, bool symbols = true}) {
    touch();
    return _backend.generate(length: length, symbols: symbols);
  }

  Future<String> generateCustomPassword(PasswordGenConfig config) {
    touch();
    return _backend.generateCustom(config);
  }

  Future<String> save(String? id, EntryDraft draft) async {
    final savedId = await _backend.save(id, draft);
    await _refresh();
    await refreshGroups();
    touch();
    return savedId;
  }

  Future<void> setEntryMetadata(
    String id, {
    required String category,
    required List<String> tags,
    required bool isFavorite,
    required bool isArchived,
    required bool isTrashed,
  }) async {
    touch();
    await _backend.setEntryMetadata(
      id,
      category: category,
      tags: tags,
      isFavorite: isFavorite,
      isArchived: isArchived,
      isTrashed: isTrashed,
    );
    await _refresh();
  }

  Future<String> createBackup(String backupDir) async {
    touch();
    final path = await _backend.createBackup(
      backupDir,
      maxBackups: maxBackupCount,
    );
    lastBackupPath = path;
    _notify();
    return path;
  }

  Future<void> delete(String id) async {
    await _backend.delete(id);
    await _refresh();
    await refreshGroups();
    touch();
  }

  Future<void> refreshGroups() async {
    if (status != VaultStatus.unlocked) return;
    try {
      final fetched = await _backend.listGroups();
      if (status != VaultStatus.unlocked) return;
      groups = fetched;
      _notify();
    } catch (_) {}
  }

  Future<String> createGroup(String name) async {
    touch();
    final gid = await _backend.createGroup(name);
    await refreshGroups();
    return gid;
  }

  void openHomeDashboard() {
    showHomeDashboard = true;
    _notify();
  }

  void closeHomeDashboard() {
    showHomeDashboard = false;
    _notify();
  }

  void selectGroup(String? groupId) {
    selectedGroupId = groupId;
    showHomeDashboard = false;
    if (groupId != null) {
      selectedCategory = VaultCategoryFilter.all;
      selectedItemCategory = null;
      selectedTag = null;
    } else {
      selectedCategory = VaultCategoryFilter.all;
      selectedItemCategory = null;
      selectedTag = null;
    }
    _notify();
  }

  void selectCategory(VaultCategoryFilter category) {
    selectedCategory = category;
    selectedGroupId = null;
    selectedItemCategory = null;
    selectedTag = null;
    showHomeDashboard = false;
    _notify();
  }

  void selectItemCategory(String? categoryName) {
    selectedItemCategory = categoryName;
    selectedGroupId = null;
    selectedCategory = VaultCategoryFilter.all;
    selectedTag = null;
    showHomeDashboard = false;
    _notify();
  }

  void selectTag(String? tag) {
    selectedTag = tag;
    selectedGroupId = null;
    selectedCategory = VaultCategoryFilter.all;
    selectedItemCategory = null;
    showHomeDashboard = false;
    _notify();
  }

  void setSort(VaultSortField field, {bool? ascending}) {
    if (sortField == field && ascending == null) {
      sortAscending = !sortAscending;
    } else {
      sortField = field;
      if (ascending != null) sortAscending = ascending;
    }
    _notify();
  }

  void updateSettings({
    bool? showSidebarCounts,
    bool? showSubtitles,
    bool? showWebsiteIcons,
    bool? includeOldPasswordsInAudit,
    bool? windowsHelloEnabled,
    bool? quickPinEnabled,
    bool? autoBackupEnabled,
    int? maxBackupCount,
    bool? wifiSyncServerRunning,
    String? wifiSyncVaultName,
    bool? checkCompromisedPasswords,
    bool? verifyBrowserSignature,
    String? connectedStorageProvider,
  }) {
    if (showSidebarCounts != null) {
      this.showSidebarCounts = showSidebarCounts;
    }
    if (showSubtitles != null) this.showSubtitles = showSubtitles;
    if (showWebsiteIcons != null) this.showWebsiteIcons = showWebsiteIcons;
    if (includeOldPasswordsInAudit != null) {
      this.includeOldPasswordsInAudit = includeOldPasswordsInAudit;
    }
    if (windowsHelloEnabled != null) {
      this.windowsHelloEnabled = windowsHelloEnabled;
    }
    if (quickPinEnabled != null) this.quickPinEnabled = quickPinEnabled;
    if (autoBackupEnabled != null) this.autoBackupEnabled = autoBackupEnabled;
    if (maxBackupCount != null) this.maxBackupCount = maxBackupCount;
    if (wifiSyncServerRunning != null) {
      this.wifiSyncServerRunning = wifiSyncServerRunning;
    }
    if (wifiSyncVaultName != null) this.wifiSyncVaultName = wifiSyncVaultName;
    if (checkCompromisedPasswords != null) {
      this.checkCompromisedPasswords = checkCompromisedPasswords;
    }
    if (verifyBrowserSignature != null) {
      this.verifyBrowserSignature = verifyBrowserSignature;
    }
    if (connectedStorageProvider != null) {
      this.connectedStorageProvider = connectedStorageProvider;
    }
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

  Future<VaultPasskey> generatePasskey(
    String entryId, {
    String rpId = '',
    String username = '',
  }) async {
    touch();
    final pk = await _backend.generatePasskey(
      entryId,
      rpId: rpId,
      username: username,
    );
    await _refresh();
    return pk;
  }

  Future<VaultPasskeyAssertion> authenticatePasskey(
    String entryId, {
    required String platform,
    String origin = '',
    bool userVerified = true,
    String? androidPackageName,
  }) {
    touch();
    return _backend.authenticatePasskey(
      entryId,
      platform: platform,
      origin: origin,
      userVerified: userVerified,
      androidPackageName: androidPackageName,
    );
  }

  Future<void> removePasskey(String entryId) async {
    touch();
    await _backend.removePasskey(entryId);
    await _refresh();
  }


  Future<void> changeMasterPassword(
    String currentMaster,
    String newMaster,
  ) async {
    touch();
    await _backend.changeMasterPassword(currentMaster, newMaster);
    await _refresh();
    await refreshGroups();
  }

  Future<void> _refresh() async {
    if (status != VaultStatus.unlocked) return;
    final fetched = await _backend.list(query);
    if (status != VaultStatus.unlocked) return;
    items = fetched;
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
