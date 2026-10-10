import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'clipboard_guard.dart';
import 'screens/unlock_screen.dart';
import 'screens/vault_screen.dart';
import 'theme.dart';
import 'vault_controller.dart';

class VaultKeepApp extends StatefulWidget {
  const VaultKeepApp({
    super.key,
    required this.controller,
    required this.defaultVaultPath,
  });

  final VaultController controller;
  final String defaultVaultPath;

  @override
  State<VaultKeepApp> createState() => _VaultKeepAppState();
}

class _VaultKeepAppState extends State<VaultKeepApp>
    with WidgetsBindingObserver {
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_closeRoutesWhenLocked);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_closeRoutesWhenLocked);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Pushed screens (e.g. an open entry) must not outlive the unlocked state.
  void _closeRoutesWhenLocked() {
    if (widget.controller.status == VaultStatus.locked) {
      _navKey.currentState?.popUntil((route) => route.isFirst);
      unawaited(ClipboardGuard.clearNow());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        (state == AppLifecycleState.inactive &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
             defaultTargetPlatform == TargetPlatform.android))) {
      unawaited(widget.controller.lock());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tacticalTheme = TacticalTheme.buildTheme();
    return MaterialApp(
      title: 'VaultKeep',
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: tacticalTheme,
      darkTheme: tacticalTheme,
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => widget.controller.touch(),
        child: child,
      ),
      home: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) =>
            widget.controller.status == VaultStatus.unlocked
                ? VaultScreen(controller: widget.controller)
                : UnlockScreen(
                    controller: widget.controller,
                    defaultPath: widget.defaultVaultPath,
                  ),
      ),
    );
  }
}
