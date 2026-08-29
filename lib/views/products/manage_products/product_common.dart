import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

// Small bits shared by the My Products grid and the product details page.

/// `AVAILABLE` → `Available`; unknown values pass through untouched.
String statusLabel(String value) {
  switch (value.toUpperCase()) {
    case 'ALL':
      return TKeys.filterAll.tr;
    case 'AVAILABLE':
      return TKeys.availableLabel.tr;
    case 'RESERVED':
      return TKeys.filterReserved.tr;
    case 'SOLD':
      return TKeys.soldLabel.tr;
    default:
      return value;
  }
}

/// `800` → `800.00 kr`; null → `—`.
String formatPrice(num? value) {
  if (value == null) return '—';
  return '${value.toStringAsFixed(2)} kr';
}

/// `2026-07-18T…` → `18.07.2026`.
String formatDate(DateTime? date) {
  if (date == null) return '—';
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.'
      '${local.year}';
}

/// Coloured pill carrying the product's stock status.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.large = false});

  final String status;

  /// Slightly bigger type for the details page header.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final upper = status.toUpperCase();
    final Color color;
    switch (upper) {
      case 'AVAILABLE':
        color = const Color(0xFF2E9E5B);
        break;
      case 'RESERVED':
        color = const Color(0xFFD08700);
        break;
      case 'SOLD':
        color = const Color(0xFFB3261E);
        break;
      default:
        color = AppColors.textSecondary;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 7,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: CustomText(
        statusLabel(upper).toUpperCase(),
        fontSize: large ? 10.5 : 8.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: Colors.white,
      ),
    );
  }
}

/// Eye icon + "Visible" / "Hidden". Sits under the product name on a card as a
/// plain line; the details page renders it as a tinted pill ([chip]).
class VisibilityBadge extends StatelessWidget {
  const VisibilityBadge({
    super.key,
    required this.isVisible,
    this.chip = false,
  });

  final bool isVisible;
  final bool chip;

  @override
  Widget build(BuildContext context) {
    final color = isVisible ? AppColors.brandNavy : AppColors.textMuted;
    return Container(
      padding: chip
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
          : EdgeInsets.zero,
      decoration: chip
          ? BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVisible
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: chip ? 14 : 12,
            color: color,
          ),
          SizedBox(width: chip ? 5 : 4),
          CustomText(
            isVisible ? TKeys.visibleLabel.tr : TKeys.hiddenLabel.tr,
            fontSize: chip ? 11.5 : 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ],
      ),
    );
  }
}

/// `Label ······ value` row used by the details page.
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: CustomText(
              label,
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: CustomText(
              value,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small all-caps section heading.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return CustomText(
      label,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
      color: AppColors.textPrimary,
    );
  }
}
