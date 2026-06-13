import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';

/// Activity — recent warehouse events. Currently static placeholder content;
/// wire to an events endpoint when the data layer lands.
class ActivitySection extends StatelessWidget {
  const ActivitySection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(
          'Recent activity',
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        SizedBox(height: 14),
        _EventTile(
          icon: Icons.add_box_rounded,
          title: 'Placement created',
          subtitle: 'Product added to bin A-01',
          time: '2h ago',
        ),
        SizedBox(height: 10),
        _EventTile(
          icon: Icons.edit_rounded,
          title: 'Location updated',
          subtitle: 'Bin B-07 renamed',
          time: 'Yesterday',
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
