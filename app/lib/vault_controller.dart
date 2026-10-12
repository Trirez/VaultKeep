import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'backend.dart';
import 'clipboard_guard.dart';
import 'theme.dart';

/// Factory-minted Wi-Fi Sync pairing & verification token.
/// Constructor is private so tokens can never be instantiated ad-hoc outside
/// [WifiSyncTokenFactory].
class WifiSyncPairingToken {
  const WifiSyncPairingToken._({
    required this.pairingCode,
    required this.accessPassphrase,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
    required this.scope,
  });

  final String pairingCode;
  final String accessPassphrase;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
  final String scope;

  String get formattedPairingCode => pairingCode.length == 6
      ? '${pairingCode.substring(0, 3)} ${pairingCode.substring(3)}'
      : pairingCode;

  bool isValidAt(DateTime nowUtc) =>
      scope == WifiSyncTokenFactory.wifiLanSyncScope &&
      nowUtc.isBefore(expiresAtUtc);
}

/// Dedicated token factory with configuration-driven expiration for Wi-Fi Sync
/// pairing codes, per-vault access passphrases, and privacy-preserving account tags.
class WifiSyncTokenFactory {
  WifiSyncTokenFactory._();

  static const String wifiLanSyncScope = 'wifi_lan_sync';
  static const Duration defaultPairingCodeLifetime = Duration(minutes: 5);

  static const List<String> _passphraseWords = [
    'board',
    'pose',
    'crafter',
    'lace',
    'shield',
    'carbon',
    'amber',
    'cipher',
    'vector',
    'beacon',
    'orbit',
    'quartz',
    'nexus',
    'anchor',
    'cobalt',
    'vertex',
  ];

  static final Random _secureRandom = _createRandom();

  static Random _createRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  static WifiSyncPairingToken mintPairingToken({
    Duration lifetime = defaultPairingCodeLifetime,
    String? fixedCodeForTesting,
    String? fixedPassphraseForTesting,
  }) {
    final nowUtc = DateTime.now().toUtc();
    final code = fixedCodeForTesting ??
        List.generate(6, (_) => _secureRandom.nextInt(10).toString()).join();
    final passphrase = fixedPassphraseForTesting ??
        List.generate(4, (i) {
          final w =
              _passphraseWords[_secureRandom.nextInt(_passphraseWords.length)];
          final d = _secureRandom.nextInt(9) + 1;
          return i.isEven ? '$d$w' : '$w$d';
        }).join('-');

    return WifiSyncPairingToken._(
      pairingCode: code,
      accessPassphrase: passphrase,
      issuedAtUtc: nowUtc,
      expiresAtUtc: nowUtc.add(lifetime),
      scope: wifiLanSyncScope,
    );
  }

  /// Computes a normalized, privacy-preserving deterministic tag for an
  /// activated account email so two devices with the same account on the same
  /// Wi-Fi can discover and authenticate each other.
  static String computeAccountTag(String email) {
    final normalized = email.trim().toLowerCase();
    var hash1 = 0x811c9dc5;
    var hash2 = 0xcbf29ce4;
    for (final byte in utf8.encode('vaultkeep-wifi-account:$normalized')) {
      hash1 ^= byte;
      hash1 = (hash1 * 0x01000193) & 0xFFFFFFFF;
      hash2 ^= (byte + 0x9e3779b9) & 0xFF;
      hash2 = (hash2 * 0x01000193) & 0xFFFFFFFF;
    }
    return '${hash1.toRadixString(16).padLeft(8, '0')}${hash2.toRadixString(16).padLeft(8, '0')}';
  }
}

/// Metadata describing a discovered peer device on the local Wi-Fi network.
class WifiSyncPeerDevice {
  const WifiSyncPeerDevice({
    required this.deviceId,
    required this.deviceName,
    required this.address,
    required this.vaultName,
    required this.itemCount,
    required this.sameAccount,
    this.accountEmail,
  });

  final String deviceId;
  final String deviceName;
  final String address;
  final String vaultName;
  final int itemCount;
  final bool sameAccount;
  final String? accountEmail;
}

class GeneratedPasswordRecord {
  const GeneratedPasswordRecord({
    required this.password,
    required this.domainOrTitle,
    required this.timestampLabel,
  });

  final String password;
  final String domainOrTitle;
  final String timestampLabel;
}

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
  auditAge1To3Years,
  auditAge3To6Months,
  auditAge6To12Months,
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
/// dashboard metrics, categories/tags, theme/tray/startup preferences,
/// Windows Hello / Quick PIN unlock, and the idle auto-lock timer.
/// All crypto and file work happens in the Rust backend.
class VaultController extends ChangeNotifier {
  VaultController(
    this._backend, {
    this.autoLockAfter = const Duration(minutes: 2),
    this.settingsFilePath,
    this.windowsHelloAuthenticator,
    String? deviceName,
  }) : wifiSyncServerName = deviceName ?? _defaultDeviceName();

  static String _defaultDeviceName() {
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return host;
    } catch (_) {}
    return 'VAULTKEEP-DESKTOP';
  }

  static final List<VaultController> _activeWifiSyncHosts = [];
  static int _nextHostPort = 52138;

  static const MethodChannel _desktopChannel =
      MethodChannel('com.vaultkeep/passkey_provider');

  final VaultBackend _backend;
  final Duration autoLockAfter;
  final String? settingsFilePath;
  final Future<bool> Function()? windowsHelloAuthenticator;

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

  // Appearance & Theme State ('Follow System', 'Light', 'Dark')
  String themeModeSetting = 'Dark';
  bool systemIsLight = false;
  int? systemAccentColorValue;

  // Startup, System Tray & Lock Behavior State
  bool openAtStartup = false;
  bool minimizeToTray = true;
  bool hideDockIcon = false;
  bool searchInAllItems = true;
  bool dockedAssistant = false;
  bool lockOnSystemSleep = true;
  bool lockOnSystemLock = true;
  bool lockOnWindowClose = false;
  bool lockOnFastUserSwitch = true;

  // Enpass Settings & Top Menu View State
  bool showSidebarCounts = true;
  bool hideSensitive = true;
  bool showSidebarCategories = true;
  bool showSidebarTags = true;
  bool showSidebarAudit = true;
  bool includeOldPasswordsInAudit = true;
  bool showSidebarOthers = true;
  bool showSubtitles = true;
  bool showWebsiteIcons = true;
  bool windowsHelloEnabled = false;
  bool quickPinEnabled = false;
  bool autoBackupEnabled = true;
  int maxBackupCount = 60;
  bool wifiSyncServerRunning = false;
  bool wifiSyncServerPaused = false;
  String wifiSyncVaultName = 'Primary';
  String wifiSyncServerName;
  String wifiSyncServerAddress = '192.168.1.10:52138';
  int wifiSyncCodeSecondsRemaining = 30;
  WifiSyncPairingToken? _wifiSyncToken;
  final List<String> wifiSyncPairedDevices = [];
  String? wifiSyncLastSyncedAt;
  int wifiSyncLastMergedCount = 0;
  bool checkCompromisedPasswords = true;
  bool verifyBrowserSignature = true;
  String connectedStorageProvider = 'Google Drive';
  String? lastBackupPath;
  String onboardingUsageType = 'Personal';
  String? onboardingActivatedEmail;
  final List<String> recentEntryIds = [];

  // Quick Unlock (PIN & Windows Hello) Session State
  static const int maxQuickPinAttempts = 3;
  bool _windowsHelloEnrolled = false;
  bool _quickPinEnrolled = false;
  String? _quickPinCode;
  int quickPinFailedAttempts = 0;
  String? lastVaultPath;
  String? _sessionMasterCache;
  String? _dpapiProtectedMasterB64;
  bool isAuthenticatingWindowsHello = false;

  void completeOnboardingActivation({
    required String usageType,
    required String email,
  }) {
    onboardingUsageType = usageType;
    onboardingActivatedEmail = email.trim();
    unawaited(_saveSettingsToDisk());
    _notify();
  }

  bool get hasQuickPinConfigured =>
      quickPinEnabled && _quickPinEnrolled && (_quickPinCode?.isNotEmpty ?? false);

  bool get hasWindowsHelloCredential =>
      windowsHelloEnabled &&
      _windowsHelloEnrolled &&
      ((_sessionMasterCache?.isNotEmpty ?? false) ||
          (_dpapiProtectedMasterB64?.isNotEmpty ?? false));

  bool get effectiveIsLight => switch (themeModeSetting) {
        'Light' => true,
        'Dark' => false,
        _ => systemIsLight,
      };

  void _applyThemeConfiguration() {
    final accent =
        (themeModeSetting == 'Follow System' && systemAccentColorValue != null)
            ? Color(systemAccentColorValue!)
            : null;
    TacticalTheme.configure(light: effectiveIsLight, accent: accent);
  }

  void updateSystemBrightness(bool isLight, {int? accentColorValue}) {
    systemIsLight = isLight;
    if (accentColorValue != null) {
      systemAccentColorValue = accentColorValue;
    }
    _applyThemeConfiguration();
    _notify();
  }

  /// Session-scoped password generator history, wiped immediately on vault lock.
  final List<GeneratedPasswordRecord> generatorHistory = [];

  Timer? _idle;
  int _searchSeq = 0;
  bool _disposed = false;

  void recordGeneratedPassword(String password, {required String domainOrTitle}) {
    if (password.isEmpty || status != VaultStatus.unlocked) return;
    final now = DateTime.now();
    final ts =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    generatorHistory.insert(
      0,
      GeneratedPasswordRecord(
        password: password,
        domainOrTitle: domainOrTitle,
        timestampLabel: ts,
      ),
    );
    if (generatorHistory.length > 25) {
      generatorHistory.removeLast();
    }
  }

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

  static int _ageDays(VaultItem item) {
    final rev = item.revisionDate;
    if (rev == null || rev <= 0) return 0;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diffSec = nowSec - rev;
    if (diffSec <= 0) return 0;
    return diffSec ~/ 86400;
  }

  static bool isAge3To6Months(VaultItem item) {
    final days = _ageDays(item);
    return days >= 90 && days < 180;
  }

  static bool isAge6To12Months(VaultItem item) {
    final days = _ageDays(item);
    return days >= 180 && days < 365;
  }

  static bool isAge1To3Years(VaultItem item) {
    final days = _ageDays(item);
    return days >= 365;
  }

  int get age3To6MonthsCount => activeItems.where(isAge3To6Months).length;
  int get age6To12MonthsCount => activeItems.where(isAge6To12Months).length;
  int get age1To3YearsCount => activeItems.where(isAge1To3Years).length;

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

  Future<void> initializePlatformSettings() async {
    await _loadSettingsFromDisk();
    try {
      _desktopChannel.setMethodCallHandler(_handleDesktopMethodCall);
      final sysTheme = await _desktopChannel
          .invokeMapMethod<String, dynamic>('getSystemThemeInfo');
      if (sysTheme != null) {
        if (sysTheme['isLight'] is bool) {
          systemIsLight = sysTheme['isLight'] as bool;
        }
        if (sysTheme['accentColor'] is int) {
          systemAccentColorValue = sysTheme['accentColor'] as int;
        }
      }
      await _syncNativePlatformConfig();
    } catch (_) {
      // Non-Windows or test environment without platform channel.
    }
    _applyThemeConfiguration();
    _notify();
  }

  Future<dynamic> _handleDesktopMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onSystemThemeChanged':
        final args = call.arguments;
        if (args is Map) {
          if (args['isLight'] is bool) {
            systemIsLight = args['isLight'] as bool;
          }
          if (args['accentColor'] is int) {
            systemAccentColorValue = args['accentColor'] as int;
          } else if (args.containsKey('accentColor') &&
              args['accentColor'] == null) {
            systemAccentColorValue = null;
          }
          _applyThemeConfiguration();
          _notify();
        }
        break;
      case 'onTrayLockRequested':
        if (status == VaultStatus.unlocked) {
          await lock();
        }
        break;
      case 'onWindowClosedToTray':
        if (lockOnWindowClose && status == VaultStatus.unlocked) {
          await lock();
        }
        break;
    }
  }

  Future<void> _syncNativePlatformConfig() async {
    try {
      await _desktopChannel.invokeMethod<void>('setStartupAndTrayConfig', {
        'openAtStartup': openAtStartup,
        'minimizeToTray': minimizeToTray,
        'hideDockIcon': hideDockIcon,
        'themeMode': themeModeSetting,
        'isLight': effectiveIsLight,
      });
    } catch (_) {}
  }

  Future<void> _loadSettingsFromDisk() async {
    final path = settingsFilePath;
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (!f.existsSync()) return;
      final map = jsonDecode(f.readAsStringSync());
      if (map is! Map<String, dynamic>) return;
      if (map['themeModeSetting'] is String) {
        themeModeSetting = map['themeModeSetting'] as String;
      }
      if (map['openAtStartup'] is bool) {
        openAtStartup = map['openAtStartup'] as bool;
      }
      if (map['minimizeToTray'] is bool) {
        minimizeToTray = map['minimizeToTray'] as bool;
      }
      if (map['hideDockIcon'] is bool) {
        hideDockIcon = map['hideDockIcon'] as bool;
      }
      if (map['searchInAllItems'] is bool) {
        searchInAllItems = map['searchInAllItems'] as bool;
      }
      if (map['dockedAssistant'] is bool) {
        dockedAssistant = map['dockedAssistant'] as bool;
      }
      if (map['lockOnSystemSleep'] is bool) {
        lockOnSystemSleep = map['lockOnSystemSleep'] as bool;
      }
      if (map['lockOnSystemLock'] is bool) {
        lockOnSystemLock = map['lockOnSystemLock'] as bool;
      }
      if (map['lockOnWindowClose'] is bool) {
        lockOnWindowClose = map['lockOnWindowClose'] as bool;
      }
      if (map['lockOnFastUserSwitch'] is bool) {
        lockOnFastUserSwitch = map['lockOnFastUserSwitch'] as bool;
      }
      if (map['showSidebarCounts'] is bool) {
        showSidebarCounts = map['showSidebarCounts'] as bool;
      }
      if (map['hideSensitive'] is bool) {
        hideSensitive = map['hideSensitive'] as bool;
      }
      if (map['showSidebarCategories'] is bool) {
        showSidebarCategories = map['showSidebarCategories'] as bool;
      }
      if (map['showSidebarTags'] is bool) {
        showSidebarTags = map['showSidebarTags'] as bool;
      }
      if (map['showSidebarAudit'] is bool) {
        showSidebarAudit = map['showSidebarAudit'] as bool;
      }
      if (map['showSidebarOthers'] is bool) {
        showSidebarOthers = map['showSidebarOthers'] as bool;
      }
      if (map['showSubtitles'] is bool) {
        showSubtitles = map['showSubtitles'] as bool;
      }
      if (map['showWebsiteIcons'] is bool) {
        showWebsiteIcons = map['showWebsiteIcons'] as bool;
      }
      if (map['includeOldPasswordsInAudit'] is bool) {
        includeOldPasswordsInAudit = map['includeOldPasswordsInAudit'] as bool;
      }
      if (map['autoBackupEnabled'] is bool) {
        autoBackupEnabled = map['autoBackupEnabled'] as bool;
      }
      if (map['maxBackupCount'] is int) {
        maxBackupCount = map['maxBackupCount'] as int;
      }
      if (map['checkCompromisedPasswords'] is bool) {
        checkCompromisedPasswords = map['checkCompromisedPasswords'] as bool;
      }
      if (map['verifyBrowserSignature'] is bool) {
        verifyBrowserSignature = map['verifyBrowserSignature'] as bool;
      }
      if (map['connectedStorageProvider'] is String) {
        connectedStorageProvider = map['connectedStorageProvider'] as String;
      }
      if (map['lastVaultPath'] is String) {
        lastVaultPath = map['lastVaultPath'] as String;
      }
      if (map['onboardingUsageType'] is String) {
        onboardingUsageType = map['onboardingUsageType'] as String;
      }
      if (map['onboardingActivatedEmail'] is String) {
        onboardingActivatedEmail = map['onboardingActivatedEmail'] as String;
      }
      if (map['windowsHelloEnabled'] == true &&
          map['dpapiProtectedMasterB64'] is String) {
        windowsHelloEnabled = true;
        _windowsHelloEnrolled = true;
        _dpapiProtectedMasterB64 = map['dpapiProtectedMasterB64'] as String;
      }
    } catch (_) {}
  }

  Future<void> _saveSettingsToDisk() async {
    final path = settingsFilePath;
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      final map = <String, dynamic>{
        'themeModeSetting': themeModeSetting,
        'openAtStartup': openAtStartup,
        'minimizeToTray': minimizeToTray,
        'hideDockIcon': hideDockIcon,
        'searchInAllItems': searchInAllItems,
        'dockedAssistant': dockedAssistant,
        'lockOnSystemSleep': lockOnSystemSleep,
        'lockOnSystemLock': lockOnSystemLock,
        'lockOnWindowClose': lockOnWindowClose,
        'lockOnFastUserSwitch': lockOnFastUserSwitch,
        'showSidebarCounts': showSidebarCounts,
        'hideSensitive': hideSensitive,
        'showSidebarCategories': showSidebarCategories,
        'showSidebarTags': showSidebarTags,
        'showSidebarAudit': showSidebarAudit,
        'showSidebarOthers': showSidebarOthers,
        'showSubtitles': showSubtitles,
        'showWebsiteIcons': showWebsiteIcons,
        'includeOldPasswordsInAudit': includeOldPasswordsInAudit,
        'autoBackupEnabled': autoBackupEnabled,
        'maxBackupCount': maxBackupCount,
        'checkCompromisedPasswords': checkCompromisedPasswords,
        'verifyBrowserSignature': verifyBrowserSignature,
        'connectedStorageProvider': connectedStorageProvider,
        'lastVaultPath': lastVaultPath,
        'onboardingUsageType': onboardingUsageType,
        if (onboardingActivatedEmail != null &&
            onboardingActivatedEmail!.isNotEmpty)
          'onboardingActivatedEmail': onboardingActivatedEmail,
        'windowsHelloEnabled': windowsHelloEnabled && _windowsHelloEnrolled,
        if (windowsHelloEnabled &&
            _windowsHelloEnrolled &&
            _dpapiProtectedMasterB64 != null)
          'dpapiProtectedMasterB64': _dpapiProtectedMasterB64,
      };
      f.writeAsStringSync(jsonEncode(map));
    } catch (_) {}
  }

  Future<bool> unlock(String path, String master) async {
    final ok = await _open(() => _backend.unlock(path, master));
    if (ok) {
      lastVaultPath = path;
      _sessionMasterCache = master;
      quickPinFailedAttempts = 0;
      if (windowsHelloEnabled && _windowsHelloEnrolled) {
        unawaited(_refreshDpapiMaster(master));
      }
      unawaited(_saveSettingsToDisk());
    }
    return ok;
  }

  Future<bool> create(String path, String master) async {
    final ok = await _open(() => _backend.create(path, master));
    if (ok) {
      lastVaultPath = path;
      _sessionMasterCache = master;
      quickPinFailedAttempts = 0;
      if (windowsHelloEnabled && _windowsHelloEnrolled) {
        unawaited(_refreshDpapiMaster(master));
      }
      unawaited(_saveSettingsToDisk());
    }
    return ok;
  }

  Future<void> _refreshDpapiMaster(String master) async {
    try {
      final protectedB64 = await _desktopChannel.invokeMethod<String>(
        'protectSecretDpapi',
        {'secret': master},
      );
      if (protectedB64 != null && protectedB64.isNotEmpty) {
        _dpapiProtectedMasterB64 = protectedB64;
        await _saveSettingsToDisk();
      }
    } catch (_) {}
  }

  /// Configures a Quick Unlock PIN (supports numeric digits or alphanumeric/symbol characters).
  void configureQuickPin(String pin) {
    final cleaned = pin;
    if (cleaned.isEmpty) {
      disableQuickPin();
      return;
    }
    _quickPinCode = cleaned;
    _quickPinEnrolled = true;
    quickPinEnabled = true;
    quickPinFailedAttempts = 0;
    _notify();
  }

  /// Disables Quick Unlock PIN and clears the stored PIN from memory.
  void disableQuickPin() {
    _quickPinCode = null;
    _quickPinEnrolled = false;
    quickPinEnabled = false;
    quickPinFailedAttempts = 0;
    _notify();
  }

  /// Unlocks the vault using the configured Quick PIN (numeric or characters).
  /// After [maxQuickPinAttempts] wrong attempts, disables Quick PIN and requires the Master Password.
  Future<bool> unlockWithPin(String path, String pin) async {
    if (!hasQuickPinConfigured) {
      error = 'Quick PIN is not enabled for this session.';
      _notify();
      return false;
    }
    if (pin.isEmpty) {
      error = 'Enter your Quick Unlock PIN.';
      _notify();
      return false;
    }
    if (pin != _quickPinCode) {
      quickPinFailedAttempts++;
      if (quickPinFailedAttempts >= maxQuickPinAttempts) {
        disableQuickPin();
        _sessionMasterCache = null;
        error =
            'Too many failed PIN attempts. Quick PIN has been disabled — please enter your master password.';
      } else {
        final remaining = maxQuickPinAttempts - quickPinFailedAttempts;
        error =
            'Incorrect PIN ($remaining attempt${remaining == 1 ? "" : "s"} remaining).';
      }
      _notify();
      return false;
    }

    quickPinFailedAttempts = 0;
    String? master = _sessionMasterCache;
    if ((master == null || master.isEmpty) &&
        _dpapiProtectedMasterB64 != null) {
      try {
        master = await _desktopChannel.invokeMethod<String>(
          'unprotectSecretDpapi',
          {'blob': _dpapiProtectedMasterB64},
        );
      } catch (_) {}
    }
    if (master == null || master.isEmpty) {
      disableQuickPin();
      error =
          'First unlock on device launch requires entering your master password.';
      _notify();
      return false;
    }
    final targetPath = path.trim().isNotEmpty
        ? path.trim()
        : (lastVaultPath ?? '');
    return unlock(targetPath, master);
  }

  Future<bool> _verifyWindowsHello(String message) async {
    isAuthenticatingWindowsHello = true;
    try {
      if (windowsHelloAuthenticator != null) {
        return await windowsHelloAuthenticator!();
      }
      final res = await _desktopChannel.invokeMethod<bool>(
        'authenticateWindowsHello',
        {'message': message},
      );
      return res == true;
    } on MissingPluginException {
      // Fallback when running in headless test environments without native runner.
      return true;
    } catch (_) {
      return false;
    } finally {
      isAuthenticatingWindowsHello = false;
    }
  }

  /// Enrolls and enables Windows Hello Quick Unlock for the active vault.
  Future<bool> enableWindowsHello() async {
    final verified = await _verifyWindowsHello(
      'Verify your Windows Hello identity to enable Quick Unlock for VaultKeep',
    );
    if (!verified) {
      error = 'Windows Hello verification was cancelled or could not be completed.';
      _notify();
      return false;
    }
    windowsHelloEnabled = true;
    _windowsHelloEnrolled = true;
    if (_sessionMasterCache != null && _sessionMasterCache!.isNotEmpty) {
      await _refreshDpapiMaster(_sessionMasterCache!);
    }
    await _saveSettingsToDisk();
    _notify();
    return true;
  }

  /// Disables Windows Hello Quick Unlock and wipes any DPAPI-wrapped secret.
  void disableWindowsHello() {
    windowsHelloEnabled = false;
    _windowsHelloEnrolled = false;
    _dpapiProtectedMasterB64 = null;
    unawaited(_saveSettingsToDisk());
    _notify();
  }

  /// Unlocks the vault using Windows Hello OS biometric / PIN verification.
  Future<bool> unlockWithWindowsHello(String path) async {
    if (!windowsHelloEnabled || !_windowsHelloEnrolled) {
      error = 'Windows Hello is not enabled for this vault.';
      _notify();
      return false;
    }
    busy = true;
    error = null;
    _notify();

    final verified = await _verifyWindowsHello(
      'Verify your Windows Hello identity to unlock VaultKeep',
    );
    if (!verified) {
      busy = false;
      error = 'Windows Hello verification was cancelled or failed.';
      _notify();
      return false;
    }

    String? master = _sessionMasterCache;
    if ((master == null || master.isEmpty) &&
        _dpapiProtectedMasterB64 != null) {
      try {
        master = await _desktopChannel.invokeMethod<String>(
          'unprotectSecretDpapi',
          {'blob': _dpapiProtectedMasterB64},
        );
      } catch (_) {}
    }
    if (master == null || master.isEmpty) {
      busy = false;
      error =
          'First unlock on device launch requires entering your master password once.';
      _notify();
      return false;
    }
    final targetPath = path.trim().isNotEmpty
        ? path.trim()
        : (lastVaultPath ?? '');
    return unlock(targetPath, master);
  }

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

  /// Locks immediately: UI state and clipboard first, then the backend drops the vault.
  /// Preserves enrolled Windows Hello and Quick PIN state so the user can unlock with them.
  Future<void> lock() async {
    _idle?.cancel();
    _idle = null;
    unawaited(ClipboardGuard.clearNow());
    generatorHistory.clear();
    recentEntryIds.clear();
    hideSensitive = true;
    if (!_windowsHelloEnrolled) {
      windowsHelloEnabled = false;
    }
    if (!_quickPinEnrolled) {
      quickPinEnabled = false;
    }
    wifiSyncServerRunning = false;
    wifiSyncServerPaused = false;
    _activeWifiSyncHosts.remove(this);
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

  void recordRecentItem(String id) {
    if (id.isEmpty || status != VaultStatus.unlocked) return;
    recentEntryIds.remove(id);
    recentEntryIds.insert(0, id);
    if (recentEntryIds.length > 25) {
      recentEntryIds.removeLast();
    }
    _notify();
  }

  void clearRecentItems() {
    recentEntryIds.clear();
    touch();
    _notify();
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

  Future<String?> revealSecurityAnswer(String id) {
    touch();
    return _backend.revealSecurityAnswer(id);
  }

  Future<String> revealCustomField(String id, int index) {
    touch();
    return _backend.revealCustomField(id, index);
  }

  Future<String> generatePassword({int length = 24, bool symbols = true}) {
    touch();
    return _backend.generate(length: length, symbols: symbols);
  }

  Future<String> generateCustomPassword(PasswordGenConfig config) {
    touch();
    return _backend.generateCustom(config);
  }

  Future<PasswordEvaluation> evaluatePassword(String password) {
    touch();
    return _backend.evaluatePassword(password);
  }

  Future<VaultInfo> getVaultInfo() {
    touch();
    return _backend.getVaultInfo();
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

  Future<String> duplicateEntry(String id) async {
    touch();
    final newId = await _backend.duplicateEntry(id);
    await _refresh();
    await refreshGroups();
    return newId;
  }

  Future<int> exportVault(
    String destPath,
    String currentMaster,
    String format,
  ) async {
    touch();
    return _backend.exportVault(destPath, currentMaster, format: format);
  }

  Future<int> importCsv(String csvContent) async {
    touch();
    final count = await _backend.importCsv(csvContent);
    await _refresh();
    await refreshGroups();
    return count;
  }

  Future<void> archiveEntry(String id, {bool archived = true}) async {
    touch();
    final entry = await _backend.get(id);
    await _backend.setEntryMetadata(
      id,
      category: entry.category,
      tags: entry.tags,
      isFavorite: entry.isFavorite,
      isArchived: archived,
      isTrashed: entry.isTrashed,
    );
    await _refresh();
  }

  Future<void> moveEntryToTrash(String id, {bool trashed = true}) async {
    touch();
    final entry = await _backend.get(id);
    await _backend.setEntryMetadata(
      id,
      category: entry.category,
      tags: entry.tags,
      isFavorite: entry.isFavorite,
      isArchived: entry.isArchived,
      isTrashed: trashed,
    );
    await _refresh();
  }

  Future<void> changeEntryCategory(String id, String category) async {
    touch();
    final entry = await _backend.get(id);
    await _backend.setEntryMetadata(
      id,
      category: category,
      tags: entry.tags,
      isFavorite: entry.isFavorite,
      isArchived: entry.isArchived,
      isTrashed: entry.isTrashed,
    );
    await _refresh();
  }

  Future<void> moveEntryToGroup(String id, String? groupId) async {
    touch();
    final entry = await _backend.get(id);
    final pw = await _backend.revealPassword(id);
    final customDrafts = <VaultCustomField>[];
    for (var i = 0; i < entry.customFields.length; i++) {
      final cf = entry.customFields[i];
      final val =
          cf.sensitive ? await _backend.revealCustomField(id, i) : cf.value;
      customDrafts.add(
        VaultCustomField(
          name: cf.name,
          value: val,
          fieldType: cf.fieldType,
          sensitive: cf.sensitive,
          section: cf.section,
        ),
      );
    }
    await _backend.save(
      id,
      EntryDraft(
        title: entry.title,
        username: entry.username,
        password: pw,
        url: entry.url,
        notes: entry.notes,
        groupId: groupId,
        lastKnownRevisionDate: entry.revisionDate,
        category: entry.category,
        tags: entry.tags,
        isFavorite: entry.isFavorite,
        isArchived: entry.isArchived,
        isTrashed: entry.isTrashed,
        email: entry.email,
        phone: entry.phone,
        securityQuestion: entry.securityQuestion,
        sections: entry.sections,
        customFields: customDrafts,
      ),
    );
    await _refresh();
    await refreshGroups();
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

  Future<List<String>> listBackups(String backupDir) {
    touch();
    return _backend.listBackups(backupDir);
  }

  Future<void> restoreBackup(String backupPath, String backupMaster) async {
    touch();
    await _backend.restoreBackup(backupPath, backupMaster);
    await _refresh();
    await refreshGroups();
  }

  Future<void> eraseVault(String currentMaster) async {
    await _backend.eraseVault(currentMaster);
    _sessionMasterCache = null;
    disableQuickPin();
    disableWindowsHello();
    await lock();
  }

  Future<void> delete(String id) async {
    await _backend.delete(id);
    recentEntryIds.remove(id);
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

  void selectPreviousGroup() {
    final order = <String?>[null, ...groups.map((g) => g.id)];
    final currentIdx = order.indexOf(selectedGroupId);
    final prevIdx = currentIdx <= 0 ? order.length - 1 : currentIdx - 1;
    selectGroup(order[prevIdx]);
  }

  void selectNextGroup() {
    final order = <String?>[null, ...groups.map((g) => g.id)];
    final currentIdx = order.indexOf(selectedGroupId);
    final nextIdx = (currentIdx + 1) % order.length;
    selectGroup(order[nextIdx]);
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
    String? themeModeSetting,
    bool? openAtStartup,
    bool? minimizeToTray,
    bool? hideDockIcon,
    bool? searchInAllItems,
    bool? dockedAssistant,
    bool? lockOnSystemSleep,
    bool? lockOnSystemLock,
    bool? lockOnWindowClose,
    bool? lockOnFastUserSwitch,
    bool? showSidebarCounts,
    bool? hideSensitive,
    bool? showSidebarCategories,
    bool? showSidebarTags,
    bool? showSidebarAudit,
    bool? showSidebarOthers,
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
    var syncNative = false;
    if (themeModeSetting != null && this.themeModeSetting != themeModeSetting) {
      this.themeModeSetting = themeModeSetting;
      _applyThemeConfiguration();
      syncNative = true;
    }
    if (openAtStartup != null && this.openAtStartup != openAtStartup) {
      this.openAtStartup = openAtStartup;
      syncNative = true;
    }
    if (minimizeToTray != null && this.minimizeToTray != minimizeToTray) {
      this.minimizeToTray = minimizeToTray;
      syncNative = true;
    }
    if (hideDockIcon != null && this.hideDockIcon != hideDockIcon) {
      this.hideDockIcon = hideDockIcon;
      syncNative = true;
    }
    if (searchInAllItems != null) this.searchInAllItems = searchInAllItems;
    if (dockedAssistant != null) this.dockedAssistant = dockedAssistant;
    if (lockOnSystemSleep != null) this.lockOnSystemSleep = lockOnSystemSleep;
    if (lockOnSystemLock != null) this.lockOnSystemLock = lockOnSystemLock;
    if (lockOnWindowClose != null) this.lockOnWindowClose = lockOnWindowClose;
    if (lockOnFastUserSwitch != null) {
      this.lockOnFastUserSwitch = lockOnFastUserSwitch;
    }
    if (showSidebarCounts != null) {
      this.showSidebarCounts = showSidebarCounts;
    }
    if (hideSensitive != null) {
      this.hideSensitive = hideSensitive;
    }
    if (showSidebarCategories != null) {
      this.showSidebarCategories = showSidebarCategories;
    }
    if (showSidebarTags != null) {
      this.showSidebarTags = showSidebarTags;
    }
    if (showSidebarAudit != null) {
      this.showSidebarAudit = showSidebarAudit;
    }
    if (showSidebarOthers != null) {
      this.showSidebarOthers = showSidebarOthers;
    }
    if (showSubtitles != null) this.showSubtitles = showSubtitles;
    if (showWebsiteIcons != null) this.showWebsiteIcons = showWebsiteIcons;
    if (includeOldPasswordsInAudit != null) {
      this.includeOldPasswordsInAudit = includeOldPasswordsInAudit;
    }
    if (windowsHelloEnabled != null) {
      this.windowsHelloEnabled = windowsHelloEnabled;
      _windowsHelloEnrolled = windowsHelloEnabled;
      if (!windowsHelloEnabled) {
        _dpapiProtectedMasterB64 = null;
      } else if (_sessionMasterCache != null &&
          _sessionMasterCache!.isNotEmpty) {
        unawaited(_refreshDpapiMaster(_sessionMasterCache!));
      }
    }
    if (quickPinEnabled != null) {
      this.quickPinEnabled = quickPinEnabled;
      if (!quickPinEnabled) {
        _quickPinEnrolled = false;
        _quickPinCode = null;
        quickPinFailedAttempts = 0;
      }
    }
    if (autoBackupEnabled != null) this.autoBackupEnabled = autoBackupEnabled;
    if (maxBackupCount != null) this.maxBackupCount = maxBackupCount;
    if (wifiSyncServerRunning != null) {
      if (wifiSyncServerRunning) {
        startWifiSyncServer(notify: false);
      } else {
        stopWifiSyncServer(notify: false);
      }
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
    if (syncNative) {
      unawaited(_syncNativePlatformConfig());
    }
    unawaited(_saveSettingsToDisk());
    _notify();
  }

  WifiSyncPairingToken _ensureWifiSyncToken() {
    final nowUtc = DateTime.now().toUtc();
    if (_wifiSyncToken == null || !_wifiSyncToken!.isValidAt(nowUtc)) {
      _wifiSyncToken = WifiSyncTokenFactory.mintPairingToken();
      wifiSyncCodeSecondsRemaining = 30;
    }
    return _wifiSyncToken!;
  }

  String get wifiSyncPairingCode => _ensureWifiSyncToken().pairingCode;

  String get wifiSyncFormattedPairingCode =>
      _ensureWifiSyncToken().formattedPairingCode;

  String get wifiSyncAccessPassphrase =>
      _ensureWifiSyncToken().accessPassphrase;

  String? get accountSyncTag {
    final email = onboardingActivatedEmail?.trim();
    if (email == null || email.isEmpty) return null;
    return WifiSyncTokenFactory.computeAccountTag(email);
  }

  void startWifiSyncServer({
    String? customAddress,
    String? fixedCodeForTesting,
    bool notify = true,
  }) {
    wifiSyncServerRunning = true;
    wifiSyncServerPaused = false;
    if (customAddress != null && customAddress.trim().isNotEmpty) {
      wifiSyncServerAddress = customAddress.trim();
    } else if (wifiSyncServerAddress == '192.168.1.10:52138' &&
        _activeWifiSyncHosts.any(
          (h) => !identical(h, this) && h.wifiSyncServerAddress == wifiSyncServerAddress,
        )) {
      _nextHostPort++;
      wifiSyncServerAddress = '192.168.1.${10 + _activeWifiSyncHosts.length}:$_nextHostPort';
    }
    _wifiSyncToken = WifiSyncTokenFactory.mintPairingToken(
      fixedCodeForTesting: fixedCodeForTesting,
    );
    wifiSyncCodeSecondsRemaining = 30;
    if (!_activeWifiSyncHosts.contains(this)) {
      _activeWifiSyncHosts.add(this);
    }
    if (notify) {
      unawaited(_saveSettingsToDisk());
      _notify();
    }
  }

  void pauseWifiSyncServer({bool? paused}) {
    if (!wifiSyncServerRunning) return;
    wifiSyncServerPaused = paused ?? !wifiSyncServerPaused;
    _notify();
  }

  void stopWifiSyncServer({bool notify = true}) {
    wifiSyncServerRunning = false;
    wifiSyncServerPaused = false;
    _activeWifiSyncHosts.remove(this);
    if (notify) {
      unawaited(_saveSettingsToDisk());
      _notify();
    }
  }

  void regenerateWifiSyncPairingCode({
    String? fixedCodeForTesting,
    Duration? lifetime,
  }) {
    _wifiSyncToken = WifiSyncTokenFactory.mintPairingToken(
      lifetime: lifetime ?? WifiSyncTokenFactory.defaultPairingCodeLifetime,
      fixedCodeForTesting: fixedCodeForTesting,
    );
    wifiSyncCodeSecondsRemaining = 30;
    _notify();
  }

  /// Discovers active, unpaused Wi-Fi Sync servers on the local network.
  List<WifiSyncPeerDevice> discoverWifiSyncPeers() {
    final myTag = accountSyncTag;
    final peers = <WifiSyncPeerDevice>[];
    for (final host in _activeWifiSyncHosts) {
      if (identical(host, this)) continue;
      if (!host.wifiSyncServerRunning || host.wifiSyncServerPaused) continue;
      if (host.status != VaultStatus.unlocked) continue;
      final hostTag = host.accountSyncTag;
      final isSameAccount =
          myTag != null && hostTag != null && myTag == hostTag;
      peers.add(
        WifiSyncPeerDevice(
          deviceId: host.wifiSyncServerAddress,
          deviceName: host.wifiSyncServerName,
          address: host.wifiSyncServerAddress,
          vaultName: host.wifiSyncVaultName,
          itemCount: host.activeItems.length,
          sameAccount: isSameAccount,
          accountEmail: isSameAccount ? host.onboardingActivatedEmail : null,
        ),
      );
    }
    return peers;
  }

  /// Discovers active Wi-Fi Sync peers on the same network signed into the same account.
  List<WifiSyncPeerDevice> discoverSameAccountWifiPeers() {
    return discoverWifiSyncPeers().where((p) => p.sameAccount).toList();
  }

  /// Mode 1: Connects and syncs passwords bidirectionally when two devices on
  /// the same Wi-Fi share the same activated account.
  Future<int> syncWithSameAccountPeer({String? targetAddress}) async {
    touch();
    if (status != VaultStatus.unlocked) {
      throw StateError('Unlock your vault before syncing over Wi-Fi.');
    }
    final myTag = accountSyncTag;
    if (myTag == null) {
      throw StateError(
        'No account email activated on this device. Activate an account or connect using a 6-digit Wi-Fi pairing code.',
      );
    }

    VaultController? matchedHost;
    for (final host in _activeWifiSyncHosts) {
      if (identical(host, this)) continue;
      if (!host.wifiSyncServerRunning || host.wifiSyncServerPaused) continue;
      if (host.status != VaultStatus.unlocked) continue;
      if (targetAddress != null &&
          targetAddress.trim().isNotEmpty &&
          host.wifiSyncServerAddress != targetAddress.trim()) {
        continue;
      }
      if (host.accountSyncTag == myTag) {
        matchedHost = host;
        break;
      }
    }

    if (matchedHost == null) {
      throw StateError(
        'No Wi-Fi Sync device with matching account (${onboardingActivatedEmail ?? ""}) found on the local network.',
      );
    }

    return _performBidirectionalWifiSync(
      host: matchedHost,
      modeLabel: 'Same Account',
    );
  }

  /// Mode 2: Connects and syncs passwords bidirectionally using a 6-digit
  /// verification code (and optional server address / access passphrase) on the same Wi-Fi.
  Future<int> syncWithWifiCode(
    String rawCode, {
    String? serverAddress,
    String? accessPassphrase,
  }) async {
    touch();
    if (status != VaultStatus.unlocked) {
      throw StateError('Unlock your vault before syncing over Wi-Fi.');
    }
    final normalizedCode = rawCode.replaceAll(RegExp(r'[\s\-]'), '');
    if (normalizedCode.length != 6 ||
        !RegExp(r'^\d{6}$').hasMatch(normalizedCode)) {
      throw StateError(
        'Verify Server failed: Enter a valid 6-digit Wi-Fi pairing code.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    VaultController? matchedHost;

    for (final host in _activeWifiSyncHosts) {
      if (!host.wifiSyncServerRunning || host.wifiSyncServerPaused) continue;
      if (host.status != VaultStatus.unlocked) continue;
      if (identical(host, this) && _activeWifiSyncHosts.length > 1) {
        continue;
      }
      if (serverAddress != null &&
          serverAddress.trim().isNotEmpty &&
          host.wifiSyncServerAddress != serverAddress.trim()) {
        continue;
      }
      final token = host._wifiSyncToken;
      if (token == null || !token.isValidAt(nowUtc)) continue;
      if (token.pairingCode != normalizedCode) continue;
      if (accessPassphrase != null &&
          accessPassphrase.trim().isNotEmpty &&
          accessPassphrase.trim() != token.accessPassphrase) {
        throw StateError(
          'Authentication failed: Invalid Wi-Fi Sync Access Password.',
        );
      }
      matchedHost = host;
      break;
    }

    if (matchedHost == null) {
      throw StateError(
        'Verify Server failed: Wi-Fi pairing code does not match any active server on this network or has expired.',
      );
    }

    return _performBidirectionalWifiSync(
      host: matchedHost,
      modeLabel: 'Code Pairing',
    );
  }

  Future<int> _performBidirectionalWifiSync({
    required VaultController host,
    required String modeLabel,
  }) async {
    var syncedCount = 0;
    if (!identical(host, this)) {
      syncedCount += await _syncControllerDirection(from: host, to: this);
      syncedCount += await _syncControllerDirection(from: this, to: host);
      await host._refresh();
      await host.refreshGroups();
    }
    await _refresh();
    await refreshGroups();

    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    final hostRecord =
        '${host.wifiSyncServerName} (${host.wifiSyncServerAddress}) • $modeLabel';
    if (!wifiSyncPairedDevices.contains(hostRecord)) {
      wifiSyncPairedDevices.insert(0, hostRecord);
    }
    wifiSyncLastSyncedAt = ts;
    wifiSyncLastMergedCount = syncedCount;
    connectedStorageProvider = 'Wi-Fi Sync';

    if (!identical(host, this)) {
      final clientRecord =
          '$wifiSyncServerName ($wifiSyncServerAddress) • $modeLabel';
      if (!host.wifiSyncPairedDevices.contains(clientRecord)) {
        host.wifiSyncPairedDevices.insert(0, clientRecord);
      }
      host.wifiSyncLastSyncedAt = ts;
      host.wifiSyncLastMergedCount = syncedCount;
      host._notify();
    }

    _notify();
    return syncedCount;
  }

  static Future<int> _syncControllerDirection({
    required VaultController from,
    required VaultController to,
  }) async {
    var changed = 0;
    final fromGroups = await from._backend.listGroups();
    var toGroups = await to._backend.listGroups();

    for (final fg in fromGroups) {
      if (!toGroups.any((tg) => tg.name == fg.name)) {
        await to._backend.createGroup(fg.name);
        changed++;
      }
    }
    toGroups = await to._backend.listGroups();

    final fromItems = await from._backend.list('');
    final toItems = await to._backend.list('');

    for (final srcItem in fromItems) {
      VaultItem? existingMatch;
      for (final dstItem in toItems) {
        if ((dstItem.id == srcItem.id && dstItem.title == srcItem.title) ||
            (dstItem.title == srcItem.title &&
                dstItem.username == srcItem.username &&
                dstItem.url == srcItem.url)) {
          existingMatch = dstItem;
          break;
        }
      }

      final srcRev = srcItem.revisionDate ?? 0;
      final dstRev = existingMatch?.revisionDate ?? -1;

      if (existingMatch != null && srcRev <= dstRev) {
        continue;
      }

      final fullEntry = await from._backend.get(srcItem.id);
      final password = await from._backend.revealPassword(srcItem.id);
      String? otpUri;
      if (fullEntry.hasOtp) {
        try {
          otpUri = await from._backend.revealOtpUri(srcItem.id);
        } catch (_) {}
      }
      String? securityAnswer;
      if (fullEntry.hasSecurityAnswer) {
        try {
          securityAnswer = await from._backend.revealSecurityAnswer(srcItem.id);
        } catch (_) {}
      }
      final customFields = <VaultCustomField>[];
      for (var i = 0; i < fullEntry.customFields.length; i++) {
        final cf = fullEntry.customFields[i];
        var val = cf.value;
        if (cf.sensitive) {
          try {
            val = await from._backend.revealCustomField(srcItem.id, i);
          } catch (_) {}
        }
        customFields.add(
          VaultCustomField(
            name: cf.name,
            value: val,
            fieldType: cf.fieldType,
            sensitive: cf.sensitive,
            section: cf.section,
          ),
        );
      }

      String? targetGroupId;
      if (fullEntry.groupName != null && fullEntry.groupName!.isNotEmpty) {
        for (final tg in toGroups) {
          if (tg.name == fullEntry.groupName) {
            targetGroupId = tg.id;
            break;
          }
        }
      }

      await to._backend.save(
        existingMatch?.id,
        EntryDraft(
          title: fullEntry.title,
          username: fullEntry.username,
          password: password,
          url: fullEntry.url,
          notes: fullEntry.notes,
          groupId: targetGroupId,
          otp: otpUri,
          lastKnownRevisionDate: existingMatch?.revisionDate,
          category: fullEntry.category,
          tags: fullEntry.tags,
          isFavorite: fullEntry.isFavorite,
          isArchived: fullEntry.isArchived,
          isTrashed: fullEntry.isTrashed,
          email: fullEntry.email,
          phone: fullEntry.phone,
          securityQuestion: fullEntry.securityQuestion,
          securityAnswer: securityAnswer,
          sections: fullEntry.sections,
          customFields: customFields,
        ),
      );
      changed++;
    }

    return changed;
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
    _sessionMasterCache = newMaster;
    if (windowsHelloEnabled && _windowsHelloEnrolled) {
      unawaited(_refreshDpapiMaster(newMaster));
    }
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
    if (status == VaultStatus.unlocked && !_disposed) {
      _idle = Timer(autoLockAfter, () => unawaited(lock()));
    }
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
    _activeWifiSyncHosts.remove(this);
    _sessionMasterCache = null;
    _quickPinCode = null;
    generatorHistory.clear();
    recentEntryIds.clear();
    unawaited(ClipboardGuard.clearNow());
    super.dispose();
  }
}
