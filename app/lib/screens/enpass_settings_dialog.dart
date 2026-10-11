import 'dart:io';

import 'package:flutter/material.dart';

import '../backend.dart';
import '../theme.dart';
import '../vault_controller.dart';

/// Enpass 1:1 8-Tab Settings Dialog (`Enpass_qsehQ4O46P.png` – `Enpass_Phx22T1g3k.png`).
class EnpassSettingsDialog extends StatefulWidget {
  const EnpassSettingsDialog({
    super.key,
    required this.controller,
    required this.onChangeMasterPassword,
    required this.onSyncVault,
  });

  final VaultController controller;
  final VoidCallback onChangeMasterPassword;
  final VoidCallback onSyncVault;

  static Future<void> show(
    BuildContext context, {
    required VaultController controller,
    required VoidCallback onChangeMasterPassword,
    required VoidCallback onSyncVault,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => EnpassSettingsDialog(
        controller: controller,
        onChangeMasterPassword: onChangeMasterPassword,
        onSyncVault: onSyncVault,
      ),
    );
  }

  @override
  State<EnpassSettingsDialog> createState() => _EnpassSettingsDialogState();
}

class _EnpassSettingsDialogState extends State<EnpassSettingsDialog> {
  int _selectedTab = 0;
  bool _selectingStorageForNewVault = false;
  bool _openAtStartup = false;
  bool _minimizeToTray = true;
  bool _lockOnSystemSleep = true;
  bool _lockOnSystemLock = true;
  bool _lockOnWindowClose = false;
  bool _disableSslPinning = false;

  static const List<({String label, IconData icon})> _tabs = [
    (label: 'General', icon: Icons.tune),
    (label: 'Vaults', icon: Icons.enhanced_encryption_outlined),
    (label: 'Security', icon: Icons.security_outlined),
    (label: 'Customize', icon: Icons.palette_outlined),
    (label: 'Autofill', icon: Icons.extension_outlined),
    (label: 'Backup', icon: Icons.backup_outlined),
    (label: 'Wi-Fi Sync', icon: Icons.wifi_tethering),
    (label: 'Advanced', icon: Icons.build_outlined),
  ];

  static const List<({String name, String subtitle, IconData icon})>
      _storageProviders = [
    (
      name: 'OneDrive',
      subtitle: 'Microsoft OneDrive Cloud Sync',
      icon: Icons.cloud_outlined,
    ),
    (
      name: 'Google Drive',
      subtitle: 'Google Drive Encrypted Sync',
      icon: Icons.add_to_drive,
    ),
    (
      name: 'iCloud',
      subtitle: 'Apple iCloud Drive Vault',
      icon: Icons.cloud_circle_outlined,
    ),
    (
      name: 'Dropbox',
      subtitle: 'Dropbox App Folder Sync',
      icon: Icons.inventory_2_outlined,
    ),
    (
      name: 'Box',
      subtitle: 'Box Enterprise Cloud Storage',
      icon: Icons.all_inbox_outlined,
    ),
    (
      name: 'WebDAV',
      subtitle: 'Self-hosted WebDAV / OwnCloud',
      icon: Icons.dns_outlined,
    ),
    (
      name: 'NextCloud',
      subtitle: 'NextCloud Private Instance',
      icon: Icons.cloud_done_outlined,
    ),
    (
      name: 'Wi-Fi Sync',
      subtitle: 'Local LAN SRP-6a Encrypted Sync',
      icon: Icons.wifi_tethering,
    ),
    (
      name: 'Folder Sync',
      subtitle: 'Local or Network Folder Replica (.kdbx)',
      icon: Icons.folder_copy_outlined,
    ),
    (
      name: 'This PC',
      subtitle: 'Offline Local KDBX4 Vault on Disk',
      icon: Icons.computer_outlined,
    ),
  ];

  VaultController get c => widget.controller;

  Future<void> _triggerBackupNow() async {
    try {
      final backupDir =
          '${Directory.systemTemp.path}${Platform.pathSeparator}vaultkeep_backups';
      final path = await c.createBackup(backupDir);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Encrypted backup created: $path')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(VaultController.describe(e))),
      );
    }
  }

  Widget _buildVaultsTab() {
    if (_selectingStorageForNewVault) {
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
              const Expanded(
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
          const SizedBox(height: 8),
          Text(
            'Choose a cloud provider, local network Wi-Fi Sync server, or offline folder replica:',
            style: TacticalTheme.monoStyle(
              fontSize: 11,
              color: TacticalTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          for (final p in _storageProviders)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(p.icon, color: TacticalTheme.amberPrimary),
                title: Text(
                  p.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: TacticalTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  p.subtitle,
                  style: TacticalTheme.monoStyle(
                    fontSize: 11,
                    color: TacticalTheme.textSecondary,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: TacticalTheme.textMuted,
                ),
                onTap: () {
                  c.updateSettings(connectedStorageProvider: p.name);
                  setState(() => _selectingStorageForNewVault = false);
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
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
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
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: TacticalTheme.amberDim,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: TacticalTheme.amberPrimary,
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_person_outlined,
                      color: TacticalTheme.amberBright,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Primary',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: TacticalTheme.textPrimary,
                          ),
                        ),
                        Text(
                          '${c.activeItems.length} Items • ${c.connectedStorageProvider}',
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
              const SizedBox(height: 14),
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
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('settings_button_add_new_vault'),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add New Vault / Connect Storage'),
          onPressed: () =>
              setState(() => _selectingStorageForNewVault = true),
        ),
      ],
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0: // General
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('RUN'),
            SwitchListTile(
              title: const Text('Open Automatically at System Startup'),
              subtitle: const Text(
                'Launch VaultKeep minimized in background on boot',
              ),
              value: _openAtStartup,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _openAtStartup = v),
            ),
            SwitchListTile(
              title: const Text('Minimize App to System Tray'),
              subtitle: const Text(
                'Keep quick-access icon in the system notification area',
              ),
              value: _minimizeToTray,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _minimizeToTray = v),
            ),
            const Divider(height: 24),
            const _SectionHeader('LANGUAGE'),
            ListTile(
              title: const Text('Language'),
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

      case 1: // Vaults
        return _buildVaultsTab();

      case 2: // Security
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('QUICK UNLOCK'),
            SwitchListTile(
              title: const Text('Windows Hello'),
              subtitle: const Text(
                'Unlock Primary vault using OS TPM / Biometric verification',
              ),
              value: c.windowsHelloEnabled,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(windowsHelloEnabled: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text('PIN'),
              subtitle: const Text(
                'Unlock quickly when app is already running in memory',
              ),
              value: c.quickPinEnabled,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) {
                c.updateSettings(quickPinEnabled: v);
                setState(() {});
              },
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
              leading: const Icon(
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
              title: const Text('System Sleeps'),
              value: _lockOnSystemSleep,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _lockOnSystemSleep = v),
            ),
            SwitchListTile(
              title: const Text('System Locks'),
              value: _lockOnSystemLock,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _lockOnSystemLock = v),
            ),
            SwitchListTile(
              title: const Text('Main Window is Closed'),
              value: _lockOnWindowClose,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _lockOnWindowClose = v),
            ),
            const Divider(height: 24),
            const _SectionHeader('CLIPBOARD'),
            ListTile(
              title: const Text('Auto-Clear Clipboard'),
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

      case 3: // Customize
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('APPEARANCE'),
            ListTile(
              title: const Text('Choose Theme'),
              trailing: Text(
                'Dark (Tactical Carbon)',
                style: TacticalTheme.monoStyle(
                  fontSize: 12,
                  color: TacticalTheme.amberBright,
                ),
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
              title: const Text('Include Old Passwords in Audit'),
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

      case 4: // Autofill
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('BROWSER EXTENSIONS'),
            SwitchListTile(
              title: const Text('Autofill in Browsers'),
              subtitle: const Text(
                'Communicate with browser extension over authenticated localhost channel',
              ),
              value: true,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (_) {},
            ),
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
          ],
        );

      case 5: // Backup
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
              ),
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

      case 6: // Wi-Fi Sync
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader('WI-FI SYNC SERVER'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TacticalTheme.bgSurface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: TacticalTheme.borderTech),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Host a local Wi-Fi Sync Server to synchronize your Primary vault with other devices on your local network without cloud storage.',
                    style: TextStyle(
                      fontSize: 13,
                      color: TacticalTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Vault: ${c.wifiSyncVaultName}',
                        style: TacticalTheme.monoStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: TacticalTheme.textPrimary,
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
                          c.wifiSyncServerRunning ? 'RUNNING' : 'STOPPED',
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
                  FilledButton.icon(
                    key: const ValueKey('settings_button_wifi_sync_toggle'),
                    icon: Icon(
                      c.wifiSyncServerRunning ? Icons.stop : Icons.play_arrow,
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
                ],
              ),
            ),
          ],
        );

      case 7: // Advanced
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const Divider(height: 24),
            const _SectionHeader('NETWORK'),
            SwitchListTile(
              title: const Text('Disable SSL Certificate Pinning'),
              value: _disableSslPinning,
              activeThumbColor: TacticalTheme.amberPrimary,
              onChanged: (v) => setState(() => _disableSslPinning = v),
            ),
            const Divider(height: 24),
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
                '• WebSocket++ & Asio (Wi-Fi Sync) • RapidJSON & jsoncpp',
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
    return Dialog(
      key: const ValueKey('enpass_settings_dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 740, maxHeight: 620),
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
                  decoration: const BoxDecoration(
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
                      const Icon(
                        Icons.settings_outlined,
                        color: TacticalTheme.amberPrimary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
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
                            // Left Settings Navigation Rail
                            Container(
                              width: 185,
                              decoration: const BoxDecoration(
                                color: TacticalTheme.bgDeepCarbon,
                                border: Border(
                                  right: BorderSide(
                                    color: TacticalTheme.borderTech,
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                itemCount: _tabs.length,
                                itemBuilder: (context, i) {
                                  final selected = _selectedTab == i;
                                  return InkWell(
                                    key: ValueKey(
                                      'settings_tab_${_tabs[i].label}',
                                    ),
                                    onTap: () => setState(() {
                                      _selectedTab = i;
                                      _selectingStorageForNewVault = false;
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 11,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? TacticalTheme.bgElevated
                                            : Colors.transparent,
                                        border: Border(
                                          left: BorderSide(
                                            color: selected
                                                ? TacticalTheme.amberPrimary
                                                : Colors.transparent,
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _tabs[i].icon,
                                            size: 17,
                                            color: selected
                                                ? TacticalTheme.amberPrimary
                                                : TacticalTheme.cyanTactical,
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
                                                color: selected
                                                    ? TacticalTheme.textPrimary
                                                    : TacticalTheme
                                                        .textSecondary,
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
