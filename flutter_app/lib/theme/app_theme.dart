import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF6B4EFF);
  static const primaryLight = Color(0xFF9B7FFF);
  static const primaryDark = Color(0xFF4A2FCC);
  static const surface = Color(0xFF1A1A2E);
  static const surfaceLight = Color(0xFF232342);
  static const surfaceLighter = Color(0xFF2D2D52);
  static const background = Color(0xFF0F0F1A);
  static const textPrimary = Color(0xFFEAEAFF);
  static const textSecondary = Color(0xFF8888AA);
  static const success = Color(0xFF4ADE80);
  static const warning = Color(0xFFFB923C);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF38BDF8);

  static const Map<String, Color> statusColors = {
    'running': success,
    'stopped': Color(0xFF6B7280),
    'crashed': danger,
    'restarting': warning,
    'failed': Color(0xFF991B1B),
  };
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorSchemeSeed: AppColors.primary,
      useMaterial3: true,
      fontFamily: GoogleFonts.inter().fontFamily,
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primaryLight, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.surfaceLighter,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppColors.surfaceLighter,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceLight,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: GoogleFonts.inter(fontSize: 13),
      ),
    );
  }
}

// Status helpers
Color statusColor(String status) => AppColors.statusColors[status] ?? AppColors.textSecondary;

IconData statusIcon(String status) {
  switch (status) {
    case 'running': return Icons.play_circle_rounded;
    case 'stopped': return Icons.stop_circle_rounded;
    case 'crashed': return Icons.error_rounded;
    case 'restarting': return Icons.autorenew_rounded;
    case 'failed': return Icons.cancel_rounded;
    default: return Icons.help_outline_rounded;
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'running': return 'Running';
    case 'stopped': return 'Stopped';
    case 'crashed': return 'Crashed';
    case 'restarting': return 'Restarting...';
    case 'failed': return 'Failed';
    default: return status;
  }
}
