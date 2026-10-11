import 'package:flutter/material.dart';

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
            title: const Row(
              children: [
                Icon(Icons.vpn_key_outlined, color: TacticalTheme.amberPrimary),
                SizedBox(width: 8),
                Expanded(
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

  void _openEntry(BuildContext context, {String? id, required bool isDesktop}) {
    if (isDesktop) {
      setState(() {
        if (id == null) {
          _creatingNewInInspector = true;
          _selectedEntryId = null;
        } else {
          _creatingNewInInspector = false;
          _selectedEntryId = id;
        }
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EntryScreen(controller: controller, entryId: id),
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
            title: const Row(
              children: [
                Icon(Icons.sync, color: TacticalTheme.amberPrimary),
                SizedBox(width: 8),
                Expanded(
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
                        icon: const Icon(
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
                    const Icon(
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
                      icon: const Icon(
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
                            icon: const Icon(
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

  Widget _buildTopTelemetryBar(BuildContext context, bool isWide) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: TacticalTheme.bgPanel,
        border: Border(
          bottom: BorderSide(color: TacticalTheme.borderTech, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.shield,
            size: 18,
            color: TacticalTheme.amberPrimary,
          ),
          const SizedBox(width: 8),
          if (isWide) ...[
            const Text(
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
            const Spacer(),
          ] else
            const Expanded(
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
            const SizedBox(width: 8),
          ],
          IconButton(
            key: const ValueKey('vault_button_password_generator'),
            tooltip: 'Password Generator',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            icon: const Icon(
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
            icon: const Icon(
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
            icon: const Icon(
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
            icon: const Icon(
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
                  side: const BorderSide(color: TacticalTheme.borderTech),
                ),
                icon: const Icon(
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
              icon: const Icon(
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
                      const Icon(
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
              icon: const Icon(
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
      decoration: const BoxDecoration(
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
            decoration: const BoxDecoration(
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
                  icon: const Icon(
                    Icons.note_add_outlined,
                    size: 18,
                    color: TacticalTheme.textSecondary,
                  ),
                  onPressed: () => _openEntry(context, isDesktop: true),
                ),
                IconButton(
                  tooltip: 'New Group',
                  icon: const Icon(
                    Icons.create_new_folder_outlined,
                    size: 18,
                    color: TacticalTheme.textSecondary,
                  ),
                  onPressed: () => _createGroup(context),
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(
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
                  icon: const Icon(
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
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Group Tree',
                        style: TacticalTheme.monoStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: TacticalTheme.textSecondary,
                        ),
                      ),
                      InkWell(
                        onTap: () => _createGroup(context),
                        child: const Icon(
                          Icons.add,
                          size: 16,
                          color: TacticalTheme.amberPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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
                            controller.selectedItemCategory == cat ? null : cat,
                          ),
                        ),

                      // Audit Section (`Enpass_UNGNDpANfa.png`)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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

                      // Others Section (`Enpass_UNGNDpANfa.png`)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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

                      // Tags Section
                      if (tags.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: OutlinedButton.icon(
                    icon: const Icon(
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
            bottom: const BorderSide(
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
                          style: const TextStyle(
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
                        const Icon(
                          Icons.star,
                          size: 14,
                          color: TacticalTheme.amberBright,
                        ),
                      ],
                      if (item.hasPasskey) ...[
                        const SizedBox(width: 6),
                        const Icon(
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
                      item.username.isEmpty ? item.url : item.username,
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

            return Scaffold(
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
                    _buildTopTelemetryBar(context, isWideBar),

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

                                // Center Pane: Either Enpass Home Security Dashboard OR Credentials Matrix
                                Expanded(
                                  child: controller.showHomeDashboard
                                      ? HomeDashboardPane(
                                          controller: controller,
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            // Search + Add Bar
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: const BoxDecoration(
                                                color: TacticalTheme.bgPanel,
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: TacticalTheme
                                                        .borderTech,
                                                    width: 1,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: TextField(
                                                      key: const ValueKey(
                                                        'vault_field_search',
                                                      ),
                                                      onChanged:
                                                          controller.search,
                                                      style: TacticalTheme
                                                          .monoStyle(
                                                        fontSize: 13,
                                                      ),
                                                      decoration:
                                                          const InputDecoration(
                                                        prefixIcon: Icon(
                                                          Icons.search,
                                                          size: 18,
                                                          color: TacticalTheme
                                                              .amberPrimary,
                                                        ),
                                                        hintText:
                                                            'Search title, username or URL',
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  FilledButton.icon(
                                                    key: const ValueKey(
                                                      'vault_button_add_entry',
                                                    ),
                                                    onPressed: () => _openEntry(
                                                      context,
                                                      isDesktop: true,
                                                    ),
                                                    icon: const Icon(
                                                      Icons.add,
                                                      size: 16,
                                                    ),
                                                    label: const Text('Add'),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Enpass `Sort By: Title v` + Column Headers
                                            Container(
                                              height: 32,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                              ),
                                              decoration: const BoxDecoration(
                                                color: TacticalTheme.bgSurface,
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: TacticalTheme
                                                        .borderTech,
                                                    width: 1,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  InkWell(
                                                    key: const ValueKey(
                                                      'vault_button_sort_title',
                                                    ),
                                                    onTap: () =>
                                                        controller.setSort(
                                                      VaultSortField.title,
                                                    ),
                                                    child: Text(
                                                      'Sort By: Title ${controller.sortAscending ? "▲" : "▼"}',
                                                      style: TacticalTheme
                                                          .monoStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: TacticalTheme
                                                            .textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    'Instant Copy Trigger',
                                                    style:
                                                        TacticalTheme.monoStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: TacticalTheme
                                                          .textSecondary,
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
                                                activeInspectorId:
                                                    activeInspectorId,
                                                isDesktop: true,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),

                                // Right Pane: Cryptographic Entry Inspector
                                Container(
                                  width: 390,
                                  decoration: const BoxDecoration(
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
                                          ? 'new_entry'
                                          : (activeInspectorId ?? 'empty'),
                                    ),
                                    controller: controller,
                                    entryId: _creatingNewInInspector
                                        ? null
                                        : activeInspectorId,
                                    isEmbedded: true,
                                    onSaved: (savedId) {
                                      setState(() {
                                        _creatingNewInInspector = false;
                                        _selectedEntryId = savedId;
                                      });
                                    },
                                    onDeleted: () {
                                      setState(() {
                                        _selectedEntryId = null;
                                        _creatingNewInInspector = false;
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
                                    style: TacticalTheme.monoStyle(fontSize: 13),
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(
                                        Icons.search,
                                        color: TacticalTheme.amberPrimary,
                                      ),
                                      hintText: 'Search title, username or URL',
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
                                        selected: controller.showHomeDashboard,
                                        onSelected: (_) =>
                                            controller.showHomeDashboard
                                                ? controller.closeHomeDashboard()
                                                : controller.openHomeDashboard(),
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
                                            VaultCategoryFilter.passkeySupported,
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
                                        avatar: const Icon(
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
              size: 14,
              color: selected
                  ? TacticalTheme.amberPrimary
                  : TacticalTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Icon(
              icon,
              size: 16,
              color: selected
                  ? TacticalTheme.amberPrimary
                  : TacticalTheme.cyanTactical,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 13,
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
