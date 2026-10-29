import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/localization/translation_keys.dart';
import '../../../../core/utils/currency.dart';
import '../product_edit_form.dart';
import '../widgets/edit_inputs.dart';

/// Catalogue price plus the auction's starting and bottom price. Buy-now and
/// MSRP are shown for reference — the edit endpoint doesn't accept them.
class PricingSection extends StatelessWidget {
  const PricingSection({super.key, required this.form});

  final ProductEditForm form;

  @override
  Widget build(BuildContext context) {
    final d = form.detail;
    return Column(
      children: [
        EditGroup(
          title: TKeys.editGroupCatalogPrice.tr,
          icon: Icons.payments_outlined,
          children: [
            EditTextField(
              label: TKeys.fieldOriginalPrice.tr,
              controller: form['veilPris'],
              numeric: true,
              suffix: 'kr',
            ),
          ],
        ),
        EditGroup(
          title: TKeys.secAuction.tr,
          icon: Icons.gavel_rounded,
          subtitle: TKeys.editStripeMinimumNote.tr,
          children: [
            EditRow(
              EditTextField(
                label: TKeys.fieldStartingPrice.tr,
                controller: form['startingPrice'],
                numeric: true,
                suffix: 'kr',
              ),
              EditTextField(
                label: TKeys.fieldBottomPrice.tr,
                controller: form['bottomPrice'],
                numeric: true,
                suffix: 'kr',
              ),
            ),
            EditNote(TKeys.bottomPriceHelp.tr),
            const SizedBox(height: 14),
          ],
        ),
        if (d.buyNowPrice != null || d.msrp != null)
          EditGroup(
            title: TKeys.editGroupReference.tr,
            icon: Icons.lock_outline_rounded,
            subtitle: TKeys.editReferenceNote.tr,
            children: [
              if (d.buyNowPrice != null)
                EditReadOnlyValue(
                  label: TKeys.buyNowPrice.tr,
                  value: formatNok(d.buyNowPrice!),
                ),
              if (d.msrp != null)
                EditReadOnlyValue(
                  label: TKeys.fieldMsrp.tr,
                  value: formatNok(d.msrp!),
                ),
            ],
          ),
      ],
    );
  }
}
