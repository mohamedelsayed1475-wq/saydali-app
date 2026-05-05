import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF00C896);
  static const primaryDark = Color(0xFF00A07A);
  static const primaryLight = Color(0xFFE6FAF5);
  static const accent = Color(0xFFFF6B35);
  static const accentLight = Color(0xFFFFF0EB);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const dark = Color(0xFF0D1B2A);
  static const darkCard = Color(0xFF132233);
  static const darkBorder = Color(0xFF1E3347);
  static const textColor = Color(0xFFE8F4F8);
  static const textMuted = Color(0xFF7A9BB5);
  static const textLight = Color(0xFFB0CCD9);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.darkCard,
          error: AppColors.danger,
        ),
        textTheme:
            GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme).copyWith(
          headlineLarge: GoogleFonts.cairo(
              color: AppColors.textColor, fontWeight: FontWeight.w800),
          headlineMedium: GoogleFonts.cairo(
              color: AppColors.textColor, fontWeight: FontWeight.w700),
          titleLarge: GoogleFonts.cairo(
              color: AppColors.textColor, fontWeight: FontWeight.w700),
          titleMedium: GoogleFonts.cairo(
              color: AppColors.textColor, fontWeight: FontWeight.w600),
          bodyLarge: GoogleFonts.cairo(color: AppColors.textColor),
          bodyMedium: GoogleFonts.cairo(color: AppColors.textLight),
          bodySmall: GoogleFonts.cairo(color: AppColors.textMuted),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkCard,
          foregroundColor: AppColors.textColor,
          elevation: 0,
          centerTitle: true,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkCard,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          hintStyle: const TextStyle(color: AppColors.textMuted),
          labelStyle: const TextStyle(color: AppColors.textMuted),
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
          color: AppColors.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.darkBorder),
          ),
          elevation: 0,
        ),
      );
}
