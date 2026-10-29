import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../localization/translation_keys.dart';
import '../theme/app_colors.dart';
import 'custom_text.dart';
import 'pro_camera_screen.dart';

/// The one place the app asks "Camera or Gallery?" and fetches the photos.
///
/// Camera always opens the in-app [ProCameraScreen] (lenses, flash, exposure,
/// focus lock, zoom, grid, timer) rather than the bare system capture. Gallery
/// re-encodes on the way in, so iPhone HEIC shots come back as JPEG and stay
/// under the upload endpoints' 5 MB cap.
class ImageSourcePicker {
  ImageSourcePicker._();

  static final ImagePicker _picker = ImagePicker();

  /// Shows the Camera / Gallery sheet and resolves with the picked photos —
  /// empty when the seller backs out at any step.
  ///
  /// [maxImages] is how many more photos the caller can take. With
  /// [multiple] false only a single photo is ever returned.
  static Future<List<XFile>> pick(
    BuildContext context, {
    int maxImages = 10,
    bool multiple = true,
    String? title,
  }) async {
    final room = multiple ? maxImages : 1;
    if (room <= 0) return const [];

    final source = await chooseSource(context, title: title);
    if (source == null || !context.mounted) return const [];

    if (source == ImageSource.camera) {
      return ProCameraScreen.capture(context, maxPhotos: room);
    }

    if (room == 1) {
      final shot = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4000,
        maxHeight: 4000,
        imageQuality: 90,
      );
      return shot == null ? const [] : [shot];
    }

    final picked = await _picker.pickMultiImage(
      maxWidth: 4000,
      maxHeight: 4000,
      imageQuality: 90,
      limit: room,
    );
    return picked.length > room ? picked.take(room).toList() : picked;
  }

  /// Single-photo convenience over [pick].
  static Future<XFile?> pickOne(BuildContext context, {String? title}) async {
    final picked = await pick(context, multiple: false, title: title);
    return picked.isEmpty ? null : picked.first;
  }

  /// Bottom sheet offering Camera or Gallery. Returns null when dismissed.
  static Future<ImageSource?> chooseSource(
    BuildContext context, {
    String? title,
  }) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.inputBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (title != null && title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CustomText(
                    title,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              )
            else
              const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.brandNavy),
              title: CustomText(TKeys.cameraSource.tr,
                  fontSize: 15, fontWeight: FontWeight.w700),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.brandNavy),
              title: CustomText(TKeys.gallerySource.tr,
                  fontSize: 15, fontWeight: FontWeight.w700),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
