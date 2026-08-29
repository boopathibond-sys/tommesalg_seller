import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'custom_text.dart';

/// Session-scoped "auto quick view" preference, shared by every screen that
/// scans products (Assign to SKU, Manage Products). Static so the seller's
/// choice sticks while the app is running — panels are re-keyed per SKU / per
/// stream, so per-widget state would reset on every change.
///
/// Not persisted: the default is deliberately "on" each launch, since the quick
/// view is how a discrepancy gets reported right after a scan.
class AutoQuickViewPref {
  AutoQuickViewPref._();

  static bool enabled = true;
}

/// Compact pill toggle controlling whether the read-only product quick view
/// pops open automatically after a known product is scanned / added. Tapping
/// anywhere on the pill flips it; a mini animated switch + eye icon make the
/// current state obvious without taking up much room.
class AutoQuickViewToggle extends StatelessWidget {
  const AutoQuickViewToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = value ? AppColors.brandNavy : AppColors.textMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
        decoration: BoxDecoration(
          color: value
              ? AppColors.brandNavy.withOpacity(0.06)
              : AppColors.inputFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value
                ? AppColors.brandNavy.withOpacity(0.30)
                : AppColors.inputBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              size: 13,
              color: accent,
            ),
            const SizedBox(width: 5),
            CustomText(
              'Auto quick view',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
            const SizedBox(width: 7),
            // Mini animated switch track.
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 25,
              height: 14,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value
                    ? AppColors.brandNavy
                    : AppColors.textMuted.withOpacity(0.4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
