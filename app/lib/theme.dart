import 'package:flutter/material.dart';

/// Tactical Carbon & Amber Hardware-Security Design System for VaultKeep.
class TacticalTheme {
  TacticalTheme._();

  // Core Surfaces
  static const Color bgDeepCarbon = Color(0xFF090A0F);
  static const Color bgPanel = Color(0xFF10121A);
  static const Color bgSurface = Color(0xFF161924);
  static const Color bgElevated = Color(0xFF1C202E);
  static const Color bgHover = Color(0xFF222738);

  // Borders & Dividers
  static const Color borderSubtle = Color(0xFF232838);
  static const Color borderTech = Color(0xFF2E354A);
  static const Color borderFocus = Color(0xFFF59E0B);

  // Tactical Accents
  static const Color amberPrimary = Color(0xFFF59E0B);
  static const Color amberBright = Color(0xFFFBBF24);
  static const Color amberDim = Color(0xFF452B06);
  static const Color cyanTactical = Color(0xFF06B6D4);
  static const Color cyanDim = Color(0xFF0B2E38);
  static const Color emeraldReady = Color(0xFF10B981);
  static const Color emeraldDim = Color(0xFF063225);
  static const Color crimsonDanger = Color(0xFFEF4444);
  static const Color crimsonDim = Color(0xFF2D1215);
  static const Color crimsonLight = Color(0xFFFCA5A5);
  static const Color shadowColor = Color(0x66000000);

  // Domain Avatar Brand Accents
  static const Color brandGithub = Color(0xFFF3F4F6);
  static const Color brandAws = Color(0xFFFF9900);
  static const Color brandGoogle = Color(0xFF38BDF8);
  static const Color brandProton = Color(0xFFA855F7);
  static const Color brandFinance = Color(0xFF10B981);
  static const Color brandCloudflare = Color(0xFFF97316);

  // Typography Colors
  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);

  // Monospace Font Family
  static const String monoFont = 'Consolas';
  static const List<String> monoFallback = ['JetBrains Mono', 'Courier New', 'monospace'];

  static TextStyle monoStyle({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.normal,
    Color color = textPrimary,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: monoFont,
      fontFamilyFallback: monoFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  static ThemeData buildTheme() {
    const colorScheme = ColorScheme.dark(
      surface: bgPanel,
      onSurface: textPrimary,
      primary: amberPrimary,
      onPrimary: bgDeepCarbon,
      primaryContainer: amberDim,
      onPrimaryContainer: amberBright,
      secondary: cyanTactical,
      onSecondary: bgDeepCarbon,
      secondaryContainer: cyanDim,
      onSecondaryContainer: cyanTactical,
      error: crimsonDanger,
      onError: Colors.white,
      outline: borderTech,
      outlineVariant: borderSubtle,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgDeepCarbon,
      canvasColor: bgPanel,
      dividerColor: borderSubtle,
      appBarTheme: const AppBarTheme(
        backgroundColor: bgPanel,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: bgSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: borderTech, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: borderTech, width: 1.5),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: bgPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          side: BorderSide(color: borderTech, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgDeepCarbon,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
        helperStyle: const TextStyle(color: textMuted, fontSize: 11),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: borderTech, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: amberPrimary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: crimsonDanger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: crimsonDanger, width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: borderTech, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: amberPrimary,
          foregroundColor: bgDeepCarbon,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: borderTech, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgSurface,
        selectedColor: amberDim,
        side: const BorderSide(color: borderTech, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        labelStyle: const TextStyle(color: textPrimary, fontSize: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgElevated,
        contentTextStyle: monoStyle(fontSize: 12, color: amberBright),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: amberPrimary, width: 1),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Renders the signature 15-block segmented amber progress bar for TOTP countdowns.
class SegmentedAmberBar extends StatelessWidget {
  const SegmentedAmberBar({
    super.key,
    required this.fraction,
    this.segments = 15,
    this.height = 12,
  });

  final double fraction;
  final int segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final clamped = fraction.clamp(0.0, 1.0);
    final activeCount = (clamped * segments).ceil();
    final isUrgent = clamped <= 0.2;

    return Row(
      children: List.generate(segments, (index) {
        final isActive = index < activeCount;
        return Expanded(
          child: Container(
            height: height,
            margin: EdgeInsets.only(right: index == segments - 1 ? 0 : 3),
            decoration: BoxDecoration(
              color: isActive
                  ? (isUrgent
                      ? TacticalTheme.crimsonDanger
                      : TacticalTheme.amberPrimary)
                  : TacticalTheme.bgDeepCarbon,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: isActive
                    ? (isUrgent
                        ? TacticalTheme.crimsonDanger
                        : TacticalTheme.amberBright)
                    : TacticalTheme.borderTech,
                width: 0.8,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Offline, zero-network domain/title avatar badge with tactical styling.
class TacticalDomainAvatar extends StatelessWidget {
  const TacticalDomainAvatar({
    super.key,
    required this.title,
    required this.url,
    this.size = 32,
  });

  final String title;
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final lower = '$title $url'.toLowerCase();
    IconData? icon;
    Color accent = TacticalTheme.amberPrimary;
    String label = title.trim().isNotEmpty ? title.trim()[0].toUpperCase() : '?';

    if (lower.contains('github')) {
      icon = Icons.code;
      accent = TacticalTheme.brandGithub;
    } else if (lower.contains('aws') || lower.contains('amazon')) {
      label = 'aws';
      accent = TacticalTheme.brandAws;
    } else if (lower.contains('google') || lower.contains('gmail')) {
      label = 'G';
      accent = TacticalTheme.brandGoogle;
    } else if (lower.contains('proton')) {
      icon = Icons.shield_outlined;
      accent = TacticalTheme.brandProton;
    } else if (lower.contains('stripe') ||
        lower.contains('bank') ||
        lower.contains('finance')) {
      icon = Icons.account_balance_outlined;
      accent = TacticalTheme.brandFinance;
    } else if (lower.contains('cloudflare') || lower.contains('server')) {
      icon = Icons.dns_outlined;
      accent = TacticalTheme.brandCloudflare;
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: TacticalTheme.bgDeepCarbon,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1),
      ),
      child: icon != null
          ? Icon(icon, size: size * 0.55, color: accent)
          : Text(
              label,
              style: TacticalTheme.monoStyle(
                fontSize: label.length > 1 ? size * 0.32 : size * 0.48,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
    );
  }
}

/// Tactical square action icon button used in credential rows and headers.
class TacticalActionSquare extends StatelessWidget {
  const TacticalActionSquare({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = TacticalTheme.cyanTactical,
    this.size = 30,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: TacticalTheme.bgElevated,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: TacticalTheme.borderTech, width: 1),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

/// Renders a revealed password with character-class color differentiation
/// (letters in `textPrimary`, digits in `cyanTactical`, symbols in `amberBright`)
/// and accessible screen-reader character semantics.
class TacticalColorPassword extends StatelessWidget {
  const TacticalColorPassword({
    super.key,
    required this.password,
    this.fontSize = 13,
  });

  final String password;
  final double fontSize;

  static final RegExp _letterRegex = RegExp(r'[a-zA-Z]');
  static final RegExp _digitRegex = RegExp(r'[0-9]');

  static String describeForAccessibility(String value) {
    final parts = <String>[];
    for (final rune in value.runes) {
      final ch = String.fromCharCode(rune);
      if (_digitRegex.hasMatch(ch)) {
        parts.add('digit $ch');
      } else if (_letterRegex.hasMatch(ch)) {
        final isUpper = ch == ch.toUpperCase() && ch != ch.toLowerCase();
        parts.add('${isUpper ? "uppercase" : "lowercase"} $ch');
      } else {
        parts.add('symbol $ch');
      }
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    for (final rune in password.runes) {
      final ch = String.fromCharCode(rune);
      final Color color;
      if (_digitRegex.hasMatch(ch)) {
        color = TacticalTheme.cyanTactical;
      } else if (_letterRegex.hasMatch(ch)) {
        color = TacticalTheme.textPrimary;
      } else {
        color = TacticalTheme.amberBright;
      }
      spans.add(
        TextSpan(
          text: ch,
          style: TacticalTheme.monoStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );
    }

    return Semantics(
      label: describeForAccessibility(password),
      excludeSemantics: true,
      child: SelectableText.rich(
        TextSpan(children: spans),
      ),
    );
  }
}
