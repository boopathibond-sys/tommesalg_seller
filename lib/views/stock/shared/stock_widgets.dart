import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/inventory_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../core/localization/translation_keys.dart';

/// Rounded search/filter input matching the warehouse form chrome. Shared by
/// the Overview, SKUs, and Search sections.
class StockSearchField extends StatelessWidget {
  const StockSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    required this.onChanged,
    this.onSubmitted,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              keyboardType: keyboardType,
              textInputAction:
                  onSubmitted != null ? TextInputAction.search : null,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact navy pill button with a leading icon. Shared across sections.
class StockPillButton extends StatelessWidget {
  const StockPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.expanded = false,
    this.dense = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool expanded;

  /// Compact variant — smaller padding, icon, and label. Use where the button
  /// sits inline beside other content (e.g. a section header).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 11, vertical: 7)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.brandNavy,
        borderRadius: BorderRadius.circular(dense ? 10 : 12),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: dense ? 14 : 17, color: AppColors.white),
          SizedBox(width: dense ? 5 : 7),
          CustomText(
            label,
            fontSize: dense ? 11.5 : 13,
            fontWeight: FontWeight.w700,
            color: AppColors.white,
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: expanded ? SizedBox(width: double.infinity, child: child) : child,
    );
  }
}

/// Renders the three warehouse stat cards (Total / Active / Products assigned)
/// from `GET .../stats`, with loading + error states.
class StockStatsCards extends StatelessWidget {
  const StockStatsCards({super.key, required this.ctrl, this.compact = false});
  final InventoryController ctrl;

  /// Compact layout — all three stats sit in one tight row with small numbers
  /// and no description note. Use where vertical space is at a premium.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoadingStats && ctrl.stats == null) {
        return StockStatsLoading(compact: compact);
      }
      if (ctrl.statsError != null && ctrl.stats == null) {
        return StockStatsError(
          message: ctrl.statsError!,
          onRetry: ctrl.fetchStats,
        );
      }
      final s = ctrl.stats;

      if (compact) {
        return Row(
          children: [
            Expanded(
              child: StockStatCard(
                label: TKeys.stTotalCaps.tr,
                value: '${s?.totalSkus ?? 0}',
                compact: true,
              ),
            ),
            // ── Active SKUs card (hidden on the Overview) ──────────────────
            // const SizedBox(width: 8),
            // Expanded(
            //   child: StockStatCard(
            //     label: 'ACTIVE',
            //     value: '${s?.activeSkus ?? 0}',
            //     valueColor: AppColors.mascotShadow,
            //     compact: true,
            //   ),
            // ),
            const SizedBox(width: 8),
            Expanded(
              child: StockStatCard(
                label: TKeys.stAssignedCaps.tr,
                value: '${s?.productsAssigned ?? 0}',
                compact: true,
              ),
            ),
          ],
        );
      }

      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StockStatCard(
                  label: TKeys.stTotalSkusCaps.tr,
                  value: '${s?.totalSkus ?? 0}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StockStatCard(
                  label: TKeys.stActiveSkusCaps.tr,
                  value: '${s?.activeSkus ?? 0}',
                  valueColor: AppColors.mascotShadow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StockStatCard(
            label: TKeys.stProductsAssignedCaps.tr,
            value: '${s?.productsAssigned ?? 0}',
            note: TKeys.stSumOfAssignments.tr,
          ),
        ],
      );
    });
  }
}

class StockStatCard extends StatelessWidget {
  const StockStatCard({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.valueColor,
    this.compact = false,
  });
  final String label;
  final String value;
  final String? note;
  final Color? valueColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 12)
          : const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: AppColors.inputBorder, width: 1),
        boxShadow: compact
            ? null
            : [
                BoxShadow(
                  color: AppColors.brandNavy.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            label,
            fontSize: compact ? 9.5 : 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.textMuted,
          ),
          SizedBox(height: compact ? 4 : 10),
          CustomText(
            value,
            fontSize: compact ? 20 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: valueColor ?? AppColors.textPrimary,
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            CustomText(
              note!,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ],
        ],
      ),
    );
  }
}

/// Placeholder shown while the stats request is in flight.
class StockStatsLoading extends StatelessWidget {
  const StockStatsLoading({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget box() => Container(
          height: compact ? 64 : 96,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(compact ? 12 : 16),
            border: Border.all(color: AppColors.inputBorder, width: 1),
          ),
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
              ),
            ),
          ),
        );

    if (compact) {
      return Row(
        children: [
          Expanded(child: box()),
          const SizedBox(width: 8),
          Expanded(child: box()),
          const SizedBox(width: 8),
          Expanded(child: box()),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: box()),
            const SizedBox(width: 12),
            Expanded(child: box()),
          ],
        ),
        const SizedBox(height: 12),
        box(),
      ],
    );
  }
}

/// Compact inline error card with a retry. Shared across sections (stats,
/// locations, search, …) despite the warehouse-stats wording in the title.
class StockStatsError extends StatelessWidget {
  const StockStatsError({
    super.key,
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 18, color: AppColors.vipps),
              const SizedBox(width: 8),
              Expanded(
                child: CustomText(
                  TKeys.stSomethingWentWrong.tr,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          CustomText(
            message,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 14),
          StockPillButton(
            icon: Icons.refresh_rounded,
            label: TKeys.tryAgain.tr,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}
