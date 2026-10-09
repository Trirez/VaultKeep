import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../backend.dart';
import '../clipboard_guard.dart';
import '../vault_controller.dart';
import 'file_picker_dialog.dart';

/// Create (`entryId == null`) or edit an entry.
class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key, required this.controller, this.entryId});

  final VaultController controller;
  final String? entryId;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _url = TextEditingController();
  final _notes = TextEditingController();
  final _otpUri = TextEditingController();

  String? _selectedGroupId;
  VaultTotp? _totp;
  Timer? _totpTimer;
  List<VaultAttachment> _attachments = [];

  bool _loading = false;
  bool _saving = false;
  bool _show = false;
  bool _showOtp = false;

  bool get _isEdit => widget.entryId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) unawaited(_load());
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    _password.text = '';
    _otpUri.text = '';
    _title.dispose();
    _username.dispose();
    _password.dispose();
    _url.dispose();
    _notes.dispose();
    _otpUri.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _refreshTotp() async {
    if (widget.entryId == null) return;
    try {
      final token = await widget.controller.getTotp(widget.entryId!);
      if (mounted) setState(() => _totp = token);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final id = widget.entryId!;
      final entry = await widget.controller.loadEntry(id);
      final password = await widget.controller.revealPassword(id);
      if (!mounted) return;
      _title.text = entry.title;
      _username.text = entry.username;
      _url.text = entry.url;
      _notes.text = entry.notes;
      _password.text = password;
      _selectedGroupId = entry.groupId;
      _otpUri.text = entry.otpUri ?? '';
      _attachments = List.of(entry.attachments);

      if (entry.otpUri != null && entry.otpUri!.isNotEmpty) {
        unawaited(_refreshTotp());
        _totpTimer?.cancel();
        _totpTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _refreshTotp(),
        );
      }
    } catch (e) {
      if (mounted) _toast(VaultController.describe(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    try {
      final password = await widget.controller.generatePassword();
      if (!mounted) return;
      setState(() {
        _password.text = password;
        _show = true;
      });
    } catch (e) {
      if (mounted) _toast(VaultController.describe(e));
    }
  }

  Future<void> _addAttachment() async {
    if (widget.entryId == null) {
      _toast('Save this entry first before attaching files.');
      return;
    }
    final picked = await FilePickerDialog.show(
      context,
      initialPath: '',
      mustExist: true,
    );
    if (picked != null) {
      final f = File(picked);
      if (f.existsSync()) {
        final name = f.uri.pathSegments.last;
        final bytes = await f.readAsBytes();
        try {
          await widget.controller.addAttachment(widget.entryId!, name, bytes);
          final updated =
              await widget.controller.listAttachments(widget.entryId!);
          if (mounted) setState(() => _attachments = updated);
          _toast('Attachment added: $name');
        } catch (e) {
          if (mounted) _toast(VaultController.describe(e));
        }
      }
    }
  }

  Future<void> _deleteAttachment(String name) async {
    try {
      await widget.controller.removeAttachment(widget.entryId!, name);
      final updated = await widget.controller.listAttachments(widget.entryId!);
      if (mounted) setState(() => _attachments = updated);
      _toast('Attachment removed.');
    } catch (e) {
      if (mounted) _toast(VaultController.describe(e));
    }
  }

  Future<void> _viewAttachment(String name) async {
    try {
      final data =
          await widget.controller.getAttachment(widget.entryId!, name);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(name),
          content: Text(
            'Attachment size: ${data.length} bytes.\n\nData is securely stored encrypted in KDBX.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _toast(VaultController.describe(e));
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    if (_password.text.isEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save without password?'),
          content: const Text(
            'The password field is empty. Do you want to save this entry without a password?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save anyway'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      await widget.controller.save(
        widget.entryId,
        EntryDraft(
          title: _title.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          url: _url.text.trim(),
          notes: _notes.text,
          groupId: _selectedGroupId,
          otp: _otpUri.text.trim(),
        ),
      );
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(VaultController.describe(e));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.delete(widget.entryId!);
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) _toast(VaultController.describe(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.controller.groups;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit entry' : 'New entry'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_totp != null) ...[
                        Card(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.timer_outlined),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'One-Time Password (TOTP)',
                                        style: Theme.of(context).textTheme.titleSmall,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_totp!.secondsRemaining}s',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: _totp!.period > 0
                                      ? (_totp!.secondsRemaining / _totp!.period)
                                      : 0,
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Text(
                                      _totp!.code.length == 6
                                          ? '${_totp!.code.substring(0, 3)} ${_totp!.code.substring(3)}'
                                          : _totp!.code,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            letterSpacing: 2,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    FilledButton.icon(
                                      icon: const Icon(Icons.copy, size: 16),
                                      label: const Text('Copy Code'),
                                      onPressed: () {
                                        ClipboardGuard.copySecret(_totp!.code);
                                        _toast(
                                            'TOTP code copied. Clears in 15 seconds.');
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                  if (groups.isNotEmpty) ...[
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedGroupId,
                      decoration: const InputDecoration(
                        labelText: 'Group',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Root Group (None)'),
                        ),
                        for (final g in groups)
                          DropdownMenuItem<String?>(
                            value: g.id,
                            child: Text(g.name),
                          ),
                      ],
                      onChanged: (val) => setState(() => _selectedGroupId = val),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Title is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _username,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Username or email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: !_show,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: _show ? 'Hide' : 'Show',
                            icon: Icon(
                              _show ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () => setState(() => _show = !_show),
                          ),
                          IconButton(
                            tooltip: 'Generate',
                            icon: const Icon(Icons.autorenew),
                            onPressed: _generate,
                          ),
                          IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy),
                            onPressed: () =>
                                ClipboardGuard.copySecret(_password.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'URL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _otpUri,
                    obscureText: !_showOtp,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'TOTP URI or Secret (otpauth://...)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _showOtp ? 'Hide' : 'Show',
                        icon: Icon(
                          _showOtp ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _showOtp = !_showOtp),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Attachments (${_attachments.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Add File'),
                        onPressed: _addAttachment,
                      ),
                    ],
                  ),
                  if (_attachments.isNotEmpty)
                    ..._attachments.map(
                      (att) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.attachment),
                        title: Text(att.name, overflow: TextOverflow.ellipsis, maxLines: 1),
                        subtitle:
                            Text('${(att.size / 1024).toStringAsFixed(1)} KB'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'View details',
                              icon: const Icon(Icons.visibility),
                              onPressed: () => _viewAttachment(att.name),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteAttachment(att.name),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}
