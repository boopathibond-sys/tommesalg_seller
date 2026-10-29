import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

import '../theme/app_colors.dart';
import 'image_source_picker.dart';

/// Asks where the photo should come from, then lets the seller frame it.
///
/// Without the crop step the picked photo is squeezed into whatever frame the
/// UI uses (`BoxFit.cover`), so faces get cut off and the seller has no say in
/// it. This runs gallery/camera (see [ImageSourcePicker]) → uCrop (Android) / TOCropViewController (iOS)
/// → returns the cropped file path, or null if the seller backed out at any
/// step.
///
/// [aspectRatio] locks the crop box to the frame the image will be shown in, so
/// what you frame is what gets displayed. Pass [circle] for avatars.
Future<String?> pickAndCropImage(
  BuildContext context, {
  required String title,
  required CropAspectRatio aspectRatio,
  bool circle = false,
  int maxWidth = 2000,
}) async {
  // Shared Camera / Gallery chooser — camera opens the in-app pro camera.
  final picked = await ImageSourcePicker.pickOne(context, title: title);
  if (picked == null) return null;

  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    maxWidth: maxWidth,
    maxHeight: maxWidth,
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 90,
    aspectRatio: aspectRatio,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: title,
        toolbarColor: AppColors.brandNavy,
        toolbarWidgetColor: AppColors.white,
        backgroundColor: AppColors.brandNavy,
        activeControlsWidgetColor: AppColors.brandYellow,
        cropStyle: circle ? CropStyle.circle : CropStyle.rectangle,
        initAspectRatio: CropAspectRatioPreset.original,
        // The frame is fixed, so the ratio presets would only let the seller
        // pick a shape we'd crop away again on display.
        lockAspectRatio: true,
        hideBottomControls: false,
        statusBarLight: false,
      ),
      IOSUiSettings(
        title: title,
        cropStyle: circle ? CropStyle.circle : CropStyle.rectangle,
        aspectRatioLockEnabled: true,
        aspectRatioPickerButtonHidden: true,
        resetAspectRatioEnabled: false,
        rotateButtonsHidden: false,
      ),
    ],
  );
  return cropped?.path;
}
