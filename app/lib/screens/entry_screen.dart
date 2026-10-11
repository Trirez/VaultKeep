import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';


import '../backend.dart';
import '../clipboard_guard.dart';
import '../theme.dart';
import '../vault_controller.dart';
import 'file_picker_dialog.dart';
import 'password_generator_sheet.dart';

/// Enpass Field Types shown in the `Field Options` modal (`Enpass_1xVwnTUhyR.png`).
const List<String> kEnpassFieldTypes = [
  'Username',
  'E-mail',
  'Password',
  'URL',
  'Phone',
  'One-time Code',
  'Multiline',
  'Cardholder Name',
  'Card Number',
  'CVC',
  'Expiry Date',
  'PIN',
  'Text',
];

class CustomFieldEntry {
  CustomFieldEntry({
    required this.name,
    required this.fieldType,
    required this.section,
    required this.sensitive,
    String initialValue = '',
    this.originalIndex,
    this.loaded = true,
  }) : controller = TextEditingController(text: initialValue);

  String name;
  String fieldType;
  String section;
  bool sensitive;
  bool revealed = false;
  int? originalIndex;
  bool loaded;
  final TextEditingController controller;

  void dispose() {
    controller.text = '';
    controller.dispose();
  }
}

/// Create (`entryId == null`) or edit an entry.
/// Can be pushed as a full-screen route or embedded in the desktop inspector pane.
class EntryScreen extends StatefulWidget {
  const EntryScreen({
    super.key,
    required this.controller,
    this.entryId,
    this.initialCategory,
    this.autofocusTitle = false,
    this.isEmbedded = false,
    this.onSaved,
    this.onDeleted,
  });

  final VaultController controller;
  final String? entryId;
  final String? initialCategory;
  final bool autofocusTitle;
  final bool isEmbedded;
  final ValueChanged<String>? onSaved;
  final VoidCallback? onDeleted;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _form = GlobalKey<FormState>();
  final _titleFocusNode = FocusNode();

  final _title = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _url = TextEditingController();
  final _phone = TextEditingController();
  final _securityQuestion = TextEditingController();
  final _securityAnswer = TextEditingController();
  final _notes = TextEditingController();
  final _otpUri = TextEditingController();
  final _tagsCtrl = TextEditingController();

  String? _selectedGroupId;
  String _selectedCategory = 'Login';
  bool _isFavorite = false;
  bool _isArchived = false;
  bool _isTrashed = false;
  int? _loadedRevisionDate;
  VaultTotp? _totp;
  Timer? _totpTimer;
  List<VaultAttachment> _attachments = [];
  VaultPasskey? _passkey;
  VaultPasskeyAssertion? _lastPasskeyAssertion;
  bool _passkeySupported = false;

  List<String> _sections = ['ADDITIONAL DETAILS', 'Section'];
  final List<CustomFieldEntry> _customFields = [];

  bool _loading = false;
  bool _saving = false;
  bool _show = false;
  bool _showOtp = false;
  bool _showSecurityAnswer = false;
  bool _hasExistingOtp = false;
  bool _otpLoaded = true;
  bool _otpModified = false;
  bool _hasExistingSecurityAnswer = false;
  bool _securityAnswerLoaded = true;
  bool _securityAnswerModified = false;
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
      _selectedCategory = widget.initialCategory ??
          widget.controller.selectedItemCategory ??
          'Login';
      if (widget.autofocusTitle) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _titleFocusNode.requestFocus();
        });
      }
    }
  }

  void _clearCustomFields() {
    for (final f in _customFields) {
      f.dispose();
    }
    _customFields.clear();
  }

  @override
  void didUpdateWidget(covariant EntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryId != widget.entryId ||
        oldWidget.initialCategory != widget.initialCategory) {
      _totpTimer?.cancel();
      _totp = null;
      _loadedRevisionDate = null;
      _password.text = '';
      _otpUri.text = '';
      _securityAnswer.text = '';
      _title.clear();
      _username.clear();
      _email.clear();
      _url.clear();
      _phone.clear();
      _securityQuestion.clear();
      _notes.clear();
      _tagsCtrl.clear();
      _clearCustomFields();
      _sections = ['ADDITIONAL DETAILS', 'Section'];
      _attachments = [];
      _passkey = null;
      _lastPasskeyAssertion = null;
      _passkeySupported = false;
      _isFavorite = false;
      _isArchived = false;
      _isTrashed = false;
      _show = false;
      _showOtp = false;
      _showSecurityAnswer = false;
      _hasExistingOtp = false;
      _otpLoaded = true;
      _otpModified = false;
      _hasExistingSecurityAnswer = false;
      _securityAnswerLoaded = true;
      _securityAnswerModified = false;

      if (_isEdit) {
        unawaited(_load());
      } else {
        setState(() {
          _selectedGroupId = widget.controller.selectedGroupId;
          _selectedCategory = widget.initialCategory ??
              widget.controller.selectedItemCategory ??
              'Login';
        });
        if (widget.autofocusTitle) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _titleFocusNode.requestFocus();
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    _password.text = '';
    _otpUri.text = '';
    _securityAnswer.text = '';
    _clearCustomFields();
    _titleFocusNode.dispose();
    _title.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _url.dispose();
    _phone.dispose();
    _securityQuestion.dispose();
    _securityAnswer.dispose();
    _notes.dispose();
    _otpUri.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _recordGeneratedPassword(String password) {
    if (password.isEmpty) return;
    final label = _url.text.trim().isNotEmpty
        ? _url.text.trim()
        : (_title.text.trim().isNotEmpty
            ? _title.text.trim()
            : 'Generated Password');
    widget.controller.recordGeneratedPassword(
      password,
      domainOrTitle: label,
    );
  }

  Future<void> _refreshTotp() async {
    if (widget.entryId == null ||
        widget.controller.status != VaultStatus.unlocked) {
      return;
    }
    try {
      final token = await widget.controller.getTotp(widget.entryId!);
      if (!mounted || widget.controller.status != VaultStatus.unlocked) return;
      setState(() => _totp = token);
    } catch (_) {}
  }

  Future<void> _toggleShowOtp() async {
    if (!_showOtp && !_otpLoaded && widget.entryId != null) {
      try {
        final uri = await widget.controller.revealOtpUri(widget.entryId!);
        if (!mounted || widget.controller.status != VaultStatus.unlocked) {
          return;
        }
        _otpUri.text = uri ?? '';
        _otpLoaded = true;
      } catch (e) {
        if (mounted) _toast(VaultController.describe(e));
        return;
      }
    }
    setState(() => _showOtp = !_showOtp);
  }

  Future<void> _toggleShowSecurityAnswer() async {
    if (!_showSecurityAnswer &&
        !_securityAnswerLoaded &&
        widget.entryId != null) {
      try {
        final ans =
            await widget.controller.revealSecurityAnswer(widget.entryId!);
        if (!mounted || widget.controller.status != VaultStatus.unlocked) {
          return;
        }
        _securityAnswer.text = ans ?? '';
        _securityAnswerLoaded = true;
      } catch (e) {
        if (mounted) _toast(VaultController.describe(e));
        return;
      }
    }
    setState(() => _showSecurityAnswer = !_showSecurityAnswer);
  }

  Future<bool> _ensureCustomFieldLoaded(CustomFieldEntry cf) async {
    if (cf.loaded ||
        !cf.sensitive ||
        widget.entryId == null ||
        cf.originalIndex == null) {
      return true;
    }
    try {
      final val = await widget.controller.revealCustomField(
        widget.entryId!,
        cf.originalIndex!,
      );
      if (!mounted || widget.controller.status != VaultStatus.unlocked) {
        return false;
      }
      cf.controller.text = val;
      cf.loaded = true;
      return true;
    } catch (e) {
      if (mounted) _toast(VaultController.describe(e));
      return false;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final id = widget.entryId!;
      final entry = await widget.controller.loadEntry(id);
      final password = await widget.controller.revealPassword(id);
      if (!mounted || widget.controller.status != VaultStatus.unlocked) return;
      _title.text = entry.title;
      _username.text = entry.username;
      _email.text = entry.email;
      _url.text = entry.url;
      _phone.text = entry.phone;
      _securityQuestion.text = entry.securityQuestion;
      _hasExistingSecurityAnswer = entry.hasSecurityAnswer;
      _securityAnswerLoaded = !entry.hasSecurityAnswer;
      _securityAnswerModified = false;
      _securityAnswer.text = '';
      _notes.text = entry.notes;
      _password.text = password;
      _selectedGroupId = entry.groupId;
      _selectedCategory = kEnpassCategories.contains(entry.category)
          ? entry.category
          : 'Login';
      _isFavorite = entry.isFavorite;
      _isArchived = entry.isArchived;
      _isTrashed = entry.isTrashed;
      _tagsCtrl.text = entry.tags.join(', ');
      _hasExistingOtp = entry.hasOtp;
      _otpLoaded = !entry.hasOtp;
      _otpModified = false;
      _otpUri.text = '';
      _attachments = List.of(entry.attachments);
      _passkey = entry.passkey;
      _lastPasskeyAssertion = null;
      _passkeySupported = entry.passkeySupported;
      _loadedRevisionDate = entry.revisionDate;

      _clearCustomFields();
      if (entry.sections.isNotEmpty) {
        _sections = List.of(entry.sections);
      } else {
        _sections = ['ADDITIONAL DETAILS', 'Section'];
      }
      for (var i = 0; i < entry.customFields.length; i++) {
        final cf = entry.customFields[i];
        if (cf.section.isNotEmpty && !_sections.contains(cf.section)) {
          _sections.add(cf.section);
        }
        _customFields.add(
          CustomFieldEntry(
            name: cf.name,
            fieldType: cf.fieldType,
            section: cf.section.isEmpty ? _sections.last : cf.section,
            sensitive: cf.sensitive,
            initialValue: cf.sensitive ? '' : cf.value,
            originalIndex: i,
            loaded: !cf.sensitive,
          ),
        );
      }

      if (entry.hasOtp) {
        unawaited(_refreshTotp());
        _totpTimer?.cancel();
        _totpTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _refreshTotp(),
        );
      }
    } catch (e) {
      if (mounted && widget.controller.status == VaultStatus.unlocked) {
        _toast(VaultController.describe(e));
      }
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
      if (!mounted || widget.controller.status != VaultStatus.unlocked) return;
      _recordGeneratedPassword(password);
      setState(() {
        _password.text = password;
        _show = true;
      });
    } catch (e) {
      if (mounted) _toast(VaultController.describe(e));
    }
  }

  Future<void> _openEnpassGenerator() async {
    await PasswordGeneratorDialog.show(
      context,
      controller: widget.controller,
      onUsePassword: (generated) {
        _recordGeneratedPassword(generated);
        setState(() {
          _password.text = generated;
          _show = true;
        });
      },
    );
  }

  Future<void> _showGeneratorHistoryDialog() async {
    final history = widget.controller.generatorHistory;
    if (history.isEmpty) {
      // Seed with current generated password if user opens history immediately
      final sample = await widget.controller.generatePassword(
        length: _genLength,
        symbols: _genSymbols,
      );
      _recordGeneratedPassword(sample);
    }
    if (!mounted) return;
    final revealedIndices = <int>{};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          key: const ValueKey('enpass_generator_history_dialog'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.history,
                        color: TacticalTheme.amberPrimary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Generator History',
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
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final rec = history[i];
                        final isRevealed = revealedIndices.contains(i);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: TacticalTheme.bgSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: TacticalTheme.borderTech),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      rec.domainOrTitle,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: TacticalTheme.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    if (isRevealed)
                                      TacticalColorPassword(
                                        password: rec.password,
                                        fontSize: 12,
                                      )
                                    else
                                      Text(
                                        'â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢',
                                        style: TacticalTheme.monoStyle(
                                          fontSize: 13,
                                          color: TacticalTheme.amberBright,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      rec.timestampLabel,
                                      style: TacticalTheme.monoStyle(
                                        fontSize: 10,
                                        color: TacticalTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton(
                                key: ValueKey('gen_history_fill_$i'),
                                onPressed: () {
                                  setState(() {
                                    _password.text = rec.password;
                                    _show = true;
                                  });
                                  Navigator.of(ctx).pop();
                                },
                                child: const Text('Fill'),
                              ),
                              IconButton(
                                tooltip: isRevealed ? 'Hide' : 'Reveal',
                                icon: Icon(
                                  isRevealed
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: TacticalTheme.cyanTactical,
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    if (isRevealed) {
                                      revealedIndices.remove(i);
                                    } else {
                                      revealedIndices.add(i);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the Enpass `Field Options` modal (`Enpass_1xVwnTUhyR.png` & `Enpass_ETlwI2CT5x.png`).
  Future<void> _showFieldOptionsModal({CustomFieldEntry? existingField}) async {
    var fieldName = existingField?.name ?? 'Custom Field';
    var selectedType = existingField?.fieldType ?? 'Username';
    if (!kEnpassFieldTypes.contains(selectedType)) {
      selectedType = 'Text';
    }
    var sensitive = existingField?.sensitive ?? false;
    final selectedSection = existingField?.section ?? _sections.last;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          key: const ValueKey('enpass_field_options_dialog'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Field Options',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: TacticalTheme.textPrimary,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.of(ctx).pop('cancel'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const ValueKey('field_options_name'),
                    initialValue: fieldName,
                    onChanged: (v) => fieldName = v,
                    style: TacticalTheme.monoStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Field Name',
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('field_options_type'),
                    initialValue: selectedType,
                    isExpanded: true,
                    dropdownColor: TacticalTheme.bgElevated,
                    decoration: const InputDecoration(
                      labelText: 'Field Type',
                    ),
                    items: [
                      for (final ft in kEnpassFieldTypes)
                        DropdownMenuItem(
                          value: ft,
                          child: Text(ft),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        selectedType = v;
                        if (v == 'Password' || v == 'CVC' || v == 'PIN') {
                          sensitive = true;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: TacticalTheme.bgSurface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: TacticalTheme.borderTech),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Sensitive',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: TacticalTheme.textPrimary,
                          ),
                        ),
                        Switch(
                          key: const ValueKey('field_options_sensitive'),
                          value: sensitive,
                          activeThumbColor: TacticalTheme.amberPrimary,
                          onChanged: (v) =>
                              setDialogState(() => sensitive = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('field_options_delete'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TacticalTheme.crimsonDanger,
                          side: BorderSide(
                            color: TacticalTheme.crimsonDanger,
                          ),
                        ),
                        onPressed: () => Navigator.of(ctx).pop('delete'),
                        child: const Text('Delete Field'),
                      ),
                      FilledButton(
                        key: const ValueKey('field_options_save'),
                        onPressed: () => Navigator.of(ctx).pop('save'),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'delete') {
      if (existingField != null) {
        setState(() {
          _customFields.remove(existingField);
          existingField.dispose();
        });
        _toast('Field deleted.');
      }
    } else if (action == 'save') {
      final trimmedName = fieldName.trim().isEmpty
          ? selectedType
          : fieldName.trim();
      setState(() {
        if (existingField != null) {
          existingField.name = trimmedName;
          existingField.fieldType = selectedType;
          existingField.sensitive = sensitive;
        } else {
          _customFields.add(
            CustomFieldEntry(
              name: trimmedName,
              fieldType: selectedType,
              section: selectedSection,
              sensitive: sensitive,
            ),
          );
        }
      });
    }
  }

  Future<void> _showAddSectionModal() async {
    var sectionName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Section'),
        content: TextFormField(
          key: const ValueKey('add_section_name_field'),
          initialValue: '',
          autofocus: true,
          onChanged: (v) => sectionName = v,
          style: TacticalTheme.monoStyle(fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Section Title',
            hintText: 'e.g. Recovery Codes, Server SSH, Billing',
          ),
          onFieldSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(sectionName.trim()),
            child: const Text('Add Section'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && mounted) {
      setState(() {
        if (!_sections.contains(name)) {
          _sections.add(name);
        }
      });
    }
  }

  Future<void> _generatePasskey() async {
    if (widget.entryId == null) {
      _toast('Save this entry first before generating a passkey.');
      return;
    }
    try {
      final pk = await widget.controller.generatePasskey(
        widget.entryId!,
        rpId: _url.text.trim(),
        username: _username.text.trim(),
      );
      final updated = await widget.controller.loadEntry(widget.entryId!);
      if (!mounted || widget.controller.status != VaultStatus.unlocked) return;
      setState(() {
        _passkey = pk;
        _lastPasskeyAssertion = null;
        _passkeySupported = false;
        _loadedRevisionDate = updated.revisionDate;
      });
      _toast('Passkey (ES256 P-256 / Synced BE=1 BS=1) bound to entry.');
    } catch (e) {
      if (mounted) _toast(VaultController.describe(e));
    }
  }

  Future<void> _verifyPasskeyAssertion() async {
    if (widget.entryId == null || _passkey == null) return;
    final platform = defaultTargetPlatform == TargetPlatform.android
        ? 'android'
        : 'windows';
    try {
      final assertion = await widget.controller.authenticatePasskey(
        widget.entryId!,
        platform: platform,
        origin: 'https://${_passkey!.rpId}',
        userVerified: true,
      );
      if (!mounted || widget.controller.status != VaultStatus.unlocked) return;
      setState(() {
        _lastPasskeyAssertion = assertion;
      });
      final flagsHex =
          '0x${assertion.flags.toRadixString(16).padLeft(2, '0')}';
      _toast(
        'WebAuthn assertion signed on ${assertion.platform.toUpperCase()} (Flags $flagsHex: UP=1, UV=1, BE=1, BS=1).',
      );
    } catch (e) {
      if (mounted) _toast(VaultController.describe(e));
    }
  }

  Future<void> _removePasskey() async {
    if (widget.entryId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove passkey?'),
        content: const Text(
          'This will remove the bound FIDO2/WebAuthn passkey from this entry.',
        ),
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.removePasskey(widget.entryId!);
      final updated = await widget.controller.loadEntry(widget.entryId!);
      if (!mounted || widget.controller.status != VaultStatus.unlocked) return;
      setState(() {
        _passkey = updated.passkey;
        _lastPasskeyAssertion = null;
        _passkeySupported = updated.passkeySupported;
        _loadedRevisionDate = updated.revisionDate;
      });
      _toast('Passkey removed from entry.');
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
          final refreshedEntry =
              await widget.controller.loadEntry(widget.entryId!);
          if (mounted && widget.controller.status == VaultStatus.unlocked) {
            setState(() {
              _attachments = updated;
              _loadedRevisionDate = refreshedEntry.revisionDate;
            });
          }
          _toast('Attachment added: $name');
        } catch (e) {
          if (mounted) _toast(VaultController.describe(e));
        }
      }
    }
  }

  Future<void> _deleteAttachment(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove attachment?'),
        content: Text('Remove "$name" from this entry?'),
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.removeAttachment(widget.entryId!, name);
      final updated = await widget.controller.listAttachments(widget.entryId!);
      final refreshedEntry = await widget.controller.loadEntry(widget.entryId!);
      if (mounted && widget.controller.status == VaultStatus.unlocked) {
        setState(() {
          _attachments = updated;
          _loadedRevisionDate = refreshedEntry.revisionDate;
        });
      }
      _toast('Attachment removed.');
    } catch (e) {
      if (mounted) _toast(VaultController.describe(e));
    }
  }

  Future<void> _viewAttachment(String name) async {
    try {
      final data =
          await widget.controller.getAttachment(widget.entryId!, name);
      if (!mounted || widget.controller.status != VaultStatus.unlocked) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            name,
            style: TacticalTheme.monoStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
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

  List<String> _parseTags() {
    return _tagsCtrl.text
        .split(RegExp(r'[,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
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
      for (final cf in _customFields) {
        if (!cf.loaded && cf.sensitive) {
          final ok = await _ensureCustomFieldLoaded(cf);
          if (!ok || !mounted) {
            if (mounted) setState(() => _saving = false);
            return;
          }
        }
      }
      final parsedTags = _parseTags();
      final hasNonDefaultMeta = _selectedCategory != 'Login' ||
          parsedTags.isNotEmpty ||
          _isFavorite ||
          _isArchived ||
          _isTrashed;
      final effectiveOtp =
          (_otpLoaded || _otpModified) ? _otpUri.text.trim() : null;
      final effectiveSecAnswer = (_securityAnswerLoaded || _securityAnswerModified)
          ? _securityAnswer.text
          : null;
      final savedId = await widget.controller.save(
        widget.entryId,
        EntryDraft(
          title: _title.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          url: _url.text.trim(),
          notes: _notes.text,
          groupId: _selectedGroupId,
          otp: effectiveOtp,
          lastKnownRevisionDate: _loadedRevisionDate,
          category: hasNonDefaultMeta ? _selectedCategory : null,
          tags: parsedTags,
          isFavorite: _isFavorite,
          isArchived: _isArchived,
          isTrashed: _isTrashed,
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          securityQuestion: _securityQuestion.text.trim(),
          securityAnswer: effectiveSecAnswer,
          sections: List.of(_sections),
          customFields: [
            for (final cf in _customFields)
              VaultCustomField(
                name: cf.name,
                value: cf.controller.text,
                fieldType: cf.fieldType,
                sensitive: cf.sensitive,
                section: cf.section,
              ),
          ],
        ),
      );
      if (!mounted) return;

      if (widget.controller.status == VaultStatus.unlocked) {
        try {
          final refreshed = await widget.controller.loadEntry(savedId);
          _loadedRevisionDate = refreshed.revisionDate;
          _hasExistingOtp = refreshed.hasOtp;
          _hasExistingSecurityAnswer = refreshed.hasSecurityAnswer;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _saving = false);
      if (widget.isEmbedded) {
        _toast('Entry saved to KDBX4 vault.');
        widget.onSaved?.call(savedId);
        if (widget.entryId != null) {
          final hasActiveOtp = (_otpLoaded || _otpModified)
              ? _otpUri.text.trim().isNotEmpty
              : _hasExistingOtp;
          if (hasActiveOtp) {
            unawaited(_refreshTotp());
            _totpTimer?.cancel();
            _totpTimer = Timer.periodic(
              const Duration(seconds: 1),
              (_) => _refreshTotp(),
            );
          } else {
            _totpTimer?.cancel();
            _totpTimer = null;
            setState(() => _totp = null);
          }
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
      if (!mounted || widget.controller.status != VaultStatus.unlocked) return;
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

  Widget _buildAddDropdownButton() {
    return PopupMenuButton<String>(
      key: const ValueKey('entry_button_add_menu'),
      tooltip: 'Add Field, Section, or Attachment',
      color: TacticalTheme.bgElevated,
      onSelected: (value) {
        if (value == 'field') {
          unawaited(_showFieldOptionsModal());
        } else if (value == 'section') {
          unawaited(_showAddSectionModal());
        } else if (value == 'attachment') {
          unawaited(_addAttachment());
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'field',
          child: Row(
            children: [
              Icon(
                Icons.playlist_add,
                size: 18,
                color: TacticalTheme.amberPrimary,
              ),
              const SizedBox(width: 10),
              const Text('Add Field'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'section',
          child: Row(
            children: [
              Icon(
                Icons.view_agenda_outlined,
                size: 18,
                color: TacticalTheme.cyanTactical,
              ),
              const SizedBox(width: 10),
              const Text('Add Section'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'attachment',
          child: Row(
            children: [
              Icon(
                Icons.attach_file,
                size: 18,
                color: TacticalTheme.emeraldReady,
              ),
              const SizedBox(width: 10),
              const Text('Add Attachment'),
            ],
          ),
        ),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: TacticalTheme.bgElevated,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: TacticalTheme.borderTech),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add',
              style: TacticalTheme.monoStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: TacticalTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 15,
              color: TacticalTheme.amberPrimary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorBody(BuildContext context) {
    final groups = widget.controller.groups;
    final groupValid = _selectedGroupId == null ||
        groups.any((g) => g.id == _selectedGroupId);
    final effectiveGroupId = groupValid ? _selectedGroupId : null;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: TacticalTheme.amberPrimary),
      );
    }

    return Form(
      key: _form,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      Icon(
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

          // Category & Group Dropdowns
          DropdownButtonFormField<String>(
            key: const ValueKey('entry_dropdown_category'),
            initialValue: _selectedCategory,
            isExpanded: true,
            dropdownColor: TacticalTheme.bgElevated,
            style: TacticalTheme.monoStyle(
              fontSize: 12,
              color: TacticalTheme.textPrimary,
            ),
            decoration: const InputDecoration(
              labelText: 'Category',
            ),
            items: [
              for (final cat in kEnpassCategories)
                DropdownMenuItem(
                  value: cat,
                  child: Text(cat, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _selectedCategory = v);
            },
          ),
          if (groups.isNotEmpty) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              key: ValueKey('entry_group_$effectiveGroupId'),
              initialValue: effectiveGroupId,
              isExpanded: true,
              dropdownColor: TacticalTheme.bgElevated,
              style: TacticalTheme.monoStyle(
                fontSize: 12,
                color: TacticalTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Group',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Root Group (None)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final g in groups)
                  DropdownMenuItem<String?>(
                    value: g.id,
                    child: Text(g.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (val) => setState(() => _selectedGroupId = val),
            ),
          ],
          const SizedBox(height: 14),

          // Title with Enpass Avatar + Edit Badge (`Enpass_RUtKiX9m54.png`)
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  TacticalDomainAvatar(
                    title: _title.text.isEmpty ? 'V' : _title.text,
                    url: _url.text,
                    size: 40,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: TacticalTheme.bgElevated,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: TacticalTheme.amberPrimary,
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.edit,
                        size: 9,
                        color: TacticalTheme.amberBright,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('entry_field_title'),
                  controller: _title,
                  focusNode: _titleFocusNode,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: TacticalTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Title',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Title is required'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Username with Field Options (â€¢â€¢â€¢)
          TextFormField(
            key: const ValueKey('entry_field_username'),
            controller: _username,
            autocorrect: false,
            style: TacticalTheme.monoStyle(
              fontSize: 13,
              color: TacticalTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(
                Icons.drag_handle,
                size: 16,
                color: TacticalTheme.textMuted,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Copy username',
                    icon: Icon(
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
                  IconButton(
                    key: const ValueKey('field_options_Username'),
                    tooltip: 'Field Options',
                    icon: Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: TacticalTheme.textSecondary,
                    ),
                    onPressed: () => _showFieldOptionsModal(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // E-mail (Enpass Primary Field)
          TextFormField(
            key: const ValueKey('entry_field_email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            style: TacticalTheme.monoStyle(
              fontSize: 13,
              color: TacticalTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'E-mail',
              prefixIcon: Icon(
                Icons.drag_handle,
                size: 16,
                color: TacticalTheme.textMuted,
              ),
              suffixIcon: IconButton(
                tooltip: 'Field Options',
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: TacticalTheme.textSecondary,
                ),
                onPressed: () => _showFieldOptionsModal(),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Password Box + Enpass Generate / Generator History + Entropy Bar
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
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    final showPw = _show || !widget.controller.hideSensitive;
                    return TextFormField(
                      key: const ValueKey('entry_field_password'),
                      controller: _password,
                      obscureText: !showPw,
                      enableSuggestions: false,
                      autocorrect: false,
                      enableIMEPersonalizedLearning: false,
                      onChanged: (_) => setState(() {}),
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
                              tooltip: showPw ? 'Hide' : 'Show',
                              icon: Icon(
                                showPw
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 18,
                              ),
                              onPressed: () {
                                if (!widget.controller.hideSensitive) {
                                  widget.controller.updateSettings(
                                    hideSensitive: true,
                                  );
                                  setState(() => _show = false);
                                } else {
                                  setState(() => _show = !_show);
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Generate',
                              icon: Icon(
                                Icons.autorenew,
                                size: 18,
                                color: TacticalTheme.amberPrimary,
                              ),
                              onPressed: _generate,
                            ),
                            IconButton(
                              tooltip: 'Copy',
                              icon: Icon(
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
                    );
                  },
                ),
                const SizedBox(height: 6),
                // Enpass Password Strength Bar under Password Field
                LinearProgressIndicator(
                  value: (_password.text.length / 20.0).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: TacticalTheme.bgDeepCarbon,
                  color: _password.text.length >= 14
                      ? TacticalTheme.emeraldReady
                      : (_password.text.length >= 8
                          ? TacticalTheme.amberPrimary
                          : TacticalTheme.crimsonDanger),
                ),
                if ((_show || !widget.controller.hideSensitive) &&
                    _password.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
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
                    child: TacticalColorPassword(
                      key: const ValueKey('entry_color_password_preview'),
                      password: _password.text,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                // Enpass `Generate` & `Generator History` Buttons (`Enpass_RUtKiX9m54.png`, `Enpass_rfEIu8FoJV.png`)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        OutlinedButton(
                          key: const ValueKey('entry_button_open_generator'),
                          onPressed: _openEnpassGenerator,
                          child: const Text('Generate'),
                        ),
                        OutlinedButton(
                          key: const ValueKey(
                            'entry_button_generator_history',
                          ),
                          onPressed: _showGeneratorHistoryDialog,
                          child: const Text('Generator History'),
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
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // URL (`Enpass_RUtKiX9m54.png`)
          TextFormField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: TacticalTheme.monoStyle(
              fontSize: 12,
              color: TacticalTheme.cyanTactical,
            ),
            decoration: InputDecoration(
              labelText: 'URL',
              prefixIcon: Icon(
                Icons.drag_handle,
                size: 16,
                color: TacticalTheme.textMuted,
              ),
              suffixIcon: IconButton(
                tooltip: 'Field Options',
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: TacticalTheme.textSecondary,
                ),
                onPressed: () => _showFieldOptionsModal(),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Passkey (FIDO2 / WebAuthn) Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TacticalTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _passkey != null
                    ? TacticalTheme.emeraldReady.withValues(alpha: 0.7)
                    : TacticalTheme.borderTech,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fingerprint,
                          size: 16,
                          color: _passkey != null
                              ? TacticalTheme.emeraldReady
                              : TacticalTheme.amberPrimary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Passkey (FIDO2 / WebAuthn)',
                            style: TacticalTheme.monoStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: TacticalTheme.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_passkey != null)
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
                          'ACTIVE PASSKEY',
                          style: TacticalTheme.monoStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: TacticalTheme.emeraldReady,
                          ),
                        ),
                      )
                    else if (_passkeySupported)
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
                          'PASSKEY SUPPORTED',
                          style: TacticalTheme.monoStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: TacticalTheme.cyanTactical,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_passkey != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: TacticalTheme.bgDeepCarbon,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: TacticalTheme.borderSubtle,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RP ID: ${_passkey!.rpId}',
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: TacticalTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'User: ${_passkey!.username}',
                          style: TacticalTheme.monoStyle(
                            fontSize: 11,
                            color: TacticalTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cred ID: ${_passkey!.credentialId}',
                          style: TacticalTheme.monoStyle(
                            fontSize: 10,
                            color: TacticalTheme.cyanTactical,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Spec: ES256 (P-256) â€¢ Synced (BE=1, BS=1) â€¢ Windows 11 & Android 14+',
                          style: TacticalTheme.monoStyle(
                            fontSize: 9,
                            color: TacticalTheme.emeraldReady,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_lastPasskeyAssertion != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Verified (${_lastPasskeyAssertion!.platform.toUpperCase()}): '
                            'Flags 0x${_lastPasskeyAssertion!.flags.toRadixString(16).padLeft(2, '0')} '
                            '(UP=1, UV=${_lastPasskeyAssertion!.userVerified ? 1 : 0}, '
                            'BE=${_lastPasskeyAssertion!.backupEligible ? 1 : 0}, '
                            'BS=${_lastPasskeyAssertion!.backupState ? 1 : 0})',
                            key: const ValueKey('passkey_assertion_status'),
                            style: TacticalTheme.monoStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: TacticalTheme.cyanTactical,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('verify_passkey_assertion_btn'),
                        icon: Icon(
                          Icons.verified_user_outlined,
                          size: 14,
                          color: TacticalTheme.emeraldReady,
                        ),
                        label: Text(
                          'Verify Assertion',
                          style: TacticalTheme.monoStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: TacticalTheme.emeraldReady,
                          ),
                        ),
                        onPressed: _verifyPasskeyAssertion,
                      ),
                      OutlinedButton.icon(
                        icon: Icon(
                          Icons.copy,
                          size: 14,
                          color: TacticalTheme.cyanTactical,
                        ),
                        label: Text(
                          'Copy Cred ID',
                          style: TacticalTheme.monoStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: TacticalTheme.cyanTactical,
                          ),
                        ),
                        onPressed: () {
                          ClipboardGuard.copySecret(_passkey!.credentialId);
                          _toast(
                            'Passkey Credential ID copied. Clears in 15 seconds.',
                          );
                        },
                      ),
                      OutlinedButton.icon(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: TacticalTheme.crimsonDanger,
                        ),
                        label: Text(
                          'Remove Passkey',
                          style: TacticalTheme.monoStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: TacticalTheme.crimsonDanger,
                          ),
                        ),
                        onPressed: _removePasskey,
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    _passkeySupported
                        ? 'This service supports FIDO2 / WebAuthn Passkeys. Generate a KDBX4 passkey to upgrade authentication.'
                        : 'No passkey bound to this entry.',
                    style: TacticalTheme.monoStyle(
                      fontSize: 11,
                      color: TacticalTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      icon: Icon(
                        Icons.fingerprint,
                        size: 15,
                        color: TacticalTheme.amberPrimary,
                      ),
                      label: Text(
                        'Generate Passkey',
                        style: TacticalTheme.monoStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: TacticalTheme.amberPrimary,
                        ),
                      ),
                      onPressed: _generatePasskey,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Enpass `ADDITIONAL DETAILS` Section (`Enpass_RUtKiX9m54.png`)
          Text(
            'ADDITIONAL DETAILS',
            style: TacticalTheme.monoStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: TacticalTheme.amberPrimary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),

          // Phone number
          TextFormField(
            key: const ValueKey('entry_field_phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            style: TacticalTheme.monoStyle(
              fontSize: 12,
              color: TacticalTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Phone number',
              prefixIcon: Icon(
                Icons.drag_handle,
                size: 16,
                color: TacticalTheme.textMuted,
              ),
              suffixIcon: IconButton(
                tooltip: 'Field Options',
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: TacticalTheme.textSecondary,
                ),
                onPressed: () => _showFieldOptionsModal(),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // One-time code (TOTP Secret URI)
          TextFormField(
            key: const ValueKey('entry_field_otp'),
            controller: _otpUri,
            obscureText: !_showOtp,
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            onChanged: (_) => _otpModified = true,
            style: TacticalTheme.monoStyle(
              fontSize: 12,
              color: TacticalTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'One-time code (TOTP URI or Secret)',
              hintText: _hasExistingOtp && !_otpLoaded && !_otpModified
                  ? 'â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢ (Stored â€” tap Show to reveal)'
                  : 'Enter secret key',
              prefixIcon: Icon(
                Icons.drag_handle,
                size: 16,
                color: TacticalTheme.textMuted,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _showOtp ? 'Hide' : 'Show',
                    icon: Icon(
                      _showOtp ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: _toggleShowOtp,
                  ),
                  IconButton(
                    tooltip: 'Field Options',
                    icon: Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: TacticalTheme.textSecondary,
                    ),
                    onPressed: () => _showFieldOptionsModal(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Security question
          TextFormField(
            key: const ValueKey('entry_field_security_question'),
            controller: _securityQuestion,
            style: TacticalTheme.monoStyle(
              fontSize: 12,
              color: TacticalTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Security question',
              prefixIcon: Icon(
                Icons.drag_handle,
                size: 16,
                color: TacticalTheme.textMuted,
              ),
              suffixIcon: IconButton(
                tooltip: 'Field Options',
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: TacticalTheme.textSecondary,
                ),
                onPressed: () => _showFieldOptionsModal(),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Security answer (Protected / Sensitive)
          TextFormField(
            key: const ValueKey('entry_field_security_answer'),
            controller: _securityAnswer,
            obscureText: !_showSecurityAnswer,
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            onChanged: (_) => _securityAnswerModified = true,
            style: TacticalTheme.monoStyle(
              fontSize: 12,
              color: TacticalTheme.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Security answer',
              hintText: _hasExistingSecurityAnswer &&
                      !_securityAnswerLoaded &&
                      !_securityAnswerModified
                  ? 'â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢ (Stored â€” tap Show to reveal)'
                  : null,
              prefixIcon: Icon(
                Icons.drag_handle,
                size: 16,
                color: TacticalTheme.textMuted,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _showSecurityAnswer ? 'Hide' : 'Show',
                    icon: Icon(
                      _showSecurityAnswer
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: _toggleShowSecurityAnswer,
                  ),
                  IconButton(
                    tooltip: 'Field Options',
                    icon: Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: TacticalTheme.textSecondary,
                    ),
                    onPressed: () => _showFieldOptionsModal(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Dynamic User-Added Sections & Custom Fields (`Enpass_HV9F8dBiu5.png`, `Enpass_1xVwnTUhyR.png`)
          for (final sectionName in _sections.where(
            (s) => s != 'ADDITIONAL DETAILS',
          )) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  sectionName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: TacticalTheme.textPrimary,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('Add Field'),
                  onPressed: () => _showFieldOptionsModal(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final cf in _customFields.where(
              (f) => f.section == sectionName,
            )) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: cf.controller,
                  obscureText: cf.sensitive && !cf.revealed,
                  maxLines: cf.fieldType == 'Multiline' && !cf.sensitive ? 3 : 1,
                  enableSuggestions: !cf.sensitive,
                  autocorrect: !cf.sensitive,
                  enableIMEPersonalizedLearning: !cf.sensitive,
                  onChanged: (_) => cf.loaded = true,
                  style: TacticalTheme.monoStyle(
                    fontSize: 12,
                    color: TacticalTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: '${cf.name} (${cf.fieldType})',
                    hintText: cf.sensitive && !cf.loaded
                        ? 'â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢ (Stored â€” tap Show to reveal)'
                        : null,
                    prefixIcon: Icon(
                      Icons.drag_handle,
                      size: 16,
                      color: TacticalTheme.textMuted,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (cf.sensitive)
                          IconButton(
                            tooltip: cf.revealed ? 'Hide' : 'Show',
                            icon: Icon(
                              cf.revealed
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 17,
                            ),
                            onPressed: () async {
                              if (!cf.revealed) {
                                final ok = await _ensureCustomFieldLoaded(cf);
                                if (!ok || !mounted) return;
                              }
                              setState(() => cf.revealed = !cf.revealed);
                            },
                          ),
                        IconButton(
                          tooltip: 'Copy ${cf.name}',
                          icon: Icon(
                            Icons.copy,
                            size: 16,
                            color: TacticalTheme.cyanTactical,
                          ),
                          onPressed: () async {
                            final ok = await _ensureCustomFieldLoaded(cf);
                            if (!ok || !mounted) return;
                            if (cf.controller.text.isNotEmpty) {
                              unawaited(
                                ClipboardGuard.copySecret(cf.controller.text),
                              );
                              _toast(
                                '${cf.name} copied. Clears in 15 seconds.',
                              );
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Field Options',
                          icon: Icon(
                            Icons.more_horiz,
                            size: 18,
                            color: TacticalTheme.amberPrimary,
                          ),
                          onPressed: () =>
                              _showFieldOptionsModal(existingField: cf),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],

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
              hintText: 'Add Note',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),

          // Tags (`Enpass_HV9F8dBiu5.png`)
          TextFormField(
            key: const ValueKey('entry_field_tags'),
            controller: _tagsCtrl,
            style: TacticalTheme.monoStyle(
              fontSize: 12,
              color: TacticalTheme.amberBright,
            ),
            decoration: InputDecoration(
              labelText: 'Tags',
              hintText: 'e.g. Cards, Crypto, Email, Finance, Hosting',
              prefixIcon: Icon(
                Icons.sell_outlined,
                size: 16,
                color: TacticalTheme.amberPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Enpass Attachments Box + Drag-and-Drop / Click Zone (`Enpass_HV9F8dBiu5.png`)
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
                      icon: Icon(
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
                const SizedBox(height: 8),
                InkWell(
                  key: const ValueKey('entry_attachments_dropzone'),
                  onTap: _addAttachment,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 18,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: TacticalTheme.bgDeepCarbon,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: TacticalTheme.borderTech,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 20,
                              color: TacticalTheme.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.image_outlined,
                              size: 20,
                              color: TacticalTheme.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.folder_zip_outlined,
                              size: 20,
                              color: TacticalTheme.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.verified_user_outlined,
                              size: 20,
                              color: TacticalTheme.textMuted,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Drag and drop or click here',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: TacticalTheme.textSecondary,
                          ),
                        ),
                        Text(
                          'to attach files',
                          style: TacticalTheme.monoStyle(
                            fontSize: 10,
                            color: TacticalTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_attachments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
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
                          Icon(
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
                            icon: Icon(
                              Icons.visibility,
                              size: 16,
                              color: TacticalTheme.cyanTactical,
                            ),
                            onPressed: () => _viewAttachment(att.name),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: Icon(
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
            key: const ValueKey('entry_button_save'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
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
            // Inspector Header Bar (`Enpass_RUtKiX9m54.png` + `Enpass_AnOaTZCopB.png`)
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: TacticalTheme.bgSurface,
                border: Border(
                  bottom: BorderSide(color: TacticalTheme.borderTech, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 15,
                    color: TacticalTheme.amberPrimary,
                  ),
                  const SizedBox(width: 6),
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
                  IconButton(
                    key: const ValueKey('entry_button_favorite'),
                    tooltip: _isFavorite
                        ? 'Remove from Favorites'
                        : 'Add to Favorites',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _isFavorite ? Icons.star : Icons.star_border,
                      size: 18,
                      color: _isFavorite
                          ? TacticalTheme.amberBright
                          : TacticalTheme.textMuted,
                    ),
                    onPressed: () =>
                        setState(() => _isFavorite = !_isFavorite),
                  ),
                  _buildAddDropdownButton(),
                  const SizedBox(width: 6),
                  InkWell(
                    key: const ValueKey('entry_header_save'),
                    onTap: _saving ? null : _save,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: TacticalTheme.amberPrimary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: TacticalTheme.bgDeepCarbon,
                        ),
                      ),
                    ),
                  ),
                  if (_isEdit)
                    IconButton(
                      key: const ValueKey('entry_button_delete'),
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
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
          IconButton(
            tooltip: _isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
            icon: Icon(
              _isFavorite ? Icons.star : Icons.star_border,
              color: _isFavorite
                  ? TacticalTheme.amberBright
                  : TacticalTheme.textMuted,
            ),
            onPressed: () => setState(() => _isFavorite = !_isFavorite),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: _buildAddDropdownButton(),
          ),
          if (_isEdit)
            IconButton(
              key: const ValueKey('entry_button_delete'),
              tooltip: 'Delete',
              icon: Icon(
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
