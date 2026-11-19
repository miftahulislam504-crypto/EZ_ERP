import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for EZ ERP.
///
/// Direction: a deep petrol-green ledger palette with a single brass accent.
/// Green anchors the brand to its primary market and to the idea of a well
/// kept account book; brass is used sparingly for the active marker and
/// highlights so it stays meaningful.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF0F6B5C);
  static const primaryDark = Color(0xFF0A5246);
  static const primarySoft = Color(0xFFE3F0EC);
  static const brass = Color(0xFFC4943A);
  static const brassSoft = Color(0xFFF6ECD8);

  static const bg = Color(0xFFF2F5F4);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE2E8E5);
  static const borderStrong = Color(0xFFCBD5D1);

  static const textPrimary = Color(0xFF0F1F1D);
  static const textSecondary = Color(0xFF4A5C59);
  static const textMuted = Color(0xFF84948F);

  static const sidebarTop = Color(0xFF0B2A27);
  static const sidebarBottom = Color(0xFF071D1B);
  static const sidebarText = Color(0xFF9FB8B3);

  static const success = Color(0xFF1E8A5A);
  static const successSoft = Color(0xFFE2F3EA);
  static const warning = Color(0xFFB7791F);
  static const warningSoft = Color(0xFFFBF0DC);
  static const danger = Color(0xFFC0392B);
  static const dangerSoft = Color(0xFFFBE6E3);
  static const info = Color(0xFF245FA6);
  static const infoSoft = Color(0xFFE4EEF9);
  static const neutral = Color(0xFF4A5C59);
  static const neutralSoft = Color(0xFFEAEFED);
}

class AppRadius {
  AppRadius._();

  static const control = 10.0;
  static const card = 14.0;
  static const dialog = 18.0;
}

class AppShadows {
  AppShadows._();

  static const card = [
    BoxShadow(color: Color(0x0A0F1F1D), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0C0F1F1D), blurRadius: 22, offset: Offset(0, 10)),
  ];

  static const overlay = [
    BoxShadow(color: Color(0x290F1F1D), blurRadius: 40, offset: Offset(0, 16)),
  ];
}

/// Manrope carries headings and figures, Inter carries everything else.
class AppText {
  AppText._();

  static TextStyle get h1 => GoogleFonts.manrope(
      fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.2, color: AppColors.textPrimary);
  static TextStyle get h2 => GoogleFonts.manrope(
      fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.25, color: AppColors.textPrimary);
  static TextStyle get h3 => GoogleFonts.manrope(
      fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: -0.1, height: 1.3, color: AppColors.textPrimary);
  static TextStyle get kpi => GoogleFonts.manrope(
      fontSize: 25,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: AppColors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()]);
  static TextStyle get body =>
      GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, height: 1.45, color: AppColors.textSecondary);
  static TextStyle get bodyStrong =>
      GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: AppColors.textPrimary);
  static TextStyle get label =>
      GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static TextStyle get small =>
      GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.4, color: AppColors.textMuted);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.light).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.brass,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      outline: AppColors.border,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      dividerColor: AppColors.border,
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.transparent,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.sidebarBottom,
        contentTextStyle: GoogleFonts.inter(fontSize: 13.5, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    );
  }
}
