import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData dark() {
    const c = AppColors.dark;
    return ThemeData.dark().copyWith(
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
    return ThemeData.light().copyWith(
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
