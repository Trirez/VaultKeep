import 'dart:async';

import 'package:flutter/services.dart';

/// Copies a secret and clears the clipboard after a delay, but only if the
/// clipboard still holds that exact value (so we never wipe something else).
///
/// Known limits: the secret lives in a Dart String for the delay, and Android
/// 10+ blocks clipboard reads from a backgrounded app, so the clear can be
/// skipped there. See .agent/skills/security-review.
class ClipboardGuard {
  ClipboardGuard._();

  static Timer? _timer;
  static String? _activeSecret;

  static Future<void> copySecret(
    String value, {
    Duration clearAfter = const Duration(seconds: 15),
  }) async {
    _activeSecret = value;
    await Clipboard.setData(ClipboardData(text: value));
    _timer?.cancel();
    _timer = Timer(clearAfter, () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == _activeSecret) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      _activeSecret = null;
      _timer = null;
    });
  }

  /// Clears the clipboard immediately if it still holds our copied secret.
  static Future<void> clearNow() async {
    _timer?.cancel();
    _timer = null;
    if (_activeSecret != null) {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == _activeSecret) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      _activeSecret = null;
    }
  }
}
