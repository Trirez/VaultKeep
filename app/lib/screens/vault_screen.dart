import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend.dart';
import '../clipboard_guard.dart';
import '../theme.dart';
import '../vault_controller.dart';
import 'enpass_settings_dialog.dart';
import 'entry_screen.dart';
import 'file_picker_dialog.dart';
import 'home_dashboard_pane.dart';
import 'password_generator_sheet.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.controller});

  final VaultController controller;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  String? _selectedEntryId;
  bool _creatingNewInInspector = false;
  int _newEntryNonce = 0;
  String? _newEntryCategory;

  VaultController get controller => widget.controller;

  static IconData _iconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'login':
        return Icons.language;
      case 'credit card':
        return Icons.credit_card;
      case 'identity':
        return Icons.badge_outlined;
      case 'note':
        return Icons.sticky_note_2_outlined;
      case 'password':
        return Icons.key_outlined;
      case 'finance':
        return Icons.account_balance_outlined;
      case 'license':
        return Icons.workspace_premium_outlined;
      case 'travel':
        return Icons.flight_takeoff;
      case 'computer':
        return Icons.computer_outlined;
      default:
        return Icons.extension_outlined;
    }
  }

  Future<void> _copyPassword(BuildContext context, VaultItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final password = await controller.revealPassword(item.id);
      if (!context.mounted || controller.status != VaultStatus.unlocked) return;
      await ClipboardGuard.copySecret(password);
      messenger.showSnackBar(
        const SnackBar(content: Text('Password copied. Clears in 15 seconds.')),
      );
    } catch (e) {
      if (!context.mounted || controller.status != VaultStatus.unlocked) return;
      messenger.showSnackBar(
        SnackBar(content: Text(VaultController.describe(e))),
      );
    }
  }

  Future<void> _copyUsername(BuildContext context, VaultItem item) async {
    if (item.username.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await ClipboardGuard.copySecret(item.username);
    messenger.showSnackBar(
      const SnackBar(content: Text('Username copied. Clears in 15 seconds.')),
    );
  }

  Future<void> _copyTotp(BuildContext context, VaultItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final totp = await controller.getTotp(item.id);
      if (!context.mounted ||
          controller.status != VaultStatus.unlocked ||
          totp == null) {
        return;
      }
      await ClipboardGuard.copySecret(totp.code);
      messenger.showSnackBar(
        const SnackBar(content: Text('TOTP code copied. Clears in 15 seconds.')),
      );
    } catch (e) {
      if (!context.mounted || controller.status != VaultStatus.unlocked) return;
      messenger.showSnackBar(
        SnackBar(content: Text(VaultController.describe(e))),
      );
    }
  }

  Future<void> _changeMasterPassword(BuildContext context) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? dialogError;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.vpn_key_outlined, color: TacticalTheme.amberPrimary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Rotate Master Password'),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Atomically re-encrypt this KDBX4 vault with a new master password (Argon2id) and advance all entry revision timestamps.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('rotate_field_current'),
                    controller: currentCtrl,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    style: TacticalTheme.monoStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Current master password',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('rotate_field_new'),
                    controller: newCtrl,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    style: TacticalTheme.monoStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'New master password (min 12 chars)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('rotate_field_confirm'),
                    controller: confirmCtrl,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    style: TacticalTheme.monoStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Repeat new master password',
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      dialogError!,
                      style: TacticalTheme.monoStyle(
                        fontSize: 11,
                        color: TacticalTheme.crimsonLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('rotate_button_submit'),
                onPressed: () {
                  if (currentCtrl.text.isEmpty) {
                    setDialogState(
                      () => dialogError = 'Enter your current master password.',
                    );
                    return;
                  }
                  if (newCtrl.text.length < 12) {
                    setDialogState(
                      () => dialogError =
                          'New master password must be at least 12 characters.',
                    );
                    return;
                  }
                  if (newCtrl.text != confirmCtrl.text) {
                    setDialogState(
                      () => dialogError = 'New passwords do not match.',
                    );
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                child: const Text('Rotate Password'),
              ),
            ],
          ),
        ),
      );

      if (confirmed == true && context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await controller.changeMasterPassword(
            currentCtrl.text,
            newCtrl.text,
          );
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Master password rotated and vault re-encrypted.'),
            ),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text(VaultController.describe(e))),
          );
        }
      }
    } finally {
      currentCtrl.text = '';
      newCtrl.text = '';
      confirmCtrl.text = '';
      currentCtrl.dispose();
      newCtrl.dispose();
      confirmCtrl.dispose();
    }
  }

  void _openEntry(
    BuildContext context, {
    String? id,
    String? category,
    required bool isDesktop,
  }) {
    if (id != null) {
      controller.recordRecentItem(id);
    }
    if (isDesktop) {
      if (controller.showHomeDashboard) {
        controller.closeHomeDashboard();
      }
      setState(() {
        if (id == null) {
          _creatingNewInInspector = true;
          _selectedEntryId = null;
          _newEntryCategory = category;
          _newEntryNonce++;
        } else {
          _creatingNewInInspector = false;
          _selectedEntryId = id;
        }
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EntryScreen(
            controller: controller,
            entryId: id,
            initialCategory: category,
            autofocusTitle: id == null,
          ),
        ),
      );
    }
  }

  Future<void> _createGroup(BuildContext context) async {
    final nameCtrl = TextEditingController();
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'New Group',
            style: TacticalTheme.monoStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: TacticalTheme.amberPrimary,
            ),
          ),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            style: TacticalTheme.monoStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Group Name',
            ),
            onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(nameCtrl.text.trim()),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      if (name != null && name.isNotEmpty) {
        try {
          await controller.createGroup(name);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(VaultController.describe(e))),
            );
          }
        }
      }
    } finally {
      nameCtrl.dispose();
    }
  }

  Future<void> _syncVault(BuildContext context) async {
    final pathCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.sync, color: TacticalTheme.amberPrimary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Sync Vault (3-Way Merge)'),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Synchronize changes between this vault and a cloud replica using KDBX 3-way merge. Both files will be updated with the latest unified state.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pathCtrl,
                    style: TacticalTheme.monoStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Replica file path (.kdbx)',
                      hintText: 'Select cloud or replica .kdbx file',
                      suffixIcon: IconButton(
                        tooltip: 'Browse files',
                        icon: Icon(
                          Icons.folder_open,
                          color: TacticalTheme.amberPrimary,
                        ),
                        onPressed: () async {
                          final picked = await FilePickerDialog.show(
                            ctx,
                            initialPath: pathCtrl.text,
                            mustExist: true,
                          );
                          if (picked != null) {
                            setDialogState(() => pathCtrl.text = picked);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    style: TacticalTheme.monoStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Replica master password',
                      hintText: 'Leave empty to use active vault password',
                      helperText:
                          'Leave blank if replica shares current password',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (pathCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please select a replica file path before syncing.',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                child: const Text('Sync'),
              ),
            ],
          ),
        ),
      );

      if (result == true && context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final trimmedPath = pathCtrl.text.trim();
        if (trimmedPath.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Sync cancelled: replica path was empty.'),
            ),
          );
          return;
        }
        try {
          final count = await controller.mergeVault(
            trimmedPath,
            passCtrl.text,
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text('Sync complete: $count merge event(s) applied.'),
            ),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Sync failed: ${VaultController.describe(e)}'),
            ),
          );
        }
      }
    } finally {
      passCtrl.text = '';
      passCtrl.dispose();
      pathCtrl.dispose();
    }
  }

  Future<void> _showAutofillModal(BuildContext context) async {
    final queryCtrl = TextEditingController();
    List<VaultItem> matches = [];
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_mode,
                      color: TacticalTheme.amberPrimary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Autofill Domain Query',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Query entries matching target domain (e.g. github.com, google.com).',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: queryCtrl,
                  autofocus: true,
                  style: TacticalTheme.monoStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Target Domain or App',
                    suffixIcon: IconButton(
                      icon: Icon(
                        Icons.search,
                        color: TacticalTheme.amberPrimary,
                      ),
                      onPressed: () async {
                        try {
                          final res = await controller.findEntriesForDomain(
                            queryCtrl.text.trim(),
                          );
                          if (!ctx.mounted ||
                              controller.status != VaultStatus.unlocked) {
                            return;
                          }
                          setSheetState(() => matches = res);
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  onSubmitted: (val) async {
                    try {
                      final res =
                          await controller.findEntriesForDomain(val.trim());
                      if (!ctx.mounted ||
                          controller.status != VaultStatus.unlocked) {
                        return;
                      }
                      setSheetState(() => matches = res);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (matches.isNotEmpty) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: matches.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = matches[i];
                        return ListTile(
                          leading: TacticalDomainAvatar(
                            title: item.title,
                            url: item.url,
                            size: 28,
                          ),
                          title: Text(item.title),
                          subtitle: Text(
                            item.username,
                            style: TacticalTheme.monoStyle(
                              fontSize: 11,
                              color: TacticalTheme.textSecondary,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Copy password',
                            icon: Icon(
                              Icons.copy,
                              color: TacticalTheme.amberPrimary,
                            ),
                            onPressed: () async {
                              try {
                                final pw =
                                    await controller.revealPassword(item.id);
                                if (!ctx.mounted ||
                                    controller.status !=
                                        VaultStatus.unlocked) {
                                  return;
                                }
                                await ClipboardGuard.copySecret(pw);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Password copied for autofill.'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('$e')),
                                  );
                                }
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ] else if (queryCtrl.text.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No matching entries found for this domain.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    } finally {
      queryCtrl.dispose();
    }
  }

  String _resolveGroupLabel(VaultItem item, List<VaultGroup> groups) {
    final gIdOrName = item.groupName;
    if (gIdOrName == null || gIdOrName.isEmpty) return 'Root';
    for (final g in groups) {
      if (g.id == gIdOrName || g.name == gIdOrName) {
        return g.name;
      }
    }
    return gIdOrName;
  }

  VaultItem? _resolveActiveItem([String? activeInspectorId]) {
    final targetId = activeInspectorId ?? _selectedEntryId;
    if (targetId != null) {
      for (final item in controller.items) {
        if (item.id == targetId) return item;
      }
    }
    final filtered = _filterAndSortItems();
    if (filtered.isNotEmpty) return filtered.first;
    if (controller.activeItems.isNotEmpty) return controller.activeItems.first;
    return null;
  }

  Future<void> _showImportDialog(BuildContext context) async {
    var pathText = '';
    var csvText = '';
    var pathVersion = 0;
    var csvVersion = 0;
    String? dialogError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          key: const ValueKey('top_menu_import_dialog'),
          title: Row(
            children: [
              Icon(Icons.file_upload_outlined, color: TacticalTheme.amberPrimary),
              const SizedBox(width: 8),
              const Expanded(child: Text('Import Items (CSV)')),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Import credentials from a CSV file (Title, Username, E-mail, Password, URL, Notes, Category, Tags) or paste CSV rows below.',
                    style: TextStyle(
                      fontSize: 12,
                      color: TacticalTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  KeyedSubtree(
                    key: ValueKey('import_path_v_$pathVersion'),
                    child: TextFormField(
                      key: const ValueKey('import_csv_path_field'),
                      initialValue: pathText,
                      onChanged: (v) => pathText = v,
                      style: TacticalTheme.monoStyle(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'CSV File Path (optional)',
                        hintText: 'Select a .csv file from disk',
                        suffixIcon: IconButton(
                          tooltip: 'Browse CSV file',
                          icon: Icon(
                            Icons.folder_open,
                            color: TacticalTheme.amberPrimary,
                          ),
                          onPressed: () async {
                            final picked = await FilePickerDialog.show(
                              ctx,
                              initialPath: pathText,
                              mustExist: true,
                            );
                            if (picked != null) {
                              setDialogState(() {
                                pathText = picked;
                                pathVersion++;
                                try {
                                  final f = File(picked);
                                  if (f.existsSync()) {
                                    csvText = f.readAsStringSync();
                                    csvVersion++;
                                  }
                                } catch (_) {}
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: ValueKey('import_csv_v_$csvVersion'),
                    child: TextFormField(
                      key: const ValueKey('import_csv_content_field'),
                      initialValue: csvText,
                      onChanged: (v) => csvText = v,
                      maxLines: 5,
                      enableSuggestions: false,
                      autocorrect: false,
                      enableIMEPersonalizedLearning: false,
                      style: TacticalTheme.monoStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        labelText: 'CSV Content',
                        hintText:
                            'Title,Username,Email,Password,URL,Notes,Category,Tags\nGitHub,octocat,octo@github.com,Secret!123,https://github.com,Dev,Login,dev',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError!,
                      style: TacticalTheme.monoStyle(
                        fontSize: 11,
                        color: TacticalTheme.crimsonLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('import_csv_submit_button'),
              onPressed: () {
                if (csvText.trim().isEmpty && pathText.trim().isNotEmpty) {
                  try {
                    final f = File(pathText.trim());
                    if (f.existsSync()) {
                      csvText = f.readAsStringSync();
                    }
                  } catch (_) {}
                }
                if (csvText.trim().isEmpty) {
                  setDialogState(
                    () => dialogError =
                        'Provide CSV content or select a valid CSV file.',
                  );
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final count = await controller.importCsv(csvText);
        messenger.showSnackBar(
          SnackBar(content: Text('Imported $count item(s) into vault.')),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(VaultController.describe(e))),
        );
      }
    }
    csvText = '';
  }

  Future<void> _showExportDialog(BuildContext context) async {
    var pathText =
        '${Directory.systemTemp.path}${Platform.pathSeparator}vaultkeep_export.kdbx';
    var masterText = '';
    var pathVersion = 0;
    var format = 'kdbx';
    String? dialogError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          key: const ValueKey('top_menu_export_dialog'),
          title: Row(
            children: [
              Icon(Icons.file_download_outlined, color: TacticalTheme.amberPrimary),
              const SizedBox(width: 8),
              const Expanded(child: Text('Export Vault')),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Verify your master password to export this vault as an encrypted KDBX 4.1 container (.kdbx) or CSV file (.csv).',
                    style: TextStyle(
                      fontSize: 12,
                      color: TacticalTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('export_format_dropdown'),
                    initialValue: format,
                    decoration: const InputDecoration(
                      labelText: 'Export Format',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'kdbx',
                        child: Text('Encrypted KDBX 4.1 (.kdbx)'),
                      ),
                      DropdownMenuItem(
                        value: 'csv',
                        child: Text('CSV Spreadsheet (.csv)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      setDialogState(() {
                        format = val;
                        if (val == 'csv' && pathText.endsWith('.kdbx')) {
                          pathText =
                              '${pathText.substring(0, pathText.length - 5)}.csv';
                          pathVersion++;
                        } else if (val == 'kdbx' &&
                            pathText.endsWith('.csv')) {
                          pathText =
                              '${pathText.substring(0, pathText.length - 4)}.kdbx';
                          pathVersion++;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: ValueKey('export_path_v_$pathVersion'),
                    child: TextFormField(
                      key: const ValueKey('export_dest_path_field'),
                      initialValue: pathText,
                      onChanged: (v) => pathText = v,
                      style: TacticalTheme.monoStyle(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Destination File Path',
                        suffixIcon: IconButton(
                          tooltip: 'Browse destination',
                          icon: Icon(
                            Icons.folder_open,
                            color: TacticalTheme.amberPrimary,
                          ),
                          onPressed: () async {
                            final picked = await FilePickerDialog.show(
                              ctx,
                              initialPath: pathText,
                              mustExist: false,
                            );
                            if (picked != null) {
                              setDialogState(() {
                                pathText = picked;
                                pathVersion++;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('export_master_password_field'),
                    onChanged: (v) => masterText = v,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    style: TacticalTheme.monoStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Current Master Password',
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError!,
                      style: TacticalTheme.monoStyle(
                        fontSize: 11,
                        color: TacticalTheme.crimsonLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('export_submit_button'),
              onPressed: () {
                if (pathText.trim().isEmpty) {
                  setDialogState(
                    () => dialogError = 'Enter a destination file path.',
                  );
                  return;
                }
                if (masterText.isEmpty) {
                  setDialogState(
                    () => dialogError =
                        'Enter your current master password to authorize export.',
                  );
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Export'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final count = await controller.exportVault(
          pathText.trim(),
          masterText,
          format,
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Exported $count item(s) to ${pathText.trim()}',
            ),
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(VaultController.describe(e))),
        );
      }
    }
    masterText = '';
  }

  Future<void> _showPrintDialog(
    BuildContext context,
    VaultItem? activeItem,
  ) async {
    final summaryText = activeItem != null
        ? 'VAULTKEEP PRINTABLE ITEM RECORD\n'
            '========================================\n'
            'Title    : ${activeItem.title}\n'
            'Category : ${activeItem.category}\n'
            'Username : ${activeItem.username.isEmpty ? "-" : activeItem.username}\n'
            'E-mail   : ${activeItem.email.isEmpty ? "-" : activeItem.email}\n'
            'URL      : ${activeItem.url.isEmpty ? "-" : activeItem.url}\n'
            'Password : [PROTECTED IN KDBX4]\n'
            '2FA TOTP : ${activeItem.hasTotp ? "Enabled" : "None"}\n'
            'Passkey  : ${activeItem.hasPasskey ? "Bound (FIDO2 ES256)" : "None"}\n'
            'Tags     : ${activeItem.tags.isEmpty ? "-" : activeItem.tags.join(", ")}\n'
        : 'VAULTKEEP PRINTABLE VAULT SUMMARY\n'
            '========================================\n'
            'Active Items    : ${controller.activeItems.length}\n'
            'Security Score  : ${controller.overallSecurityScore}% (${controller.overallSecurityLabel})\n'
            '2FA (TOTP)      : ${controller.totpCount}\n'
            'Passkeys        : ${controller.passkeyCount}\n';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('top_menu_print_dialog'),
        title: Row(
          children: [
            Icon(Icons.print_outlined, color: TacticalTheme.amberPrimary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Print Item Summary')),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TacticalTheme.bgDeepCarbon,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: TacticalTheme.borderTech),
            ),
            child: SelectableText(
              summaryText,
              style: TacticalTheme.monoStyle(
                fontSize: 12,
                color: TacticalTheme.textPrimary,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            key: const ValueKey('print_copy_summary_button'),
            icon: const Icon(Icons.copy, size: 15),
            label: const Text('Copy Summary'),
            onPressed: () {
              ClipboardGuard.copySecret(summaryText);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Printable summary copied to clipboard.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showChangeCategoryDialog(
    BuildContext context,
    VaultItem item,
  ) async {
    var selected = kEnpassCategories.contains(item.category)
        ? item.category
        : 'Login';
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          key: const ValueKey('top_menu_change_category_dialog'),
          title: Text('Change Category — ${item.title}'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final cat in kEnpassCategories)
                    ListTile(
                      key: ValueKey('change_cat_option_$cat'),
                      dense: true,
                      leading: Icon(
                        _iconForCategory(cat),
                        size: 18,
                        color: selected == cat
                            ? TacticalTheme.amberPrimary
                            : TacticalTheme.cyanTactical,
                      ),
                      title: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected == cat
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: TacticalTheme.textPrimary,
                        ),
                      ),
                      trailing: selected == cat
                          ? Icon(
                              Icons.check,
                              size: 16,
                              color: TacticalTheme.amberPrimary,
                            )
                          : null,
                      onTap: () => setDialogState(() => selected = cat),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('change_category_save_button'),
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && context.mounted) {
      try {
        await controller.changeEntryCategory(item.id, chosen);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Category changed to "$chosen".'),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(VaultController.describe(e))),
          );
        }
      }
    }
  }

  Future<void> _showAddToVaultDialog(
    BuildContext context,
    VaultItem item,
  ) async {
    String? selectedGroupId = controller.selectedGroupId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          key: const ValueKey('top_menu_add_to_vault_dialog'),
          title: Text('Add to Vault / Group — ${item.title}'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    key: const ValueKey('add_to_vault_group_root'),
                    dense: true,
                    leading: Icon(
                      Icons.enhanced_encryption_outlined,
                      size: 18,
                      color: selectedGroupId == null
                          ? TacticalTheme.amberPrimary
                          : TacticalTheme.cyanTactical,
                    ),
                    title: Text(
                      'Primary Vault (Root)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selectedGroupId == null
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: TacticalTheme.textPrimary,
                      ),
                    ),
                    trailing: selectedGroupId == null
                        ? Icon(
                            Icons.check,
                            size: 16,
                            color: TacticalTheme.amberPrimary,
                          )
                        : null,
                    onTap: () => setDialogState(() => selectedGroupId = null),
                  ),
                  for (final g in controller.groups)
                    ListTile(
                      key: ValueKey('add_to_vault_group_${g.id}'),
                      dense: true,
                      leading: Icon(
                        Icons.folder_outlined,
                        size: 18,
                        color: selectedGroupId == g.id
                            ? TacticalTheme.amberPrimary
                            : TacticalTheme.cyanTactical,
                      ),
                      title: Text(
                        g.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selectedGroupId == g.id
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: TacticalTheme.textPrimary,
                        ),
                      ),
                      trailing: selectedGroupId == g.id
                          ? Icon(
                              Icons.check,
                              size: 16,
                              color: TacticalTheme.amberPrimary,
                            )
                          : null,
                      onTap: () => setDialogState(() => selectedGroupId = g.id),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('add_to_vault_save_button'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await controller.moveEntryToGroup(item.id, selectedGroupId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Item vault/group assignment updated.'),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(VaultController.describe(e))),
          );
        }
      }
    }
  }

  Future<void> _showHelpDialog(
    BuildContext context, {
    required String title,
    required String description,
    required String url,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('top_menu_help_dialog'),
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: TacticalTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                url,
                style: TacticalTheme.monoStyle(
                  fontSize: 12,
                  color: TacticalTheme.amberPrimary,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              ClipboardGuard.copySecret(url);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied link: $url')),
              );
            },
            child: const Text('Copy Link'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFeedbackDialog(
    BuildContext context, {
    required String title,
    required bool isBugReport,
  }) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('top_menu_feedback_dialog'),
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isBugReport
                    ? 'Describe the issue you encountered. Zero-knowledge guarantee: no vault contents, passwords, or keys are ever included.'
                    : 'Send feedback or feature requests to the VaultKeep engineering team.',
                style: TextStyle(
                  fontSize: 12,
                  color: TacticalTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('feedback_message_field'),
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: isBugReport ? 'Steps to Reproduce' : 'Message',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('feedback_submit_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBugReport
                ? 'Bug report recorded locally.'
                : 'Thank you for your feedback!',
          ),
        ),
      );
    }
  }

  Future<void> _showCheckUpdatesDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('top_menu_check_updates_dialog'),
        title: const Text('Check for Updates'),
        content: Text(
          'VaultKeep v6.11.19 (KDBX 4.1 / Argon2id)\n\nYou are running the latest version.',
          style: TextStyle(
            fontSize: 13,
            color: TacticalTheme.textSecondary,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTopMenuAction(
    BuildContext context,
    String action, [
    String? activeInspectorId,
  ]) async {
    final messenger = ScaffoldMessenger.of(context);
    final activeItem = _resolveActiveItem(activeInspectorId);

    switch (action) {
      // File Menu
      case 'file_backup':
        await EnpassSettingsDialog.show(
          context,
          controller: controller,
          onChangeMasterPassword: () => _changeMasterPassword(context),
          onSyncVault: () => _syncVault(context),
          initialTab: 5,
        );
        break;
      case 'file_import':
        await _showImportDialog(context);
        break;
      case 'file_export':
        await _showExportDialog(context);
        break;
      case 'file_print':
        await _showPrintDialog(context, activeItem);
        break;
      case 'file_close':
        await controller.lock();
        break;

      // View Menu
      case 'view_show_item_counts':
        controller.updateSettings(
          showSidebarCounts: !controller.showSidebarCounts,
        );
        break;
      case 'view_hide_sensitive':
        controller.updateSettings(
          hideSensitive: !controller.hideSensitive,
        );
        break;
      case 'view_categories':
        controller.updateSettings(
          showSidebarCategories: !controller.showSidebarCategories,
        );
        break;
      case 'view_tags':
        controller.updateSettings(
          showSidebarTags: !controller.showSidebarTags,
        );
        break;
      case 'view_audit_in_sidebar':
        controller.updateSettings(
          showSidebarAudit: !controller.showSidebarAudit,
        );
        break;
      case 'view_show_old_passwords':
        controller.updateSettings(
          includeOldPasswordsInAudit: !controller.includeOldPasswordsInAudit,
        );
        break;
      case 'view_others':
        controller.updateSettings(
          showSidebarOthers: !controller.showSidebarOthers,
        );
        break;
      case 'view_previous_group':
        controller.selectPreviousGroup();
        break;
      case 'view_next_group':
        controller.selectNextGroup();
        break;

      // Item Menu
      case 'item_duplicate':
        if (activeItem == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Select an item first.')),
          );
          return;
        }
        try {
          final newId = await controller.duplicateEntry(activeItem.id);
          if (mounted) {
            setState(() {
              _creatingNewInInspector = false;
              _selectedEntryId = newId;
            });
          }
          messenger.showSnackBar(
            SnackBar(content: Text('Duplicated "${activeItem.title}".')),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text(VaultController.describe(e))),
          );
        }
        break;
      case 'item_archive':
        if (activeItem == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Select an item first.')),
          );
          return;
        }
        try {
          final nextArchived = !activeItem.isArchived;
          await controller.archiveEntry(activeItem.id, archived: nextArchived);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                nextArchived
                    ? 'Archived "${activeItem.title}".'
                    : 'Unarchived "${activeItem.title}".',
              ),
            ),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text(VaultController.describe(e))),
          );
        }
        break;
      case 'item_move_to_trash':
        if (activeItem == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Select an item first.')),
          );
          return;
        }
        try {
          final nextTrashed = !activeItem.isTrashed;
          await controller.moveEntryToTrash(
            activeItem.id,
            trashed: nextTrashed,
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                nextTrashed
                    ? 'Moved "${activeItem.title}" to Trash.'
                    : 'Restored "${activeItem.title}" from Trash.',
              ),
            ),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text(VaultController.describe(e))),
          );
        }
        break;
      case 'item_copy_username':
        if (activeItem == null || activeItem.username.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No username on selected item.')),
          );
          return;
        }
        await _copyUsername(context, activeItem);
        break;
      case 'item_copy_email':
        if (activeItem == null || activeItem.email.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No e-mail on selected item.')),
          );
          return;
        }
        await ClipboardGuard.copySecret(activeItem.email);
        messenger.showSnackBar(
          const SnackBar(content: Text('E-mail copied. Clears in 15 seconds.')),
        );
        break;
      case 'item_copy_password':
        if (activeItem == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Select an item first.')),
          );
          return;
        }
        await _copyPassword(context, activeItem);
        break;
      case 'item_show_passwords':
        final nextHide = !controller.hideSensitive;
        controller.updateSettings(hideSensitive: nextHide);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              nextHide
                  ? 'Sensitive fields hidden.'
                  : 'Passwords revealed in inspector.',
            ),
          ),
        );
        break;
      case 'item_copy_url':
        if (activeItem == null || activeItem.url.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No URL on selected item.')),
          );
          return;
        }
        await ClipboardGuard.copySecret(activeItem.url);
        messenger.showSnackBar(
          const SnackBar(content: Text('URL copied. Clears in 15 seconds.')),
        );
        break;
      case 'item_copy_otp':
        if (activeItem == null || !activeItem.hasTotp) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No TOTP configured on selected item.')),
          );
          return;
        }
        await _copyTotp(context, activeItem);
        break;
      case 'item_launch_url':
        if (activeItem == null || activeItem.url.trim().isEmpty) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No URL on selected item.')),
          );
          return;
        }
        var rawUrl = activeItem.url.trim();
        if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
          rawUrl = 'https://$rawUrl';
        }
        final uri = Uri.tryParse(rawUrl);
        if (uri == null ||
            (uri.scheme != 'https' && uri.scheme != 'http') ||
            uri.host.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Invalid URL on selected item.')),
          );
          return;
        }
        await ClipboardGuard.copySecret(uri.toString());
        if (Platform.isWindows) {
          try {
            unawaited(
              Process.run('rundll32', ['url.dll,FileProtocolHandler', uri.toString()]),
            );
          } catch (_) {}
        }
        messenger.showSnackBar(
          SnackBar(content: Text('Launched ${uri.toString()}')),
        );
        break;
      case 'item_change_category':
        if (activeItem == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Select an item first.')),
          );
          return;
        }
        await _showChangeCategoryDialog(context, activeItem);
        break;
      case 'item_add_to_vault':
        if (activeItem == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Select an item first.')),
          );
          return;
        }
        await _showAddToVaultDialog(context, activeItem);
        break;

      // Tools Menu
      case 'tools_lock':
        await controller.lock();
        break;
      case 'tools_sync_now':
        await _syncVault(context);
        break;
      case 'tools_clear_clipboard':
        await ClipboardGuard.clearNow();
        messenger.showSnackBar(
          const SnackBar(content: Text('Clipboard cleared.')),
        );
        break;
      case 'tools_generate_password':
        if (context.mounted) {
          await PasswordGeneratorDialog.show(context, controller: controller);
        }
        break;
      case 'tools_auto_backups':
        await EnpassSettingsDialog.show(
          context,
          controller: controller,
          onChangeMasterPassword: () => _changeMasterPassword(context),
          onSyncVault: () => _syncVault(context),
          initialTab: 5,
        );
        break;
      case 'tools_clear_recent_items':
        controller.clearRecentItems();
        messenger.showSnackBar(
          const SnackBar(content: Text('Recent items cleared.')),
        );
        break;

      // Help Menu
      case 'help_support_forum':
        await _showHelpDialog(
          context,
          title: 'Support Forum',
          description:
              'Join the VaultKeep community forum to discuss KDBX4 encryption, Argon2id parameters, passkeys, and desktop/mobile workflows.',
          url: 'https://discussion.enpass.io',
        );
        break;
      case 'help_blog':
        await _showHelpDialog(
          context,
          title: 'Blog',
          description:
              'Read the latest security advisories, cryptographic architecture notes, and release announcements.',
          url: 'https://www.enpass.io/blog',
        );
        break;
      case 'help_twitter':
        await _showHelpDialog(
          context,
          title: 'X(Twitter)',
          description:
              'Follow official release updates and security tips on X (formerly Twitter).',
          url: 'https://x.com/EnpassApp',
        );
        break;
      case 'help_report_bug':
        await _showFeedbackDialog(
          context,
          title: 'Report a Bug',
          isBugReport: true,
        );
        break;
      case 'help_write_to_us':
        await _showFeedbackDialog(
          context,
          title: 'Write to Us',
          isBugReport: false,
        );
        break;
      case 'help_check_updates':
        await _showCheckUpdatesDialog(context);
        break;
      case 'help_about':
        await EnpassSettingsDialog.show(
          context,
          controller: controller,
          onChangeMasterPassword: () => _changeMasterPassword(context),
          onSyncVault: () => _syncVault(context),
          initialTab: 8,
        );
        break;
    }
  }

  PopupMenuItem<String> _buildTopPopupMenuItem({
    required String value,
    required String label,
    String? shortcut,
    bool? checked,
    bool hasCheckColumn = false,
  }) {
    return PopupMenuItem<String>(
      key: ValueKey('menu_item_$value'),
      value: value,
      height: 32,
      child: SizedBox(
        width: 225,
        child: Row(
          children: [
            if (hasCheckColumn) ...[
              SizedBox(
                width: 18,
                child: checked == true
                    ? Icon(
                        Icons.check,
                        size: 14,
                        color: TacticalTheme.textPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: TacticalTheme.textPrimary,
                ),
              ),
            ),
            if (shortcut != null) ...[
              const SizedBox(width: 12),
              Text(
                shortcut,
                style: TextStyle(
                  fontSize: 11.5,
                  color: TacticalTheme.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopDropdownMenu({
    required BuildContext context,
    required String menuKey,
    required String label,
    required List<PopupMenuEntry<String>> Function(BuildContext) itemBuilder,
    String? activeInspectorId,
  }) {
    return PopupMenuButton<String>(
      key: ValueKey(menuKey),
      tooltip: '$label menu',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      color: TacticalTheme.bgElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: TacticalTheme.borderSubtle, width: 1),
      ),
      onSelected: (action) =>
          unawaited(_handleTopMenuAction(context, action, activeInspectorId)),
      itemBuilder: itemBuilder,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: TacticalTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTopTelemetryBar(
    BuildContext context,
    bool isWide, [
    String? activeInspectorId,
  ]) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: TacticalTheme.bgPanel,
        border: Border(
          bottom: BorderSide(color: TacticalTheme.borderTech, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.shield,
            size: 18,
            color: TacticalTheme.amberPrimary,
          ),
          const SizedBox(width: 8),
          if (isWide) ...[
            Text(
              'VaultKeep',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: TacticalTheme.textPrimary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: TacticalTheme.bgDeepCarbon,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: TacticalTheme.borderTech, width: 1),
              ),
              child: Text(
                '[KDBX4 / ARGON2ID]',
                style: TacticalTheme.monoStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: TacticalTheme.amberPrimary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Enpass Top Menu Bar (`File`, `View`, `Item`, `Tools`, `Help`)
            _buildTopDropdownMenu(
              context: context,
              menuKey: 'top_menu_file',
              label: 'File',
              activeInspectorId: activeInspectorId,
              itemBuilder: (_) => [
                _buildTopPopupMenuItem(
                  value: 'file_backup',
                  label: 'Backup',
                ),
                const PopupMenuDivider(height: 8),
                _buildTopPopupMenuItem(
                  value: 'file_import',
                  label: 'Import',
                ),
                _buildTopPopupMenuItem(
                  value: 'file_export',
                  label: 'Export',
                ),
                const PopupMenuDivider(height: 8),
                _buildTopPopupMenuItem(
                  value: 'file_print',
                  label: 'Print',
                ),
                const PopupMenuDivider(height: 8),
                _buildTopPopupMenuItem(
                  value: 'file_close',
                  label: 'Close',
                  shortcut: 'Ctrl+W',
                ),
              ],
            ),
            _buildTopDropdownMenu(
              context: context,
              menuKey: 'top_menu_view',
              label: 'View',
              activeInspectorId: activeInspectorId,
              itemBuilder: (_) => [
                _buildTopPopupMenuItem(
                  value: 'view_show_item_counts',
                  label: 'Show Item Counts',
                  checked: controller.showSidebarCounts,
                  hasCheckColumn: true,
                ),
                _buildTopPopupMenuItem(
                  value: 'view_hide_sensitive',
                  label: 'Hide Sensitive',
                  checked: controller.hideSensitive,
                  hasCheckColumn: true,
                ),
                const PopupMenuDivider(height: 8),
                _buildTopPopupMenuItem(
                  value: 'view_categories',
                  label: 'Categories',
                  checked: controller.showSidebarCategories,
                  hasCheckColumn: true,
                ),
                _buildTopPopupMenuItem(
                  value: 'view_tags',
                  label: 'Tags',
                  checked: controller.showSidebarTags,
                  hasCheckColumn: true,
                ),
                _buildTopPopupMenuItem(
                  value: 'view_audit_in_sidebar',
                  label: 'Audit in sidebar',
                  checked: controller.showSidebarAudit,
                  hasCheckColumn: true,
                ),
                _buildTopPopupMenuItem(
                  value: 'view_show_old_passwords',
                  label: 'Show Old Passwords',
                  checked: controller.includeOldPasswordsInAudit,
                  hasCheckColumn: true,
                ),
                _buildTopPopupMenuItem(
                  value: 'view_others',
                  label: 'Others',
                  checked: controller.showSidebarOthers,
                  hasCheckColumn: true,
                ),
                const PopupMenuDivider(height: 8),
                _buildTopPopupMenuItem(
                  value: 'view_previous_group',
                  label: 'Previous Group',
                  shortcut: 'Ctrl+up',
                  hasCheckColumn: true,
                ),
                _buildTopPopupMenuItem(
                  value: 'view_next_group',
                  label: 'Next Group',
                  shortcut: 'Ctrl+down',
                  hasCheckColumn: true,
                ),
              ],
            ),
            _buildTopDropdownMenu(
              context: context,
              menuKey: 'top_menu_item',
              label: 'Item',
              activeInspectorId: activeInspectorId,
              itemBuilder: (_) => [
                _buildTopPopupMenuItem(
                  value: 'item_duplicate',
                  label: 'Duplicate',
                  shortcut: 'Ctrl+D',
                ),
                _buildTopPopupMenuItem(
                  value: 'item_archive',
                  label: 'Archive',
                  shortcut: 'Shift+Backspace',
                ),
                _buildTopPopupMenuItem(
                  value: 'item_move_to_trash',
                  label: 'Move to Trash',
                  shortcut: 'Backspace',
                ),
                const PopupMenuDivider(height: 8),
                _buildTopPopupMenuItem(
                  value: 'item_copy_username',
                  label: 'Copy Username',
                  shortcut: 'Shift+Ctrl+U',
                ),
                _buildTopPopupMenuItem(
                  value: 'item_copy_email',
                  label: 'Copy E-mail',
                  shortcut: 'Shift+Ctrl+E',
                ),
                _buildTopPopupMenuItem(
                  value: 'item_copy_password',
                  label: 'Copy Password',
                  shortcut: 'Shift+Ctrl+P',
                ),
                _buildTopPopupMenuItem(
                  value: 'item_show_passwords',
                  label: 'Show Passwords',
                  shortcut: 'Shift+Ctrl+H',
                ),
                _buildTopPopupMenuItem(
                  value: 'item_copy_url',
                  label: 'Copy URL',
                  shortcut: 'Shift+Ctrl+R',
                ),
                _buildTopPopupMenuItem(
                  value: 'item_copy_otp',
                  label: 'Copy OTP',
                  shortcut: 'Shift+Ctrl+T',
                ),
                _buildTopPopupMenuItem(
                  value: 'item_launch_url',
                  label: 'Launch URL',
                  shortcut: 'Shift+Ctrl+L',
                ),
                const PopupMenuDivider(height: 8),
                _buildTopPopupMenuItem(
                  value: 'item_change_category',
                  label: 'Change Category',
                ),
                _buildTopPopupMenuItem(
                  value: 'item_add_to_vault',
                  label: 'Add to Vault',
                ),
              ],
            ),
            _buildTopDropdownMenu(
              context: context,
              menuKey: 'top_menu_tools',
              label: 'Tools',
              activeInspectorId: activeInspectorId,
              itemBuilder: (_) => [
                _buildTopPopupMenuItem(
                  value: 'tools_lock',
                  label: 'Lock',
                  shortcut: 'Ctrl+L',
                ),
                _buildTopPopupMenuItem(
                  value: 'tools_sync_now',
                  label: 'Sync Now',
                  shortcut: 'Ctrl+J',
                ),
                _buildTopPopupMenuItem(
                  value: 'tools_clear_clipboard',
                  label: 'Clear Clipboard',
                  shortcut: 'Ctrl+B',
                ),
                _buildTopPopupMenuItem(
                  value: 'tools_generate_password',
                  label: 'Generate Password',
                  shortcut: 'Ctrl+G',
                ),
                const PopupMenuDivider(height: 8),
                _buildTopPopupMenuItem(
                  value: 'tools_auto_backups',
                  label: 'Auto Backups',
                ),
                _buildTopPopupMenuItem(
                  value: 'tools_clear_recent_items',
                  label: 'Clear Recent Items',
                ),
              ],
            ),
            _buildTopDropdownMenu(
              context: context,
              menuKey: 'top_menu_help',
              label: 'Help',
              activeInspectorId: activeInspectorId,
              itemBuilder: (_) => [
                _buildTopPopupMenuItem(
                  value: 'help_support_forum',
                  label: 'Support Forum',
                ),
                _buildTopPopupMenuItem(
                  value: 'help_blog',
                  label: 'Blog',
                ),
                const PopupMenuDivider(height: 8),
                _buildTopPopupMenuItem(
                  value: 'help_twitter',
                  label: 'X(Twitter)',
                ),
                const PopupMenuDivider(height: 8),
                _buildTopPopupMenuItem(
                  value: 'help_report_bug',
                  label: 'Report a Bug',
                ),
                _buildTopPopupMenuItem(
                  value: 'help_write_to_us',
                  label: 'Write to Us',
                ),
                const PopupMenuDivider(height: 8),
                _buildTopPopupMenuItem(
                  value: 'help_check_updates',
                  label: 'Check for Updates',
                ),
                _buildTopPopupMenuItem(
                  value: 'help_about',
                  label: 'About',
                ),
              ],
            ),
            const Spacer(),
          ] else
            Expanded(
              child: Text(
                'VaultKeep',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: TacticalTheme.textPrimary,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          if (isWide) ...[
            // Enpass `+ New Item | v` Top Action Button (`Enpass_UNGNDpANfa.png`)
            PopupMenuButton<String>(
              key: const ValueKey('vault_button_new_item_top'),
              tooltip: 'Create New Item',
              position: PopupMenuPosition.under,
              offset: const Offset(0, 4),
              onOpened: () => _openEntry(context, isDesktop: true),
              onSelected: (val) {
                if (val == '__group__') {
                  _createGroup(context);
                } else {
                  _openEntry(context, category: val, isDesktop: true);
                }
              },
              itemBuilder: (ctx) => [
                for (final cat in kEnpassCategories)
                  PopupMenuItem<String>(
                    key: ValueKey('new_item_category_$cat'),
                    value: cat,
                    height: 36,
                    child: Row(
                      children: [
                        Icon(
                          _iconForCategory(cat),
                          size: 16,
                          color: TacticalTheme.amberPrimary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'New $cat',
                          style: TextStyle(
                            fontSize: 13,
                            color: TacticalTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  key: const ValueKey('new_item_group'),
                  value: '__group__',
                  height: 36,
                  child: Row(
                    children: [
                      Icon(
                        Icons.create_new_folder_outlined,
                        size: 16,
                        color: TacticalTheme.cyanTactical,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'New Group...',
                        style: TextStyle(
                          fontSize: 13,
                          color: TacticalTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: TacticalTheme.amberPrimary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add,
                      size: 15,
                      color: TacticalTheme.bgDeepCarbon,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'New Item',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: TacticalTheme.bgDeepCarbon,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 15,
                      color: TacticalTheme.bgDeepCarbon,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: TacticalTheme.bgDeepCarbon,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: TacticalTheme.borderTech, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SECURITY SCORE: ',
                    style: TacticalTheme.monoStyle(
                      fontSize: 11,
                      color: TacticalTheme.textSecondary,
                    ),
                  ),
                  Text(
                    '${controller.overallSecurityScore}% (${controller.overallSecurityLabel})',
                    style: TacticalTheme.monoStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: TacticalTheme.emeraldReady,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
          IconButton(
            key: const ValueKey('vault_button_password_generator'),
            tooltip: 'Password Generator',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            icon: Icon(
              Icons.password,
              size: 19,
              color: TacticalTheme.amberBright,
            ),
            onPressed: () => PasswordGeneratorDialog.show(
              context,
              controller: controller,
            ),
          ),
          IconButton(
            tooltip: 'Autofill Query',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            icon: Icon(
              Icons.auto_mode,
              size: 19,
              color: TacticalTheme.cyanTactical,
            ),
            onPressed: () => _showAutofillModal(context),
          ),
          IconButton(
            key: const ValueKey('vault_button_rotate_password'),
            tooltip: 'Rotate Master Password',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            icon: Icon(
              Icons.vpn_key_outlined,
              size: 19,
              color: TacticalTheme.amberPrimary,
            ),
            onPressed: () => _changeMasterPassword(context),
          ),
          IconButton(
            key: const ValueKey('vault_button_settings'),
            tooltip: 'Settings',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            icon: Icon(
              Icons.settings_outlined,
              size: 19,
              color: TacticalTheme.textPrimary,
            ),
            onPressed: () => EnpassSettingsDialog.show(
              context,
              controller: controller,
              onChangeMasterPassword: () => _changeMasterPassword(context),
              onSyncVault: () => _syncVault(context),
            ),
          ),
          if (isWide)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                  side: BorderSide(color: TacticalTheme.borderTech),
                ),
                icon: Icon(
                  Icons.sync,
                  size: 15,
                  color: TacticalTheme.cyanTactical,
                ),
                label: Text(
                  '3-WAY SYNC',
                  style: TacticalTheme.monoStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: TacticalTheme.cyanTactical,
                  ),
                ),
                onPressed: () => _syncVault(context),
              ),
            )
          else
            IconButton(
              tooltip: 'Sync Vault (3-Way Merge)',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(
                Icons.sync,
                size: 19,
                color: TacticalTheme.cyanTactical,
              ),
              onPressed: () => _syncVault(context),
            ),
          if (isWide)
            const Tooltip(
              message: 'Sync Vault (3-Way Merge)',
              child: SizedBox.shrink(),
            ),
          const SizedBox(width: 4),
          if (isWide)
            Tooltip(
              message: 'Lock now',
              child: InkWell(
                key: const ValueKey('vault_button_lock'),
                onTap: () => controller.lock(),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: TacticalTheme.amberDim,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: TacticalTheme.amberPrimary,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock,
                        size: 14,
                        color: TacticalTheme.amberBright,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'LOCK',
                        style: TacticalTheme.monoStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: TacticalTheme.amberBright,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            IconButton(
              key: const ValueKey('vault_button_lock'),
              tooltip: 'Lock now',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(
                Icons.lock_outline,
                size: 19,
                color: TacticalTheme.amberPrimary,
              ),
              onPressed: () => controller.lock(),
            ),
        ],
      ),
    );
  }

  Widget _buildLeftGroupTree(
    BuildContext context,
    List<VaultGroup> groups,
    String? selectedGroupId,
    int totalCount,
  ) {
    final showCounts = controller.showSidebarCounts;
    final tags = controller.allTags;

    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: TacticalTheme.bgPanel,
        border: Border(
          right: BorderSide(color: TacticalTheme.borderTech, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Narrow Tactical Icon Strip
          Container(
            width: 42,
            decoration: BoxDecoration(
              color: TacticalTheme.bgDeepCarbon,
              border: Border(
                right: BorderSide(color: TacticalTheme.borderSubtle, width: 1),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Tooltip(
                  message: 'Home Security Audit',
                  child: InkWell(
                    onTap: () => controller.openHomeDashboard(),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: controller.showHomeDashboard
                            ? TacticalTheme.amberPrimary
                            : TacticalTheme.amberDim,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: TacticalTheme.amberPrimary,
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: controller.showHomeDashboard
                            ? TacticalTheme.bgDeepCarbon
                            : TacticalTheme.amberBright,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                IconButton(
                  tooltip: 'New Credential',
                  icon: Icon(
                    Icons.note_add_outlined,
                    size: 18,
                    color: TacticalTheme.textSecondary,
                  ),
                  onPressed: () => _openEntry(context, isDesktop: true),
                ),
                IconButton(
                  tooltip: 'New Group',
                  icon: Icon(
                    Icons.create_new_folder_outlined,
                    size: 18,
                    color: TacticalTheme.textSecondary,
                  ),
                  onPressed: () => _createGroup(context),
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: Icon(
                    Icons.settings_outlined,
                    size: 18,
                    color: TacticalTheme.textSecondary,
                  ),
                  onPressed: () => EnpassSettingsDialog.show(
                    context,
                    controller: controller,
                    onChangeMasterPassword: () =>
                        _changeMasterPassword(context),
                    onSyncVault: () => _syncVault(context),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Lock Vault',
                  icon: Icon(
                    Icons.logout,
                    size: 18,
                    color: TacticalTheme.textMuted,
                  ),
                  onPressed: () => controller.lock(),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // Enpass Sidebar + Group Tree Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Enpass `Primary` Vault Selector Header (`Enpass_UNGNDpANfa.png`)
                InkWell(
                  key: const ValueKey('sidebar_primary_vault_header'),
                  onTap: () => EnpassSettingsDialog.show(
                    context,
                    controller: controller,
                    onChangeMasterPassword: () =>
                        _changeMasterPassword(context),
                    onSyncVault: () => _syncVault(context),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
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
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: TacticalTheme.amberDim,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: TacticalTheme.amberPrimary,
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.enhanced_encryption_outlined,
                            size: 15,
                            color: TacticalTheme.amberBright,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Primary',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: TacticalTheme.textPrimary,
                                ),
                              ),
                              Text(
                                '$totalCount Items â€¢ ${controller.connectedStorageProvider}',
                                style: TacticalTheme.monoStyle(
                                  fontSize: 10,
                                  color: TacticalTheme.textMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: TacticalTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Group Tree',
                        style: TacticalTheme.monoStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: TacticalTheme.textSecondary,
                        ),
                      ),
                      InkWell(
                        onTap: () => _createGroup(context),
                        child: Icon(
                          Icons.add,
                          size: 16,
                          color: TacticalTheme.amberPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _GroupTreeTile(
                          key: const ValueKey('sidebar_home'),
                          name: 'Home',
                          count: totalCount,
                          showCount: showCounts,
                          selected: controller.showHomeDashboard,
                          icon: Icons.home_outlined,
                          onTap: () => controller.openHomeDashboard(),
                        ),
                        _GroupTreeTile(
                          name: 'All Items',
                          count: totalCount,
                          showCount: showCounts,
                          selected: !controller.showHomeDashboard &&
                              selectedGroupId == null &&
                              controller.selectedCategory ==
                                  VaultCategoryFilter.all &&
                              controller.selectedItemCategory == null &&
                              controller.selectedTag == null,
                          icon: Icons.folder_special,
                          onTap: () => controller.selectGroup(null),
                        ),
                        _GroupTreeTile(
                          key: const ValueKey('sidebar_favorites'),
                          name: 'Favorites',
                          count: controller.favoritesCount,
                          showCount: showCounts,
                          selected: controller.selectedCategory ==
                              VaultCategoryFilter.favorites,
                          icon: Icons.star_outline,
                          onTap: () => controller.selectCategory(
                            VaultCategoryFilter.favorites,
                          ),
                        ),

                        // Categories (All 10 Enpass Categories)
                        if (controller.showSidebarCategories) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                            child: Text(
                              'CATEGORIES',
                              style: TacticalTheme.monoStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: TacticalTheme.textMuted,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          for (final cat in kEnpassCategories)
                            _GroupTreeTile(
                              key: ValueKey('sidebar_cat_$cat'),
                              name: cat,
                              count: controller.categoryCount(cat),
                              showCount: showCounts,
                              selected: controller.selectedItemCategory == cat,
                              icon: _iconForCategory(cat),
                              onTap: () => controller.selectItemCategory(
                                controller.selectedItemCategory == cat
                                    ? null
                                    : cat,
                              ),
                            ),
                        ],

                        // Audit Section (`Enpass_UNGNDpANfa.png` & `Enpass_4B5a9NsMjk.png`)
                        if (controller.showSidebarAudit) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                            child: Text(
                              'AUDIT',
                              style: TacticalTheme.monoStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: TacticalTheme.textMuted,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          _GroupTreeTile(
                            name: 'Excellent',
                            count: controller.excellentCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.auditExcellent,
                            icon: Icons.verified_outlined,
                            onTap: () => controller.selectCategory(
                              VaultCategoryFilter.auditExcellent,
                            ),
                          ),
                          _GroupTreeTile(
                            name: 'Compromised',
                            count: controller.compromisedCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.auditCompromised,
                            icon: Icons.gpp_bad_outlined,
                            onTap: () => controller.selectCategory(
                              VaultCategoryFilter.auditCompromised,
                            ),
                          ),
                          _GroupTreeTile(
                            name: 'Weak',
                            count: controller.weakCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.auditWeak,
                            icon: Icons.warning_amber_rounded,
                            onTap: () => controller.selectCategory(
                              VaultCategoryFilter.auditWeak,
                            ),
                          ),
                          _GroupTreeTile(
                            name: 'Identical',
                            count: controller.identicalCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.auditIdentical,
                            icon: Icons.copy_all_outlined,
                            onTap: () => controller.selectCategory(
                              VaultCategoryFilter.auditIdentical,
                            ),
                          ),
                          _GroupTreeTile(
                            name: 'Breached',
                            count: controller.breachedCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.auditBreached,
                            icon: Icons.report_problem_outlined,
                            onTap: () => controller.selectCategory(
                              VaultCategoryFilter.auditBreached,
                            ),
                          ),
                          _GroupTreeTile(
                            key: const ValueKey(
                              'sidebar_audit_two_fa_supported',
                            ),
                            name: '2FA Supported',
                            count: controller.twoFaSupportedCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.auditTwoFaSupported,
                            icon: Icons.phonelink_lock_outlined,
                            onTap: () => controller.selectCategory(
                              VaultCategoryFilter.auditTwoFaSupported,
                            ),
                          ),
                          _GroupTreeTile(
                            name: 'Passkey Supported',
                            count: controller.passkeySupportedCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.passkeySupported,
                            icon: Icons.verified_user_outlined,
                            onTap: () => controller.selectCategory(
                              controller.selectedCategory ==
                                      VaultCategoryFilter.passkeySupported
                                  ? VaultCategoryFilter.all
                                  : VaultCategoryFilter.passkeySupported,
                            ),
                          ),
                          _GroupTreeTile(
                            name: '2FA (TOTP)',
                            count: controller.totpCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.totp2fa,
                            icon: Icons.timer_outlined,
                            onTap: () => controller.selectCategory(
                              controller.selectedCategory ==
                                      VaultCategoryFilter.totp2fa
                                  ? VaultCategoryFilter.all
                                  : VaultCategoryFilter.totp2fa,
                            ),
                          ),
                          _GroupTreeTile(
                            name: 'Expired',
                            count: controller.expiredCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.auditExpired,
                            icon: Icons.schedule_outlined,
                            onTap: () => controller.selectCategory(
                              VaultCategoryFilter.auditExpired,
                            ),
                          ),
                          if (controller.includeOldPasswordsInAudit) ...[
                            _GroupTreeTile(
                              key: const ValueKey('sidebar_audit_1_3_years'),
                              name: '1-3 Years old',
                              count: controller.age1To3YearsCount,
                              showCount: showCounts,
                              selected: controller.selectedCategory ==
                                  VaultCategoryFilter.auditAge1To3Years,
                              icon: Icons.history_toggle_off,
                              onTap: () => controller.selectCategory(
                                VaultCategoryFilter.auditAge1To3Years,
                              ),
                            ),
                            _GroupTreeTile(
                              key: const ValueKey('sidebar_audit_3_6_months'),
                              name: '3-6 Months old',
                              count: controller.age3To6MonthsCount,
                              showCount: showCounts,
                              selected: controller.selectedCategory ==
                                  VaultCategoryFilter.auditAge3To6Months,
                              icon: Icons.history,
                              onTap: () => controller.selectCategory(
                                VaultCategoryFilter.auditAge3To6Months,
                              ),
                            ),
                            _GroupTreeTile(
                              key: const ValueKey('sidebar_audit_6_12_months'),
                              name: '6-12 Months old',
                              count: controller.age6To12MonthsCount,
                              showCount: showCounts,
                              selected: controller.selectedCategory ==
                                  VaultCategoryFilter.auditAge6To12Months,
                              icon: Icons.update,
                              onTap: () => controller.selectCategory(
                                VaultCategoryFilter.auditAge6To12Months,
                              ),
                            ),
                          ],
                        ],

                        // Others Section (`Enpass_UNGNDpANfa.png` & `Enpass_4B5a9NsMjk.png`)
                        if (controller.showSidebarOthers) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                            child: Text(
                              'OTHERS',
                              style: TacticalTheme.monoStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: TacticalTheme.textMuted,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          _GroupTreeTile(
                            key: const ValueKey('sidebar_one_time_codes'),
                            name: 'One-time Codes',
                            count: controller.totpCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.totp2fa,
                            icon: Icons.pin_outlined,
                            onTap: () => controller.selectCategory(
                              VaultCategoryFilter.totp2fa,
                            ),
                          ),
                          _GroupTreeTile(
                            name: 'Passkeys',
                            count: controller.passkeyCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.passkeys,
                            icon: Icons.fingerprint,
                            onTap: () => controller.selectCategory(
                              controller.selectedCategory ==
                                      VaultCategoryFilter.passkeys
                                  ? VaultCategoryFilter.all
                                  : VaultCategoryFilter.passkeys,
                            ),
                          ),
                          _GroupTreeTile(
                            name: 'Attachments',
                            count: controller.attachmentsCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.attachments,
                            icon: Icons.attach_file,
                            onTap: () => controller.selectCategory(
                              VaultCategoryFilter.attachments,
                            ),
                          ),
                          _GroupTreeTile(
                            name: 'Archived',
                            count: controller.archivedCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.archived,
                            icon: Icons.archive_outlined,
                            onTap: () => controller.selectCategory(
                              VaultCategoryFilter.archived,
                            ),
                          ),
                          _GroupTreeTile(
                            name: 'Trashed',
                            count: controller.trashedCount,
                            showCount: showCounts,
                            selected: controller.selectedCategory ==
                                VaultCategoryFilter.trashed,
                            icon: Icons.delete_outline,
                            onTap: () => controller.selectCategory(
                              VaultCategoryFilter.trashed,
                            ),
                          ),
                        ],

                        // Tags Section
                        if (controller.showSidebarTags && tags.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                            child: Text(
                              'TAGS',
                              style: TacticalTheme.monoStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: TacticalTheme.textMuted,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          for (final t in tags)
                            _GroupTreeTile(
                              name: t,
                              count: controller.activeItems
                                  .where(
                                    (i) => i.tags.any(
                                      (x) =>
                                          x.toLowerCase() == t.toLowerCase(),
                                    ),
                                  )
                                  .length,
                              showCount: showCounts,
                              selected: controller.selectedTag == t,
                              icon: Icons.sell_outlined,
                              onTap: () => controller.selectTag(
                                controller.selectedTag == t ? null : t,
                              ),
                            ),
                        ],

                        if (groups.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                            child: Text(
                              'GROUPS',
                              style: TacticalTheme.monoStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: TacticalTheme.textMuted,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        for (final g in groups)
                          _GroupTreeTile(
                            name: g.name,
                            count: g.entryCount,
                            showCount: showCounts,
                            selected: selectedGroupId == g.id,
                            icon: Icons.folder,
                            onTap: () => controller.selectGroup(
                              selectedGroupId == g.id ? null : g.id,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: OutlinedButton.icon(
                    icon: Icon(
                      Icons.add,
                      size: 15,
                      color: TacticalTheme.amberPrimary,
                    ),
                    label: Text(
                      'NEW GROUP',
                      style: TacticalTheme.monoStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: TacticalTheme.amberPrimary,
                      ),
                    ),
                    onPressed: () => _createGroup(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialRow(
    BuildContext context,
    VaultItem item,
    List<VaultGroup> groups, {
    required bool isSelected,
    required bool isDesktop,
  }) {
    final groupLabel = _resolveGroupLabel(item, groups);

    return InkWell(
      key: ValueKey('vault_row_${item.id}'),
      onTap: () => _openEntry(context, id: item.id, isDesktop: isDesktop),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? TacticalTheme.bgHover : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected
                  ? TacticalTheme.amberPrimary
                  : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(
              color: TacticalTheme.borderSubtle,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            if (controller.showWebsiteIcons) ...[
              TacticalDomainAvatar(
                title: item.title,
                url: item.url,
                size: 32,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: TacticalTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.isFavorite) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.star,
                          size: 14,
                          color: TacticalTheme.amberBright,
                        ),
                      ],
                      if (item.hasPasskey) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.fingerprint,
                          size: 14,
                          color: TacticalTheme.emeraldReady,
                        ),
                      ],
                    ],
                  ),
                  if (controller.showSubtitles) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.username.isNotEmpty
                          ? item.username
                          : (item.email.isNotEmpty ? item.email : item.url),
                      style: TacticalTheme.monoStyle(
                        fontSize: 11,
                        color: TacticalTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                ],
              ),
            ),
            if (isDesktop) ...[
              if (item.hasPasskey) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: TacticalTheme.emeraldDim,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: TacticalTheme.emeraldReady,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'PASSKEY',
                    style: TacticalTheme.monoStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: TacticalTheme.emeraldReady,
                    ),
                  ),
                ),
              ] else if (item.passkeySupported) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: TacticalTheme.cyanDim,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: TacticalTheme.cyanTactical,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'PASSKEY READY',
                    style: TacticalTheme.monoStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: TacticalTheme.cyanTactical,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                '[$groupLabel]',
                style: TacticalTheme.monoStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: TacticalTheme.amberPrimary,
                ),
              ),
              const SizedBox(width: 14),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDesktop) ...[
                  TacticalActionSquare(
                    icon: Icons.person,
                    tooltip: 'Copy username',
                    color: TacticalTheme.cyanTactical,
                    onPressed: () => _copyUsername(context, item),
                  ),
                  const SizedBox(width: 6),
                ],
                TacticalActionSquare(
                  icon: Icons.key,
                  tooltip: 'Copy password',
                  color: TacticalTheme.amberPrimary,
                  onPressed: () => _copyPassword(context, item),
                ),
                if (item.hasTotp) ...[
                  const SizedBox(width: 6),
                  TacticalActionSquare(
                    key: ValueKey('vault_copy_totp_${item.id}'),
                    icon: Icons.pin_outlined,
                    tooltip: 'Copy TOTP code',
                    color: TacticalTheme.amberBright,
                    onPressed: () => _copyTotp(context, item),
                  ),
                ],
                if (isDesktop) ...[
                  const SizedBox(width: 6),
                  TacticalActionSquare(
                    icon: Icons.timer_outlined,
                    tooltip: 'Inspect entry & TOTP',
                    color: TacticalTheme.cyanTactical,
                    onPressed: () =>
                        _openEntry(context, id: item.id, isDesktop: true),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<VaultItem> _filterAndSortItems() {
    final allItems = controller.items;
    final selectedGroupId = controller.selectedGroupId;
    final selectedCategory = controller.selectedCategory;
    final selectedItemCat = controller.selectedItemCategory;
    final selectedTag = controller.selectedTag;
    final groups = controller.groups;

    // Exclude archived/trashed unless specifically viewing Archived or Trashed
    final basePool = switch (selectedCategory) {
      VaultCategoryFilter.archived =>
        allItems.where((i) => !i.isTrashed && i.isArchived).toList(),
      VaultCategoryFilter.trashed =>
        allItems.where((i) => i.isTrashed).toList(),
      _ => allItems.where((i) => !i.isTrashed && !i.isArchived).toList(),
    };

    final isRootGroup =
        groups.isNotEmpty && selectedGroupId == groups.first.id;
    final selectedGroupName = selectedGroupId == null
        ? null
        : groups
                .where((g) => g.id == selectedGroupId)
                .map((g) => g.name)
                .firstOrNull ??
            selectedGroupId;

    var filtered = selectedGroupName == null
        ? basePool
        : basePool
            .where(
              (i) =>
                  i.groupName == selectedGroupName ||
                  i.groupName == selectedGroupId ||
                  (isRootGroup &&
                      (i.groupName == null || i.groupName!.isEmpty)),
            )
            .toList();

    if (selectedItemCat != null) {
      final target = selectedItemCat.toLowerCase();
      filtered = filtered
          .where((i) => i.category.toLowerCase() == target)
          .toList();
    }

    if (selectedTag != null) {
      final target = selectedTag.toLowerCase();
      filtered = filtered
          .where((i) => i.tags.any((t) => t.toLowerCase() == target))
          .toList();
    }

    filtered = switch (selectedCategory) {
      VaultCategoryFilter.all ||
      VaultCategoryFilter.archived ||
      VaultCategoryFilter.trashed =>
        filtered,
      VaultCategoryFilter.favorites =>
        filtered.where((i) => i.isFavorite).toList(),
      VaultCategoryFilter.passkeys =>
        filtered.where((i) => i.hasPasskey).toList(),
      VaultCategoryFilter.passkeySupported =>
        filtered.where((i) => i.passkeySupported).toList(),
      VaultCategoryFilter.totp2fa =>
        filtered.where((i) => i.hasTotp).toList(),
      VaultCategoryFilter.auditExcellent => filtered
          .where(
            (i) =>
                !i.isWeak &&
                !i.isIdentical &&
                !i.isCompromised &&
                !i.isBreached &&
                i.strengthScore >= 75,
          )
          .toList(),
      VaultCategoryFilter.auditCompromised =>
        filtered.where((i) => i.isCompromised).toList(),
      VaultCategoryFilter.auditWeak =>
        filtered.where((i) => i.isWeak).toList(),
      VaultCategoryFilter.auditIdentical =>
        filtered.where((i) => i.isIdentical).toList(),
      VaultCategoryFilter.auditBreached =>
        filtered.where((i) => i.isBreached).toList(),
      VaultCategoryFilter.auditTwoFaSupported =>
        filtered.where((i) => i.twoFaSupported).toList(),
      VaultCategoryFilter.auditExpired =>
        filtered.where((i) => i.isExpired).toList(),
      VaultCategoryFilter.auditAge3To6Months =>
        filtered.where(VaultController.isAge3To6Months).toList(),
      VaultCategoryFilter.auditAge6To12Months =>
        filtered.where(VaultController.isAge6To12Months).toList(),
      VaultCategoryFilter.auditAge1To3Years =>
        filtered.where(VaultController.isAge1To3Years).toList(),
      VaultCategoryFilter.attachments =>
        filtered.where((i) => i.hasAttachment).toList(),
    };

    final sorted = List.of(filtered);
    sorted.sort((a, b) {
      final cmp = switch (controller.sortField) {
        VaultSortField.title =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        VaultSortField.username =>
          a.username.toLowerCase().compareTo(b.username.toLowerCase()),
        VaultSortField.url =>
          a.url.toLowerCase().compareTo(b.url.toLowerCase()),
        VaultSortField.revisionDate =>
          (b.revisionDate ?? 0).compareTo(a.revisionDate ?? 0),
      };
      return controller.sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  static String _alphaHeaderFor(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '#';
    final first = trimmed[0].toUpperCase();
    if (RegExp(r'[0-9]').hasMatch(first)) return first;
    if (RegExp(r'[A-Z]').hasMatch(first)) return first;
    return '#';
  }

  Widget _buildGroupedListView(
    BuildContext context,
    List<VaultItem> items,
    List<VaultGroup> groups, {
    required String? activeInspectorId,
    required bool isDesktop,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          controller.query.isEmpty
              ? 'No entries yet. Tap Add to create one.'
              : 'No matches.',
          style: TacticalTheme.monoStyle(color: TacticalTheme.textMuted),
        ),
      );
    }

    final rows = <Widget>[];
    String? lastBucket;
    for (final item in items) {
      if (controller.sortField == VaultSortField.title) {
        final bucket = _alphaHeaderFor(item.title);
        if (bucket != lastBucket) {
          lastBucket = bucket;
          rows.add(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              color: TacticalTheme.bgDeepCarbon,
              child: Text(
                bucket,
                style: TacticalTheme.monoStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: TacticalTheme.amberPrimary,
                ),
              ),
            ),
          );
        }
      }
      rows.add(
        _buildCredentialRow(
          context,
          item,
          groups,
          isSelected: isDesktop &&
              !_creatingNewInInspector &&
              item.id == activeInspectorId,
          isDesktop: isDesktop,
        ),
      );
    }

    return ListView(children: rows);
  }

  Widget _buildCenterItemListColumn(
    BuildContext context,
    List<VaultItem> items,
    List<VaultGroup> groups,
    String? activeInspectorId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search + Add Bar (`Enpass_UNGNDpANfa.png`)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: TacticalTheme.bgPanel,
            border: Border(
              bottom: BorderSide(
                color: TacticalTheme.borderTech,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('vault_field_search'),
                  onChanged: controller.search,
                  style: TacticalTheme.monoStyle(fontSize: 13),
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: TacticalTheme.amberPrimary,
                    ),
                    suffixIcon: PopupMenuButton<VaultSortField>(
                      key: const ValueKey('vault_search_options_menu'),
                      tooltip: 'Search & Sort Options',
                      icon: Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: TacticalTheme.textSecondary,
                      ),
                      onSelected: controller.setSort,
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: VaultSortField.title,
                          child: Text('Sort by Title'),
                        ),
                        PopupMenuItem(
                          value: VaultSortField.username,
                          child: Text('Sort by Username'),
                        ),
                        PopupMenuItem(
                          value: VaultSortField.url,
                          child: Text('Sort by Website URL'),
                        ),
                        PopupMenuItem(
                          value: VaultSortField.revisionDate,
                          child: Text('Sort by Last Modified'),
                        ),
                      ],
                    ),
                    hintText: 'Search (Ctrl+F)',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('vault_button_add_entry'),
                onPressed: () => _openEntry(context, isDesktop: true),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
        ),

        // Enpass `Sort By: Title â–²` + Column Headers
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
              InkWell(
                key: const ValueKey('vault_button_sort_title'),
                onTap: () => controller.setSort(VaultSortField.title),
                child: Text(
                  'Sort By: Title ${controller.sortAscending ? "â–²" : "â–¼"}',
                  style: TacticalTheme.monoStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: TacticalTheme.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              if (!controller.showHomeDashboard)
                Text(
                  'Instant Copy Trigger',
                  style: TacticalTheme.monoStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: TacticalTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ),

        // Alphabetically Grouped Credentials List
        Expanded(
          child: _buildGroupedListView(
            context,
            items,
            groups,
            activeInspectorId: activeInspectorId,
            isDesktop: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selectedGroupId = controller.selectedGroupId;
        final selectedCategory = controller.selectedCategory;
        final groups = controller.groups;
        final items = _filterAndSortItems();

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 840;
            final isWideBar = constraints.maxWidth >= 680;

            String? activeInspectorId = _selectedEntryId;
            if (isDesktop && !_creatingNewInInspector) {
              if (activeInspectorId == null ||
                  !items.any((e) => e.id == activeInspectorId)) {
                activeInspectorId = items.isNotEmpty ? items.first.id : null;
              }
            }

            return CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(
                  LogicalKeyboardKey.keyW,
                  control: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'file_close',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.arrowUp,
                  control: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'view_previous_group',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.arrowDown,
                  control: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'view_next_group',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyD,
                  control: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'item_duplicate',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyL,
                  control: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'tools_lock',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyJ,
                  control: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'tools_sync_now',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyB,
                  control: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'tools_clear_clipboard',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyG,
                  control: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'tools_generate_password',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyU,
                  control: true,
                  shift: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'item_copy_username',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyE,
                  control: true,
                  shift: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'item_copy_email',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyP,
                  control: true,
                  shift: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'item_copy_password',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyH,
                  control: true,
                  shift: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'item_show_passwords',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyR,
                  control: true,
                  shift: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'item_copy_url',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyT,
                  control: true,
                  shift: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'item_copy_otp',
                        activeInspectorId,
                      ),
                    ),
                const SingleActivator(
                  LogicalKeyboardKey.keyL,
                  control: true,
                  shift: true,
                ): () => unawaited(
                      _handleTopMenuAction(
                        context,
                        'item_launch_url',
                        activeInspectorId,
                      ),
                    ),
              },
              child: Scaffold(
                backgroundColor: TacticalTheme.bgDeepCarbon,
                floatingActionButton: isDesktop
                    ? null
                    : FloatingActionButton.extended(
                        key: const ValueKey('vault_button_add_entry'),
                        backgroundColor: TacticalTheme.amberPrimary,
                        foregroundColor: TacticalTheme.bgDeepCarbon,
                        onPressed: () => _openEntry(context, isDesktop: false),
                        icon: const Icon(Icons.add),
                        label: const Text(
                          'Add',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                body: SafeArea(
                  child: Column(
                    children: [
                      // Top Telemetry Bar
                      _buildTopTelemetryBar(
                        context,
                        isWideBar,
                        activeInspectorId,
                      ),

                      // Main Content Area
                      Expanded(
                        child: isDesktop
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Left Pane: Enpass Sidebar + Group Tree
                                  _buildLeftGroupTree(
                                    context,
                                    groups,
                                    selectedGroupId,
                                    controller.activeItems.length,
                                  ),

                                  // Center Pane: Persistent Enpass Item List (`Enpass_UNGNDpANfa.png`)
                                  if (controller.showHomeDashboard)
                                    Container(
                                      width: 340,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          right: BorderSide(
                                            color: TacticalTheme.borderTech,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: _buildCenterItemListColumn(
                                        context,
                                        items,
                                        groups,
                                        activeInspectorId,
                                      ),
                                    )
                                  else
                                    Expanded(
                                      child: _buildCenterItemListColumn(
                                        context,
                                        items,
                                        groups,
                                        activeInspectorId,
                                      ),
                                    ),

                                  // Right Pane: Either Enpass Home Security Score Dashboard OR Cryptographic Entry Inspector
                                  if (controller.showHomeDashboard)
                                    Expanded(
                                      child: HomeDashboardPane(
                                        controller: controller,
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 390,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            color: TacticalTheme.borderTech,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: EntryScreen(
                                        key: ValueKey(
                                          _creatingNewInInspector
                                              ? 'new_entry_$_newEntryNonce'
                                              : (activeInspectorId ??
                                                  'empty_$_newEntryNonce'),
                                        ),
                                        controller: controller,
                                        entryId: _creatingNewInInspector
                                            ? null
                                            : activeInspectorId,
                                        initialCategory: _creatingNewInInspector
                                            ? _newEntryCategory
                                            : null,
                                        autofocusTitle: _creatingNewInInspector,
                                        isEmbedded: true,
                                        onSaved: (savedId) {
                                          setState(() {
                                            _creatingNewInInspector = false;
                                            _newEntryCategory = null;
                                            _selectedEntryId = savedId;
                                          });
                                        },
                                        onDeleted: () {
                                          setState(() {
                                            _selectedEntryId = null;
                                            _creatingNewInInspector = false;
                                            _newEntryCategory = null;
                                          });
                                        },
                                      ),
                                    ),
                                ],
                              )
                            : Column(
                                children: [
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(12, 10, 12, 4),
                                    child: TextField(
                                      key: const ValueKey('vault_field_search'),
                                      onChanged: controller.search,
                                      style:
                                          TacticalTheme.monoStyle(fontSize: 13),
                                      decoration: InputDecoration(
                                        prefixIcon: Icon(
                                          Icons.search,
                                          color: TacticalTheme.amberPrimary,
                                        ),
                                        hintText:
                                            'Search title, username or URL',
                                      ),
                                    ),
                                  ),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        FilterChip(
                                          key: const ValueKey(
                                            'mobile_chip_home',
                                          ),
                                          label: const Text('Home Audit'),
                                          selected:
                                              controller.showHomeDashboard,
                                          onSelected: (_) =>
                                              controller.showHomeDashboard
                                                  ? controller
                                                      .closeHomeDashboard()
                                                  : controller
                                                      .openHomeDashboard(),
                                        ),
                                        const SizedBox(width: 8),
                                        FilterChip(
                                          label: const Text('All'),
                                          selected: !controller
                                                  .showHomeDashboard &&
                                              selectedGroupId == null &&
                                              selectedCategory ==
                                                  VaultCategoryFilter.all,
                                          onSelected: (_) =>
                                              controller.selectGroup(null),
                                        ),
                                        const SizedBox(width: 8),
                                        FilterChip(
                                          label: Text(
                                            'Passkeys (${controller.passkeyCount})',
                                          ),
                                          selected: selectedCategory ==
                                              VaultCategoryFilter.passkeys,
                                          onSelected: (_) =>
                                              controller.selectCategory(
                                            selectedCategory ==
                                                    VaultCategoryFilter.passkeys
                                                ? VaultCategoryFilter.all
                                                : VaultCategoryFilter.passkeys,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        FilterChip(
                                          label: Text(
                                            'Passkey Supported (${controller.passkeySupportedCount})',
                                          ),
                                          selected: selectedCategory ==
                                              VaultCategoryFilter
                                                  .passkeySupported,
                                          onSelected: (_) =>
                                              controller.selectCategory(
                                            selectedCategory ==
                                                    VaultCategoryFilter
                                                        .passkeySupported
                                                ? VaultCategoryFilter.all
                                                : VaultCategoryFilter
                                                    .passkeySupported,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        FilterChip(
                                          key: const ValueKey(
                                            'vault_filter_totp',
                                          ),
                                          label: Text(
                                            '2FA (TOTP) (${controller.totpCount})',
                                          ),
                                          selected: selectedCategory ==
                                              VaultCategoryFilter.totp2fa,
                                          onSelected: (_) =>
                                              controller.selectCategory(
                                            selectedCategory ==
                                                    VaultCategoryFilter.totp2fa
                                                ? VaultCategoryFilter.all
                                                : VaultCategoryFilter.totp2fa,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        for (final g in groups) ...[
                                          FilterChip(
                                            label: Text(
                                              '${g.name} (${g.entryCount})',
                                            ),
                                            selected: selectedGroupId == g.id,
                                            onSelected: (_) =>
                                                controller.selectGroup(
                                              selectedGroupId == g.id
                                                  ? null
                                                  : g.id,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        ActionChip(
                                          avatar: Icon(
                                            Icons.add,
                                            size: 16,
                                            color: TacticalTheme.amberPrimary,
                                          ),
                                          label: const Text('Group'),
                                          onPressed: () =>
                                              _createGroup(context),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: controller.showHomeDashboard
                                        ? HomeDashboardPane(
                                            controller: controller,
                                          )
                                        : _buildGroupedListView(
                                            context,
                                            items,
                                            groups,
                                            activeInspectorId: null,
                                            isDesktop: false,
                                          ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GroupTreeTile extends StatelessWidget {
  const _GroupTreeTile({
    super.key,
    required this.name,
    required this.count,
    this.showCount = true,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String name;
  final int count;
  final bool showCount;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
        decoration: BoxDecoration(
          color: selected ? TacticalTheme.bgElevated : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? TacticalTheme.amberPrimary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.chevron_right,
              size: 13,
              color: selected
                  ? TacticalTheme.amberPrimary
                  : TacticalTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Icon(
              icon,
              size: 15,
              color: selected
                  ? TacticalTheme.amberPrimary
                  : TacticalTheme.cyanTactical,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? TacticalTheme.textPrimary
                      : TacticalTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showCount)
              Text(
                '($count)',
                style: TacticalTheme.monoStyle(
                  fontSize: 11,
                  color: selected
                      ? TacticalTheme.amberBright
                      : TacticalTheme.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
