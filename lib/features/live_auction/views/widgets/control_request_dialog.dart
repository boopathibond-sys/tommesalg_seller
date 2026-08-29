import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../controllers/auction_room_controller.dart';
import '../../data/models/session_device.dart';
import '../../../../core/localization/translation_keys.dart';

/// Modal prompt raised when another device asks *this* one for a handoff.
///
/// A snackbar used to carry this, but it auto-dismisses and carries no action —
/// a seller mid-broadcast would miss it and leave the other device hanging.
/// This states who is asking, when they asked, and what saying yes costs, with
/// Decline / Accept on the spot.
///
/// Covers both handoff systems (PRIMARY and auction control); [isPrimaryRequest]
/// picks the wording *and* which pair of controller methods answer it — the two
/// request-id spaces are not interchangeable.
///
/// Dismissing by tapping outside leaves the request pending, still visible as
/// the Live-tab banner, so the seller is never trapped by it mid-auction.
Future<void> showControlRequestDialog({
  required AuctionRoomController ctrl,
  required ControlRequest request,
  required bool isPrimaryRequest,
}) {
  return Get.dialog<void>(
    _ControlRequestDialog(
      ctrl: ctrl,
      request: request,
      isPrimaryRequest: isPrimaryRequest,
    ),
    barrierColor: AppColors.brandNavy.withOpacity(0.55),
  );
}

class _ControlRequestDialog extends StatelessWidget {
  const _ControlRequestDialog({
    required this.ctrl,
    required this.request,
    required this.isPrimaryRequest,
  });

  final AuctionRoomController ctrl;
  final ControlRequest request;
  final bool isPrimaryRequest;

  /// Role reported for the asking device, when it's in the session list.
  String? get _askingRole {
    for (final d in ctrl.devices) {
      if (d.deviceId == request.deviceId) {
        return d.isPrimary ? TKeys.cdMainDevice.tr : TKeys.cdSecondaryDevice.tr;
      }
    }
    return null;
  }

  void _answer(bool accept) {
    // Close first: both calls hit the network and refresh the snapshot, and the
    // prompt has already done its job once the seller has decided.
    if (Get.isDialogOpen ?? false) Get.back<void>();
    if (isPrimaryRequest) {
      accept
          ? ctrl.approvePrimary(request.requestId)
          : ctrl.rejectPrimary(request.requestId);
    } else {
      accept
          ? ctrl.approveControl(request.requestId)
          : ctrl.rejectControl(request.requestId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = isPrimaryRequest
        ? TKeys.cdMainDeviceRequest.tr
        : TKeys.cdAuctionControlRequest.tr;
    final consequence = isPrimaryRequest
        ? 'Accepting makes that device the main device for this stream. This '
            'device drops to secondary and stops owning the session.'
        : 'Accepting hands the auction over to that device — it will run the '
            'bidding and the queue, and this device will have to ask for '
            'control back.';

    return Dialog(
      backgroundColor: AppColors.white,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryBlue.withOpacity(0.10),
                  border: Border.all(
                    color: AppColors.primaryBlue.withOpacity(0.18),
                  ),
                ),
                child: const Icon(Icons.pan_tool_alt_rounded,
                    size: 28, color: AppColors.primaryBlue),
              ),
            ),
            const SizedBox(height: 16),

            CustomText(
              title,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              textAlign: TextAlign.center,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 8),

            CustomText(
              isPrimaryRequest
                  ? TKeys.cdAnotherDeviceMain.tr
                  : TKeys.cdAnotherDeviceControl.tr,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.45,
              textAlign: TextAlign.center,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),

            // The details block — who is asking and since when, so the seller
            // can tell their own second phone from someone else's.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.inputBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DetailRow(
                    icon: Icons.smartphone_rounded,
                    label: TKeys.cdDevice.tr,
                    value: _shortId(request.deviceId),
                  ),
                  if (_askingRole != null) ...[
                    const SizedBox(height: 8),
                    _DetailRow(
                      icon: Icons.badge_outlined,
                      label: TKeys.cdRole.tr,
                      value: _askingRole!,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _DetailRow(
                    icon: Icons.schedule_rounded,
                    label: TKeys.cdRequested.tr,
                    value: _requestedAgo(request.createdAt),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            CustomText(
              consequence,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.45,
              textAlign: TextAlign.center,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 20),

            // Decline sits quiet on the left, Accept as the filled CTA — the
            // same weighting the app's confirm dialog uses for a non-
            // destructive confirm.
            Row(
              children: [
                Expanded(
                  child: _Action(
                    label: TKeys.cdDecline.tr,
                    onTap: () => _answer(false),
                    background: AppColors.inputFill,
                    foreground: AppColors.textSecondary,
                    border: AppColors.textMuted.withOpacity(0.28),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Action(
                    label: TKeys.cdAccept.tr,
                    onTap: () => _answer(true),
                    background: AppColors.primaryBlue,
                    foreground: AppColors.white,
                    shadow: AppColors.primaryBlueDark.withOpacity(0.35),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        CustomText(label, fontSize: 12.5,
            fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        const Spacer(),
        Flexible(
          child: CustomText(
            value,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
    this.border,
    this.shadow,
  });

  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final Color? border;
  final Color? shadow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        boxShadow: shadow == null
            ? null
            : [BoxShadow(color: shadow!, blurRadius: 10,
                offset: const Offset(0, 4))],
      ),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: border == null ? null : Border.all(color: border!),
            ),
            child: CustomText(label, fontSize: 13,
                fontWeight: FontWeight.w800, maxLines: 1,
                overflow: TextOverflow.ellipsis, color: foreground),
          ),
        ),
      ),
    );
  }
}

String _shortId(String id) => id.length > 8 ? '${id.substring(0, 8)}…' : id;

/// "Just now" / "3 min ago" for the request timestamp; falls back to the raw
/// value when the server sends something we can't parse.
String _requestedAgo(String? createdAt) {
  if (createdAt == null || createdAt.isEmpty) return TKeys.cdJustNow.tr;
  final at = DateTime.tryParse(createdAt);
  if (at == null) return createdAt;
  final diff = DateTime.now().difference(at.toLocal());
  if (diff.inSeconds < 60) return TKeys.cdJustNow.tr;
  if (diff.inMinutes < 60) return TKeys.cdMinAgo.trParams({'count': '${diff.inMinutes}'});
  if (diff.inHours < 24) return TKeys.cdHoursAgo.trParams({'count': '${diff.inHours}'});
  return TKeys.cdDaysAgo.trParams({'count': '${diff.inDays}'});
}
