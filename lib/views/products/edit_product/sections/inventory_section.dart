import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/localization/translation_keys.dart';
import '../product_edit_form.dart';
import '../widgets/edit_inputs.dart';

/// Warehouse codes, stock and weight.
class InventorySection extends StatelessWidget {
  const InventorySection({super.key, required this.form});

  final ProductEditForm form;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EditGroup(
          title: TKeys.editGroupIdentifiers.tr,
          icon: Icons.qr_code_2_rounded,
          children: [
            EditRow(
              EditTextField(label: 'SKU', controller: form['sku']),
              EditTextField(
                  label: 'UPC', controller: form['upc'], numeric: true, integer: true),
            ),
          ],
        ),
        EditGroup(
          title: TKeys.editGroupStock.tr,
          icon: Icons.inventory_2_outlined,
          children: [
            EditRow(
              EditTextField(
                label: TKeys.fieldStockCount.tr,
                controller: form['stockCount'],
                numeric: true,
                integer: true,
              ),
              EditTextField(
                label: TKeys.fieldWeight.tr,
                controller: form['weight'],
                numeric: true,
                suffix: 'kg',
              ),
            ),
            EditNote(TKeys.weightHelp.tr),
            const SizedBox(height: 14),
          ],
        ),
      ],
    );
  }
}
