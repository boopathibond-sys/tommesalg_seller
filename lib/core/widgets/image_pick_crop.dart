import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';
import 'custom_text.dart';

/// Asks where the photo should come from, then lets the seller frame it.
///
/// Without the crop step the picked photo is squeezed into whatever frame the
/// UI uses (`BoxFit.cover`), so faces get cut off and the seller has no say in
/// it. This runs gallery/camera → uCrop (Android) / TOCropViewController (iOS)
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
  final source = await _askSource(context, title);
  if (source == null) return null;

  final picked = await ImagePicker().pickImage(
    source: source,
    // Cap the input, but stay generous — the cropper output is what we upload.
    maxWidth: maxWidth.toDouble(),
    imageQuality: 95,
  );
  if (picked == null) return null;

  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
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

/// Gallery / camera chooser. Returns null when dismissed.
Future<ImageSource?> _askSource(BuildContext context, String title) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.inputBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CustomText(title, fontSize: 16,
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
          ),
          _SourceTile(
            icon: Icons.photo_library_outlined,
            label: 'Choose from gallery',
            onTap: () => Navigator.of(sctx).pop(ImageSource.gallery),
          ),
          _SourceTile(
            icon: Icons.photo_camera_outlined,
            label: 'Take a photo',
            onTap: () => Navigator.of(sctx).pop(ImageSource.camera),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppColors.brandNavy),
        title: CustomText(label, fontSize: 15,
            fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      );
}
