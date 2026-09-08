import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/localization/translation_keys.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../controllers/auction_room_controller.dart';
import '../../data/models/seller_camera_option.dart';

/// The camera / lens picker, opened from the room's "⋮" menu.
///
/// Lists only what the handset reported — one phone shows Back + Front, an
/// iPhone Pro shows Back, Wide, Ultra Wide, Telephoto and Front. Selecting
/// reconfigures local capture only: the seller stays in the same stream, on the
/// same Agora channel, with the auction running underneath.
Future<void> showCameraSelectorSheet(
  BuildContext context,
  AuctionRoomController ctrl,
) {
  // Re-query on open so a seller who denied camera access on the first attempt,
  // then granted it, doesn't get a permanently empty list.
  if (ctrl.cameraOptions.isEmpty) {
    ctrl.refreshCameraCapabilities();
  }
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SafeArea(child: _CameraSelectorSheet(ctrl: ctrl)),
  );
}

class _CameraSelectorSheet extends StatelessWidget {
  const _CameraSelectorSheet({required this.ctrl});

  // Passed in rather than looked up: the room controller is registered under a
  // per-stream tag, so a bare Get.find would miss it.
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.inputBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Icon(Icons.camera_alt_rounded,
                  size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              CustomText(TKeys.cameraSource.tr,
                  fontSize: 16, fontWeight: FontWeight.w800),
              const Spacer(),
              // A lens change while switching is dropped, so the spinner is the
              // honest signal that further taps do nothing yet.
              Obx(() => ctrl.cameraSwitching.value
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const SizedBox.shrink()),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Obx(() {
          final options = ctrl.cameraOptions;
          if (options.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: CustomText(TKeys.csNoCameras.tr,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary),
            );
          }
          final selected = ctrl.selectedCamera.value;
          final switching = ctrl.cameraSwitching.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                _CameraRow(
                  option: option,
                  selected: selected?.mode == option.mode,
                  disabled: switching,
                  onTap: () => ctrl.selectCamera(option),
                ),
            ],
          );
        }),
        // Switching / failure notice. Never phrased as a broadcast error: the
        // stream is still up on the previous lens either way.
        Obx(() {
          final switching = ctrl.cameraSwitching.value;
          final error = ctrl.cameraError.value;
          if (!switching && error == null) return const SizedBox(height: 6);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Row(
              children: [
                Icon(
                  switching
                      ? Icons.sync_rounded
                      : Icons.info_outline_rounded,
                  size: 15,
                  color: switching ? AppColors.textSecondary : AppColors.vipps,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomText(
                    switching ? TKeys.csSwitching.tr : error!,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        switching ? AppColors.textSecondary : AppColors.vipps,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _CameraRow extends StatelessWidget {
  const _CameraRow({
    required this.option,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final SellerCameraOption option;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: disabled ? null : onTap,
      enabled: !disabled,
      leading: Icon(
        option.mode == SellerCameraMode.front
            ? Icons.person_rounded
            : Icons.camera_rear_rounded,
        color: selected ? AppColors.brandNavy : AppColors.textSecondary,
      ),
      title: CustomText(
        option.label,
        fontSize: 15,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
        color: disabled && !selected
            ? AppColors.textMuted
            : AppColors.textPrimary,
      ),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.brandNavy)
          : null,
    );
  }
}
