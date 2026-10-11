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
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    final isLight = WidgetsBinding
            .instance.platformDispatcher.platformBrightness ==
        Brightness.light;
    if (widget.controller.systemIsLight != isLight) {
      widget.controller.systemIsLight = isLight;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.controller.isAuthenticatingWindowsHello) {
      return;
    }
    final isMobile = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    if (state == AppLifecycleState.paused ||
        (state == AppLifecycleState.hidden &&
            (isMobile || widget.controller.lockOnWindowClose)) ||
        (state == AppLifecycleState.inactive && isMobile)) {
      unawaited(widget.controller.lock());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final platformLight = WidgetsBinding
                .instance.platformDispatcher.platformBrightness ==
            Brightness.light;
        final bool useLight = switch (c.themeModeSetting) {
          'Light' => true,
          'Dark' => false,
          _ => c.systemIsLight || platformLight,
        };
        final Color? sysAccent = (c.themeModeSetting == 'Follow System' &&
                c.systemAccentColorValue != null)
            ? Color(c.systemAccentColorValue!)
            : null;

        TacticalTheme.configure(light: useLight, accent: sysAccent);
        final activeTheme = TacticalTheme.buildTheme(light: useLight);

        final themeMode = switch (c.themeModeSetting) {
          'Light' => ThemeMode.light,
          'Dark' => ThemeMode.dark,
          _ => useLight ? ThemeMode.light : ThemeMode.dark,
        };

        return MaterialApp(
          title: 'VaultKeep',
          navigatorKey: _navKey,
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: activeTheme,
          darkTheme: activeTheme,
          builder: (context, child) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => widget.controller.touch(),
            child: child,
          ),
          home: c.status == VaultStatus.unlocked
              ? VaultScreen(controller: c)
              : UnlockScreen(
                  controller: c,
                  defaultPath: widget.defaultVaultPath,
                ),
        );
      },
    );
  }
}
