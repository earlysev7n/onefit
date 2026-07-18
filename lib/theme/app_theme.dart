import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  /// Shared type scale. Space Grotesk (w700) for display/headline/title,
  /// Inter for body/label. Colors are left to the widget / ColorScheme so
  /// this stays additive — inline `GoogleFonts.*` call sites still override.
  static TextTheme _textTheme(TextTheme base) {
    final heading = GoogleFonts.spaceGroteskTextTheme(base);
    final body = GoogleFonts.interTextTheme(base);
    return base.copyWith(
      displayLarge: heading.displayLarge?.copyWith(fontWeight: FontWeight.w700),
      displayMedium: heading.displayMedium?.copyWith(fontWeight: FontWeight.w700),
      displaySmall: heading.displaySmall?.copyWith(fontWeight: FontWeight.w700),
      headlineLarge: heading.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
      headlineMedium: heading.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall: heading.headlineSmall
          ?.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
      titleLarge:
          heading.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium:
          heading.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall:
          heading.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge:
          body.bodyLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
      bodyMedium:
          body.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall:
          body.bodySmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w400),
      labelLarge:
          body.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium:
          body.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall:
          body.labelSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
    );
  }

  static ThemeData dark() {
    const c = AppColors.dark;
    final base = ThemeData.dark();
    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      scaffoldBackgroundColor: c.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        surface: Color(0xFF1A1A1A),
        onSurface: Colors.white,
        onPrimary: Colors.black,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.onBackground,
        elevation: 0,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: c.onBackground,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
      ),
      dividerTheme: DividerThemeData(color: c.border),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: c.inputFill,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        hintStyle: GoogleFonts.inter(color: c.muted),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surface,
        contentTextStyle: GoogleFonts.inter(color: c.onBackground),
      ),
    );
  }

  static ThemeData light() {
    const c = AppColors.light;
    final base = ThemeData.light();
    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      scaffoldBackgroundColor: c.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF1A1A1A),
        onPrimary: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.onBackground,
        elevation: 0,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: c.onBackground,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
      ),
      dividerTheme: DividerThemeData(color: c.border),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: c.inputFill,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        hintStyle: GoogleFonts.inter(color: c.muted),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surface,
        contentTextStyle: GoogleFonts.inter(color: c.onBackground),
      ),
    );
  }
}
