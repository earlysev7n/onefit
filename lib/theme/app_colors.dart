import 'package:flutter/material.dart';

class AppColors {
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color inputFill;
  final Color border;
  final Color borderLight;
  final Color muted;
  final Color inactive;
  final Color subtle;
  final Color disabled;
  final Color onBackground;
  final Color onPrimary;
  final Color shadow;
  final Color surfaceVariant;
  final Color surfaceAlt;

  const AppColors._({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.inputFill,
    required this.border,
    required this.borderLight,
    required this.muted,
    required this.inactive,
    required this.subtle,
    required this.disabled,
    required this.onBackground,
    required this.onPrimary,
    required this.shadow,
    required this.surfaceVariant,
    required this.surfaceAlt,
  });

  static const primary = Color(0xFF00C97B);
  static const orange = Color(0xFFFF6B35);
  static const purple = Color(0xFF6C63FF);
  static const cyan = Color(0xFF00B4D8);
  static const yellow = Color(0xFFFFD60A);
  static const amber = Color(0xFFFFA726);

  static const dark = AppColors._(
    background: Color(0xFF0D0D0D),
    surface: Color(0xFF1A1A1A),
    surfaceElevated: Color(0xFF111111),
    inputFill: Color(0xFF222222),
    border: Color(0xFF2E2E2E),
    borderLight: Color(0xFF333333),
    muted: Color(0xFF888888),
    inactive: Color(0xFF555555),
    subtle: Color(0xFF444444),
    disabled: Color(0xFF666666),
    onBackground: Colors.white,
    onPrimary: Colors.black,
    shadow: Colors.black54,
    surfaceVariant: Color(0xFF1E1E1E),
    surfaceAlt: Color(0xFF2A2A2A),
  );

  static const light = AppColors._(
    background: Color(0xFFFAFAF5),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF5F5F0),
    inputFill: Color(0xFFF0F0EB),
    border: Color(0xFFE0E0DB),
    borderLight: Color(0xFFD5D5D0),
    muted: Color(0xFF717171),
    inactive: Color(0xFF9E9E9E),
    subtle: Color(0xFFBBBBBB),
    disabled: Color(0xFFA0A0A0),
    onBackground: Color(0xFF1A1A1A),
    onPrimary: Colors.white,
    shadow: Colors.black26,
    surfaceVariant: Color(0xFFF7F7F2),
    surfaceAlt: Color(0xFFEAEAE5),
  );
}

extension AppColorsX on BuildContext {
  AppColors get colors {
    final brightness = Theme.of(this).brightness;
    return brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  }
}
