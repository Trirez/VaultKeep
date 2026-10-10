import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkeep/backend.dart';
import 'package:vaultkeep/screens/entry_screen.dart';
import 'package:vaultkeep/screens/file_picker_dialog.dart';
import 'package:vaultkeep/screens/unlock_screen.dart';
import 'package:vaultkeep/screens/vault_screen.dart';
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
}
