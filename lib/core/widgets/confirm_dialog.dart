import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'custom_text.dart';

/// App-wide "are you sure?" dialog.
///
/// Returns `true` when the user taps the confirm (destructive) action, `false`
/// otherwise — including when the sheet is dismissed by tapping outside.
///
/// Layout is deliberately safety-first: the destructive action sits on the
/// left as a quiet grey button, while the "stay put" action is the filled blue
/// CTA on the right, so the easy tap is always the harmless one.
///
/// Pass `destructive: false` when confirming something the seller *wants* to
/// happen (sending products to the auction queue, say). That mirrors the
/// layout — Cancel first in quiet grey, the confirm action as the blue CTA on
/// the right — because putting the harmless tap under their thumb only makes
/// sense when the other option can lose them something.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Yes',
  String cancelLabel  = 'Cancel',
  IconData icon       = Icons.help_outline_rounded,
  bool barrierDismissible = true,
  bool destructive = true,
}) async
{
  // Quiet grey pill vs. filled blue CTA — which label wears which depends on
  // whether the confirm action is the risky one.
  final accent = destructive ? AppColors.vipps : AppColors.primaryBlue;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: AppColors.brandNavy.withOpacity(0.45),
    builder: (dialogCtx) => Dialog(
      backgroundColor: AppColors.white,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon badge
            Center(
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.10),
                  border: Border.all(
                    color: accent.withOpacity(0.18),
                    width: 1,
                  ),
                ),
                child: Icon(icon, size: 28, color: accent),
              ),
            ),
            const SizedBox(height: 18),

            CustomText(
              title,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              textAlign: TextAlign.center,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 10),

            CustomText(
              message,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.45,
              textAlign: TextAlign.center,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 22),

            // Content-sized buttons parked on the right. `Wrap` (instead of a
            // Row) keeps them hugging their labels and drops the second one to
            // a new line rather than overflowing if a label is ever long.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              // Both actions share one fixed width so neither looks weightier
              // than the other, whatever the labels are.
              children: [
                // Whichever action is the *quiet* one goes first: the confirm
                // when it's destructive, otherwise Cancel.
                _DialogAction(
                  label: destructive ? confirmLabel : cancelLabel,
                  onTap: () =>
                      Navigator.of(dialogCtx).pop(destructive ? true : false),
                  background: AppColors.inputFill,
                  foreground: AppColors.textSecondary,
                  border: AppColors.textMuted.withOpacity(0.28),
                ),
                // …and the filled blue CTA with its soft shadow goes second.
                _DialogAction(
                  label: destructive ? cancelLabel : confirmLabel,
                  onTap: () =>
                      Navigator.of(dialogCtx).pop(destructive ? false : true),
                  background: AppColors.primaryBlue,
                  foreground: AppColors.white,
                  shadow: AppColors.primaryBlueDark.withOpacity(0.35),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  return result ?? false;
}

/// Shared width for both dialog actions — keeps them visually equal.
const double _kActionWidth = 88;

/// One dialog button: rounded pill, optional border, optional drop shadow.
class _DialogAction extends StatelessWidget {
  const _DialogAction({
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
    this.border,
    this.shadow,
  });

  final String        label;
  final VoidCallback  onTap;
  final Color         background;
  final Color         foreground;
  final Color?        border;
  final Color?        shadow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kActionWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          boxShadow: shadow == null
              ? null
              : [
                  BoxShadow(
                    color: shadow!,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: border == null ? null : Border.all(color: border!),
              ),
              child: CustomText(
                label,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
