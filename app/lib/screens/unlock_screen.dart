import 'dart:io';

import 'package:flutter/material.dart';

import '../vault_controller.dart';
import 'file_picker_dialog.dart';

/// Unlocks an existing vault file, or creates one if the file does not exist.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({
    super.key,
    required this.controller,
    required this.defaultPath,
  });

  final VaultController controller;
  final String defaultPath;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  late final TextEditingController _path =
      TextEditingController(text: widget.defaultPath);
  final _master = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  String? _localError;

  bool? _isCreatingOverride;

  static const _minMasterLength = 12;

  bool get _creating =>
      _isCreatingOverride ?? !File(_path.text.trim()).existsSync();

  @override
  void dispose() {
    _master.text = '';
    _confirm.text = '';
    _path.dispose();
    _master.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final path = _path.text.trim();
    final master = _master.text;
    final creating = _creating;
    final fileExists = File(path).existsSync();

    String? problem;
    if (path.isEmpty) {
      problem = 'Enter the vault file path.';
    } else if (creating) {
      if (fileExists) {
        problem = 'A file already exists at this path. Switch to Unlock or choose a new path.';
      } else if (master.length < _minMasterLength) {
        problem =
            'Use at least $_minMasterLength characters for the master password.';
      } else if (master != _confirm.text) {
        problem = 'The two passwords do not match.';
      }
    } else {
      if (!fileExists) {
        problem = 'Vault file does not exist at this path. Check path or switch to Create.';
      } else if (master.isEmpty) {
        problem = 'Enter your master password.';
      }
    }
    setState(() => _localError = problem);
    if (problem != null) return;

    if (creating) {
      final ok = await widget.controller.create(path, master);
      if (ok && mounted) {
        _master.clear();
        _confirm.clear();
      }
    } else {
      final ok = await widget.controller.unlock(path, master);
      if (ok && mounted) {
        _master.clear();
      }
    }
  }

  Future<void> _pickVaultPath() async {
    final picked = await FilePickerDialog.show(
      context,
      initialPath: _path.text.trim(),
      mustExist: !_creating,
      selectFolder: false,
    );
    if (picked != null && mounted) {
      setState(() {
        _path.text = picked;
        _localError = null;
      });
    }
  }

  Future<void> _authenticateBiometric() async {
    final path = _path.text.trim();
    if (!File(path).existsSync()) {
      setState(() => _localError = 'Vault file does not exist at this path.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.fingerprint, size: 48),
        title: const Text('Biometric Authentication'),
        content: const Text(
          'Hardware biometric unlock requires biometric credentials stored in device keystore/keychain.\n\n'
          'Security Advisory: Biometrics confirm user presence only and trade some security for convenience. '
          'First unlock on device launch or reboot requires entering the master password.',
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final c = widget.controller;
                  final creating = _creating;
                  final message = _localError ?? c.error;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.lock_outline, size: 48, color: scheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        'VaultKeep',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Unlock'),
                            icon: Icon(Icons.lock_open),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Create'),
                            icon: Icon(Icons.add),
                          ),
                        ],
                        selected: {creating},
                        onSelectionChanged: (set) {
                          setState(() {
                            _isCreatingOverride = set.first;
                            _localError = null;
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _path,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Vault file (.kdbx)',
                          helperText:
                              'Tip: a path inside a Drive/OneDrive folder syncs the vault.',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: 'Browse files or cloud folders',
                            icon: const Icon(Icons.folder_open),
                            onPressed: _pickVaultPath,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _master,
                        obscureText: !_show,
                        enableSuggestions: false,
                        autocorrect: false,
                        onSubmitted: (_) => creating ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Master password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _show ? 'Hide' : 'Show',
                            icon: Icon(
                              _show ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () => setState(() => _show = !_show),
                          ),
                        ),
                      ),
                      if (creating) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _confirm,
                          obscureText: !_show,
                          enableSuggestions: false,
                          autocorrect: false,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Repeat master password',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (message != null) ...[
                        const SizedBox(height: 12),
                        Text(message, style: TextStyle(color: scheme.error)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: c.busy ? null : _submit,
                        child: c.busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(creating ? 'Create vault' : 'Unlock'),
                      ),
                      if (!creating) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Unlock with Biometrics'),
                          onPressed: c.busy ? null : _authenticateBiometric,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
