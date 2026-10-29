import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/localization/translation_keys.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/custom_text.dart';
import '../product_edit_form.dart';
import '../widgets/edit_inputs.dart';

/// Platform-default shipping, or one of the fixed amounts the platform
/// allows. Never a free-typed price: the API only accepts a value from
/// `allowedShippingAmountsNok`.
class ShippingSection extends StatelessWidget {
  const ShippingSection({super.key, required this.form});

  final ProductEditForm form;

  @override
  Widget build(BuildContext context) {
    final defaultPrice = form.platformShipping?.defaultShippingPriceNok;
    final canOverride = form.canOverrideShipping;

    return EditGroup(
      title: TKeys.shippingSettings.tr,
      icon: Icons.local_shipping_outlined,
      children: [
        _Option(
          title: TKeys.shippingStandardOption.tr,
          subtitle: formatNokOrDash(defaultPrice),
          selected: form.useDefaultShipping,
          onTap: () => form.setUseDefaultShipping(true),
        ),
        const SizedBox(height: 10),
        _Option(
          title: TKeys.shippingCustomOption.tr,
          subtitle: canOverride
              ? (form.shippingPriceNok == null
                  ? TKeys.shippingPickAmount.tr
                  : formatNok(form.shippingPriceNok!))
              : TKeys.editShippingOverrideOff.tr,
          selected: !form.useDefaultShipping,
          onTap: canOverride ? () => form.setUseDefaultShipping(false) : null,
        ),
        if (!form.useDefaultShipping && canOverride) ...[
          const SizedBox(height: 16),
          EditFieldLabel(TKeys.editShippingAmount.tr),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final amount in form.shippingAmounts)
                EditChoicePill(
                  label: formatNok(amount),
                  selected: form.shippingPriceNok == amount,
                  onTap: () => form.setShippingPrice(amount),
                ),
            ],
          ),
          if (form.platformShipping?.maxShippingPerProductNok != null) ...[
            const SizedBox(height: 10),
            EditNote(TKeys.editShippingMax.trParams({
              'price':
                  formatNok(form.platformShipping!.maxShippingPerProductNok!),
            })),
          ],
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled || selected ? 1 : 0.5,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brandNavy.withOpacity(0.05)
                : AppColors.inputFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.brandNavy : AppColors.borderGrey,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? AppColors.brandNavy : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(title,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                    const SizedBox(height: 2),
                    CustomText(subtitle,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
