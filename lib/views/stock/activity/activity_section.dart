import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

/// Activity — recent warehouse events. Currently static placeholder content;
/// wire to an events endpoint when the data layer lands.
class ActivitySection extends StatelessWidget {
  const ActivitySection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(
          TKeys.stRecentActivity.tr,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        const SizedBox(height: 14),
        _EventTile(
          icon: Icons.add_box_rounded,
          title: TKeys.stPlacementCreated.tr,
          subtitle: TKeys.stProductAddedToBin.tr,
          time: TKeys.stTwoHoursAgo.tr,
        ),
        const SizedBox(height: 10),
        _EventTile(
          icon: Icons.edit_rounded,
          title: TKeys.stLocationUpdated.tr,
          subtitle: TKeys.stBinRenamed.tr,
          time: TKeys.stYesterday.tr,
        ),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.brandYellow.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: AppColors.brandNavy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  title,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 2),
                CustomText(
                  subtitle,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          CustomText(
            time,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}
