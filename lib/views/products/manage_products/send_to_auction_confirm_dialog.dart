import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/localization/translation_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/product_request_model.dart';

/// "Are you sure?" before "Send to auction": the product and unit counts,
/// and (TW-193) how many lines stay in draft for the admin. True only when the seller taps "Yes, send".
Future<bool> showSendToAuctionConfirm({
  required BuildContext context,
  required String streamTitle,
  required List<ProductRequestItem> ready,
  required int units,
  required int heldIssues,
  required int heldUnknown,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.brandNavy.withOpacity(0.45),
    builder: (_) => _SendToAuctionConfirmDialog(
      streamTitle: streamTitle,
      ready: ready,
      units: units,
      heldIssues: heldIssues,
      heldUnknown: heldUnknown,
    ),
  );
  return result ?? false;
}

class _SendToAuctionConfirmDialog extends StatelessWidget {
  const _SendToAuctionConfirmDialog({
    required this.streamTitle,
    required this.ready,
    required this.units,
    required this.heldIssues,
    required this.heldUnknown,
  });

  final String streamTitle;
  final List<ProductRequestItem> ready;
  final int units;
  final int heldIssues;
  final int heldUnknown;

  @override
  Widget build(BuildContext context) {
    final held = heldIssues + heldUnknown;

    return Dialog(
      backgroundColor: AppColors.white,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryBlue.withOpacity(0.10),
                  ),
                  child: const Icon(Icons.gavel_rounded,
                      size: 22, color: AppColors.primaryBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomText(
                        TKeys.sendConfirmTitle.tr,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      CustomText(
                        streamTitle,
                        fontSize: 12,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // The two numbers the seller is agreeing to.
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    value: '${ready.length}',
                    label: TKeys.sendConfirmProducts.tr,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    value: '$units',
                    label: TKeys.sendConfirmUnits.tr,
                  ),
                ),
              ],
            ),
            if (held > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade800.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.hourglass_top_rounded,
                        size: 16, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CustomText(
                        [
                          if (heldIssues > 0)
                            TKeys.sendToLiveHeldIssueNote
                                .trParams({'count': '$heldIssues'}),
                          if (heldUnknown > 0)
                            TKeys.sendToLiveUnknownNote
                                .trParams({'unknown': '$heldUnknown'}),
                        ].join(' '),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(
                          color: AppColors.textMuted.withOpacity(0.35)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: CustomText(
                      TKeys.cancelAction.tr,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: AppColors.primaryBlue,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: CustomText(
                      TKeys.sendConfirmYes
                          .trParams({'count': '${ready.length}'}),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            value,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.brandNavy,
          ),
          CustomText(
            label,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}
