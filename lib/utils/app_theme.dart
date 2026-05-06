import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // ── الألوان الأساسية (ثابتة) ──────────────────────────
  static const primary = Color(0xFF00C896);
  static const primaryDark = Color(0xFF00A07A);
  static const primaryLight = Color(0xFFE6FAF5);
  static const accent = Color(0xFFFF6B35);
  static const accentLight = Color(0xFFFFF0EB);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);

  // ── الوضع الليلي ──────────────────────────
  static const dark = Color(0xFF0D1B2A);
  static const darkCard = Color(0xFF132233);
  static const darkBorder = Color(0xFF1E3347);
  static const textColor = Color(0xFFE8F4F8);
  static const textMuted = Color(0xFF7A9BB5);
  static const textLight = Color(0xFFB0CCD9);

  // ── الوضع النهاري ──────────────────────────
  static const lightBg = Color(0xFFF5F7FA);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE2E8F0);
  static const lightTextColor = Color(0xFF1A202C);
  static const lightTextMuted = Color(0xFF718096);
  static const lightTextLight = Color(0xFF4A5568);
}

class AppTheme {
  static ThemeData get darkTheme => _buildTheme(
        brightness: Brightness.dark,
        scaffoldBg: AppColors.dark,
        cardColor: AppColors.darkCard,
        borderColor: AppColors.darkBorder,
        textColor: AppColors.textColor,
        textMuted: AppColors.textMuted,
        textLight: AppColors.textLight,
      );

  static ThemeData get lightTheme => _buildTheme(
        brightness: Brightness.light,
        scaffoldBg: AppColors.lightBg,
        cardColor: AppColors.lightCard,
        borderColor: AppColors.lightBorder,
        textColor: AppColors.lightTextColor,
        textMuted: AppColors.lightTextMuted,
        textLight: AppColors.lightTextLight,
      );

  // backward compat
  static ThemeData get theme => darkTheme;

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color scaffoldBg,
    required Color cardColor,
    required Color borderColor,
    required Color textColor,
    required Color textMuted,
    required Color textLight,
  }) {
    final isDark = brightness == Brightness.dark;
    final baseTextTheme =
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
        onSecondary: Colors.white,
        error: AppColors.danger,
        onError: Colors.white,
        surface: cardColor,
        onSurface: textColor,
      ),
      textTheme: GoogleFonts.cairoTextTheme(baseTextTheme).copyWith(
        headlineLarge:
            GoogleFonts.cairo(color: textColor, fontWeight: FontWeight.w800),
        headlineMedium:
            GoogleFonts.cairo(color: textColor, fontWeight: FontWeight.w700),
        titleLarge:
            GoogleFonts.cairo(color: textColor, fontWeight: FontWeight.w700),
        titleMedium:
            GoogleFonts.cairo(color: textColor, fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.cairo(color: textColor),
        bodyMedium: GoogleFonts.cairo(color: textLight),
        bodySmall: GoogleFonts.cairo(color: textMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: cardColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cardColor,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: TextStyle(color: textMuted),
        labelStyle: TextStyle(color: textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 15, fontFamily: 'Cairo'),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        elevation: 0,
      ),
    );
  }
}
