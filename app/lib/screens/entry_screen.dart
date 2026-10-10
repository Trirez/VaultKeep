import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../backend.dart';
import '../clipboard_guard.dart';
import '../theme.dart';
import '../vault_controller.dart';
import 'file_picker_dialog.dart';

/// Create (`entryId == null`) or edit an entry.
/// Can be pushed as a full-screen route or embedded in the desktop inspector pane.
class EntryScreen extends StatefulWidget {
  const EntryScreen({
    super.key,
    required this.controller,
    this.entryId,
    this.isEmbedded = false,
    this.onSaved,
    this.onDeleted,
  });

  final VaultController controller;
  final String? entryId;
  final bool isEmbedded;
  final ValueChanged<String>? onSaved;
  final VoidCallback? onDeleted;

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
  int _genLength = 24;
  bool _genSymbols = true;

  bool get _isEdit => widget.entryId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      unawaited(_load());
    } else {
      _selectedGroupId = widget.controller.selectedGroupId;
    }
  }

  @override
  void didUpdateWidget(covariant EntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryId != widget.entryId) {
      _totpTimer?.cancel();
      _totp = null;
      _password.text = '';
      _otpUri.text = '';
      _title.clear();
      _username.clear();
      _url.clear();
      _notes.clear();
      _attachments = [];
      _show = false;
      _showOtp = false;
      if (_isEdit) {
        unawaited(_load());
      } else {
        setState(() {
          _selectedGroupId = widget.controller.selectedGroupId;
        });
      }
    }
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
      final password = await widget.controller.generatePassword(
        length: _genLength,
        symbols: _genSymbols,
      );
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
          title: Text(name, style: TacticalTheme.monoStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
      final savedId = await widget.controller.save(
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
      setState(() => _saving = false);
      if (widget.isEmbedded) {
        _toast('Entry saved to KDBX4 vault.');
        widget.onSaved?.call(savedId);
        if (_otpUri.text.trim().isNotEmpty && widget.entryId != null) {
          unawaited(_refreshTotp());
        }
      } else {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
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
            style: FilledButton.styleFrom(
              backgroundColor: TacticalTheme.crimsonDanger,
              foregroundColor: Colors.white,
            ),
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
      if (widget.isEmbedded) {
        _toast('Entry deleted.');
        widget.onDeleted?.call();
      } else {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) _toast(VaultController.describe(e));
    }
  }

  Widget _buildInspectorBody(BuildContext context) {
    final groups = widget.controller.groups;
    final groupValid = _selectedGroupId == null ||
        groups.any((g) => g.id == _selectedGroupId);
    final effectiveGroupId = groupValid ? _selectedGroupId : null;

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: TacticalTheme.amberPrimary),
      );
    }

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // TOTP Digital Amber Readout + Segmented Bar
          if (_totp != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TacticalTheme.bgDeepCarbon,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: TacticalTheme.amberPrimary.withValues(alpha: 0.7),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: TacticalTheme.amberPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'One-Time Password (TOTP)',
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: TacticalTheme.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: TacticalTheme.amberDim,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '${_totp!.secondsRemaining}s',
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: TacticalTheme.amberBright,
                          ),
                        ),
                      ),
                    ],
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
                        style: TacticalTheme.monoStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: TacticalTheme.amberBright,
                          letterSpacing: 3,
                        ),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.copy, size: 15),
                        label: const Text('Copy Code'),
                        onPressed: () {
                          ClipboardGuard.copySecret(_totp!.code);
                          _toast('TOTP code copied. Clears in 15 seconds.');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedAmberBar(
                    fraction: _totp!.period > 0
                        ? (_totp!.secondsRemaining / _totp!.period)
                        : 0,
                    segments: 15,
                    height: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Group Dropdown
          if (groups.isNotEmpty) ...[
            DropdownButtonFormField<String?>(
              initialValue: effectiveGroupId,
              dropdownColor: TacticalTheme.bgElevated,
              style: TacticalTheme.monoStyle(
                fontSize: 13,
                color: TacticalTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Group',
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
            const SizedBox(height: 14),
          ],

          // Title
          TextFormField(
            controller: _title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: TacticalTheme.textPrimary,
            ),
            decoration: const InputDecoration(
              labelText: 'Title',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Title is required' : null,
          ),
          const SizedBox(height: 14),

          // Username
          TextFormField(
            controller: _username,
            autocorrect: false,
            style: TacticalTheme.monoStyle(
              fontSize: 13,
              color: TacticalTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Username or email',
              suffixIcon: IconButton(
                tooltip: 'Copy username',
                icon: const Icon(
                  Icons.copy,
                  size: 17,
                  color: TacticalTheme.cyanTactical,
                ),
                onPressed: () {
                  if (_username.text.isNotEmpty) {
                    ClipboardGuard.copySecret(_username.text);
                    _toast('Username copied. Clears in 15 seconds.');
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Password Box + Entropy Generator Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TacticalTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: TacticalTheme.borderTech, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _password,
                  obscureText: !_show,
                  enableSuggestions: false,
                  autocorrect: false,
                  style: TacticalTheme.monoStyle(
                    fontSize: 13,
                    color: TacticalTheme.amberBright,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: _show ? 'Hide' : 'Show',
                          icon: Icon(
                            _show ? Icons.visibility_off : Icons.visibility,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _show = !_show),
                        ),
                        IconButton(
                          tooltip: 'Generate',
                          icon: const Icon(
                            Icons.autorenew,
                            size: 18,
                            color: TacticalTheme.amberPrimary,
                          ),
                          onPressed: _generate,
                        ),
                        IconButton(
                          tooltip: 'Copy',
                          icon: const Icon(
                            Icons.copy,
                            size: 18,
                            color: TacticalTheme.cyanTactical,
                          ),
                          onPressed: () {
                            ClipboardGuard.copySecret(_password.text);
                            _toast('Password copied. Clears in 15 seconds.');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Tactical Entropy Generator Controls
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.tune,
                          size: 14,
                          color: TacticalTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Entropy Generator (${_genLength}c)',
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            color: TacticalTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TacticalActionSquare(
                          icon: Icons.remove,
                          tooltip: 'Decrease length',
                          size: 26,
                          color: TacticalTheme.textPrimary,
                          onPressed: _genLength > 12
                              ? () => setState(() => _genLength -= 4)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        TacticalActionSquare(
                          icon: Icons.add,
                          tooltip: 'Increase length',
                          size: 26,
                          color: TacticalTheme.textPrimary,
                          onPressed: _genLength < 64
                              ? () => setState(() => _genLength += 4)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () =>
                              setState(() => _genSymbols = !_genSymbols),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _genSymbols
                                  ? TacticalTheme.cyanDim
                                  : TacticalTheme.bgDeepCarbon,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _genSymbols
                                    ? TacticalTheme.cyanTactical
                                    : TacticalTheme.borderTech,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '#!@',
                              style: TacticalTheme.monoStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _genSymbols
                                    ? TacticalTheme.cyanTactical
                                    : TacticalTheme.textMuted,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: _generate,
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: TacticalTheme.amberDim,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: TacticalTheme.amberPrimary,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              'GEN KEY',
                              style: TacticalTheme.monoStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: TacticalTheme.amberBright,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // URL
          TextFormField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: TacticalTheme.monoStyle(
              fontSize: 12,
              color: TacticalTheme.cyanTactical,
            ),
            decoration: const InputDecoration(
              labelText: 'URL',
            ),
          ),
          const SizedBox(height: 14),

          // TOTP Secret URI
          TextFormField(
            controller: _otpUri,
            obscureText: !_showOtp,
            enableSuggestions: false,
            autocorrect: false,
            style: TacticalTheme.monoStyle(
              fontSize: 12,
              color: TacticalTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'TOTP URI or Secret (otpauth://...)',
              suffixIcon: IconButton(
                tooltip: _showOtp ? 'Hide' : 'Show',
                icon: Icon(
                  _showOtp ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                onPressed: () => setState(() => _showOtp = !_showOtp),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Notes
          TextFormField(
            controller: _notes,
            maxLines: 3,
            style: TacticalTheme.monoStyle(
              fontSize: 12,
              color: TacticalTheme.textPrimary,
            ),
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),

          // Protected Binary Attachments Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TacticalTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: TacticalTheme.borderTech, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Attachments (${_attachments.length})',
                        style: TacticalTheme.monoStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: TacticalTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(
                        Icons.attach_file,
                        size: 16,
                        color: TacticalTheme.amberPrimary,
                      ),
                      label: Text(
                        'Add File',
                        style: TacticalTheme.monoStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: TacticalTheme.amberPrimary,
                        ),
                      ),
                      onPressed: _addAttachment,
                    ),
                  ],
                ),
                if (_attachments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'No protected binary attachments.',
                      style: TacticalTheme.monoStyle(
                        fontSize: 11,
                        color: TacticalTheme.textMuted,
                      ),
                    ),
                  )
                else
                  ..._attachments.map(
                    (att) => Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: TacticalTheme.bgDeepCarbon,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: TacticalTheme.borderSubtle,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.insert_drive_file_outlined,
                            size: 16,
                            color: TacticalTheme.cyanTactical,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  att.name,
                                  style: TacticalTheme.monoStyle(
                                    fontSize: 12,
                                    color: TacticalTheme.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  '${(att.size / 1024).toStringAsFixed(1)} KB',
                                  style: TacticalTheme.monoStyle(
                                    fontSize: 10,
                                    color: TacticalTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'View details',
                            icon: const Icon(
                              Icons.visibility,
                              size: 16,
                              color: TacticalTheme.cyanTactical,
                            ),
                            onPressed: () => _viewAttachment(att.name),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: TacticalTheme.crimsonDanger,
                            ),
                            onPressed: () => _deleteAttachment(att.name),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: TacticalTheme.bgDeepCarbon,
                    ),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedded) {
      return Container(
        color: TacticalTheme.bgPanel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Inspector Header Bar
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                color: TacticalTheme.bgSurface,
                border: Border(
                  bottom: BorderSide(color: TacticalTheme.borderTech, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 15,
                    color: TacticalTheme.amberPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isEdit
                          ? 'Cryptographic Entry Inspector'
                          : 'New Credential Entry',
                      style: TacticalTheme.monoStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: TacticalTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_isEdit)
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: TacticalTheme.crimsonDanger,
                      ),
                      onPressed: _saving ? null : _delete,
                    ),
                ],
              ),
            ),
            Expanded(child: _buildInspectorBody(context)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: TacticalTheme.bgDeepCarbon,
      appBar: AppBar(
        title: Text(
          _isEdit ? 'Edit entry' : 'New entry',
          style: TacticalTheme.monoStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: TacticalTheme.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: TacticalTheme.borderTech),
        ),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(
                Icons.delete_outline,
                color: TacticalTheme.crimsonDanger,
              ),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _buildInspectorBody(context),
        ),
      ),
    );
  }
}
