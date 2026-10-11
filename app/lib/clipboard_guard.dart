import 'dart:async';

import 'package:flutter/foundation.dart';
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

  @visibleForTesting
  static bool get hasActiveSecret => _activeSecret != null;

  static Future<void> copySecret(
    String value, {
    Duration clearAfter = const Duration(seconds: 15),
  }) async {
    _activeSecret = value;
    try {
      await Clipboard.setData(ClipboardData(text: value));
    } catch (_) {}
    _timer?.cancel();
    _timer = Timer(clearAfter, () async {
      final secretToClear = _activeSecret;
      _activeSecret = null;
      _timer = null;
      if (secretToClear != null) {
        try {
          final current = await Clipboard.getData(Clipboard.kTextPlain);
          if (current?.text == secretToClear) {
            await Clipboard.setData(const ClipboardData(text: ''));
          }
        } catch (_) {}
      }
    });
  }

  /// Clears the clipboard immediately if it still holds our copied secret.
  static Future<void> clearNow() async {
    _timer?.cancel();
    _timer = null;
    if (_activeSecret != null) {
      final secretToClear = _activeSecret;
      _activeSecret = null;
      try {
        final current = await Clipboard.getData(Clipboard.kTextPlain);
        if (current?.text == secretToClear) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {}
    }
  }
}
