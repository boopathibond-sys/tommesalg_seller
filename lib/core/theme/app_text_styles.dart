import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography ramp for the app.
///
/// Single family — **Manrope** — used at varying weights to keep the
/// hierarchy quiet and Scandi-clean. All call sites should consume these
/// helpers rather than instantiating `TextStyle` inline.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
    Color color = AppColors.textPrimary,
  }) =>
      GoogleFonts.manrope(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );

  // Display — the screaming "Logg inn" header.
  static TextStyle get display => _base(
        size: 32,
        weight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -0.5,
      );

  // Subtle subtitle under the display.
  static TextStyle get subtitle => _base(
        size: 14,
        weight: FontWeight.w500,
        height: 1.4,
        color: AppColors.textSecondary,
      );

  // Tracked-out label above each input.
  static TextStyle get fieldLabel => _base(
        size: 11,
        weight: FontWeight.w700,
        letterSpacing: 1.4,
        color: AppColors.textSecondary,
      );

  // The text typed inside the input itself.
  static TextStyle get input => _base(
        size: 14.5,
        weight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  // Button label.
  static TextStyle get button => _base(
        size: 15.5,
        weight: FontWeight.w700,
        letterSpacing: 0.1,
      );

  // "Glemt passord?" / "Registrer deg nå" links.
  static TextStyle get link => _base(
        size: 13,
        weight: FontWeight.w700,
        color: AppColors.accent,
      );

  // Tab toggle label (Passord / E-postkode).
  static TextStyle get toggle => _base(
        size: 13.5,
        weight: FontWeight.w600,
      );

  // Body footer "Har du ikke en konto?".
  static TextStyle get footerBody => _base(
        size: 13,
        weight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  // Divider eyebrow text "ELLER FORTSETT MED".
  static TextStyle get divider => _base(
        size: 11,
        weight: FontWeight.w700,
        letterSpacing: 1.6,
        color: AppColors.textMuted,
      );
}
