import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
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
        problem =
            'A file already exists at this path. Switch to Unlock or choose a new path.';
      } else if (master.length < _minMasterLength) {
        problem =
            'Use at least $_minMasterLength characters for the master password.';
      } else if (master != _confirm.text) {
        problem = 'The two passwords do not match.';
      }
    } else {
      if (!fileExists) {
        problem =
            'Vault file does not exist at this path. Check path or switch to Create.';
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
        icon: const Icon(
          Icons.fingerprint,
          size: 44,
          color: TacticalTheme.amberPrimary,
        ),
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
    return Scaffold(
      backgroundColor: TacticalTheme.bgDeepCarbon,
      body: SafeArea(
        child: Column(
          children: [
            // Tactical Top Telemetry Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    size: 16,
                    color: TacticalTheme.amberPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SECURITY CONSOLE // KDBX4 / ARGON2ID',
                      style: TacticalTheme.monoStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: TacticalTheme.amberPrimary,
                        letterSpacing: 0.8,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: TacticalTheme.bgDeepCarbon,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: TacticalTheme.borderTech,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: TacticalTheme.amberPrimary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'LOCKED',
                          style: TacticalTheme.monoStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: TacticalTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Main Centered Console Card
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) {
                        final c = widget.controller;
                        final creating = _creating;
                        final message = _localError ?? c.error;

                        return Container(
                          decoration: BoxDecoration(
                            color: TacticalTheme.bgPanel,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: TacticalTheme.borderTech,
                              width: 1.2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: TacticalTheme.shadowColor,
                                blurRadius: 24,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Top Amber Accent Line
                              Container(
                                height: 3,
                                decoration: const BoxDecoration(
                                  color: TacticalTheme.amberPrimary,
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(5),
                                  ),
                                ),
                              ),

                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Header Row
                                    Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: TacticalTheme.amberDim,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                              color: TacticalTheme.amberPrimary,
                                              width: 1,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.lock_outline,
                                            size: 24,
                                            color: TacticalTheme.amberBright,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'VaultKeep',
                                                style: TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w800,
                                                  color:
                                                      TacticalTheme.textPrimary,
                                                  letterSpacing: 0.4,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'CRYPTOGRAPHIC VAULT ENGINE',
                                                style: TacticalTheme.monoStyle(
                                                  fontSize: 10,
                                                  color:
                                                      TacticalTheme.amberPrimary,
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // Mode Switcher
                                    SegmentedButton<bool>(
                                      style: SegmentedButton.styleFrom(
                                        backgroundColor:
                                            TacticalTheme.bgDeepCarbon,
                                        selectedBackgroundColor:
                                            TacticalTheme.amberPrimary,
                                        selectedForegroundColor:
                                            TacticalTheme.bgDeepCarbon,
                                        foregroundColor:
                                            TacticalTheme.textSecondary,
                                        side: const BorderSide(
                                          color: TacticalTheme.borderTech,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      ),
                                      segments: const [
                                        ButtonSegment<bool>(
                                          value: false,
                                          label: Text('Unlock'),
                                          icon: Icon(Icons.lock_open, size: 16),
                                        ),
                                        ButtonSegment<bool>(
                                          value: true,
                                          label: Text('Create'),
                                          icon: Icon(Icons.add, size: 16),
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

                                    // Vault Path Input
                                    TextField(
                                      key: const ValueKey('unlock_field_path'),
                                      controller: _path,
                                      style: TacticalTheme.monoStyle(
                                        fontSize: 12,
                                        color: TacticalTheme.textPrimary,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                      decoration: InputDecoration(
                                        labelText: 'Vault file (.kdbx)',
                                        helperText:
                                            'Tip: a path inside a Drive/OneDrive folder syncs the vault.',
                                        helperMaxLines: 2,
                                        suffixIcon: IconButton(
                                          tooltip:
                                              'Browse files or cloud folders',
                                          icon: const Icon(
                                            Icons.folder_open,
                                            color: TacticalTheme.amberPrimary,
                                            size: 20,
                                          ),
                                          onPressed: _pickVaultPath,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Master Password Input
                                    TextField(
                                      key: const ValueKey(
                                        'unlock_field_master',
                                      ),
                                      controller: _master,
                                      obscureText: !_show,
                                      enableSuggestions: false,
                                      autocorrect: false,
                                      enableIMEPersonalizedLearning: false,
                                      style: TacticalTheme.monoStyle(
                                        fontSize: 13,
                                        color: TacticalTheme.textPrimary,
                                      ),
                                      onChanged: (_) {
                                        if (creating) setState(() {});
                                      },
                                      onSubmitted: (_) =>
                                          creating ? null : _submit(),
                                      decoration: InputDecoration(
                                        labelText: 'Master password',
                                        suffixIcon: IconButton(
                                          tooltip: _show ? 'Hide' : 'Show',
                                          icon: Icon(
                                            _show
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            size: 19,
                                            color: TacticalTheme.textSecondary,
                                          ),
                                          onPressed: () =>
                                              setState(() => _show = !_show),
                                        ),
                                      ),
                                    ),

                                    // Entropy / Length bar when creating
                                    if (creating) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'KEY ENTROPY (MIN 12 CHARS)',
                                              style: TacticalTheme.monoStyle(
                                                fontSize: 10,
                                                color:
                                                    TacticalTheme.textSecondary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${_master.text.length}/$_minMasterLength+',
                                            style: TacticalTheme.monoStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: _master.text.length >=
                                                      _minMasterLength
                                                  ? TacticalTheme.emeraldReady
                                                  : TacticalTheme.amberPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      SegmentedAmberBar(
                                        fraction: (_master.text.length / 16)
                                            .clamp(0.0, 1.0),
                                        segments: 12,
                                        height: 6,
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        key: const ValueKey(
                                          'unlock_field_confirm',
                                        ),
                                        controller: _confirm,
                                        obscureText: !_show,
                                        enableSuggestions: false,
                                        autocorrect: false,
                                        enableIMEPersonalizedLearning: false,
                                        style: TacticalTheme.monoStyle(
                                          fontSize: 13,
                                          color: TacticalTheme.textPrimary,
                                        ),
                                        onSubmitted: (_) => _submit(),
                                        decoration: const InputDecoration(
                                          labelText: 'Repeat master password',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: TacticalTheme.amberDim,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: TacticalTheme.amberPrimary,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.privacy_tip_outlined,
                                              size: 16,
                                              color: TacticalTheme.amberBright,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Zero-Knowledge Warning: Your master password is never stored or transmitted. If lost, your vault cannot be recovered.',
                                                style: TacticalTheme.monoStyle(
                                                  fontSize: 11,
                                                  color:
                                                      TacticalTheme.amberBright,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    // Error Message Box
                                    if (message != null) ...[
                                      const SizedBox(height: 14),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: TacticalTheme.crimsonDim,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: TacticalTheme.crimsonDanger,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.warning_amber_rounded,
                                              size: 16,
                                              color:
                                                  TacticalTheme.crimsonDanger,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                message,
                                                style: TacticalTheme.monoStyle(
                                                  fontSize: 11,
                                                  color: TacticalTheme
                                                      .crimsonLight,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 20),

                                    // Submit CTA
                                    FilledButton(
                                      key: const ValueKey(
                                        'unlock_button_submit',
                                      ),
                                      onPressed: c.busy ? null : _submit,
                                      child: c.busy
                                          ? const SizedBox(
                                              height: 18,
                                              width: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color:
                                                    TacticalTheme.bgDeepCarbon,
                                              ),
                                            )
                                          : Text(
                                              creating
                                                  ? 'Create vault'
                                                  : 'Unlock',
                                            ),
                                    ),

                                    if (!creating) ...[
                                      const SizedBox(height: 10),
                                      OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.fingerprint,
                                          size: 18,
                                          color: TacticalTheme.cyanTactical,
                                        ),
                                        label: const Text(
                                          'Unlock with Biometrics',
                                        ),
                                        onPressed: c.busy
                                            ? null
                                            : _authenticateBiometric,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
