import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Modal file/folder browser for selecting local or cloud-synced KDBX vaults.
class FilePickerDialog extends StatefulWidget {
  const FilePickerDialog({
    super.key,
    required this.initialPath,
    this.mustExist = true,
    this.selectFolder = false,
  });

  final String initialPath;
  final bool mustExist;
  final bool selectFolder;

  static Future<String?> show(
    BuildContext context, {
    required String initialPath,
    bool mustExist = true,
    bool selectFolder = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => FilePickerDialog(
        initialPath: initialPath,
        mustExist: mustExist,
        selectFolder: selectFolder,
      ),
    );
  }

  @override
  State<FilePickerDialog> createState() => _FilePickerDialogState();
}

class _FilePickerDialogState extends State<FilePickerDialog> {
  late Directory _currentDir;
  final List<FileSystemEntity> _entries = [];
  String? _selectedPath;
  final _filenameController = TextEditingController(text: 'vaultkeep.kdbx');

  @override
  void initState() {
    super.initState();
    final f = File(widget.initialPath);
    if (f.existsSync()) {
      _currentDir = f.parent;
      _selectedPath = f.path;
      _filenameController.text = p.basename(f.path);
    } else {
      final d = Directory(widget.initialPath);
      if (d.existsSync()) {
        _currentDir = d;
      } else {
        _currentDir = Directory.current;
      }
    }
    _loadEntries();
  }

  @override
  void dispose() {
    _filenameController.dispose();
    super.dispose();
  }

  void _loadEntries() {
    _entries.clear();
    try {
      final list = _currentDir.listSync();
      list.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
      _entries.addAll(list);
    } catch (_) {
      // Permission or unreadable directory
    }
    setState(() {});
  }

  void _navigateTo(Directory dir) {
    if (dir.existsSync()) {
      _currentDir = dir;
      _loadEntries();
    }
  }

  void _navigateUp() {
    final parent = _currentDir.parent;
    if (parent.path != _currentDir.path) {
      _navigateTo(parent);
    }
  }

  String? _statusMessage;

  void _selectQuickPath(String folderName) {
    final userProfile = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final candidates = <String>[];
    if (folderName == 'OneDrive') {
      if (Platform.environment['OneDrive'] != null) {
        candidates.add(Platform.environment['OneDrive']!);
      }
      if (Platform.environment['OneDriveConsumer'] != null) {
        candidates.add(Platform.environment['OneDriveConsumer']!);
      }
      if (userProfile.isNotEmpty) {
        candidates.add(p.join(userProfile, 'OneDrive'));
      }
    } else if (folderName == 'Google Drive') {
      candidates.add(r'G:\My Drive');
      candidates.add(r'G:\');
      if (userProfile.isNotEmpty) {
        candidates.add(p.join(userProfile, 'Google Drive'));
      }
    } else if (folderName == 'Documents') {
      if (userProfile.isNotEmpty) {
        candidates.add(p.join(userProfile, 'Documents'));
      }
    } else if (folderName == 'Vault Sandbox') {
      if (userProfile.isNotEmpty) {
        final sandbox = Directory(p.join(userProfile, 'Documents', 'VaultKeep_GoogleDrive_Cloud'));
        if (!sandbox.existsSync()) {
          try {
            sandbox.createSync(recursive: true);
          } catch (_) {}
        }
        candidates.add(sandbox.path);
      }
    }

    for (final candidate in candidates) {
      final target = Directory(candidate);
      if (target.existsSync()) {
        setState(() {
          _statusMessage = null;
        });
        _navigateTo(target);
        return;
      }
    }

    setState(() {
      _statusMessage = '$folderName folder was not found on this system.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(widget.selectFolder ? Icons.folder : Icons.file_present),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.selectFolder ? 'Choose Cloud / Local Folder' : 'Choose Vault File',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: (MediaQuery.sizeOf(context).height * 0.6).clamp(280.0, 420.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.cloud_outlined, size: 16),
                  label: const Text('Google Drive'),
                  onPressed: () => _selectQuickPath('Google Drive'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.cloud_outlined, size: 16),
                  label: const Text('OneDrive'),
                  onPressed: () => _selectQuickPath('OneDrive'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Documents'),
                  onPressed: () => _selectQuickPath('Documents'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.science_outlined, size: 16),
                  label: const Text('Cloud Sandbox'),
                  onPressed: () => _selectQuickPath('Vault Sandbox'),
                ),
              ],
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                _statusMessage!,
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Go to parent folder',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: _navigateUp,
                ),
                Expanded(
                  child: Text(
                    _currentDir.path,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: _entries.isEmpty
                  ? const Center(child: Text('Folder is empty or inaccessible.'))
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (ctx, i) {
                        final entity = _entries[i];
                        final isDir = entity is Directory;
                        final name = p.basename(entity.path);
                        final isKdbx = name.toLowerCase().endsWith('.kdbx');
                        final isSelected = _selectedPath == entity.path;

                        if (!isDir && !isKdbx && !widget.selectFolder) {
                          // Hide non-kdbx files when picking vault files
                          return const SizedBox.shrink();
                        }

                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          leading: Icon(
                            isDir ? Icons.folder : Icons.lock,
                            color: isDir
                                ? Colors.amber
                                : (isKdbx ? Colors.teal : Colors.grey),
                          ),
                          title: Text(name),
                          onTap: () {
                            if (isDir) {
                              _navigateTo(entity);
                            } else {
                              setState(() {
                                _selectedPath = entity.path;
                                _filenameController.text = name;
                              });
                            }
                          },
                        );
                      },
                    ),
            ),
            if (!widget.selectFolder) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _filenameController,
                decoration: const InputDecoration(
                  labelText: 'File Name',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (widget.selectFolder) {
              Navigator.of(context).pop(_currentDir.path);
            } else {
              final path = _selectedPath ??
                  p.join(_currentDir.path, _filenameController.text.trim());
              Navigator.of(context).pop(path);
            }
          },
          child: const Text('Select'),
        ),
      ],
    );
  }
}
