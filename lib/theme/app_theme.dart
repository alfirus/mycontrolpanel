import 'package:flutter/material.dart';

class AppColors {
  // Pitch black system
  static const pitchBlack = Color(0xFF000000);
  static const surface0 = Color(0xFF0A0A0A);
  static const surface1 = Color(0xFF111111);
  static const surface2 = Color(0xFF1A1A1A);
  static const border = Color(0xFF1E1E1E);
  static const borderLight = Color(0xFF262626);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8A8A8E);
  static const textMuted = Color(0xFF52525B);
  static const textDim = Color(0xFF3F3F46);
  // Accents
  static const accentCyan = Color(0xFF00E5CC);
  static const accentCyanDim = Color(0xFF00B8A6);
  static const accentGreen = Color(0xFF00FF88);
  static const accentAmber = Color(0xFFFFCC02);
  static const accentRed = Color(0xFFFF3B30);
  static const accentBlue = Color(0xFF0A84FF);
  static const accentPurple = Color(0xFFAF52DE);
  // Status
  static const success = Color(0xFF00C950);
  static const warning = Color(0xFFEAB308);
  static const critical = Color(0xFFEF4444);
  static const info = Color(0xFF06B6D4);
}

class AppFonts {
  static const String mono = 'JetBrainsMono';
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: AppFonts.mono,
      scaffoldBackgroundColor: AppColors.pitchBlack,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accentCyan,
        secondary: AppColors.accentCyan,
        surface: AppColors.surface0,
        error: AppColors.critical,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.pitchBlack,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface0,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        titleLarge: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        titleMedium: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
        bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w400),
        labelLarge: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
        labelSmall: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.6),
      ),
    );
  }
}
