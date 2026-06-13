import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';

/// Generic dropdown that visually matches the rest of the auth form.
///
/// Tapping the field opens a rounded bottom sheet — the selected option
/// gets a soft cream highlight and a leading orange check, so the picker
/// itself stays inside the app's warm aesthetic instead of looking like
/// a stock OS spinner.
class AuthDropdownField extends StatelessWidget {
  const AuthDropdownField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
    this.hint = '',
    this.sheetTitle,
  });

  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final IconData? icon;
  final String hint;
  final String? sheetTitle;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) => _OptionsSheet(
        title: sheetTitle,
        options: options,
        selected: value,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return GestureDetector(
      onTap: () => _open(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.inputBorder, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: CustomText(
                hasValue ? value! : hint,
                fontSize: 14.5,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
                color:
                    hasValue ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
            const Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Options sheet — drag handle, optional title, then a list of pill rows.
// ─────────────────────────────────────────────────────────────────────────────
class _OptionsSheet extends StatelessWidget {
  const _OptionsSheet({
    required this.options,
    required this.selected,
    this.title,
  });

  final List<String> options;
  final String? selected;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle.
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.inputBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          if (title != null) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: CustomText(
                title!,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...options.map((opt) {
            final isSelected = opt == selected;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(opt),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.backgroundSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        if (isSelected)
                          Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          )
                        else
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.inputBorder,
                                width: 1.5,
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 14),
                        CustomText(
                          opt,
                          fontSize: 15,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
