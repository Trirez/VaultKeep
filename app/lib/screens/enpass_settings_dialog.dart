import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../backend.dart';
import '../clipboard_guard.dart';
import '../theme.dart';
import '../vault_controller.dart';

/// Enpass 1:1 8-Tab Settings Dialog (`Enpass_qsehQ4O46P.png` – `Enpass_Phx22T1g3k.png`).
class EnpassSettingsDialog extends StatefulWidget {
  const EnpassSettingsDialog({
    super.key,
    required this.controller,
    required this.onChangeMasterPassword,
    required this.onSyncVault,
    this.initialTab = 0,
  });

  final VaultController controller;
  final VoidCallback onChangeMasterPassword;
  final VoidCallback onSyncVault;
  final int initialTab;

  static Future<void> show(
    BuildContext context, {
    required VaultController controller,
    required VoidCallback onChangeMasterPassword,
    required VoidCallback onSyncVault,
    int initialTab = 0,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => EnpassSettingsDialog(
        controller: controller,
        onChangeMasterPassword: onChangeMasterPassword,
        onSyncVault: onSyncVault,
        initialTab: initialTab,
      ),
    );
  }

  @override
  State<EnpassSettingsDialog> createState() => _EnpassSettingsDialogState();
}

class _EnpassSettingsDialogState extends State<EnpassSettingsDialog> {
  late int _selectedTab = widget.initialTab.clamp(0, _tabs.length - 1);
  int? _hoveredTab;
  String? _hoveredProvider;
  bool _selectingStorageForNewVault = false;
  bool _autofillInBrowsers = true;
  bool _fillAndSubmitAuto = false;
  bool _showMenuOnFocus = true;
  bool _askUnverifiedBrowser = true;
  bool _disableSslPinning = false;
  bool _checkClipboard = true;
  bool _autoCheckUpdates = true;
  bool _checkForAlerts = true;
  bool _enableLogs = false;
  VaultInfo? _vaultInfo;
  List<String> _backups = const [];
  final _wifiCodeCtrl = TextEditingController();
  final _wifiAddressCtrl = TextEditingController();
  final _wifiAccessPassCtrl = TextEditingController();
  String? _wifiSyncStatusBanner;
  bool _wifiSyncIsError = false;

  @override
  void dispose() {
    _wifiCodeCtrl.text = '';
    _wifiAddressCtrl.text = '';
    _wifiAccessPassCtrl.text = '';
    _wifiCodeCtrl.dispose();
    _wifiAddressCtrl.dispose();
    _wifiAccessPassCtrl.dispose();
    super.dispose();
  }

  Future<bool> _promptConfigurePinDialog() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _QuickPinSetupDialog(),
    );
    if (pin != null && pin.length >= 4) {
      c.configureQuickPin(pin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quick Unlock PIN enabled for this vault.'),
          ),
        );
      }
      return true;
    }
    return false;
  }

  static const List<({String label, IconData icon})> _tabs = [
    (label: 'General', icon: Icons.tune),
    (label: 'Vaults', icon: Icons.enhanced_encryption_outlined),
    (label: 'Security', icon: Icons.security_outlined),
    (label: 'Customize', icon: Icons.palette_outlined),
    (label: 'Autofill', icon: Icons.extension_outlined),
    (label: 'Backup', icon: Icons.backup_outlined),
    (label: 'Wi-Fi Sync', icon: Icons.wifi_tethering),
    (label: 'Advanced', icon: Icons.build_outlined),
    (label: 'About', icon: Icons.info_outline),
  ];

  static const List<({String name, String subtitle, IconData icon, bool isCloud})>
      _storageProviders = [
    (
      name: 'OneDrive',
      subtitle: 'Microsoft OneDrive Cloud Sync',
      icon: Icons.cloud_outlined,
      isCloud: true,
    ),
    (
      name: 'Google Drive',
      subtitle: 'Google Drive Encrypted Sync',
      icon: Icons.add_to_drive,
      isCloud: true,
    ),
    (
      name: 'iCloud',
      subtitle: 'Apple iCloud Drive Vault',
      icon: Icons.cloud_circle_outlined,
      isCloud: true,
    ),
    (
      name: 'Dropbox',
      subtitle: 'Dropbox App Folder Sync',
      icon: Icons.inventory_2_outlined,
      isCloud: true,
    ),
    (
      name: 'Box',
      subtitle: 'Box Enterprise Cloud Storage',
      icon: Icons.all_inbox_outlined,
      isCloud: true,
    ),
    (
      name: 'WebDAV',
      subtitle: 'Self-hosted WebDAV / OwnCloud',
      icon: Icons.dns_outlined,
      isCloud: true,
    ),
    (
      name: 'NextCloud',
      subtitle: 'NextCloud Private Instance',
      icon: Icons.cloud_done_outlined,
      isCloud: true,
    ),
    (
      name: 'Wi-Fi Sync',
      subtitle: 'Local LAN SRP-6a Encrypted Sync',
      icon: Icons.wifi_tethering,
      isCloud: false,
    ),
    (
      name: 'Folder Sync',
      subtitle: 'Local or Network Folder Replica (.kdbx)',
      icon: Icons.folder_copy_outlined,
      isCloud: false,
    ),
    (
      name: 'This PC',
      subtitle: 'Offline Local KDBX4 Vault on Disk',
      icon: Icons.computer_outlined,
      isCloud: false,
    ),
  ];

  VaultController get c => widget.controller;

  String get _defaultBackupDir =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}vaultkeep_backups';

  @override
  void initState() {
    super.initState();
    unawaited(_loadVaultDiagnostics());
  }

  Future<void> _loadVaultDiagnostics() async {
    try {
      final info = await c.getVaultInfo();
      final backups = await c.listBackups(_defaultBackupDir);
      if (!mounted) return;
      setState(() {
        _vaultInfo = info;
        _backups = backups;
      });
    } catch (_) {}
  }

  Future<void> _triggerBackupNow() async {
    try {
      final path = await c.createBackup(_defaultBackupDir);
      final backups = await c.listBackups(_defaultBackupDir);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Encrypted backup created: $path')),
      );
      setState(() {
        _backups = backups;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(VaultController.describe(e))),
      );
    }
  }

  Future<void> _restoreFromBackupSnapshot(String backupPath) async {
    try {
      await c.restoreBackup(backupPath, '');
      await _loadVaultDiagnostics();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vault restored from snapshot: $backupPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(VaultController.describe(e))),
      );
    }
  }

  Future<void> _confirmEraseEverything() async {
    final masterCtrl = TextEditingController();
    final confirmedMaster = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('settings_erase_vault_confirm_dialog'),
        title: const Text('Erase Everything?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This permanently deletes the active encrypted KDBX4 vault file from disk and locks the session. Enter your Master Password to confirm:',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('settings_erase_vault_password_field'),
              controller: masterCtrl,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              decoration: const InputDecoration(
                labelText: 'Master Password',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('settings_erase_vault_confirm_button'),
            style: FilledButton.styleFrom(
              backgroundColor: TacticalTheme.crimsonDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(masterCtrl.text),
            child: const Text('Erase Vault'),
          ),
        ],
      ),
    );
    masterCtrl.text = '';
    masterCtrl.dispose();
    if (confirmedMaster == null || confirmedMaster.isEmpty || !mounted) return;
    try {
      await c.eraseVault(confirmedMaster);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(VaultController.describe(e))),
      );
    }
  }


  Widget _buildStorageTile(({String name, String subtitle, IconData icon, bool isCloud}) p) {
    final isSelected = c.connectedStorageProvider == p.name;
    final isHovered = _hoveredProvider == p.name;
    return InkWell(
      key: ValueKey('storage_provider_${p.name}'),
      borderRadius: BorderRadius.circular(8),
      onHover: (v) => setState(() {
        if (v) {
          _hoveredProvider = p.name;
        } else if (_hoveredProvider == p.name) {
          _hoveredProvider = null;
        }
      }),
      onTap: () {
        c.updateSettings(connectedStorageProvider: p.name);
        setState(() {
          _selectingStorageForNewVault = false;
          if (p.name == 'Wi-Fi Sync') {
            _selectedTab = 6;
          }
        });
        if (p.name == 'Folder Sync') {
          Navigator.of(context).pop();
          widget.onSyncVault();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Primary vault storage target set to ${p.name}.',
              ),
            ),
          );
        }
      },
      child: Container(
        width: 108,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isHovered ? TacticalTheme.bgHover : TacticalTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: (isSelected || isHovered)
                ? TacticalTheme.amberPrimary
                : TacticalTheme.borderTech,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isHovered ? TacticalTheme.borderGlow : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: TacticalTheme.bgDeepCarbon,
                shape: BoxShape.circle,
                border: Border.all(
                  color: (isSelected || isHovered)
                      ? TacticalTheme.amberPrimary
                      : TacticalTheme.borderSubtle,
                ),
              ),
              child: Icon(
                p.icon,
                color: (isSelected || isHovered)
                    ? TacticalTheme.amberBright
                    : TacticalTheme.cyanTactical,
                size: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              p.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isHovered
                    ? TacticalTheme.amberBright
                    : TacticalTheme.textPrimary,
                shadows: isHovered ? TacticalTheme.textGlow : null,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVaultsTab() {
    if (_selectingStorageForNewVault) {
      final cloudProviders =
          _storageProviders.where((p) => p.isCloud).toList();
      final nonCloudProviders =
          _storageProviders.where((p) => !p.isCloud).toList();

      return Column(
        key: const ValueKey('settings_vault_select_storage'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to Vaults',
                icon: const Icon(Icons.arrow_back, size: 18),
                onPressed: () =>
                    setState(() => _selectingStorageForNewVault = false),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Select Storage to Create or Restore Vault',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: TacticalTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _SectionHeader('CLOUD'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final p in cloudProviders) _buildStorageTile(p),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionHeader('NON-CLOUD'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final p in nonCloudProviders) _buildStorageTile(p),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Vault Header (`Enpass_Phx22T1g3k.png`)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TacticalTheme.bgSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: TacticalTheme.borderTech, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: TacticalTheme.amberDim,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: TacticalTheme.amberPrimary,
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.lock_person_outlined,
                  color: TacticalTheme.amberBright,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Primary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: TacticalTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '${c.activeItems.length} Items',
                      style: TacticalTheme.monoStyle(
                        fontSize: 11,
                        color: TacticalTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('settings_button_add_new_vault'),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add New Vault'),
                onPressed: () =>
                    setState(() => _selectingStorageForNewVault = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // SYNC INFO Card (`Enpass_Phx22T1g3k.png`)
        const _SectionHeader('SYNC INFO'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TacticalTheme.bgSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: TacticalTheme.borderTech, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cloud_done_outlined,
                    color: TacticalTheme.cyanTactical,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Synchronizing with ${c.connectedStorageProvider}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: TacticalTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'Last Synchronized: Today • Last Attempt: Just now',
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            color: TacticalTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.sync, size: 15),
                    label: const Text('Sync Now (3-Way Merge)'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onSyncVault();
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_queue, size: 15),
                    label: const Text('Change Storage Provider'),
                    onPressed: () =>
                        setState(() => _selectingStorageForNewVault = true),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // VAULT INFO Card (`Enpass_Phx22T1g3k.png`)
        const _SectionHeader('VAULT INFO'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TacticalTheme.bgSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: TacticalTheme.borderTech, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Vault Location',
                    style: TextStyle(
                      fontSize: 13,
                      color: TacticalTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _vaultInfo?.path.isNotEmpty == true
                          ? _vaultInfo!.path
                          : 'Encrypted KDBX4 Container',
                      style: TacticalTheme.monoStyle(
                        fontSize: 11,
                        color: TacticalTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Divider(height: 20, color: TacticalTheme.borderSubtle),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Master Password',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: TacticalTheme.textPrimary,
                          ),
                        ),
                        Text(
                          _vaultInfo != null
                              ? 'Argon2id (${_vaultInfo!.kdfMemoryMib} MiB, ${_vaultInfo!.kdfIterations} iters, ${_vaultInfo!.kdfParallelism} lanes) • ChaCha20-Poly1305'
                              : 'Argon2id Key Derivation • ChaCha20-Poly1305',
                          style: TextStyle(
                            fontSize: 11,
                            color: TacticalTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.vpn_key_outlined, size: 15),
                    label: const Text('Change Master Password'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onChangeMasterPassword();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThemeOptionCard({
    required String label,
    required IconData icon,
    required Color previewBg,
    required Color previewSurface,
  }) {
    final selected = c.themeModeSetting == label;
    return Expanded(
      child: InkWell(
        key: ValueKey('settings_theme_$label'),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          c.updateSettings(themeModeSetting: label);
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: TacticalTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? TacticalTheme.amberPrimary
                  : TacticalTheme.borderTech,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: previewBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: TacticalTheme.borderSubtle),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      decoration: BoxDecoration(
                        color: previewSurface,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(3),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Icon(
                          icon,
                          size: 16,
                          color: selected
                              ? TacticalTheme.amberBright
                              : TacticalTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) ...[
                    Icon(
                      Icons.check_circle,
                      size: 14,
                      color: TacticalTheme.amberPrimary,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? TacticalTheme.amberBright
                            : TacticalTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0: // General (`Enpass_s93PhrrNLy.png`)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('RUN'),
            SwitchListTile(
              key: const ValueKey('settings_switch_open_at_startup'),
              title: const Text('Open Automatically at System Startup'),
              subtitle: const Text(
                'Launch VaultKeep minimized in background on boot',
              ),
              value: c.openAtStartup,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(openAtStartup: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              key: const ValueKey('settings_switch_minimize_to_tray'),
              title: const Text('Minimize App to System Tray'),
              subtitle: const Text(
                'Keep quick-access icon in the system notification area',
              ),
              value: c.minimizeToTray,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(minimizeToTray: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              key: const ValueKey('settings_switch_hide_dock_icon'),
              title: const Text('Hide Dock Icon When Main Window is Closed'),
              subtitle: const Text(
                'Minimize to hidden icons / tray instead of exiting when closed',
              ),
              value: c.hideDockIcon,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(hideDockIcon: v);
                setState(() {});
              },
            ),
            const Divider(height: 24),
            const _SectionHeader('BEHAVIOR'),
            SwitchListTile(
              title: const Text('Search in All Items'),
              subtitle: const Text(
                'Include all categories when searching from sidebar filters',
              ),
              value: c.searchInAllItems,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(searchInAllItems: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text('Always run Assistant in docked mode'),
              value: c.dockedAssistant,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(dockedAssistant: v);
                setState(() {});
              },
            ),
            ListTile(
              title: const Text('System-wide Hotkey'),
              subtitle: const Text('Summon VaultKeep Mini Assistant anywhere'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: TacticalTheme.bgDeepCarbon,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: TacticalTheme.borderTech),
                ),
                child: Text(
                  r'Ctrl + Alt + \',
                  style: TacticalTheme.monoStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: TacticalTheme.amberBright,
                  ),
                ),
              ),
            ),
            const Divider(height: 24),
            const _SectionHeader('LANGUAGE'),
            ListTile(
              title: const Text('Choose Language'),
              subtitle: Text(
                'System Default (English)',
                style: TacticalTheme.monoStyle(
                  fontSize: 11,
                  color: TacticalTheme.cyanTactical,
                ),
              ),
            ),
          ],
        );

      case 1: // Vaults (`Enpass_Phx22T1g3k.png` & `Enpass_lOdDigGaYv.png`)
        return _buildVaultsTab();

      case 2: // Security (`Enpass_Klr1jH4sgQ.png`)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('QUICK UNLOCK'),
            SwitchListTile(
              key: const ValueKey('settings_switch_windows_hello'),
              title: const Text('Windows Hello'),
              subtitle: const Text(
                'Unlock Primary vault using OS TPM / Biometric verification',
              ),
              value: c.windowsHelloEnabled,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) async {
                if (v) {
                  await c.enableWindowsHello();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Windows Hello Quick Unlock enabled for this vault.',
                        ),
                      ),
                    );
                  }
                } else {
                  c.disableWindowsHello();
                }
                if (mounted) setState(() {});
              },
            ),
            SwitchListTile(
              key: const ValueKey('settings_switch_quick_pin'),
              title: const Text('PIN'),
              subtitle: Text(
                c.hasQuickPinConfigured
                    ? 'Quick Unlock PIN configured (supports numbers or characters)'
                    : 'Unlock quickly using numeric digits or characters when locked',
              ),
              value: c.quickPinEnabled,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) async {
                if (v) {
                  await _promptConfigurePinDialog();
                } else {
                  c.disableQuickPin();
                }
                if (mounted) setState(() {});
              },
            ),
            if (c.quickPinEnabled)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const ValueKey('settings_button_change_pin'),
                    icon: const Icon(Icons.pin_outlined, size: 15),
                    label: const Text('Change Quick Unlock PIN'),
                    onPressed: () async {
                      await _promptConfigurePinDialog();
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ),
            const Divider(height: 24),
            const _SectionHeader('MASTER PASSWORD'),
            ListTile(
              title: const Text('Change Master Password'),
              subtitle: const Text(
                'Atomically re-encrypt KDBX4 vault and advance item revisions',
              ),
              trailing: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onChangeMasterPassword();
                },
                child: const Text('Change'),
              ),
            ),
            const Divider(height: 24),
            const _SectionHeader('AUTOLOCK WHEN'),
            ListTile(
              leading: Icon(
                Icons.timer_outlined,
                color: TacticalTheme.amberPrimary,
              ),
              title: const Text('System is Idle for'),
              trailing: Text(
                '${c.autoLockAfter.inMinutes} minutes',
                style: TacticalTheme.monoStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: TacticalTheme.amberBright,
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('Main Window is Closed'),
              value: c.lockOnWindowClose,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(lockOnWindowClose: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text('System Sleeps'),
              value: c.lockOnSystemSleep,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(lockOnSystemSleep: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text('System Locks'),
              value: c.lockOnSystemLock,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(lockOnSystemLock: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text('Fast User Switching'),
              value: c.lockOnFastUserSwitch,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(lockOnFastUserSwitch: v);
                setState(() {});
              },
            ),
            const Divider(height: 24),
            const _SectionHeader('CLIPBOARD'),
            ListTile(
              title: const Text('Clear Clipboard After'),
              subtitle: const Text(
                'Automatically scrubs copied passwords and TOTP codes',
              ),
              trailing: Text(
                '15 seconds',
                style: TacticalTheme.monoStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: TacticalTheme.emeraldReady,
                ),
              ),
            ),
          ],
        );

      case 3: // Customize (`Enpass_67kaj69rme.png`)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('APPEARANCE'),
            Row(
              children: [
                _buildThemeOptionCard(
                  label: 'Follow System',
                  icon: Icons.brightness_auto_outlined,
                  previewBg: c.systemIsLight
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFF10121A),
                  previewSurface: c.systemIsLight
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFF1E2233),
                ),
                const SizedBox(width: 10),
                _buildThemeOptionCard(
                  label: 'Light',
                  icon: Icons.light_mode_outlined,
                  previewBg: const Color(0xFFF8FAFC),
                  previewSurface: const Color(0xFFE2E8F0),
                ),
                const SizedBox(width: 10),
                _buildThemeOptionCard(
                  label: 'Dark',
                  icon: Icons.dark_mode_outlined,
                  previewBg: const Color(0xFF090A0F),
                  previewSurface: const Color(0xFF10121A),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              c.themeModeSetting == 'Follow System'
                  ? 'Following OS theme (${c.systemIsLight ? 'Light' : 'Dark'}) and system accent color'
                  : 'Active Theme: ${c.themeModeSetting} Mode',
              style: TacticalTheme.monoStyle(
                fontSize: 11,
                color: TacticalTheme.textSecondary,
              ),
            ),
            const Divider(height: 24),
            const _SectionHeader('SIDEBAR'),
            SwitchListTile(
              key: const ValueKey('settings_switch_sidebar_counts'),
              title: const Text('Show Item Counts'),
              value: c.showSidebarCounts,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(showSidebarCounts: v);
                setState(() {});
              },
            ),
            const Divider(height: 24),
            const _SectionHeader('ITEMS'),
            SwitchListTile(
              key: const ValueKey('settings_switch_show_subtitles'),
              title: const Text('Show Subtitles'),
              value: c.showSubtitles,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(showSubtitles: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              key: const ValueKey('settings_switch_old_passwords_audit'),
              title: const Text('Include Old Passwords in Audit'),
              subtitle: const Text(
                'Show 3-6 Months, 6-12 Months, and 1-3 Years filters in Sidebar Audit',
              ),
              value: c.includeOldPasswordsInAudit,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(includeOldPasswordsInAudit: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text('Show Website Icons'),
              subtitle: const Text(
                'Offline zero-network brand avatar badges (Zero IP leakage)',
              ),
              value: c.showWebsiteIcons,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(showWebsiteIcons: v);
                setState(() {});
              },
            ),
            const Divider(height: 24),
            const _SectionHeader('CATEGORIES & TEMPLATES'),
            ListTile(
              leading: Icon(
                Icons.category_outlined,
                color: TacticalTheme.amberPrimary,
              ),
              title: const Text('Manage Categories'),
              subtitle: Text('${kEnpassCategories.length} active categories'),
              trailing: const Icon(Icons.chevron_right),
            ),
            ListTile(
              leading: Icon(
                Icons.dashboard_customize_outlined,
                color: TacticalTheme.cyanTactical,
              ),
              title: const Text('Add Custom Templates'),
              subtitle: const Text('Create custom item templates & sections'),
              trailing: const Icon(Icons.chevron_right),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final cat in kEnpassCategories)
                  Chip(
                    label: Text('$cat (${c.categoryCount(cat)})'),
                  ),
              ],
            ),
          ],
        );

      case 4: // Autofill (`Enpass_7BxQCDo7er.png`)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('BROWSER EXTENSIONS'),
            SwitchListTile(
              title: const Text('Autofill in Browsers'),
              subtitle: const Text(
                'Communicate with browser extension over authenticated localhost channel',
              ),
              value: _autofillInBrowsers,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _autofillInBrowsers = v),
            ),
            SwitchListTile(
              title: const Text('Fill and Submit Automatically'),
              value: _fillAndSubmitAuto,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _fillAndSubmitAuto = v),
            ),
            SwitchListTile(
              title: const Text('Show Autofill Menu on Field Focus'),
              value: _showMenuOnFocus,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _showMenuOnFocus = v),
            ),
            ListTile(
              title: const Text('Keyboard Shortcut'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: TacticalTheme.bgDeepCarbon,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: TacticalTheme.borderTech),
                ),
                child: Text(
                  'Ctrl + /',
                  style: TacticalTheme.monoStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: TacticalTheme.cyanTactical,
                  ),
                ),
              ),
            ),
            const Divider(height: 24),
            const _SectionHeader('BROWSER AUTHENTICATION'),
            SwitchListTile(
              title: const Text('Verify Browser Code Signature'),
              subtitle: const Text(
                'Validate Authenticode / OS code signature of connecting browsers',
              ),
              value: c.verifyBrowserSignature,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(verifyBrowserSignature: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text(
                'Ask for Confirmation When Unverified Browser Connects',
              ),
              value: _askUnverifiedBrowser,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _askUnverifiedBrowser = v),
            ),
            ListTile(
              leading: Icon(
                Icons.verified_user_outlined,
                color: TacticalTheme.emeraldReady,
              ),
              title: const Text('Authorized Browsers'),
              subtitle: const Text('Chrome, Edge, Firefox, Brave (Verified)'),
            ),
          ],
        );

      case 5: // Backup (`Enpass_1o1M4IhFW9.png`)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('AUTO BACKUPS'),
            SwitchListTile(
              title: const Text('Backup Automatically'),
              subtitle: Text(
                'Retain up to ${c.maxBackupCount} encrypted KDBX4 snapshots on disk',
              ),
              value: c.autoBackupEnabled,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(autoBackupEnabled: v);
                setState(() {});
              },
            ),
            ListTile(
              leading: Icon(
                Icons.folder_outlined,
                color: TacticalTheme.amberPrimary,
              ),
              title: const Text('Location'),
              subtitle: Text(
                _defaultBackupDir,
                style: TacticalTheme.monoStyle(
                  fontSize: 11,
                  color: TacticalTheme.textSecondary,
                ),
              ),
            ),
            const Divider(height: 24),
            const _SectionHeader('PREVIOUS BACKUPS'),
            if (c.lastBackupPath != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Text(
                  'Latest snapshot: ${c.lastBackupPath}',
                  style: TacticalTheme.monoStyle(
                    fontSize: 11,
                    color: TacticalTheme.emeraldReady,
                  ),
                ),
              )
            else if (_backups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Text(
                  'No automatic backups recorded in this session yet.',
                  style: TacticalTheme.monoStyle(
                    fontSize: 11,
                    color: TacticalTheme.textMuted,
                  ),
                ),
              ),
            if (_backups.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (var i = 0; i < _backups.take(5).length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: TacticalTheme.bgSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: TacticalTheme.borderTech),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.archive_outlined,
                        size: 16,
                        color: TacticalTheme.cyanTactical,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _backups[i].split(RegExp(r'[/\\]')).last,
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            color: TacticalTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        key: ValueKey('settings_restore_backup_$i'),
                        icon: const Icon(Icons.restore, size: 14),
                        label: const Text('Restore'),
                        onPressed: () =>
                            _restoreFromBackupSnapshot(_backups[i]),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  key: const ValueKey('settings_button_backup_now'),
                  icon: const Icon(Icons.save_alt, size: 16),
                  label: const Text('Backup Now'),
                  onPressed: _triggerBackupNow,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('Restore From Backup (Merge)'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onSyncVault();
                  },
                ),
              ],
            ),
          ],
        );

      case 6: // Wi-Fi Sync (`Enpass_H1MKK11Thm.png`)
        final allPeers = c.discoverWifiSyncPeers();
        final sameAccountPeers = c.discoverSameAccountWifiPeers();
        final statusLabel = !c.wifiSyncServerRunning
            ? 'STOPPED'
            : (c.wifiSyncServerPaused ? 'PAUSED' : 'RUNNING');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('WI-FI SYNC SERVER'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TacticalTheme.bgSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TacticalTheme.borderTech),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: TacticalTheme.bgDeepCarbon,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c.wifiSyncServerRunning
                            ? TacticalTheme.emeraldReady
                            : TacticalTheme.amberPrimary,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.wifi_tethering,
                      size: 26,
                      color: c.wifiSyncServerRunning
                          ? TacticalTheme.emeraldReady
                          : TacticalTheme.amberBright,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Synchronize your vaults with other devices on the same local Wi-Fi network via Same Account or a 6-digit verification code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: TacticalTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Vault: ${c.wifiSyncVaultName}',
                        style: TacticalTheme.monoStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: TacticalTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Server: ${c.wifiSyncServerName} (${c.wifiSyncServerAddress})',
                        style: TacticalTheme.monoStyle(
                          fontSize: 11,
                          color: TacticalTheme.cyanTactical,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: c.wifiSyncServerRunning
                              ? TacticalTheme.emeraldDim
                              : TacticalTheme.bgDeepCarbon,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: c.wifiSyncServerRunning
                                ? TacticalTheme.emeraldReady
                                : TacticalTheme.borderTech,
                          ),
                        ),
                        child: Text(
                          statusLabel,
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: c.wifiSyncServerRunning
                                ? TacticalTheme.emeraldReady
                                : TacticalTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('settings_button_wifi_sync_toggle'),
                        icon: Icon(
                          c.wifiSyncServerRunning
                              ? Icons.stop
                              : Icons.play_arrow,
                          size: 16,
                        ),
                        label: Text(
                          c.wifiSyncServerRunning
                              ? 'Stop Wi-Fi Sync'
                              : 'Start Wi-Fi Sync',
                        ),
                        onPressed: () {
                          c.updateSettings(
                            wifiSyncServerRunning: !c.wifiSyncServerRunning,
                          );
                          setState(() {});
                        },
                      ),
                      if (c.wifiSyncServerRunning)
                        OutlinedButton.icon(
                          key: const ValueKey(
                            'settings_button_wifi_sync_pause',
                          ),
                          icon: Icon(
                            c.wifiSyncServerPaused
                                ? Icons.play_arrow_outlined
                                : Icons.pause_outlined,
                            size: 16,
                          ),
                          label: Text(
                            c.wifiSyncServerPaused ? 'Resume' : 'Pause',
                          ),
                          onPressed: () {
                            c.pauseWifiSyncServer();
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                  if (c.wifiSyncServerRunning) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: TacticalTheme.bgDeepCarbon,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: TacticalTheme.borderTech),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'PAIRING CODE & ACCESS PASSWORD (SAME WI-FI)',
                            style: TacticalTheme.monoStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: TacticalTheme.amberPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '6-Digit Verification Code:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: TacticalTheme.textSecondary,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: TacticalTheme.bgSurface,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: TacticalTheme.amberPrimary,
                                      ),
                                    ),
                                    child: Text(
                                      c.wifiSyncFormattedPairingCode,
                                      key: const ValueKey(
                                        'wifi_sync_server_pairing_code',
                                      ),
                                      style: TacticalTheme.monoStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: TacticalTheme.amberBright,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    key: const ValueKey(
                                      'wifi_sync_button_regenerate_code',
                                    ),
                                    tooltip: 'Regenerate 6-digit pairing code',
                                    icon: Icon(
                                      Icons.refresh,
                                      size: 16,
                                      color: TacticalTheme.cyanTactical,
                                    ),
                                    onPressed: () {
                                      c.regenerateWifiSyncPairingCode();
                                      setState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Access Password:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: TacticalTheme.textSecondary,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      c.wifiSyncAccessPassphrase,
                                      key: const ValueKey(
                                        'wifi_sync_server_access_passphrase',
                                      ),
                                      style: TacticalTheme.monoStyle(
                                        fontSize: 11,
                                        color: TacticalTheme.cyanTactical,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    key: const ValueKey(
                                      'wifi_sync_button_copy_passphrase',
                                    ),
                                    tooltip: 'Copy Wi-Fi Sync Access Password',
                                    icon: Icon(
                                      Icons.copy_outlined,
                                      size: 16,
                                      color: TacticalTheme.amberPrimary,
                                    ),
                                    onPressed: () async {
                                      await ClipboardGuard.copySecret(
                                        c.wifiSyncAccessPassphrase,
                                      );
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Wi-Fi Sync Access Password copied. Clears in 15 seconds.',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _SectionHeader('1. SAME-ACCOUNT WI-FI SYNC'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TacticalTheme.bgSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TacticalTheme.borderTech),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'When two devices on the same Wi-Fi are activated with the same account, they automatically recognize each other and sync passwords.',
                    style: TextStyle(
                      fontSize: 12,
                      color: TacticalTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 16,
                        color: c.onboardingActivatedEmail != null
                            ? TacticalTheme.emeraldReady
                            : TacticalTheme.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c.onboardingActivatedEmail != null
                              ? 'Account: ${c.onboardingActivatedEmail} (${sameAccountPeers.length} same-account peer(s) on Wi-Fi)'
                              : 'Account: Not activated (use 6-digit code below or activate email)',
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            color: TacticalTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const ValueKey(
                        'wifi_sync_button_same_account_sync',
                      ),
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text('Sync with Same-Account Device'),
                      onPressed: () async {
                        try {
                          final count = await c.syncWithSameAccountPeer();
                          if (!mounted) return;
                          setState(() {
                            _wifiSyncIsError = false;
                            _wifiSyncStatusBanner =
                                'Same-Account Wi-Fi Sync complete ($count item(s) updated).';
                          });
                        } catch (e) {
                          if (!mounted) return;
                          setState(() {
                            _wifiSyncIsError = true;
                            _wifiSyncStatusBanner = VaultController.describe(e);
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _SectionHeader('2. CONNECT & SYNC USING CODE ON SAME WI-FI'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TacticalTheme.bgSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TacticalTheme.borderTech),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter the 6-digit verification code displayed on the other device on the same Wi-Fi network to pair and sync passwords:',
                    style: TextStyle(
                      fontSize: 12,
                      color: TacticalTheme.textSecondary,
                    ),
                  ),
                  if (allPeers.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final p in allPeers)
                          ActionChip(
                            key: ValueKey('wifi_sync_peer_${p.address}'),
                            avatar: Icon(
                              Icons.computer,
                              size: 14,
                              color: TacticalTheme.cyanTactical,
                            ),
                            label: Text(
                              '${p.deviceName} (${p.address})',
                              style: TacticalTheme.monoStyle(fontSize: 11),
                            ),
                            onPressed: () {
                              setState(() {
                                _wifiAddressCtrl.text = p.address;
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('wifi_sync_input_pairing_code'),
                    controller: _wifiCodeCtrl,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    style: TacticalTheme.monoStyle(
                      fontSize: 13,
                      letterSpacing: 1.2,
                    ),
                    decoration: const InputDecoration(
                      labelText: '6-Digit Wi-Fi Pairing Code (e.g. 861 303)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('wifi_sync_input_server_address'),
                    controller: _wifiAddressCtrl,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    style: TacticalTheme.monoStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText:
                          'Server Address IP:Port (optional, auto-detected on LAN)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('wifi_sync_input_access_passphrase'),
                    controller: _wifiAccessPassCtrl,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    style: TacticalTheme.monoStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Vault Access Password (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const ValueKey(
                        'wifi_sync_button_connect_with_code',
                      ),
                      icon: const Icon(Icons.phonelink_lock_outlined, size: 16),
                      label: const Text('Connect & Sync with Code'),
                      onPressed: () async {
                        try {
                          final count = await c.syncWithWifiCode(
                            _wifiCodeCtrl.text,
                            serverAddress: _wifiAddressCtrl.text,
                            accessPassphrase: _wifiAccessPassCtrl.text,
                          );
                          if (!mounted) return;
                          setState(() {
                            _wifiSyncIsError = false;
                            _wifiSyncStatusBanner =
                                'Wi-Fi Sync via code complete ($count item(s) updated).';
                          });
                        } catch (e) {
                          if (!mounted) return;
                          setState(() {
                            _wifiSyncIsError = true;
                            _wifiSyncStatusBanner = VaultController.describe(e);
                          });
                        }
                      },
                    ),
                  ),
                  if (_wifiSyncStatusBanner != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      key: const ValueKey('wifi_sync_status_banner'),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _wifiSyncIsError
                            ? TacticalTheme.crimsonDim
                            : TacticalTheme.emeraldDim,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _wifiSyncIsError
                              ? TacticalTheme.crimsonDanger
                              : TacticalTheme.emeraldReady,
                        ),
                      ),
                      child: Text(
                        _wifiSyncStatusBanner!,
                        style: TacticalTheme.monoStyle(
                          fontSize: 11,
                          color: _wifiSyncIsError
                              ? TacticalTheme.crimsonDanger
                              : TacticalTheme.emeraldReady,
                        ),
                      ),
                    ),
                  ],
                  if (c.wifiSyncPairedDevices.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'PAIRED DEVICES & LAST SYNC (${c.wifiSyncLastSyncedAt ?? "Just now"}):',
                      style: TacticalTheme.monoStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: TacticalTheme.amberPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final dev in c.wifiSyncPairedDevices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $dev',
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            color: TacticalTheme.textPrimary,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );

      case 7: // Advanced (`Enpass_fCwTlOyXdP.png` & `Enpass_T10Ysz9Nij.png`)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('DATA LOCATION'),
            ListTile(
              leading: Icon(
                Icons.folder_special_outlined,
                color: TacticalTheme.amberPrimary,
              ),
              title: const Text('Vaults & Backups Directory'),
              subtitle: const Text('Default Local KDBX4 Workspace'),
            ),
            const Divider(height: 24),
            const _SectionHeader('NETWORK'),
            SwitchListTile(
              title: const Text('Disable SSL Certificate Pinning'),
              value: _disableSslPinning,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _disableSslPinning = v),
            ),
            const ListTile(
              title: Text('Proxy Configuration'),
              subtitle: Text('Use System Proxy Settings'),
            ),
            const Divider(height: 24),
            const _SectionHeader('SHARING'),
            ListTile(
              leading: Icon(
                Icons.key_outlined,
                color: TacticalTheme.cyanTactical,
              ),
              title: const Text('Pre-Shared Keys (PSK)'),
              subtitle: const Text(
                'Define symmetric keys for encrypted item export & sharing',
              ),
            ),
            const Divider(height: 24),
            const _SectionHeader('SECURITY'),
            SwitchListTile(
              title: const Text('Check for Compromised Passwords'),
              subtitle: const Text(
                'Evaluate credentials against offline k-anonymity breach corpus',
              ),
              value: c.checkCompromisedPasswords,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(checkCompromisedPasswords: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text('Check Clipboard for Sensitive Data'),
              value: _checkClipboard,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _checkClipboard = v),
            ),
            const Divider(height: 24),
            const _SectionHeader('UPDATES & LOGS'),
            SwitchListTile(
              title: const Text('Automatically Check for Updates'),
              value: _autoCheckUpdates,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _autoCheckUpdates = v),
            ),
            SwitchListTile(
              title: const Text('Check for Website Breach Alerts'),
              value: _checkForAlerts,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _checkForAlerts = v),
            ),
            SwitchListTile(
              title: const Text('Enable Diagnostic Logs (Zero Secrets)'),
              value: _enableLogs,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _enableLogs = v),
            ),
            const Divider(height: 24),
            const _SectionHeader('RESET'),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('settings_button_erase_everything'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: TacticalTheme.crimsonDanger,
                  side: BorderSide(color: TacticalTheme.crimsonDanger),
                ),
                icon: const Icon(Icons.delete_forever_outlined, size: 16),
                label: const Text('Erase Everything'),
                onPressed: _confirmEraseEverything,
              ),
            ),
          ],
        );

      case 8: // About (`Screenshots/aas.txt`)
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('ABOUT VAULTKEEP'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TacticalTheme.bgSurface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: TacticalTheme.borderTech),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.shield,
                    color: TacticalTheme.amberPrimary,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VaultKeep Pro — Zero-Knowledge Password Manager',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: TacticalTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'KDBX 4.0/4.1 • Argon2id • ChaCha20-Poly1305 • FIDO2 ES256',
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            color: TacticalTheme.cyanTactical,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _SectionHeader('OPEN SOURCE SOFTWARE & CRYPTO STACK'),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TacticalTheme.bgDeepCarbon,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: TacticalTheme.borderTech),
              ),
              child: Text(
                'VaultKeep KDBX4 Core (Rust):\n'
                '• keepass-rs (KDBX4 XML/Binary Stream)\n'
                '• Argon2id + ChaCha20-Poly1305 / AES-256-CBC + HMAC-SHA256\n'
                '• totp-rs (RFC 6238) + zeroize + getrandom (OS CSPRNG)\n\n'
                'Enpass Reference Open Source Credits (Screenshots/aas.txt):\n'
                '• Zxcvbn (Password Strength) • ZXing (QR TOTP) • pugixml\n'
                '• OpenSSL & Libsodium • SingleApplication & QHotkey\n'
                '• WebSocket++ & Asio (Wi-Fi Sync) • RapidJSON & jsoncpp\n'
                '• Gumbo HTML5 Parser • libqrencode • breakpad',
                style: TacticalTheme.monoStyle(
                  fontSize: 11,
                  color: TacticalTheme.textSecondary,
                ),
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return Dialog(
          key: const ValueKey('enpass_settings_dialog'),
          backgroundColor: TacticalTheme.bgPanel,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 560;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Header
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: TacticalTheme.bgSurface,
                        border: Border(
                          bottom: BorderSide(
                            color: TacticalTheme.borderTech,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.settings_outlined,
                            color: TacticalTheme.amberPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Settings',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: TacticalTheme.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close Settings',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),

                    if (!isWide)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            for (var i = 0; i < _tabs.length; i++) ...[
                              ChoiceChip(
                                label: Text(_tabs[i].label),
                                selected: _selectedTab == i,
                                onSelected: (_) => setState(() {
                                  _selectedTab = i;
                                  _selectingStorageForNewVault = false;
                                }),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),

                    Expanded(
                      child: isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Left Settings Navigation Rail (`Enpass_s93PhrrNLy.png`)
                                Container(
                                  width: 195,
                                  decoration: BoxDecoration(
                                    color: TacticalTheme.bgDeepCarbon,
                                    border: Border(
                                      right: BorderSide(
                                        color: TacticalTheme.borderTech,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Top Enpass License / Account Badge (`Enpass_s93PhrrNLy.png`)
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: TacticalTheme.bgSurface,
                                          border: Border(
                                            bottom: BorderSide(
                                              color: TacticalTheme.borderSubtle,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 30,
                                              height: 30,
                                              decoration: BoxDecoration(
                                                color: TacticalTheme.amberDim,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: TacticalTheme
                                                      .amberPrimary,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.workspace_premium,
                                                size: 16,
                                                color:
                                                    TacticalTheme.amberBright,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'VaultKeep Pro',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: TacticalTheme
                                                          .textPrimary,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Registered License',
                                                    style:
                                                        TacticalTheme.monoStyle(
                                                          fontSize: 10,
                                                          color: TacticalTheme
                                                              .amberBright,
                                                        ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: ListView.builder(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          itemCount: _tabs.length,
                                          itemBuilder: (context, i) {
                                            final selected =
                                                _selectedTab == i;
                                            final hovered =
                                                _hoveredTab == i;
                                            return InkWell(
                                              key: ValueKey(
                                                'settings_tab_${_tabs[i].label}',
                                              ),
                                              onHover: (v) => setState(() {
                                                if (v) {
                                                  _hoveredTab = i;
                                                } else if (_hoveredTab == i) {
                                                  _hoveredTab = null;
                                                }
                                              }),
                                              onTap: () => setState(() {
                                                _selectedTab = i;
                                                _selectingStorageForNewVault =
                                                    false;
                                              }),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      14,
                                                      9,
                                                      13,
                                                      9,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: selected
                                                      ? TacticalTheme.bgElevated
                                                      : (hovered
                                                          ? TacticalTheme.bgHover
                                                          : Colors.transparent),
                                                  border: Border(
                                                    left: BorderSide(
                                                      color: selected
                                                          ? TacticalTheme
                                                              .amberPrimary
                                                          : (hovered
                                                              ? TacticalTheme
                                                                  .hoverBorderColor
                                                              : Colors
                                                                  .transparent),
                                                      width: 3,
                                                    ),
                                                    top: BorderSide(
                                                      color: hovered
                                                          ? TacticalTheme
                                                              .hoverBorderColor
                                                          : Colors.transparent,
                                                      width: 1,
                                                    ),
                                                    right: BorderSide(
                                                      color: hovered
                                                          ? TacticalTheme
                                                              .hoverBorderColor
                                                          : Colors.transparent,
                                                      width: 1,
                                                    ),
                                                    bottom: BorderSide(
                                                      color: hovered
                                                          ? TacticalTheme
                                                              .hoverBorderColor
                                                          : Colors.transparent,
                                                      width: 1,
                                                    ),
                                                  ),
                                                  boxShadow: hovered
                                                      ? TacticalTheme.borderGlow
                                                      : null,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      _tabs[i].icon,
                                                      size: 17,
                                                      color: (selected ||
                                                              hovered)
                                                          ? TacticalTheme
                                                              .amberPrimary
                                                          : TacticalTheme
                                                              .cyanTactical,
                                                      shadows: hovered
                                                          ? TacticalTheme
                                                              .textGlow
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Text(
                                                        _tabs[i].label,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: selected
                                                              ? FontWeight.w700
                                                              : FontWeight.w500,
                                                          color: hovered
                                                              ? TacticalTheme
                                                                  .amberBright
                                                              : (selected
                                                                  ? TacticalTheme
                                                                      .textPrimary
                                                                  : TacticalTheme
                                                                      .textSecondary),
                                                          shadows: hovered
                                                              ? TacticalTheme
                                                                  .textGlow
                                                              : null,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(20),
                                    child: _buildTabContent(),
                                  ),
                                ),
                              ],
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: _buildTabContent(),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TacticalTheme.monoStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: TacticalTheme.amberPrimary,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _QuickPinSetupDialog extends StatefulWidget {
  const _QuickPinSetupDialog();

  @override
  State<_QuickPinSetupDialog> createState() => _QuickPinSetupDialogState();
}

class _QuickPinSetupDialogState extends State<_QuickPinSetupDialog> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showPin = false;
  String? _pinError;

  @override
  void dispose() {
    _pinCtrl.text = '';
    _confirmCtrl.text = '';
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pin.length < 4) {
      setState(() => _pinError = 'PIN must be at least 4 characters.');
      return;
    }
    if (pin != confirm) {
      setState(() => _pinError = 'PIN entries do not match.');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('settings_quick_pin_dialog'),
      title: Row(
        children: [
          Icon(Icons.pin_outlined, color: TacticalTheme.amberPrimary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Set Quick Unlock PIN'),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter a Quick Unlock PIN using numbers (e.g. 123456) or characters (e.g. Pass#99) to quickly unlock VaultKeep when locked.',
              style: TextStyle(
                fontSize: 12,
                color: TacticalTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('settings_pin_input'),
              controller: _pinCtrl,
              autofocus: true,
              obscureText: !_showPin,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              style: TacticalTheme.monoStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'New PIN (numeric or characters, min 4)',
                suffixIcon: IconButton(
                  tooltip: _showPin ? 'Hide PIN' : 'Show PIN',
                  icon: Icon(
                    _showPin ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                    color: TacticalTheme.textSecondary,
                  ),
                  onPressed: () => setState(() => _showPin = !_showPin),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('settings_pin_confirm'),
              controller: _confirmCtrl,
              obscureText: !_showPin,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              style: TacticalTheme.monoStyle(fontSize: 13),
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
              ),
            ),
            if (_pinError != null) ...[
              const SizedBox(height: 10),
              Text(
                _pinError!,
                style: TacticalTheme.monoStyle(
                  fontSize: 11,
                  color: TacticalTheme.crimsonDanger,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('settings_pin_save_button'),
          onPressed: _submit,
          child: const Text('Set PIN'),
        ),
      ],
    );
  }
}

