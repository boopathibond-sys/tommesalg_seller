import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/localization/translation_keys.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import '../product_edit_form.dart';

/// Horizontal gallery strip with per-photo remove and an "add" tile. The first
/// photo is the cover, so it is labelled as such.
class ImageGalleryEditor extends StatelessWidget {
  const ImageGalleryEditor({
    super.key,
    required this.images,
    required this.uploading,
    required this.onAdd,
    required this.onRemove,
  });

  final List<GalleryImage> images;
  final bool uploading;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  static const double _w = 96;
  static const double _h = 104;

  @override
  Widget build(BuildContext context) {
    final canAdd = images.length < ProductEditForm.maxImages;
    return SizedBox(
      height: _h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length + (canAdd ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) =>
            i == images.length ? _addTile() : _photo(i, images[i]),
      ),
    );
  }

  Widget _addTile() {
    return GestureDetector(
      onTap: uploading ? null : onAdd,
      child: Container(
        width: _w,
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderGrey),
        ),
        child: uploading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo_outlined,
                      color: AppColors.brandNavy, size: 22),
                  const SizedBox(height: 6),
                  CustomText(TKeys.addAction.tr,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandNavy),
                ],
              ),
      ),
    );
  }

  Widget _photo(int index, GalleryImage image) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: _w,
            height: _h,
            color: AppColors.inputFill,
            child: _thumb(image),
          ),
        ),
        if (index == 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.brandYellow,
                borderRadius: BorderRadius.circular(6),
              ),
              child: CustomText(TKeys.editCoverPhoto.tr,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => onRemove(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _thumb(GalleryImage image) {
    const fallback = Center(
      child: Icon(Icons.image_not_supported_outlined,
          color: AppColors.textMuted, size: 22),
    );
    final local = image.localPath;
    if (local != null) {
      return Image.file(File(local),
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
    }
    final url = image.display;
    if (url == null || !url.startsWith('http')) return fallback;
    return Image.network(url,
        fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
  }
}
