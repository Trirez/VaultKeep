import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkeep/backend.dart';
import 'package:vaultkeep/screens/entry_screen.dart';
import 'package:vaultkeep/screens/file_picker_dialog.dart';
import 'package:vaultkeep/screens/unlock_screen.dart';
import 'package:vaultkeep/screens/vault_screen.dart';
import 'package:vaultkeep/theme.dart';
import 'package:vaultkeep/vault_controller.dart';

import 'vault_controller_test.dart';

void main() {
  late FakeBackend backend;
  late VaultController controller;

  setUp(() {
    backend = FakeBackend();
    controller = VaultController(backend);
  });

  testWidgets('UnlockScreen renders without overflow on 360x640 and 1920x1080', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(
      MaterialApp(
        home: UnlockScreen(
          controller: controller,
          defaultPath: 'test.kdbx',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('VaultKeep'), findsOneWidget);

    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pumpAndSettle();
    expect(find.text('VaultKeep'), findsOneWidget);
    await controller.lock();
  });

  testWidgets('VaultScreen renders without overflow on 360x640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await backend.unlock('path', 'correct-horse-battery');
    controller.status = VaultStatus.unlocked;
    await controller.createGroup('Engineering');
    await controller.save(
      null,
      const EntryDraft(
        title: 'Very Long Title For A Website Account That Might Exceed Bounds',
        username: 'very_long_username_that_could_potentially_cause_issues@subdomain.example.com',
        password: 'password123',
        url: 'https://very-long-subdomain-name-with-many-words.example.com/login/auth/session',
        notes: 'Some notes here',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VaultScreen(controller: controller),
      ),
    );
    await tester.pump();
    expect(find.text('VaultKeep'), findsOneWidget);

    // Verify 1920x1080 desktop 3-pane Command-Center layout
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pumpAndSettle();
    expect(find.text('Group Tree'), findsOneWidget);
    expect(find.text('Cryptographic Entry Inspector'), findsOneWidget);

    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sync Vault Dialog renders without overflow on 360x640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await backend.unlock('path', 'correct-horse-battery');
    controller.status = VaultStatus.unlocked;

    await tester.pumpWidget(
      MaterialApp(
        home: VaultScreen(controller: controller),
      ),
    );
    await tester.pump();

    // Tap sync button
    await tester.tap(find.byTooltip('Sync Vault (3-Way Merge)'));
    await tester.pumpAndSettle();

    expect(find.text('Sync Vault (3-Way Merge)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Autofill Modal renders without overflow on 360x640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await backend.unlock('path', 'correct-horse-battery');
    controller.status = VaultStatus.unlocked;

    await tester.pumpWidget(
      MaterialApp(
        home: VaultScreen(controller: controller),
      ),
    );
    await tester.pump();

    // Tap autofill query button
    await tester.tap(find.byTooltip('Autofill Query'));
    await tester.pumpAndSettle();

    expect(find.text('Autofill Domain Query'), findsOneWidget);

    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('EntryScreen with TOTP renders without overflow on 360x640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await backend.unlock('path', 'correct-horse-battery');
    controller.status = VaultStatus.unlocked;
    final id = await controller.save(
      null,
      const EntryDraft(
        title: 'GitHub',
        username: 'octocat',
        password: 'secretpassword',
        url: 'https://github.com',
        notes: 'Notes',
        otp: 'otpauth://totp/GitHub:octocat?secret=JBSWY3DPEHPK3PXP&period=30',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EntryScreen(controller: controller, entryId: id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit entry'), findsOneWidget);
    expect(find.text('One-Time Password (TOTP)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await controller.lock();
  });

  testWidgets('FilePickerDialog renders without overflow on 360x640', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FilePickerDialog(initialPath: '', selectFolder: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose Vault File'), findsOneWidget);

    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Passkeys category and Passkey generation render without overflow', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await backend.unlock('path', 'correct-horse-battery');
    controller.status = VaultStatus.unlocked;
    final id = await controller.save(
      null,
      const EntryDraft(
        title: 'GitHub',
        username: 'octocat',
        password: 'secretpassword',
        url: 'https://github.com',
        notes: 'Notes',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VaultScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Passkeys and Passkey Supported sidebar items exist
    expect(find.text('Passkeys'), findsOneWidget);
    expect(find.text('Passkey Supported'), findsOneWidget);
    expect(find.text('Passkey (FIDO2 / WebAuthn)'), findsOneWidget);
    expect(find.text('PASSKEY SUPPORTED'), findsOneWidget);

    // Generate Passkey for GitHub
    await controller.generatePasskey(id, rpId: 'github.com', username: 'octocat');
    await tester.pumpAndSettle();

    // Tap Passkeys category in sidebar
    await tester.tap(find.text('Passkeys'));
    await tester.pumpAndSettle();
    expect(find.text('GitHub'), findsWidgets);

    // Check mobile 360x640 layout with bound Passkey
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();

    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('TacticalColorPassword renders character classes and screen-reader semantics', (tester) async {
    final description = TacticalColorPassword.describeForAccessibility('Ab9!');
    expect(description, 'uppercase A, lowercase b, digit 9, symbol !');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TacticalColorPassword(password: 'Ab9!'),
        ),
      ),
    );
    expect(find.byType(TacticalColorPassword), findsOneWidget);
  });

  testWidgets('Mobile 2FA (TOTP) filter chip, quick-copy TOTP, and Rotate Master Password dialog render cleanly', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await backend.unlock('path', 'correct-horse-battery');
    controller.status = VaultStatus.unlocked;
    final id = await controller.save(
      null,
      const EntryDraft(
        title: 'Cloudflare',
        username: 'ops@example.com',
        password: 'pw!9',
        url: 'https://cloudflare.com',
        notes: '',
        otp: 'otpauth://totp/Cloudflare:ops?secret=JBSWY3DPEHPK3PXP',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VaultScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('vault_filter_totp')), findsOneWidget);
    expect(find.byKey(ValueKey('vault_copy_totp_$id')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('vault_button_rotate_password')));
    await tester.pumpAndSettle();
    expect(find.text('Rotate Master Password'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Enpass 1:1 Home Security Score Dashboard, 8-Tab Settings, and Password Generator render cleanly', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await backend.unlock('path', 'correct-horse-battery');
    controller.status = VaultStatus.unlocked;
    await controller.save(
      null,
      const EntryDraft(
        title: 'Accenture Candidate',
        username: 'kingshuk',
        password: 'VeryStrongUniquePassword!2026',
        url: 'https://candidate.accenture.com',
        notes: '',
        category: 'Login',
        tags: ['Logins'],
        isFavorite: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VaultScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Open Home Security Score Dashboard via Sidebar
    await tester.tap(find.byKey(const ValueKey('sidebar_home')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('enpass_home_dashboard')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_security_score_value')), findsOneWidget);
    expect(find.byKey(const ValueKey('audit_card_excellent')), findsOneWidget);
    expect(find.byKey(const ValueKey('audit_card_compromised')), findsOneWidget);

    // Open 'What does this score mean?' modal
    await tester.tap(find.byKey(const ValueKey('home_button_score_meaning')));
    await tester.pumpAndSettle();
    expect(find.text('What does this score mean?'), findsWidgets);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    // Verify top Enpass toolbar and sidebar filters (including default Old Passwords age buckets)
    expect(find.byKey(const ValueKey('vault_button_new_item_top')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar_primary_vault_header')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar_audit_two_fa_supported')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar_one_time_codes')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar_audit_1_3_years')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar_audit_3_6_months')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar_audit_6_12_months')), findsOneWidget);

    // Open Enpass Password Generator Dialog
    await tester.tap(find.byKey(const ValueKey('vault_button_password_generator')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('enpass_password_generator_dialog')), findsOneWidget);
    expect(find.text('Pronounceable'), findsOneWidget);
    expect(find.text('Ambiguous Characters'), findsOneWidget);
    expect(find.byKey(const ValueKey('pwgen_button_regenerate')), findsOneWidget);
    expect(find.byKey(const ValueKey('pwgen_button_copy')), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // Open Enpass 9-Tab Settings Dialog
    await tester.tap(find.byKey(const ValueKey('vault_button_settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('enpass_settings_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_tab_Vaults')));
    await tester.pumpAndSettle();

    // Verify Primary Vault detail view (SYNC INFO & VAULT INFO) and open storage grid
    expect(find.text('SYNC INFO'), findsOneWidget);
    expect(find.text('VAULT INFO'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_button_add_new_vault')));
    await tester.pumpAndSettle();
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('OneDrive'), findsOneWidget);
    expect(find.text('WebDAV'), findsOneWidget);

    // Switch to Customize tab and toggle Include Old Passwords in Audit off
    await tester.tap(find.byKey(const ValueKey('settings_tab_Customize')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings_theme_Follow System')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_theme_Light')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_theme_Dark')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_switch_old_passwords_audit')));
    await tester.pumpAndSettle();

    // Switch to About tab
    await tester.tap(find.byKey(const ValueKey('settings_tab_About')));
    await tester.pumpAndSettle();
    expect(find.text('ABOUT VAULTKEEP'), findsOneWidget);

    await tester.tap(find.byTooltip('Close Settings'));
    await tester.pumpAndSettle();

    // Confirm Old Password audit age buckets are hidden when toggled off
    expect(find.byKey(const ValueKey('sidebar_audit_1_3_years')), findsNothing);
    expect(find.byKey(const ValueKey('sidebar_audit_3_6_months')), findsNothing);
    expect(find.byKey(const ValueKey('sidebar_audit_6_12_months')), findsNothing);

    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Enpass Item Editor: Add Field, Add Section, Field Options Modal, and Generator History work end-to-end', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await backend.unlock('path', 'correct-horse-battery');
    controller.status = VaultStatus.unlocked;
    final id = await controller.save(
      null,
      const EntryDraft(
        title: 'Accenture Candidate',
        username: 'kingshuk',
        password: 'VeryStrongUniquePassword!2026',
        url: 'https://candidate.accenture.com',
        notes: 'Notes',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EntryScreen(controller: controller, entryId: id),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Enpass Additional Details, Tags, and Attachments dropzone
    expect(find.text('ADDITIONAL DETAILS'), findsOneWidget);
    expect(find.byKey(const ValueKey('entry_field_email')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry_field_phone')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry_field_security_question')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry_field_security_answer')), findsOneWidget);
    expect(find.byKey(const ValueKey('entry_field_tags')), findsOneWidget);
    expect(find.text('Drag and drop or click here'), findsOneWidget);

    // Open Field Options modal
    await tester.tap(find.byKey(const ValueKey('field_options_Username')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('enpass_field_options_dialog')), findsOneWidget);
    expect(find.text('Field Options'), findsOneWidget);
    expect(find.text('Sensitive'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('field_options_name')), 'API Secret Key');
    await tester.tap(find.byKey(const ValueKey('field_options_sensitive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('field_options_save')));
    await tester.pumpAndSettle();

    // Open Generator History dialog
    await tester.tap(find.byKey(const ValueKey('entry_button_generator_history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('enpass_generator_history_dialog')), findsOneWidget);
    expect(find.text('Fill'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('gen_history_fill_0')));
    await tester.pumpAndSettle();

    // Enter email, phone, security question/answer, and save to backend
    await tester.enterText(find.byKey(const ValueKey('entry_field_email')), 'candidate@accenture.com');
    await tester.enterText(find.byKey(const ValueKey('entry_field_phone')), '+1-555-0199');
    await tester.enterText(find.byKey(const ValueKey('entry_field_security_question')), 'First pet?');
    await tester.enterText(find.byKey(const ValueKey('entry_field_security_answer')), 'FluffySecret');
    await tester.ensureVisible(find.byKey(const ValueKey('entry_button_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('entry_button_save')));
    await tester.pumpAndSettle();

    final savedEntry = await controller.loadEntry(id);
    expect(savedEntry.email, 'candidate@accenture.com');
    expect(savedEntry.phone, '+1-555-0199');
    expect(savedEntry.securityQuestion, 'First pet?');
    expect(await controller.revealSecurityAnswer(id), 'FluffySecret');
    expect(savedEntry.sections, isNotEmpty);
    expect(savedEntry.customFields, isNotEmpty);
    expect(savedEntry.customFields.first.name, 'API Secret Key');
    expect(savedEntry.customFields.first.sensitive, isTrue);

    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('New Item category dropdown, Light Mode theme switch, Startup/Tray settings, and Quick PIN unlock UI work end-to-end', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      TacticalTheme.configure(light: false, accent: null);
      tester.view.reset();
    });

    await backend.unlock('path', 'correct-horse-battery');
    controller.status = VaultStatus.unlocked;

    await tester.pumpWidget(
      MaterialApp(
        home: VaultScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Click '+ New Item v' top button -> opens category popup menu and New Credential Entry form
    await tester.tap(find.byKey(const ValueKey('vault_button_new_item_top')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new_item_category_Credit Card')), findsOneWidget);
    expect(find.byKey(const ValueKey('new_item_group')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('new_item_category_Credit Card')));
    await tester.pumpAndSettle();
    expect(find.text('New Credential Entry'), findsOneWidget);
    expect(find.text('Credit Card'), findsWidgets);

    // 2. Open Settings -> General: toggle Startup, Minimize to Tray, Hide Dock Icon
    await tester.tap(find.byKey(const ValueKey('vault_button_settings')));
    await tester.pumpAndSettle();
    expect(controller.minimizeToTray, isTrue);
    await tester.tap(find.byKey(const ValueKey('settings_switch_open_at_startup')));
    await tester.tap(find.byKey(const ValueKey('settings_switch_minimize_to_tray')));
    await tester.tap(find.byKey(const ValueKey('settings_switch_hide_dock_icon')));
    await tester.pumpAndSettle();
    expect(controller.openAtStartup, isTrue);
    expect(controller.minimizeToTray, isFalse);
    expect(controller.hideDockIcon, isTrue);
    await tester.tap(find.byKey(const ValueKey('settings_switch_minimize_to_tray')));
    await tester.pumpAndSettle();
    expect(controller.minimizeToTray, isTrue);

    // 3. Settings -> Customize -> Light Mode
    await tester.tap(find.byKey(const ValueKey('settings_tab_Customize')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings_theme_Light')));
    await tester.pumpAndSettle();
    expect(controller.themeModeSetting, 'Light');
    expect(controller.effectiveIsLight, isTrue);

    // 4. Settings -> Security -> Configure Quick Unlock PIN (alphanumeric "Pin#2026")
    await tester.tap(find.byKey(const ValueKey('settings_tab_Security')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings_switch_quick_pin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings_quick_pin_dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('settings_pin_input')), 'Pin#2026');
    await tester.enterText(find.byKey(const ValueKey('settings_pin_confirm')), 'Pin#2026');
    await tester.tap(find.byKey(const ValueKey('settings_pin_save_button')));
    await tester.pumpAndSettle();
    expect(controller.quickPinEnabled, isTrue);
    expect(controller.hasQuickPinConfigured, isTrue);

    await tester.tap(find.byTooltip('Close Settings'));
    await tester.pumpAndSettle();

    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('First-launch Onboarding Flow: Personal/Business -> Activate Email & 6-Digit OTP -> Select Container Location -> Create Container', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(
      MaterialApp(
        home: UnlockScreen(
          controller: controller,
          defaultPath: 'nonexistent_first_launch_vault.kdbx',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Step 1: Centered Welcome & Personal / Business selection
    expect(find.text('VaultKeep'), findsOneWidget);
    expect(find.text("Choose how you'll use VaultKeep"), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_card_personal')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_card_business')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding_card_personal')));
    await tester.pumpAndSettle();

    // Step 2a: Activate Enpass Email Modal
    expect(find.text('Activate Enpass'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_input_email')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('onboarding_input_email')),
      'killfury212@gmail.com',
    );
    await tester.tap(find.byKey(const ValueKey('onboarding_button_email_continue')));
    await tester.pumpAndSettle();

    // Step 2b: 6-digit OTP verification Modal
    expect(find.text('Enter the 6-digit code sent to you at'), findsOneWidget);
    expect(find.text('killfury212@gmail.com'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await tester.enterText(
        find.byKey(ValueKey('onboarding_otp_box_$i')),
        '${i + 1}',
      );
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding_button_otp_continue')));
    await tester.pumpAndSettle();

    expect(controller.onboardingUsageType, 'Personal');
    expect(controller.onboardingActivatedEmail, 'killfury212@gmail.com');

    // Step 3: Select where you already have or want to keep your data
    expect(
      find.text('Select where you already have or want to keep your data:'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('onboarding_location_onedrive')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_location_googledrive')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_location_icloud')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_location_dropbox')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_location_box')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_button_activation_details')), findsOneWidget);

    // Select OneDrive -> transitions to Step 4 (Container Path & Master Password creation)
    await tester.tap(find.byKey(const ValueKey('onboarding_location_onedrive')));
    await tester.pumpAndSettle();
    expect(controller.connectedStorageProvider, 'OneDrive');
    expect(find.byKey(const ValueKey('unlock_field_path')), findsOneWidget);
    expect(find.byKey(const ValueKey('unlock_field_master')), findsOneWidget);
    expect(find.byKey(const ValueKey('unlock_field_confirm')), findsOneWidget);

    // Create the container
    await tester.enterText(
      find.byKey(const ValueKey('unlock_field_master')),
      'correct-horse-battery',
    );
    await tester.enterText(
      find.byKey(const ValueKey('unlock_field_confirm')),
      'correct-horse-battery',
    );
    await tester.tap(find.byKey(const ValueKey('unlock_button_submit')));
    await tester.pumpAndSettle();

    expect(controller.status, VaultStatus.unlocked);
    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Top Menu Bar (File, View, Item, Tools, Help) dropdowns and actions work end-to-end', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await backend.unlock('path', 'correct-horse-battery');
    controller.status = VaultStatus.unlocked;
    await controller.save(
      null,
      const EntryDraft(
        title: 'GitHub',
        username: 'octocat',
        password: 'VeryStrongUniquePassword!2026',
        url: 'https://github.com',
        notes: 'Notes',
        email: 'octo@github.com',
        category: 'Login',
        tags: ['dev'],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VaultScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify all 5 Top Menu buttons exist
    expect(find.byKey(const ValueKey('top_menu_file')), findsOneWidget);
    expect(find.byKey(const ValueKey('top_menu_view')), findsOneWidget);
    expect(find.byKey(const ValueKey('top_menu_item')), findsOneWidget);
    expect(find.byKey(const ValueKey('top_menu_tools')), findsOneWidget);
    expect(find.byKey(const ValueKey('top_menu_help')), findsOneWidget);

    // 2. Open File menu -> verify Backup, Import, Export, Print, Close (Ctrl+W) -> open Import dialog
    await tester.tap(find.byKey(const ValueKey('top_menu_file')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu_item_file_backup')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_file_import')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_file_export')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_file_print')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_file_close')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('menu_item_file_import')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('top_menu_import_dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('import_csv_content_field')),
      'Title,Username,Email,Password,URL,Notes,Category,Tags\nGitLab,devops,dev@gitlab.com,GitLabPass!99,https://gitlab.com,CI,Login,ci',
    );
    await tester.tap(find.byKey(const ValueKey('import_csv_submit_button')));
    await tester.pumpAndSettle();
    expect(controller.items.any((i) => i.title == 'GitLab'), isTrue);

    // 3. Open View menu -> toggle Categories off and verify sidebar CATEGORIES header hides
    expect(find.text('CATEGORIES'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('top_menu_view')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu_item_view_show_item_counts')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_view_hide_sensitive')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_view_categories')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_view_tags')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_view_audit_in_sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_view_show_old_passwords')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_view_others')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_view_previous_group')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_view_next_group')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('menu_item_view_categories')));
    await tester.pumpAndSettle();
    expect(controller.showSidebarCategories, isFalse);
    expect(find.text('CATEGORIES'), findsNothing);

    // 4. Open Item menu -> Duplicate item
    final countBefore = controller.items.length;
    await tester.tap(find.byKey(const ValueKey('top_menu_item')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu_item_item_duplicate')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_item_archive')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_item_move_to_trash')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_item_copy_username')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_item_copy_email')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_item_copy_password')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_item_show_passwords')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_item_copy_url')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_item_copy_otp')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_item_launch_url')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_item_change_category')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_item_add_to_vault')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('menu_item_item_duplicate')));
    await tester.pumpAndSettle();
    expect(controller.items.length, countBefore + 1);

    // 5. Open Tools menu -> verify Lock, Sync Now, Clear Clipboard, Generate Password, Auto Backups, Clear Recent Items
    await tester.tap(find.byKey(const ValueKey('top_menu_tools')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu_item_tools_lock')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_tools_sync_now')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_tools_clear_clipboard')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_tools_generate_password')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_tools_auto_backups')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_tools_clear_recent_items')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('menu_item_tools_clear_recent_items')));
    await tester.pumpAndSettle();
    expect(controller.recentEntryIds, isEmpty);

    // 6. Open Help menu -> verify Support Forum, Blog, X(Twitter), Report a Bug, Write to Us, Check for Updates, About
    await tester.tap(find.byKey(const ValueKey('top_menu_help')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu_item_help_support_forum')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_help_blog')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_help_twitter')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_help_report_bug')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_help_write_to_us')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_help_check_updates')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu_item_help_about')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('menu_item_help_check_updates')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('top_menu_check_updates_dialog')), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });
}


