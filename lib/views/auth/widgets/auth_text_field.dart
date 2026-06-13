import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Pill-shaped form input used by both the email and password fields.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.icon,
    required this.hint,
    this.obscure = false,
    this.suffix,
    this.readOly=false,
    this.keyboardType,
    this.autofillHints,
    this.maxLength,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final bool obscure;
  final bool readOly;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;

  /// Hard character cap on the field. `null` = no cap. The cap counts
  /// against the underlying [TextField.maxLength] so the OS keyboard
  /// stops accepting input at the limit.
  final int? maxLength;

  /// Optional input formatters — e.g. `[FilteringTextInputFormatter
  /// .digitsOnly]` on a postal-code field to strip non-numeric input
  /// before it ever lands in the controller.
  final List<TextInputFormatter>? inputFormatters;

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
          const SizedBox(width: 14),
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              autofillHints: autofillHints,
              maxLength: maxLength,
              inputFormatters: inputFormatters,
              style: AppTextStyles.input,
              cursorColor: AppColors.accent,
              cursorWidth: 1.4,
              readOnly:readOly ,
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
                // Hide Flutter's built-in counter ("3/4") on capped
                // fields — the form already shows a helper line for
                // the postal-code rule.
                counterText: '',
              ),
            ),
          ),
          if (suffix != null) ...[
            suffix!,
            const SizedBox(width: 12),
          ] else
            const SizedBox(width: 14),
        ],
      ),
    );
  }
}
