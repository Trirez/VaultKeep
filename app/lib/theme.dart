import 'package:flutter/material.dart';

/// Tactical Carbon & Amber Hardware-Security Design System for VaultKeep.
/// Supports Dark, Light, and Follow System (OS brightness + system accent color).
class TacticalTheme {
  TacticalTheme._();

  /// Whether Light Mode is currently active.
  static bool isLight = false;

  /// Optional OS system accent color active when "Follow System" is selected.
  static Color? systemAccent;

  static void configure({
    required bool light,
    Color? accent,
  }) {
    isLight = light;
    systemAccent = accent;
  }

  // Core Surfaces
  static Color get bgDeepCarbon =>
      isLight ? const Color(0xFFF1F5F9) : const Color(0xFF090A0F);
  static Color get bgPanel =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF10121A);
  static Color get bgSurface =>
      isLight ? const Color(0xFFF8FAFC) : const Color(0xFF161924);
  static Color get bgElevated =>
      isLight ? const Color(0xFFE2E8F0) : const Color(0xFF1C202E);
  static Color get bgHover =>
      isLight ? const Color(0xFFCBD5E1) : const Color(0xFF222738);

  // Borders & Dividers
  static Color get borderSubtle =>
      isLight ? const Color(0xFFE2E8F0) : const Color(0xFF232838);
  static Color get borderTech =>
      isLight ? const Color(0xFFCBD5E1) : const Color(0xFF2E354A);
  static Color get borderFocus => amberPrimary;

  // Tactical Accents
  static Color get amberPrimary {
    if (systemAccent != null) return systemAccent!;
    return isLight ? const Color(0xFFD97706) : const Color(0xFFF59E0B);
  }

  static Color get amberBright {
    if (systemAccent != null) {
      final hsl = HSLColor.fromColor(systemAccent!);
      return isLight
          ? hsl.withLightness((hsl.lightness * 0.72).clamp(0.18, 0.45)).toColor()
          : hsl.withLightness((hsl.lightness * 1.18).clamp(0.55, 0.82)).toColor();
    }
    return isLight ? const Color(0xFFB45309) : const Color(0xFFFBBF24);
  }

  static Color get amberDim {
    if (systemAccent != null) {
      return isLight
          ? systemAccent!.withValues(alpha: 0.16)
          : systemAccent!.withValues(alpha: 0.24);
    }
    return isLight ? const Color(0xFFFEF3C7) : const Color(0xFF452B06);
  }

  static Color get cyanTactical =>
      isLight ? const Color(0xFF0284C7) : const Color(0xFF06B6D4);
  static Color get cyanDim =>
      isLight ? const Color(0xFFE0F2FE) : const Color(0xFF0B2E38);
  static Color get emeraldReady =>
      isLight ? const Color(0xFF059669) : const Color(0xFF10B981);
  static Color get emeraldDim =>
      isLight ? const Color(0xFFD1FAE5) : const Color(0xFF063225);
  static Color get crimsonDanger =>
      isLight ? const Color(0xFFDC2626) : const Color(0xFFEF4444);
  static Color get crimsonDim =>
      isLight ? const Color(0xFFFEE2E2) : const Color(0xFF2D1215);
  static Color get crimsonLight =>
      isLight ? const Color(0xFFB91C1C) : const Color(0xFFFCA5A5);
  static Color get shadowColor =>
      isLight ? const Color(0x220F172A) : const Color(0x66000000);

  // Domain Avatar Brand Accents
  static Color get brandGithub =>
      isLight ? const Color(0xFF1E293B) : const Color(0xFFF3F4F6);
  static const Color brandAws = Color(0xFFFF9900);
  static const Color brandGoogle = Color(0xFF38BDF8);
  static const Color brandProton = Color(0xFFA855F7);
  static const Color brandFinance = Color(0xFF10B981);
  static const Color brandCloudflare = Color(0xFFF97316);

  // Onboarding Split-Screen & Activation Modal Semantic Tokens
  static const Color onboardingHeroBlue = Color(0xFF0A439C);
  static const Color onboardingEmblemFill = Color(0xFF174EA6);
  static const Color onboardingEmblemBorder = Color(0xFF2B63B8);
  static const Color onboardingHeroSubtext = Color(0xFFB8CFF2);
  static const Color onboardingRightPanelBg = Color(0xFFFAFAFA);
  static const Color onboardingCardWhite = Color(0xFFFFFFFF);
  static const Color onboardingCardBorder = Color(0xFFE5E7EB);
  static const Color onboardingSelectedBlue = Color(0xFF1565C0);
  static const Color onboardingButtonBlue = Color(0xFF3B6CB7);
  static const Color onboardingTextDark = Color(0xFF111827);
  static const Color onboardingTextMuted = Color(0xFF6B7280);
  static const Color onboardingPersonalBg = Color(0xFFBEF2B9);
  static const Color onboardingPersonalFg = Color(0xFF15803D);
  static const Color onboardingBusinessBg = Color(0xFFE6CFF7);
  static const Color onboardingBusinessFg = Color(0xFF7E22CE);
  static const Color onboardingSafeTeal = Color(0xFF4CA6B8);
  static const Color onboardingSafeDark = Color(0xFF2B6777);
  static const Color onboardingBubblePink = Color(0xFFFF4D8D);
  static const Color onboardingShieldGold = Color(0xFFFACC15);
  static const Color onboardingKeyGreen = Color(0xFF2AD1A3);
  static const Color onboardingCardIndigo = Color(0xFF6979B8);
  static const Color onboardingFolderYellow = Color(0xFFF7B500);
  static const Color onboardingPadlockGrey = Color(0xFF94A3B8);
  static const Color onboardingEnvelopeBack = Color(0xFFDCEBFA);
  static const Color onboardingEnvelopeFront = Color(0xFFEAF3FC);
  static const Color onboardingEnvelopeCard = Color(0xFF1E56C5);
  static const Color providerOneDrive = Color(0xFF0078D4);
  static const Color providerGoogleBlue = Color(0xFF4285F4);
  static const Color providerGoogleGreen = Color(0xFF34A853);
  static const Color providerGoogleYellow = Color(0xFFFBBC05);
  static const Color providerGoogleRed = Color(0xFFEA4335);
  static const Color providerICloud = Color(0xFF0A84FF);
  static const Color providerDropbox = Color(0xFF0061FF);
  static const Color providerBox = Color(0xFF0061D5);

  // Typography Colors
  static Color get textPrimary =>
      isLight ? const Color(0xFF0F172A) : const Color(0xFFF3F4F6);
  static Color get textSecondary =>
      isLight ? const Color(0xFF475569) : const Color(0xFF9CA3AF);
  static Color get textMuted =>
      isLight ? const Color(0xFF64748B) : const Color(0xFF6B7280);

  // Monospace Font Family
  static const String monoFont = 'Consolas';
  static const List<String> monoFallback = [
    'JetBrains Mono',
    'Courier New',
    'monospace',
  ];

  static TextStyle monoStyle({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: monoFont,
      fontFamilyFallback: monoFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? textPrimary,
      letterSpacing: letterSpacing,
    );
  }

  static ThemeData buildTheme({bool? light}) {
    final useLight = light ?? isLight;
    final brightness = useLight ? Brightness.light : Brightness.dark;
    final colorScheme = useLight
        ? ColorScheme.light(
            surface: bgPanel,
            onSurface: textPrimary,
            primary: amberPrimary,
            onPrimary: bgDeepCarbon,
            primaryContainer: amberDim,
            onPrimaryContainer: amberBright,
            secondary: cyanTactical,
            onSecondary: Colors.white,
            secondaryContainer: cyanDim,
            onSecondaryContainer: cyanTactical,
            error: crimsonDanger,
            onError: Colors.white,
            outline: borderTech,
            outlineVariant: borderSubtle,
          )
        : ColorScheme.dark(
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
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgDeepCarbon,
      canvasColor: bgPanel,
      dividerColor: borderSubtle,
      appBarTheme: AppBarTheme(
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
          side: BorderSide(color: borderTech, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: borderTech, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bgPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          side: BorderSide(color: borderTech, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgDeepCarbon,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        labelStyle: TextStyle(color: textSecondary, fontSize: 13),
        hintStyle: TextStyle(color: textMuted, fontSize: 13),
        helperStyle: TextStyle(color: textMuted, fontSize: 11),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: borderTech, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: amberPrimary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: crimsonDanger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: crimsonDanger, width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: borderTech, width: 1),
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
          side: BorderSide(color: borderTech, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgSurface,
        selectedColor: amberDim,
        side: BorderSide(color: borderTech, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        labelStyle: TextStyle(color: textPrimary, fontSize: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgElevated,
        contentTextStyle: monoStyle(fontSize: 12, color: amberBright),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: amberPrimary, width: 1),
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
    this.color,
    this.size = 30,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
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
          child: Icon(icon, size: 15, color: color ?? TacticalTheme.cyanTactical),
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
