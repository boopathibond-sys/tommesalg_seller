import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/localization/translation_keys.dart';
import '../product_edit_form.dart';
import '../widgets/edit_inputs.dart';
import '../widgets/image_gallery_editor.dart';

/// Name, brand, category, descriptions and the photo gallery.
class GeneralSection extends StatelessWidget {
  const GeneralSection({
    super.key,
    required this.form,
    required this.uploading,
    required this.onAddImages,
  });

  final ProductEditForm form;
  final bool uploading;
  final VoidCallback onAddImages;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EditGroup(
          title: TKeys.editGroupBasics.tr,
          icon: Icons.sell_outlined,
          children: [
            EditTextField(label: TKeys.fieldNameRequired.tr, controller: form['name']),
            EditTextField(label: TKeys.fieldBrand.tr, controller: form['brand']),
            EditTextField(
              label: TKeys.fieldTaxonomy.tr,
              controller: form['taxonomyNodeId'],
              helper: TKeys.fieldTaxonomyHelp.tr,
            ),
          ],
        ),
        EditGroup(
          title: TKeys.editGroupDescriptions.tr,
          icon: Icons.notes_rounded,
          children: [
            EditTextField(
              label: TKeys.fieldShortDescription.tr,
              controller: form['shortDescription'],
              maxLines: 3,
            ),
            EditTextField(
              label: TKeys.fieldDescription.tr,
              controller: form['description'],
              maxLines: 8,
            ),
          ],
        ),
        EditGroup(
          title: TKeys.fieldImages.tr,
          icon: Icons.photo_library_outlined,
          subtitle: TKeys.upToPhotos
              .trParams({'max': '${ProductEditForm.maxImages}'}),
          children: [
            ImageGalleryEditor(
              images: form.images,
              uploading: uploading,
              onAdd: onAddImages,
              onRemove: form.removeImageAt,
            ),
            const SizedBox(height: 10),
            if (form.imagesChanged) EditNote(TKeys.savingReplacesGallery.tr),
            const SizedBox(height: 10),
          ],
        ),
      ],
    );
  }
}
