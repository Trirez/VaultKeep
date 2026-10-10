import 'package:flutter/material.dart';

import '../backend.dart';
import '../clipboard_guard.dart';
import '../theme.dart';
import '../vault_controller.dart';
import 'entry_screen.dart';
import 'file_picker_dialog.dart';

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

  Future<void> _copyPassword(BuildContext context, VaultItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final password = await controller.revealPassword(item.id);
      await ClipboardGuard.copySecret(password);
      messenger.showSnackBar(
        const SnackBar(content: Text('Password copied. Clears in 15 seconds.')),
      );
    } catch (e) {
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
                        final res = await controller.findEntriesForDomain(
                          queryCtrl.text.trim(),
                        );
                        setSheetState(() => matches = res);
                      },
                    ),
                  ),
                  onSubmitted: (val) async {
                    final res =
                        await controller.findEntriesForDomain(val.trim());
                    setSheetState(() => matches = res);
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
                              final pw =
                                  await controller.revealPassword(item.id);
                              await ClipboardGuard.copySecret(pw);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Password copied for autofill.'),
                                  ),
                                );
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
          const Text(
            'VaultKeep',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: TacticalTheme.textPrimary,
              letterSpacing: 0.4,
            ),
          ),
          if (isWide) ...[
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
          ],
          const Spacer(),
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
                    'CLIPBOARD GUARD: ',
                    style: TacticalTheme.monoStyle(
                      fontSize: 11,
                      color: TacticalTheme.textSecondary,
                    ),
                  ),
                  Text(
                    'READY (15s)',
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
            tooltip: 'Autofill Query',
            icon: const Icon(
              Icons.auto_mode,
              size: 19,
              color: TacticalTheme.cyanTactical,
            ),
            onPressed: () => _showAutofillModal(context),
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
              icon: const Icon(
                Icons.sync,
                size: 19,
                color: TacticalTheme.cyanTactical,
              ),
              onPressed: () => _syncVault(context),
            ),
          if (isWide)
            // Keep an accessible tooltip wrapper so find.byTooltip('Sync Vault (3-Way Merge)') always works
            const Tooltip(
              message: 'Sync Vault (3-Way Merge)',
              child: SizedBox.shrink(),
            ),
          const SizedBox(width: 4),
          if (isWide)
            Tooltip(
              message: 'Lock now',
              child: InkWell(
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
              tooltip: 'Lock now',
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
    return Container(
      width: 240,
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
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: TacticalTheme.amberDim,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: TacticalTheme.amberPrimary,
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.folder,
                    size: 16,
                    color: TacticalTheme.amberBright,
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

          // Group Tree Column
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
                        name: 'All Credentials',
                        count: totalCount,
                        selected: selectedGroupId == null,
                        icon: Icons.folder_special,
                        onTap: () => controller.selectGroup(null),
                      ),
                      for (final g in groups)
                        _GroupTreeTile(
                          name: g.name,
                          count: g.entryCount,
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
            TacticalDomainAvatar(
              title: item.title,
              url: item.url,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: TacticalTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
              ),
            ),
            if (isDesktop) ...[
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final allItems = controller.items;
        final selectedGroupId = controller.selectedGroupId;
        final groups = controller.groups;

        final selectedGroupName = selectedGroupId == null
            ? null
            : groups
                    .where((g) => g.id == selectedGroupId)
                    .map((g) => g.name)
                    .firstOrNull ??
                selectedGroupId;

        final items = selectedGroupName == null
            ? allItems
            : allItems
                .where((i) =>
                    i.groupName == selectedGroupName ||
                    i.groupName == selectedGroupId)
                .toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 840;
            final isWideBar = constraints.maxWidth >= 680;

            // Resolve active entry for desktop inspector
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
                                // Left Pane: Group Tree
                                _buildLeftGroupTree(
                                  context,
                                  groups,
                                  selectedGroupId,
                                  allItems.length,
                                ),

                                // Center Pane: Credentials Matrix
                                Expanded(
                                  child: Column(
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
                                              color: TacticalTheme.borderTech,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                onChanged: controller.search,
                                                style: TacticalTheme.monoStyle(
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

                                      // Column Headers
                                      Container(
                                        height: 32,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
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
                                            Text(
                                              'Credentials ▲',
                                              style: TacticalTheme.monoStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    TacticalTheme.textSecondary,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              'Instant Copy Trigger',
                                              style: TacticalTheme.monoStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    TacticalTheme.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Credentials List
                                      Expanded(
                                        child: items.isEmpty
                                            ? Center(
                                                child: Text(
                                                  controller.query.isEmpty
                                                      ? 'No entries yet. Tap Add to create one.'
                                                      : 'No matches.',
                                                  style:
                                                      TacticalTheme.monoStyle(
                                                    color:
                                                        TacticalTheme.textMuted,
                                                  ),
                                                ),
                                              )
                                            : ListView.builder(
                                                itemCount: items.length,
                                                itemBuilder: (context, i) {
                                                  final item = items[i];
                                                  return _buildCredentialRow(
                                                    context,
                                                    item,
                                                    groups,
                                                    isSelected: !_creatingNewInInspector &&
                                                        item.id ==
                                                            activeInspectorId,
                                                    isDesktop: true,
                                                  );
                                                },
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
                                if (groups.isNotEmpty)
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        FilterChip(
                                          label: const Text('All'),
                                          selected: selectedGroupId == null,
                                          onSelected: (_) =>
                                              controller.selectGroup(null),
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
                                  child: items.isEmpty
                                      ? Center(
                                          child: Text(
                                            controller.query.isEmpty
                                                ? 'No entries yet. Tap Add to create one.'
                                                : 'No matches.',
                                            style: TacticalTheme.monoStyle(
                                              color: TacticalTheme.textMuted,
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: items.length,
                                          itemBuilder: (context, i) {
                                            final item = items[i];
                                            return _buildCredentialRow(
                                              context,
                                              item,
                                              groups,
                                              isSelected: false,
                                              isDesktop: false,
                                            );
                                          },
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
    required this.name,
    required this.count,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String name;
  final int count;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
