import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Phone-number field shaped like [AuthTextField] but with a tappable
/// country-code chip on the leading edge: a hand-painted Norwegian flag,
/// a chevron, then a hairline divider, then the dial code, then the input.
class AuthPhoneField extends StatelessWidget {
  const AuthPhoneField({
    super.key,
    required this.controller,
    this.dialCode = '',
    this.onCountryTap,
    this.readOly = false,
    this.hint = '',
  });

  final TextEditingController controller;
  final String dialCode;
  final VoidCallback? onCountryTap;
  final String hint;
  final bool readOly;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      child: Row(
        children: [
          // ── Country chip ─────────────────────────────────────────────────
          GestureDetector(
            onTap: onCountryTap ?? () {/* TODO: country picker */},
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(14, 16, 8, 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NorwayFlag(),
                  SizedBox(width: 6),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          // Hairline divider — visual continuity with the website mock.
          Container(
            width: 1,
            height: 26,
            color: AppColors.inputBorder,
          ),
          const SizedBox(width: 12),
          // Dial code.
          Text(
            dialCode,
            style: AppTextStyles.input.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          // const SizedBox(width: 8),
          // ── Number input ─────────────────────────────────────────────────
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              style: AppTextStyles.input,
              cursorColor: AppColors.accent,
              cursorWidth: 1.4,
              readOnly: readOly,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTextStyles.input.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hand-painted Norwegian flag — same "primitives, no asset pipeline" approach
// the login illustration uses, so it renders identically across platforms.
// ─────────────────────────────────────────────────────────────────────────────
class _NorwayFlag extends StatelessWidget {
  const _NorwayFlag();

  static const double width  = 22;
  static const double height = 16;

  static const Color _red  = Color(0xFFEF2B2D);
  static const Color _blue = Color(0xFF002868);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            // Red field.
            Positioned.fill(child: Container(color: _red)),
            // White vertical bar (offset toward the hoist).
            Positioned(
              left: width * 0.30,
              top: 0,
              bottom: 0,
              child: Container(width: width * 0.18, color: Colors.white),
            ),
            // White horizontal bar.
            Positioned(
              top: height * 0.40,
              left: 0,
              right: 0,
              child: Container(height: height * 0.20, color: Colors.white),
            ),
            // Blue vertical bar (inside white).
            Positioned(
              left: width * 0.34,
              top: 0,
              bottom: 0,
              child: Container(width: width * 0.10, color: _blue),
            ),
            // Blue horizontal bar (inside white).
            Positioned(
              top: height * 0.46,
              left: 0,
              right: 0,
              child: Container(height: height * 0.10, color: _blue),
            ),
          ],
        ),
      ),
    );
  }
}
