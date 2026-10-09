import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'rust_backend.dart';
import 'src/rust/frb_generated.dart';
import 'vault_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  final dir = await getApplicationDocumentsDirectory();
  runApp(
    VaultKeepApp(
      controller: VaultController(RustBackend()),
      defaultVaultPath: p.join(dir.path, 'vaultkeep.kdbx'),
    ),
  );
}
