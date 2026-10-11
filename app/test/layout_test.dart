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

    // Open Enpass Password Generator Dialog
    await tester.tap(find.byKey(const ValueKey('vault_button_password_generator')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('enpass_password_generator_dialog')), findsOneWidget);
    expect(find.text('Pronounceable'), findsOneWidget);
    expect(find.text('Ambiguous Characters'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // Open Enpass 8-Tab Settings Dialog
    await tester.tap(find.byKey(const ValueKey('vault_button_settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('enpass_settings_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_tab_Vaults')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings_button_add_new_vault')));
    await tester.pumpAndSettle();
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('OneDrive'), findsOneWidget);
    expect(find.text('WebDAV'), findsOneWidget);
    await tester.tap(find.byTooltip('Close Settings'));
    await tester.pumpAndSettle();

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

    await controller.lock();
    await tester.pumpWidget(const SizedBox());
  });
}
