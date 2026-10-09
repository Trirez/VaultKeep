import 'package:flutter/material.dart';

import '../backend.dart';
import '../clipboard_guard.dart';
import '../vault_controller.dart';
import 'entry_screen.dart';
import 'file_picker_dialog.dart';

class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key, required this.controller});

  final VaultController controller;

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

  void _openEntry(BuildContext context, {String? id}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryScreen(controller: controller, entryId: id),
      ),
    );
  }

  Future<void> _createGroup(BuildContext context) async {
    final nameCtrl = TextEditingController();
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New Group'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Group Name',
              border: OutlineInputBorder(),
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
              Icon(Icons.sync),
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
                  decoration: InputDecoration(
                    labelText: 'Replica file path (.kdbx)',
                    hintText: 'Select cloud or replica .kdbx file',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Browse files',
                      icon: const Icon(Icons.folder_open),
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
                  decoration: const InputDecoration(
                    labelText: 'Replica master password',
                    hintText: 'Leave empty to use active vault password',
                    helperText: 'Leave blank if replica shares current password',
                    border: OutlineInputBorder(),
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
                      content: Text('Please select a replica file path before syncing.'),
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
          const SnackBar(content: Text('Sync cancelled: replica path was empty.')),
        );
        return;
      }
      try {
        final count = await controller.mergeVault(
          trimmedPath,
          passCtrl.text,
        );
        messenger.showSnackBar(
          SnackBar(content: Text('Sync complete: $count merge event(s) applied.')),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Sync failed: ${VaultController.describe(e)}')),
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
                  const Icon(Icons.auto_mode),
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
                decoration: InputDecoration(
                  labelText: 'Target Domain or App',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () async {
                      final res = await controller.findEntriesForDomain(
                        queryCtrl.text.trim(),
                      );
                      setSheetState(() => matches = res);
                    },
                  ),
                ),
                onSubmitted: (val) async {
                  final res = await controller.findEntriesForDomain(val.trim());
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
                        title: Text(item.title),
                        subtitle: Text(item.username),
                        trailing: IconButton(
                          tooltip: 'Copy password',
                          icon: const Icon(Icons.copy),
                          onPressed: () async {
                            final pw = await controller.revealPassword(item.id);
                            await ClipboardGuard.copySecret(pw);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Password copied for autofill.'),
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
                .firstOrNull ?? selectedGroupId;

        final items = selectedGroupName == null
            ? allItems
            : allItems
                .where((i) =>
                    i.groupName == selectedGroupName ||
                    i.groupName == selectedGroupId)
                .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('VaultKeep'),
            actions: [
              IconButton(
                tooltip: 'Autofill Query',
                icon: const Icon(Icons.auto_mode),
                onPressed: () => _showAutofillModal(context),
              ),
              IconButton(
                tooltip: 'Sync Vault (3-Way Merge)',
                icon: const Icon(Icons.sync),
                onPressed: () => _syncVault(context),
              ),
              IconButton(
                tooltip: 'Lock now',
                icon: const Icon(Icons.lock_outline),
                onPressed: () => controller.lock(),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEntry(context),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      onChanged: controller.search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search title, username or URL',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (groups.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('All'),
                            selected: selectedGroupId == null,
                            onSelected: (_) => controller.selectGroup(null),
                          ),
                          const SizedBox(width: 8),
                          for (final g in groups) ...[
                            FilterChip(
                              label: Text('${g.name} (${g.entryCount})'),
                              selected: selectedGroupId == g.id,
                              onSelected: (_) => controller.selectGroup(
                                selectedGroupId == g.id ? null : g.id,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: const Text('Group'),
                            onPressed: () => _createGroup(context),
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
                            ),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final item = items[i];
                              return ListTile(
                                title: Text(item.title),
                                subtitle: Text(
                                  item.username.isEmpty ? item.url : item.username,
                                ),
                                onTap: () => _openEntry(context, id: item.id),
                                trailing: IconButton(
                                  tooltip: 'Copy password',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () => _copyPassword(context, item),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

