import 'package:flutter/material.dart';

/// Single source of truth for colour values used in the app.
///
/// **Brand palette (product-given):**
///   • Yellow `#FFD84D` — page background everywhere
///   • Navy   `#0A1420` — primary text + navy details on the brand mark
///
/// Surrounding values are derived from these two so every view can pick up
/// the new look just by depending on this file. Field **names** are kept
/// stable from the previous warm-cream palette so the rest of the codebase
/// (every `lib/views/**` screen + auth widgets) needs no edits.
class AppColors {
  AppColors._();

  // ── Brand (product-given) ────────────────────────────────────────────────
  static const Color brandYellow = Color(0xFFFFD84D);
  static const Color brandNavy   = Color(0xFF0A1420);

  // ── Surfaces ─────────────────────────────────────────────────────────────
  static const Color background      = Color(0xFFFFFFFF);    // page bg — white
  static const Color backgroundSoft  = Color(0xFFFFD84D);    // gradient stop, deeper yellow
  static const Color card            = Color(0xFFFFFFFF);    // white card on yellow
  // Single source of truth for every text-field fill (AuthTextField,
  // AuthPhoneField, AuthDateField, AuthDropdownField). Neutral light
  // grey on white so the form chrome stays out of the way and the
  // brand yellow + navy can be reserved for highlights.
  static const Color inputFill       = Color(0xFFF2F3F5);    // light grey input fill
  static const Color inputBorder     = Color(0xFFE6CC85);    // muted amber border
  // Neutral hairline for card outlines and dividers, where the amber
  // `inputBorder` reads as a highlight rather than as structure.
  static const Color borderGrey      = Color(0xFFE4E7EC);    // neutral grey border
  static const Color toggleTrack     = Color(0xFFFFEFA0);    // toggle / track surface

  // ── Brand / CTA gradient ─────────────────────────────────────────────────
  // Kept yellow→amber so the navy text on every primary CTA, profile card,
  // and category chip stays legible without touching widget code.
  static const Color primaryYellow   = brandYellow;          // gradient start
  static const Color primaryOrange   = Color(0xFFFFD84D);    // gradient end (rich amber)

  // ── Accent ───────────────────────────────────────────────────────────────
  // Used by links ("Forgot password?"), input cursors, picker chrome.
  // Amber instead of the old hot orange so it harmonises with the gradient
  // and keeps contrast on both white cards and the yellow page.
  static const Color accent          = Color(0xFFFFD84D);

  // ── Vipps / destructive ──────────────────────────────────────────────────
  // The Vipps brand orange-red — kept as-is on purpose:
  //   * the "Logg inn med Vipps" button still has to look like Vipps
  //   * `AppColors.vipps` doubles as the destructive colour for inline
  //     errors and the logout button, where a warm red still reads
  //     correctly on yellow + white surfaces.
  static const Color vipps           = Color(0xFFFF5B24);

  // ── Safe / primary action ────────────────────────────────────────────────
  // The filled "keep me here" button in confirmation dialogs ("Stay",
  // "Stay signed in"). Blue reads as calm/safe next to the warm `vipps`
  // destructive colour, and stays legible as white-on-blue.
  static const Color primaryBlue     = Color(0xFF1E63E9);
  static const Color primaryBlueDark = Color(0xFF1348B8);      // shadow tint

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary     = brandNavy;            // headlines, body
  static const Color textSecondary   = Color(0xFF4F5C70);    // navy-tinted slate
  static const Color textMuted       = Color(0xFF8A93A4);    // lighter slate

  // ── Illustration (splash storefront brand mark) ──────────────────────────
  // The mark itself stays a yellow→amber squircle so it reads as "brand".
  // The painted details flip to navy where they used to be orange, so the
  // little shop pops on the new yellow page.
  static const Color shopWall        = Color(0xFFFFFFFF);
  static const Color shopShadow      = Color(0xFFFFD84D);
  static const Color awningLight     = brandYellow;
  static const Color awningDark      = brandNavy;            // header bar — was orange
  static const Color door            = brandNavy;            // door     — was orange
  static const Color mascot          = brandYellow;
  static const Color mascotShadow    = Color(0xFFC9A53A);
  static const Color leaf            = Color(0xFF7DAA52);
  static const Color leafDark        = Color(0xFF5F8B3C);
  static const Color pot             = Color(0xFF1F2D45);    // accent block — was warm orange

  // ── Misc shadows ─────────────────────────────────────────────────────────
  // Navy-tinted shadow lifts cards/CTAs off the yellow page without going
  // muddy the way the old orange shadow did.
  static const Color buttonShadow    = Color(0x330A1420);
  static const Color cardShadow      = Color(0x14000000);
  static const Color white      = Colors.white;
  static const Color grey      = Colors.grey;
}
