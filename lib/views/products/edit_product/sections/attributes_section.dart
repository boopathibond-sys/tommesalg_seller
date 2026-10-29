import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/localization/translation_keys.dart';
import '../product_edit_form.dart';
import '../widgets/colour_field.dart';
import '../widgets/edit_inputs.dart';

/// Look & material, sizing, tags and the long-form details.
class AttributesSection extends StatelessWidget {
  const AttributesSection({super.key, required this.form});

  final ProductEditForm form;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EditGroup(
          title: TKeys.editGroupAppearance.tr,
          icon: Icons.palette_outlined,
          children: [
            ColourField(label: TKeys.fieldPrimaryColour.tr, controller: form['colour']),
            EditTextField(label: TKeys.fieldMaterial.tr, controller: form['material']),
            EditChipInput(
              label: TKeys.fieldTags.tr,
              values: form.tags,
              hint: TKeys.addTagHint.tr,
              onAdd: form.addTags,
              onRemove: form.removeTag,
            ),
          ],
        ),
        EditGroup(
          title: TKeys.fieldSizing.tr,
          icon: Icons.straighten_rounded,
          children: [
            EditTextField(label: TKeys.fieldSize.tr, controller: form['size']),
            EditRow(
              EditTextField(label: TKeys.fieldUsSize.tr, controller: form['usSize']),
              EditTextField(label: TKeys.fieldEuSize.tr, controller: form['euSize']),
            ),
            EditTextField(
              label: TKeys.fieldSizesAvailable.tr,
              controller: form['sizesAvailable'],
              hint: TKeys.sizesHint.tr,
            ),
          ],
        ),
        EditGroup(
          title: TKeys.fieldDetails.tr,
          icon: Icons.article_outlined,
          children: [
            EditTextField(
                label: TKeys.fieldFeatures.tr, controller: form['features'], maxLines: 5),
            EditTextField(
              label: TKeys.fieldMaterialsCare.tr,
              controller: form['materialsAndCare'],
              maxLines: 5,
            ),
          ],
        ),
      ],
    );
  }
}
