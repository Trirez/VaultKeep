import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../vault_controller.dart';
import 'enpass_settings_dialog.dart';
import 'file_picker_dialog.dart';

enum _OnboardingStep {
  welcomeUsage,
  selectLocation,
  containerSetup,
}

enum _ActivationModalStep {
  none,
  email,
  otp,
}

/// First-launch onboarding wizard (Personal/Business -> Email & 6-digit OTP Activation
/// -> Cloud/Local Storage Container Selection) and Vault Unlock/Create screen.
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
  final _pin = TextEditingController();
  final _emailCtrl = TextEditingController();
  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  late _OnboardingStep _step;
  _ActivationModalStep _modalStep = _ActivationModalStep.none;
  String? _selectedUsage;
  String? _modalError;

  bool _show = false;
  bool _showPin = false;
  bool _forceMasterPassword = false;
  String? _localError;
  bool? _isCreatingOverride;

  static const _minMasterLength = 12;

  bool get _creating =>
      _isCreatingOverride ?? !File(_path.text.trim()).existsSync();

  bool _isPinMode(VaultController c) =>
      !_creating && c.hasQuickPinConfigured && !_forceMasterPassword;

  @override
  void initState() {
    super.initState();
    final initialPath = widget.defaultPath.trim();
    final exists = initialPath.isNotEmpty && File(initialPath).existsSync();
    final c = widget.controller;
    if (exists || c.hasQuickPinConfigured || c.windowsHelloEnabled) {
      _step = _OnboardingStep.containerSetup;
      _selectedUsage = c.onboardingUsageType;
    } else if (c.onboardingActivatedEmail != null &&
        c.onboardingActivatedEmail!.isNotEmpty) {
      _step = _OnboardingStep.selectLocation;
      _selectedUsage = c.onboardingUsageType;
      _emailCtrl.text = c.onboardingActivatedEmail!;
    } else {
      _step = _OnboardingStep.welcomeUsage;
    }
  }

  @override
  void dispose() {
    _master.text = '';
    _confirm.text = '';
    _pin.text = '';
    _emailCtrl.text = '';
    for (final c in _otpCtrls) {
      c.text = '';
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _path.dispose();
    _master.dispose();
    _confirm.dispose();
    _pin.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _selectUsageMode(String usage) {
    setState(() {
      _selectedUsage = usage;
      _modalError = null;
      if (_emailCtrl.text.trim().isEmpty &&
          widget.controller.onboardingActivatedEmail != null) {
        _emailCtrl.text = widget.controller.onboardingActivatedEmail!;
      }
      _modalStep = _ActivationModalStep.email;
    });
  }

  void _submitEmailStep() {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _modalError = 'Please enter a valid email address to continue.';
      });
      return;
    }
    for (final c in _otpCtrls) {
      c.text = '';
    }
    setState(() {
      _modalError = null;
      _modalStep = _ActivationModalStep.otp;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _otpFocusNodes.isNotEmpty) {
        _otpFocusNodes.first.requestFocus();
      }
    });
  }

  void _submitOtpStep() {
    final code = _otpCtrls.map((c) => c.text.trim()).join();
    if (code.length < 6) {
      setState(() {
        _modalError = 'Please enter the 6-digit verification code.';
      });
      return;
    }
    widget.controller.completeOnboardingActivation(
      usageType: _selectedUsage ?? 'Personal',
      email: _emailCtrl.text.trim(),
    );
    setState(() {
      _modalError = null;
      _modalStep = _ActivationModalStep.none;
      _step = _OnboardingStep.selectLocation;
    });
  }

  String _suggestPathForProvider(String provider) {
    final current = _path.text.trim();
    final baseDir = current.isNotEmpty
        ? File(current).parent.path
        : Directory.current.path;
    final sep = Platform.pathSeparator;
    final slug = switch (provider) {
      'OneDrive' => 'OneDrive_vaultkeep.kdbx',
      'Google Drive' => 'GoogleDrive_vaultkeep.kdbx',
      'iCloud' => 'iCloud_vaultkeep.kdbx',
      'Dropbox' => 'Dropbox_vaultkeep.kdbx',
      'Box' => 'Box_vaultkeep.kdbx',
      'WebDAV' => 'WebDAV_vaultkeep.kdbx',
      _ => 'vaultkeep.kdbx',
    };
    if (provider == 'This Device') {
      return current.isNotEmpty ? current : '$baseDir$sep$slug';
    }
    return '$baseDir$sep$slug';
  }

  Future<void> _selectStorageProvider(String provider) async {
    widget.controller.updateSettings(connectedStorageProvider: provider);
    if (provider == 'This Device') {
      setState(() {
        _localError = null;
        _step = _OnboardingStep.containerSetup;
      });
      return;
    }
    setState(() {
      if (!File(_path.text.trim()).existsSync()) {
        _path.text = _suggestPathForProvider(provider);
      }
      _localError = null;
      _step = _OnboardingStep.containerSetup;
    });
  }

  void _showActivationDetailsDialog() {
    final c = widget.controller;
    final email = (c.onboardingActivatedEmail?.isNotEmpty ?? false)
        ? c.onboardingActivatedEmail!
        : (_emailCtrl.text.trim().isNotEmpty
            ? _emailCtrl.text.trim()
            : 'Offline Local Vault (Not Activated)');
    final usage = _selectedUsage ?? c.onboardingUsageType;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('onboarding_activation_details_dialog'),
        title: const Text('Activation Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plan Type: $usage'),
            const SizedBox(height: 8),
            Text('Registered Email: $email'),
            const SizedBox(height: 8),
            const Text(
              'Status: Active (Zero-Knowledge Client Encryption)',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _step = _OnboardingStep.welcomeUsage;
              });
            },
            child: const Text('Switch Plan / Email'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final path = _path.text.trim();
    final creating = _creating;
    final fileExists = File(path).existsSync();
    final pinMode = _isPinMode(widget.controller);

    if (pinMode) {
      final pinValue = _pin.text;
      if (path.isEmpty) {
        setState(() => _localError = 'Enter the vault file path.');
        return;
      }
      if (!fileExists) {
        setState(
          () => _localError =
              'Vault file does not exist at this path. Check path or switch to Create.',
        );
        return;
      }
      if (pinValue.isEmpty) {
        setState(
          () => _localError =
              'Enter your Quick Unlock PIN (numbers or characters).',
        );
        return;
      }
      setState(() => _localError = null);
      final ok = await widget.controller.unlockWithPin(path, pinValue);
      if (mounted) {
        _pin.clear();
        if (!ok && !widget.controller.hasQuickPinConfigured) {
          setState(() => _forceMasterPassword = true);
        }
      }
      return;
    }

    final master = _master.text;

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
    if (path.isEmpty || !File(path).existsSync()) {
      setState(() => _localError = 'Vault file does not exist at this path.');
      return;
    }
    setState(() => _localError = null);
    await widget.controller.unlockWithWindowsHello(path);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return Scaffold(
          backgroundColor: TacticalTheme.onboardingHeroBlue,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 600 || constraints.maxHeight < 460;

                return Stack(
                  children: [
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 8 : 20),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 580,
                            maxHeight: 740,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              color: TacticalTheme.onboardingRightPanelBg,
                              child: _buildRightPaneContent(c, compact: compact),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Modal Overlay for Step 2: Activate (Email & 6-Digit Code)
                    if (_modalStep != _ActivationModalStep.none)
                      Positioned.fill(
                        child: Container(
                          color: TacticalTheme.shadowColor,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(16),
                          child: _buildActivationModalCard(),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildRightPaneContent(VaultController c, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 18 : 42,
              vertical: compact ? 14 : 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!compact && _step != _OnboardingStep.containerSetup) ...[
                      const Center(child: _WelcomeCredentialsIllustration()),
                      const SizedBox(height: 18),
                    ],
                    // Heading: "Welcome to VaultKeep" (keeps Text('VaultKeep') as a standalone node)
                    const Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Welcome to ',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: TacticalTheme.onboardingTextDark,
                          ),
                        ),
                        Text(
                          'VaultKeep',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: TacticalTheme.onboardingTextDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Keep your passwords, passkeys, logins, bank accounts, credit cards, identities, files and other important credentials safe and handy in one place.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: TacticalTheme.onboardingTextDark,
                      ),
                    ),
                    const SizedBox(height: 16),
                    switch (_step) {
                      _OnboardingStep.welcomeUsage => _buildWelcomeUsageStep(),
                      _OnboardingStep.selectLocation =>
                        _buildSelectLocationStep(),
                      _OnboardingStep.containerSetup =>
                        _buildContainerSetupStep(c),
                    },
                  ],
                ),
              ),
            ),
          ),
        ),
        // Bottom Footer Bar (View Activation Details + Settings Gear Icon)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: TacticalTheme.onboardingCardWhite,
            border: Border(
              top: BorderSide(
                color: TacticalTheme.onboardingCardBorder,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              if (_step != _OnboardingStep.welcomeUsage)
                TextButton.icon(
                  key: const ValueKey('onboarding_button_back'),
                  onPressed: () {
                    setState(() {
                      _localError = null;
                      if (_step == _OnboardingStep.containerSetup) {
                        _step = _OnboardingStep.selectLocation;
                      } else {
                        _step = _OnboardingStep.welcomeUsage;
                      }
                    });
                  },
                  icon: const Icon(
                    Icons.arrow_back,
                    size: 15,
                    color: TacticalTheme.onboardingSelectedBlue,
                  ),
                  label: Text(
                    _step == _OnboardingStep.containerSetup
                        ? 'Change Location'
                        : 'Back',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: TacticalTheme.onboardingSelectedBlue,
                    ),
                  ),
                )
              else
                const SizedBox(width: 48),
              Expanded(
                child: Center(
                  child: _step == _OnboardingStep.selectLocation
                      ? InkWell(
                          key: const ValueKey(
                            'onboarding_button_activation_details',
                          ),
                          borderRadius: BorderRadius.circular(4),
                          onTap: _showActivationDetailsDialog,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              'View Activation Details',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: TacticalTheme.onboardingTextDark,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              IconButton(
                key: const ValueKey('onboarding_button_settings'),
                tooltip: 'Settings',
                icon: const Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: TacticalTheme.onboardingTextDark,
                ),
                onPressed: () => EnpassSettingsDialog.show(
                  context,
                  controller: c,
                  onChangeMasterPassword: () {},
                  onSyncVault: () {},
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeUsageStep() {
    final personalSelected = _selectedUsage == 'Personal';
    final businessSelected = _selectedUsage == 'Business';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Choose how you'll use VaultKeep",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: TacticalTheme.onboardingTextDark,
          ),
        ),
        const SizedBox(height: 14),
        _UsageModeCard(
          cardKey: const ValueKey('onboarding_card_personal'),
          title: 'Personal',
          subtitle: 'For personal use',
          icon: Icons.person,
          iconBg: TacticalTheme.onboardingPersonalBg,
          iconFg: TacticalTheme.onboardingPersonalFg,
          selected: personalSelected,
          onTap: () => _selectUsageMode('Personal'),
        ),
        const SizedBox(height: 14),
        _UsageModeCard(
          cardKey: const ValueKey('onboarding_card_business'),
          title: 'Business',
          subtitle: 'For use at work',
          icon: Icons.business_rounded,
          iconBg: TacticalTheme.onboardingBusinessBg,
          iconFg: TacticalTheme.onboardingBusinessFg,
          selected: businessSelected,
          onTap: () => _selectUsageMode('Business'),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton.icon(
              key: const ValueKey('onboarding_button_choose_location_direct'),
              onPressed: () {
                setState(() {
                  _selectedUsage ??= 'Personal';
                  _step = _OnboardingStep.selectLocation;
                });
              },
              icon: const Icon(
                Icons.cloud_outlined,
                size: 16,
                color: TacticalTheme.onboardingSelectedBlue,
              ),
              label: const Text(
                'Choose Storage Location',
                style: TextStyle(
                  fontSize: 12,
                  color: TacticalTheme.onboardingSelectedBlue,
                ),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('onboarding_button_direct_vault'),
              onPressed: () {
                setState(() {
                  _selectedUsage ??= 'Personal';
                  _step = _OnboardingStep.containerSetup;
                });
              },
              icon: const Icon(
                Icons.folder_open_outlined,
                size: 16,
                color: TacticalTheme.onboardingSelectedBlue,
              ),
              label: const Text(
                'Local .kdbx Container',
                style: TextStyle(
                  fontSize: 12,
                  color: TacticalTheme.onboardingSelectedBlue,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectLocationStep() {
    const locations = <({
      String keyName,
      String label,
      Widget icon,
    })>[
      (
        keyName: 'onedrive',
        label: 'OneDrive',
        icon: Icon(
          Icons.cloud,
          size: 20,
          color: TacticalTheme.providerOneDrive,
        ),
      ),
      (
        keyName: 'googledrive',
        label: 'Google Drive',
        icon: Icon(
          Icons.add_to_drive,
          size: 20,
          color: TacticalTheme.providerGoogleGreen,
        ),
      ),
      (
        keyName: 'icloud',
        label: 'iCloud',
        icon: Icon(
          Icons.cloud_queue_rounded,
          size: 20,
          color: TacticalTheme.providerICloud,
        ),
      ),
      (
        keyName: 'dropbox',
        label: 'Dropbox',
        icon: Icon(
          Icons.widgets_rounded,
          size: 20,
          color: TacticalTheme.providerDropbox,
        ),
      ),
      (
        keyName: 'box',
        label: 'Box',
        icon: _BoxWordmarkIcon(),
      ),
      (
        keyName: 'webdav',
        label: 'WebDAV',
        icon: Icon(
          Icons.dns_outlined,
          size: 20,
          color: TacticalTheme.onboardingSelectedBlue,
        ),
      ),
      (
        keyName: 'wifisync',
        label: 'Wi-Fi Sync',
        icon: Icon(
          Icons.wifi_tethering,
          size: 20,
          color: TacticalTheme.onboardingSelectedBlue,
        ),
      ),
      (
        keyName: 'local',
        label: 'This Device',
        icon: Icon(
          Icons.computer_rounded,
          size: 20,
          color: TacticalTheme.onboardingSelectedBlue,
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Select where you already have or want to keep your data:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: TacticalTheme.onboardingTextDark,
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < locations.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _StorageLocationTile(
            tileKey: ValueKey('onboarding_location_${locations[i].keyName}'),
            label: locations[i].label,
            leading: locations[i].icon,
            onTap: () => _selectStorageProvider(locations[i].label),
          ),
        ],
      ],
    );
  }

  Widget _buildContainerSetupStep(VaultController c) {
    final creating = _creating;
    final pinMode = _isPinMode(c);
    final message = _localError ?? c.error;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TacticalTheme.onboardingCardWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: TacticalTheme.onboardingCardBorder,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Selected Storage Provider Header
          Row(
            children: [
              const Icon(
                Icons.cloud_done_outlined,
                size: 18,
                color: TacticalTheme.onboardingSelectedBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Container Location: ${c.connectedStorageProvider}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: TacticalTheme.onboardingTextDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                key: const ValueKey('onboarding_button_change_location'),
                onPressed: () {
                  setState(() {
                    _localError = null;
                    _step = _OnboardingStep.selectLocation;
                  });
                },
                child: const Text(
                  'Change Location',
                  style: TextStyle(
                    fontSize: 12,
                    color: TacticalTheme.onboardingSelectedBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Mode Switcher (Unlock vs Create)
          SegmentedButton<bool>(
            style: SegmentedButton.styleFrom(
              backgroundColor: TacticalTheme.onboardingRightPanelBg,
              selectedBackgroundColor: TacticalTheme.onboardingButtonBlue,
              selectedForegroundColor: TacticalTheme.onboardingCardWhite,
              foregroundColor: TacticalTheme.onboardingTextDark,
              side: const BorderSide(
                color: TacticalTheme.onboardingCardBorder,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
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
          const SizedBox(height: 14),

          // Vault Path Input
          TextField(
            key: const ValueKey('unlock_field_path'),
            controller: _path,
            style: TacticalTheme.monoStyle(
              fontSize: 12,
              color: TacticalTheme.onboardingTextDark,
            ),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              filled: true,
              fillColor: TacticalTheme.onboardingCardWhite,
              labelText: 'Vault file (.kdbx)',
              labelStyle: const TextStyle(
                color: TacticalTheme.onboardingTextMuted,
              ),
              helperText:
                  'Tip: a path inside a Drive/OneDrive folder syncs the vault.',
              helperStyle: const TextStyle(
                color: TacticalTheme.onboardingTextMuted,
              ),
              helperMaxLines: 2,
              suffixIcon: IconButton(
                tooltip: 'Browse files or cloud folders',
                icon: const Icon(
                  Icons.folder_open,
                  color: TacticalTheme.onboardingSelectedBlue,
                  size: 20,
                ),
                onPressed: _pickVaultPath,
              ),
            ),
          ),
          const SizedBox(height: 14),

          if (pinMode) ...[
            TextField(
              key: const ValueKey('unlock_field_pin'),
              controller: _pin,
              autofocus: true,
              obscureText: !_showPin,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              style: TacticalTheme.monoStyle(
                fontSize: 13,
                color: TacticalTheme.onboardingTextDark,
              ),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                filled: true,
                fillColor: TacticalTheme.onboardingCardWhite,
                labelText: 'Quick Unlock PIN (numbers or characters)',
                labelStyle: const TextStyle(
                  color: TacticalTheme.onboardingTextMuted,
                ),
                prefixIcon: const Icon(
                  Icons.pin_outlined,
                  size: 18,
                  color: TacticalTheme.onboardingSelectedBlue,
                ),
                suffixIcon: IconButton(
                  tooltip: _showPin ? 'Hide PIN' : 'Show PIN',
                  icon: Icon(
                    _showPin ? Icons.visibility_off : Icons.visibility,
                    size: 19,
                    color: TacticalTheme.onboardingTextMuted,
                  ),
                  onPressed: () => setState(() => _showPin = !_showPin),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('unlock_button_use_master'),
                icon: const Icon(Icons.password, size: 15),
                label: const Text('Use Master Password Instead'),
                onPressed: () => setState(() {
                  _forceMasterPassword = true;
                  _localError = null;
                }),
              ),
            ),
          ] else ...[
            TextField(
              key: const ValueKey('unlock_field_master'),
              controller: _master,
              obscureText: !_show,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              style: TacticalTheme.monoStyle(
                fontSize: 13,
                color: TacticalTheme.onboardingTextDark,
              ),
              onChanged: (_) {
                if (creating) setState(() {});
              },
              onSubmitted: (_) => creating ? null : _submit(),
              decoration: InputDecoration(
                filled: true,
                fillColor: TacticalTheme.onboardingCardWhite,
                labelText: 'Master password',
                labelStyle: const TextStyle(
                  color: TacticalTheme.onboardingTextMuted,
                ),
                suffixIcon: IconButton(
                  tooltip: _show ? 'Hide' : 'Show',
                  icon: Icon(
                    _show ? Icons.visibility_off : Icons.visibility,
                    size: 19,
                    color: TacticalTheme.onboardingTextMuted,
                  ),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
            if (!creating &&
                c.hasQuickPinConfigured &&
                _forceMasterPassword) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('unlock_button_use_pin'),
                  icon: const Icon(Icons.pin_outlined, size: 15),
                  label: const Text('Use Quick Unlock PIN'),
                  onPressed: () => setState(() {
                    _forceMasterPassword = false;
                    _localError = null;
                  }),
                ),
              ),
            ],
          ],

          if (creating) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'KEY ENTROPY (MIN 12 CHARS)',
                    style: TacticalTheme.monoStyle(
                      fontSize: 10,
                      color: TacticalTheme.onboardingTextMuted,
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
                    color: _master.text.length >= _minMasterLength
                        ? TacticalTheme.emeraldReady
                        : TacticalTheme.onboardingSelectedBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SegmentedAmberBar(
              fraction: (_master.text.length / 16).clamp(0.0, 1.0),
              segments: 12,
              height: 6,
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('unlock_field_confirm'),
              controller: _confirm,
              obscureText: !_show,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              style: TacticalTheme.monoStyle(
                fontSize: 13,
                color: TacticalTheme.onboardingTextDark,
              ),
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                filled: true,
                fillColor: TacticalTheme.onboardingCardWhite,
                labelText: 'Repeat master password',
                labelStyle: TextStyle(
                  color: TacticalTheme.onboardingTextMuted,
                ),
              ),
            ),
          ],

          if (message != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TacticalTheme.crimsonDim,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: TacticalTheme.crimsonDanger,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: TacticalTheme.crimsonDanger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: TacticalTheme.monoStyle(
                        fontSize: 11,
                        color: TacticalTheme.crimsonDanger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          SizedBox(
            height: 40,
            child: FilledButton(
              key: const ValueKey('unlock_button_submit'),
              style: FilledButton.styleFrom(
                backgroundColor: TacticalTheme.onboardingButtonBlue,
                foregroundColor: TacticalTheme.onboardingCardWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              onPressed: c.busy ? null : _submit,
              child: c.busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: TacticalTheme.onboardingCardWhite,
                      ),
                    )
                  : Text(
                      creating
                          ? 'Create vault'
                          : pinMode
                              ? 'Unlock with PIN'
                              : 'Unlock',
                    ),
            ),
          ),

          if (!creating && c.windowsHelloEnabled) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('unlock_button_biometric'),
              style: OutlinedButton.styleFrom(
                foregroundColor: TacticalTheme.onboardingSelectedBlue,
                side: const BorderSide(
                  color: TacticalTheme.onboardingSelectedBlue,
                ),
              ),
              icon: const Icon(
                Icons.fingerprint,
                size: 18,
                color: TacticalTheme.onboardingSelectedBlue,
              ),
              label: const Text('Unlock with Windows Hello'),
              onPressed: c.busy ? null : _authenticateBiometric,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivationModalCard() {
    final isOtp = _modalStep == _ActivationModalStep.otp;
    final usageLabel = (_selectedUsage ?? 'Personal').toLowerCase();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Material(
        color: TacticalTheme.onboardingCardWhite,
        elevation: 16,
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top-right close 'X' button
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  key: const ValueKey('onboarding_activate_close'),
                  tooltip: 'Close activation modal',
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                    color: TacticalTheme.onboardingTextDark,
                  ),
                  onPressed: () {
                    setState(() {
                      _modalError = null;
                      _modalStep = _ActivationModalStep.none;
                    });
                  },
                ),
              ),

              // Modal Top Illustration (Email funnel vs Envelope OTP)
              Center(
                child: isOtp
                    ? const _ActivateEnvelopeIllustration()
                    : const _ActivateEmailIllustration(),
              ),
              const SizedBox(height: 16),

              const Text(
                'Activate Enpass',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: TacticalTheme.onboardingTextDark,
                ),
              ),
              const SizedBox(height: 8),

              if (!isOtp) ...[
                Text(
                  'Enter your $usageLabel email address to continue.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: TacticalTheme.onboardingTextMuted,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Email',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: TacticalTheme.onboardingTextDark,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const ValueKey('onboarding_input_email'),
                  controller: _emailCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: TacticalTheme.onboardingTextDark,
                  ),
                  onSubmitted: (_) => _submitEmailStep(),
                  decoration: InputDecoration(
                    hintText: 'Enter your email',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: TacticalTheme.onboardingTextMuted,
                    ),
                    filled: true,
                    fillColor: TacticalTheme.onboardingCardWhite,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(
                        color: TacticalTheme.onboardingCardBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(
                        color: TacticalTheme.onboardingSelectedBlue,
                        width: 1.8,
                      ),
                    ),
                  ),
                ),
                if (_modalError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _modalError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: TacticalTheme.crimsonDanger,
                    ),
                  ),
                ],
                const SizedBox(height: 36),
                RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 11.5,
                      color: TacticalTheme.onboardingTextMuted,
                    ),
                    children: [
                      TextSpan(text: 'By continuing you agree to Enpass '),
                      TextSpan(
                        text: 'Terms of Use.',
                        style: TextStyle(
                          color: TacticalTheme.onboardingSelectedBlue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 38,
                  child: FilledButton(
                    key: const ValueKey('onboarding_button_email_continue'),
                    style: FilledButton.styleFrom(
                      backgroundColor: TacticalTheme.onboardingButtonBlue,
                      foregroundColor: TacticalTheme.onboardingCardWhite,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    onPressed: _submitEmailStep,
                    child: const Text('Continue'),
                  ),
                ),
              ] else ...[
                const Text(
                  'Enter the 6-digit code sent to you at',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: TacticalTheme.onboardingTextMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _emailCtrl.text.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: TacticalTheme.onboardingTextDark,
                  ),
                ),
                const SizedBox(height: 22),

                // 6-digit verification boxes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 48,
                      height: 48,
                      child: TextField(
                        key: ValueKey('onboarding_otp_box_$index'),
                        controller: _otpCtrls[index],
                        focusNode: _otpFocusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9A-Za-z]'),
                          ),
                        ],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: TacticalTheme.onboardingTextDark,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: TacticalTheme.onboardingCardWhite,
                          contentPadding: EdgeInsets.zero,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: TacticalTheme.onboardingCardBorder,
                              width: 1.2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: TacticalTheme.onboardingSelectedBlue,
                              width: 1.8,
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.isNotEmpty && index < 5) {
                            _otpFocusNodes[index + 1].requestFocus();
                          } else if (val.isEmpty && index > 0) {
                            _otpFocusNodes[index - 1].requestFocus();
                          }
                        },
                        onSubmitted: (_) => _submitOtpStep(),
                      ),
                    );
                  }),
                ),
                if (_modalError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _modalError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: TacticalTheme.crimsonDanger,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      key: const ValueKey('onboarding_button_resend'),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Verification code resent to ${_emailCtrl.text.trim()}',
                            ),
                          ),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Resend',
                          style: TextStyle(
                            fontSize: 12,
                            color: TacticalTheme.onboardingTextMuted,
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      key: const ValueKey('onboarding_button_change_email'),
                      onTap: () {
                        setState(() {
                          _modalError = null;
                          _modalStep = _ActivationModalStep.email;
                        });
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Change Email',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: TacticalTheme.onboardingSelectedBlue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 38,
                  child: FilledButton(
                    key: const ValueKey('onboarding_button_otp_continue'),
                    style: FilledButton.styleFrom(
                      backgroundColor: TacticalTheme.onboardingButtonBlue,
                      foregroundColor: TacticalTheme.onboardingCardWhite,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    onPressed: _submitOtpStep,
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// White rounded trapezoid emblem with a keyhole cutout in the center.
class _KeyholeShieldEmblem extends StatelessWidget {
  const _KeyholeShieldEmblem({
    required this.size,
    this.shieldColor = TacticalTheme.onboardingCardWhite,
    this.keyholeColor = TacticalTheme.onboardingHeroBlue,
  });

  final double size;
  final Color shieldColor;
  final Color keyholeColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _KeyholeShieldPainter(
        shieldColor: shieldColor,
        keyholeColor: keyholeColor,
      ),
    );
  }
}

class _KeyholeShieldPainter extends CustomPainter {
  const _KeyholeShieldPainter({
    required this.shieldColor,
    required this.keyholeColor,
  });

  final Color shieldColor;
  final Color keyholeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final shieldPaint = Paint()
      ..color = shieldColor
      ..style = PaintingStyle.fill;

    // Rounded tapered bucket/shield shape matching the screenshot logo
    final path = Path()
      ..moveTo(w * 0.16, h * 0.14)
      ..lineTo(w * 0.84, h * 0.14)
      ..quadraticBezierTo(w * 0.96, h * 0.14, w * 0.94, h * 0.28)
      ..lineTo(w * 0.85, h * 0.78)
      ..quadraticBezierTo(w * 0.82, h * 0.90, w * 0.68, h * 0.90)
      ..lineTo(w * 0.32, h * 0.90)
      ..quadraticBezierTo(w * 0.18, h * 0.90, w * 0.15, h * 0.78)
      ..lineTo(w * 0.06, h * 0.28)
      ..quadraticBezierTo(w * 0.04, h * 0.14, w * 0.16, h * 0.14)
      ..close();

    canvas.drawPath(path, shieldPaint);

    // Keyhole circle + lower slot
    final keyholePaint = Paint()
      ..color = keyholeColor
      ..style = PaintingStyle.fill;

    final center = Offset(w * 0.5, h * 0.43);
    canvas.drawCircle(center, w * 0.14, keyholePaint);

    final slotRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.62),
        width: w * 0.15,
        height: h * 0.30,
      ),
      Radius.circular(w * 0.03),
    );
    canvas.drawRRect(slotRect, keyholePaint);
  }

  @override
  bool shouldRepaint(covariant _KeyholeShieldPainter oldDelegate) =>
      oldDelegate.shieldColor != shieldColor ||
      oldDelegate.keyholeColor != keyholeColor;
}

/// Top hero illustration on the right pane (Safe + Smartphone + Shield + Padlock + Key + Card + Folder).
class _WelcomeCredentialsIllustration extends StatelessWidget {
  const _WelcomeCredentialsIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 150,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Baseline
          Positioned(
            left: 16,
            right: 16,
            bottom: 8,
            child: Container(
              height: 2.5,
              color: TacticalTheme.onboardingTextDark,
            ),
          ),
          // Teal Safe Box on Left
          Positioned(
            left: 34,
            bottom: 10,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: TacticalTheme.onboardingSafeTeal,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: TacticalTheme.onboardingSafeDark,
                    width: 3,
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.hub_outlined,
                  size: 16,
                  color: TacticalTheme.onboardingSafeDark,
                ),
              ),
            ),
          ),
          // Smartphone in Center
          Positioned(
            left: 118,
            bottom: 10,
            child: Container(
              width: 56,
              height: 92,
              decoration: BoxDecoration(
                color: TacticalTheme.onboardingCardWhite,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                border: Border.all(
                  color: TacticalTheme.onboardingTextMuted,
                  width: 3,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  const Icon(
                    Icons.lock_rounded,
                    size: 15,
                    color: TacticalTheme.onboardingSafeDark,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: TacticalTheme.onboardingCardBorder,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '••••••',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1,
                        color: TacticalTheme.onboardingTextMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Pink Shield Speech Bubble overlapping Smartphone
          Positioned(
            left: 142,
            top: 26,
            child: Container(
              width: 68,
              height: 50,
              decoration: BoxDecoration(
                color: TacticalTheme.onboardingBubblePink,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 26,
                height: 30,
                decoration: BoxDecoration(
                  color: TacticalTheme.onboardingShieldGold,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.check,
                  size: 16,
                  color: TacticalTheme.onboardingBubblePink,
                ),
              ),
            ),
          ),
          // Top-Right Padlock
          Positioned(
            right: 54,
            top: 4,
            child: Container(
              width: 38,
              height: 44,
              decoration: BoxDecoration(
                color: TacticalTheme.onboardingCardBorder,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 22,
                color: TacticalTheme.onboardingTextDark,
              ),
            ),
          ),
          // Green Key Circle Badge
          Positioned(
            right: 18,
            top: 44,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: TacticalTheme.onboardingKeyGreen,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.vpn_key_rounded,
                size: 18,
                color: TacticalTheme.onboardingSafeDark,
              ),
            ),
          ),
          // Credit Card at Bottom Center-Right
          Positioned(
            left: 184,
            bottom: 10,
            child: Container(
              width: 42,
              height: 28,
              decoration: BoxDecoration(
                color: TacticalTheme.onboardingCardIndigo,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: TacticalTheme.crimsonDanger,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: TacticalTheme.onboardingFolderYellow,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Yellow Folder at Bottom Right
          const Positioned(
            right: 42,
            bottom: 10,
            child: Icon(
              Icons.folder_rounded,
              size: 46,
              color: TacticalTheme.onboardingFolderYellow,
            ),
          ),
        ],
      ),
    );
  }
}

/// Illustration for Activate Email Modal (Floating App Tiles -> Keyhole Emblem).
class _ActivateEmailIllustration extends StatelessWidget {
  const _ActivateEmailIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 175,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Floating App Credential Tiles
          const Positioned(
            left: 34,
            top: 10,
            child: _FloatingAppTile(
              bg: TacticalTheme.providerDropbox,
              fg: TacticalTheme.onboardingCardWhite,
              icon: Icons.widgets_rounded,
            ),
          ),
          const Positioned(
            left: 74,
            top: 22,
            child: _FloatingAppTile(
              bg: TacticalTheme.onboardingTextDark,
              fg: TacticalTheme.onboardingFolderYellow,
              icon: Icons.grid_view_rounded,
            ),
          ),
          const Positioned(
            top: 4,
            left: 112,
            child: _FloatingAppTile(
              bg: TacticalTheme.onboardingShieldGold,
              fg: TacticalTheme.onboardingTextDark,
              icon: Icons.description_outlined,
            ),
          ),
          const Positioned(
            right: 62,
            top: 18,
            child: _FloatingAppTile(
              bg: TacticalTheme.onboardingCardWhite,
              fg: TacticalTheme.providerGoogleBlue,
              icon: Icons.g_mobiledata_rounded,
            ),
          ),
          const Positioned(
            right: 26,
            top: 32,
            child: _FloatingAppTile(
              bg: TacticalTheme.onboardingCardWhite,
              fg: TacticalTheme.onboardingHeroBlue,
              icon: Icons.payment_rounded,
            ),
          ),
          Positioned(
            left: 38,
            top: 56,
            child: _FloatingAppTile(
              bg: TacticalTheme.crimsonDim,
              fg: TacticalTheme.crimsonDanger,
              icon: Icons.credit_card_rounded,
            ),
          ),
          const Positioned(
            left: 98,
            top: 48,
            child: _FloatingAppTile(
              bg: TacticalTheme.providerOneDrive,
              fg: TacticalTheme.onboardingCardWhite,
              icon: Icons.facebook_rounded,
            ),
          ),
          const Positioned(
            right: 44,
            top: 60,
            child: _FloatingAppTile(
              bg: TacticalTheme.onboardingPersonalBg,
              fg: TacticalTheme.onboardingPersonalFg,
              icon: Icons.badge_outlined,
            ),
          ),
          // Bottom Keyhole Funnel Emblem
          const Positioned(
            bottom: 4,
            child: _KeyholeShieldEmblem(
              size: 86,
              shieldColor: TacticalTheme.onboardingButtonBlue,
              keyholeColor: TacticalTheme.onboardingCardWhite,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingAppTile extends StatelessWidget {
  const _FloatingAppTile({
    required this.bg,
    required this.fg,
    required this.icon,
  });

  final Color bg;
  final Color fg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: TacticalTheme.onboardingCardBorder,
          width: 0.8,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 17, color: fg),
    );
  }
}

/// Illustration for Activate 6-Digit OTP Modal (Open Envelope with Keyhole Card).
class _ActivateEnvelopeIllustration extends StatelessWidget {
  const _ActivateEnvelopeIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 145,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Envelope Back Flap
          Container(
            width: 120,
            height: 92,
            decoration: BoxDecoration(
              color: TacticalTheme.onboardingEnvelopeBack,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          // Rising Blue Keyhole Card Inside Envelope
          Positioned(
            bottom: 34,
            child: Container(
              width: 92,
              height: 76,
              decoration: BoxDecoration(
                color: TacticalTheme.onboardingEnvelopeCard,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const _KeyholeShieldEmblem(
                size: 36,
                shieldColor: TacticalTheme.onboardingHeroBlue,
                keyholeColor: TacticalTheme.onboardingEnvelopeCard,
              ),
            ),
          ),
          // Envelope Front Pocket
          Container(
            width: 120,
            height: 54,
            decoration: const BoxDecoration(
              color: TacticalTheme.onboardingEnvelopeFront,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Personal / Business selectable card on Step 1.
class _UsageModeCard extends StatelessWidget {
  const _UsageModeCard({
    required this.cardKey,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.selected,
    required this.onTap,
  });

  final Key cardKey;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TacticalTheme.onboardingCardWhite,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        key: cardKey,
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? TacticalTheme.onboardingSelectedBlue
                  : TacticalTheme.onboardingCardBorder,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: iconFg),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: TacticalTheme.onboardingTextDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: TacticalTheme.onboardingTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check,
                  size: 18,
                  color: TacticalTheme.onboardingSelectedBlue,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cloud / Local Storage Location Card on Step 3 ("Select where you already have or want to keep your data:").
class _StorageLocationTile extends StatelessWidget {
  const _StorageLocationTile({
    required this.tileKey,
    required this.label,
    required this.leading,
    required this.onTap,
  });

  final Key tileKey;
  final String label;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TacticalTheme.onboardingCardWhite,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        key: tileKey,
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: TacticalTheme.onboardingCardBorder,
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Center(child: leading),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: TacticalTheme.onboardingTextDark,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: TacticalTheme.onboardingTextDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoxWordmarkIcon extends StatelessWidget {
  const _BoxWordmarkIcon();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'box',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: TacticalTheme.providerBox,
        letterSpacing: -0.5,
      ),
    );
  }
}
