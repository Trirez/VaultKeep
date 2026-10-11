import 'dart:async';

import 'package:flutter/material.dart';

import '../backend.dart';
import '../clipboard_guard.dart';
import '../theme.dart';
import '../vault_controller.dart';

/// Enpass 1:1 Password Generator Dialog / Popover (`Enpass_5dPDQrZflh.png`).
class PasswordGeneratorDialog extends StatefulWidget {
  const PasswordGeneratorDialog({
    super.key,
    required this.controller,
    this.onUsePassword,
  });

  final VaultController controller;
  final ValueChanged<String>? onUsePassword;

  static Future<String?> show(
    BuildContext context, {
    required VaultController controller,
    ValueChanged<String>? onUsePassword,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => PasswordGeneratorDialog(
        controller: controller,
        onUsePassword: onUsePassword,
      ),
    );
  }

  @override
  State<PasswordGeneratorDialog> createState() =>
      _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<PasswordGeneratorDialog> {
  String _generated = '';
  int _length = 20;
  bool _pronounceable = false;
  bool _uppercase = true;
  bool _digits = true;
  bool _symbols = true;
  bool _moreOptionsExpanded = true;
  bool _exactMode = false;
  int _minUpper = 2;
  int _minDigits = 2;
  int _minSymbols = 2;
  bool _excludeMode = true;
  bool _allowAmbiguous = false;
  final _customCharsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_regenerate());
  }

  @override
  void dispose() {
    _customCharsCtrl.text = '';
    _customCharsCtrl.dispose();
    super.dispose();
  }

  Future<void> _regenerate() async {
    try {
      final pw = await widget.controller.generateCustomPassword(
        PasswordGenConfig(
          length: _length,
          uppercase: _uppercase,
          digits: _digits,
          symbols: _symbols,
          pronounceable: _pronounceable,
          allowAmbiguous: _allowAmbiguous,
          exactMode: _exactMode,
          minUpper: _uppercase ? _minUpper : 0,
          minDigits: _digits ? _minDigits : 0,
          minSymbols: _symbols ? _minSymbols : 0,
          excludeChars: _excludeMode ? _customCharsCtrl.text : '',
          includeChars: !_excludeMode ? _customCharsCtrl.text : '',
        ),
      );
      if (!mounted) return;
      setState(() => _generated = pw);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(VaultController.describe(e))),
      );
    }
  }

  String _strengthLabel() {
    if (_generated.length >= 16 && (_uppercase || _digits || _symbols)) {
      return 'Excellent';
    }
    if (_generated.length >= 12) return 'Good';
    if (_generated.length >= 8) return 'Moderate';
    return 'Weak';
  }

  Color _strengthColor() {
    final label = _strengthLabel();
    if (label == 'Excellent') return TacticalTheme.emeraldReady;
    if (label == 'Good') return TacticalTheme.cyanTactical;
    if (label == 'Moderate') return TacticalTheme.amberPrimary;
    return TacticalTheme.crimsonDanger;
  }

  @override
  Widget build(BuildContext context) {
    final strengthLabel = _strengthLabel();
    final strengthColor = _strengthColor();

    return Dialog(
      key: const ValueKey('enpass_password_generator_dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(
                      Icons.password,
                      color: TacticalTheme.amberPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Password Generator',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: TacticalTheme.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Generated Password Preview Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: TacticalTheme.bgDeepCarbon,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: TacticalTheme.borderTech,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_generated.isNotEmpty)
                        TacticalColorPassword(
                          key: const ValueKey('pwgen_preview_text'),
                          password: _generated,
                          fontSize: 16,
                        )
                      else
                        Text(
                          'Generating...',
                          style: TacticalTheme.monoStyle(
                            color: TacticalTheme.textMuted,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: TacticalTheme.bgSurface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: strengthColor,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              strengthLabel,
                              style: TacticalTheme.monoStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: strengthColor,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TacticalActionSquare(
                                key: const ValueKey('pwgen_button_regenerate'),
                                icon: Icons.refresh,
                                tooltip: 'Regenerate password',
                                color: TacticalTheme.amberPrimary,
                                onPressed: _regenerate,
                              ),
                              const SizedBox(width: 8),
                              TacticalActionSquare(
                                key: const ValueKey('pwgen_button_copy'),
                                icon: Icons.copy,
                                tooltip: 'Copy password',
                                color: TacticalTheme.cyanTactical,
                                onPressed: () {
                                  if (_generated.isEmpty) return;
                                  ClipboardGuard.copySecret(_generated);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Generated password copied. Clears in 15 seconds.',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Length Slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Length',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: TacticalTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '$_length',
                      style: TacticalTheme.monoStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: TacticalTheme.amberBright,
                      ),
                    ),
                  ],
                ),
                Slider(
                  key: const ValueKey('pwgen_slider_length'),
                  value: _length.toDouble(),
                  min: 8,
                  max: 64,
                  divisions: 56,
                  activeColor: TacticalTheme.amberPrimary,
                  onChanged: (v) {
                    setState(() => _length = v.round());
                    unawaited(_regenerate());
                  },
                ),

                // Pronounceable / Uppercase / Digits / Symbols switches
                _ToggleRow(
                  key: const ValueKey('pwgen_switch_pronounceable'),
                  label: 'Pronounceable',
                  value: _pronounceable,
                  onChanged: (v) {
                    setState(() => _pronounceable = v);
                    unawaited(_regenerate());
                  },
                ),
                _ToggleRow(
                  key: const ValueKey('pwgen_switch_uppercase'),
                  label: 'Uppercase',
                  value: _uppercase,
                  onChanged: (v) {
                    setState(() => _uppercase = v);
                    unawaited(_regenerate());
                  },
                ),
                _ToggleRow(
                  key: const ValueKey('pwgen_switch_digits'),
                  label: 'Digits',
                  value: _digits,
                  onChanged: (v) {
                    setState(() => _digits = v);
                    unawaited(_regenerate());
                  },
                ),
                _ToggleRow(
                  key: const ValueKey('pwgen_switch_symbols'),
                  label: 'Symbols',
                  value: _symbols,
                  onChanged: (v) {
                    setState(() => _symbols = v);
                    unawaited(_regenerate());
                  },
                ),
                const Divider(height: 20),

                // More Options Header
                InkWell(
                  onTap: () => setState(
                    () => _moreOptionsExpanded = !_moreOptionsExpanded,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'More Options',
                          style: TacticalTheme.monoStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: TacticalTheme.amberPrimary,
                          ),
                        ),
                        Icon(
                          _moreOptionsExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: TacticalTheme.amberPrimary,
                        ),
                      ],
                    ),
                  ),
                ),

                if (_moreOptionsExpanded) ...[
                  const SizedBox(height: 8),
                  // Using: Minimum | Exactly
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        'Using',
                        style: TacticalTheme.monoStyle(
                          fontSize: 12,
                          color: TacticalTheme.textSecondary,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChoiceChip(
                            label: const Text('Minimum'),
                            selected: !_exactMode,
                            onSelected: (_) {
                              setState(() => _exactMode = false);
                              unawaited(_regenerate());
                            },
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: const Text('Exactly'),
                            selected: _exactMode,
                            onSelected: (_) {
                              setState(() => _exactMode = true);
                              unawaited(_regenerate());
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_uppercase)
                    _CountSliderRow(
                      label: 'Uppercase',
                      value: _minUpper,
                      onChanged: (v) {
                        setState(() => _minUpper = v);
                        unawaited(_regenerate());
                      },
                    ),
                  if (_digits)
                    _CountSliderRow(
                      label: 'Digits',
                      value: _minDigits,
                      onChanged: (v) {
                        setState(() => _minDigits = v);
                        unawaited(_regenerate());
                      },
                    ),
                  if (_symbols)
                    _CountSliderRow(
                      label: 'Symbols',
                      value: _minSymbols,
                      onChanged: (v) {
                        setState(() => _minSymbols = v);
                        unawaited(_regenerate());
                      },
                    ),
                  const SizedBox(height: 8),
                  // Exclude / Include custom characters
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Exclude'),
                        selected: _excludeMode,
                        onSelected: (_) {
                          setState(() => _excludeMode = true);
                          unawaited(_regenerate());
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Include'),
                        selected: !_excludeMode,
                        onSelected: (_) {
                          setState(() => _excludeMode = false);
                          unawaited(_regenerate());
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customCharsCtrl,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    style: TacticalTheme.monoStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: _excludeMode
                          ? 'Characters to exclude (e.g. {}[]()/\\\')'
                          : 'Additional characters to include',
                    ),
                    onChanged: (_) => unawaited(_regenerate()),
                  ),
                  const SizedBox(height: 8),
                  _ToggleRow(
                    key: const ValueKey('pwgen_switch_ambiguous'),
                    label: 'Ambiguous Characters',
                    value: _allowAmbiguous,
                    onChanged: (v) {
                      setState(() => _allowAmbiguous = v);
                      unawaited(_regenerate());
                    },
                  ),
                ],

                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 15),
                      label: const Text('Copy'),
                      onPressed: () {
                        if (_generated.isEmpty) return;
                        ClipboardGuard.copySecret(_generated);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Password copied. Clears in 15 seconds.',
                            ),
                          ),
                        );
                      },
                    ),
                    if (widget.onUsePassword != null)
                      FilledButton.icon(
                        key: const ValueKey('pwgen_button_fill'),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Fill Password'),
                        onPressed: () {
                          widget.onUsePassword?.call(_generated);
                          Navigator.of(context).pop(_generated);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: TacticalTheme.textPrimary,
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: TacticalTheme.amberPrimary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _CountSliderRow extends StatelessWidget {
  const _CountSliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TacticalTheme.monoStyle(
                fontSize: 11,
                color: TacticalTheme.textSecondary,
              ),
            ),
            Text(
              '$value',
              style: TacticalTheme.monoStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: TacticalTheme.cyanTactical,
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: 8,
          divisions: 8,
          activeColor: TacticalTheme.cyanTactical,
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}
