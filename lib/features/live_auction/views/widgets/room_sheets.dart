import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../controllers/auction_room_controller.dart';
import '../../data/models/pre_bid.dart';
import '../../data/models/session_device.dart';
import '../media_push_view.dart';
import '../../../../core/localization/translation_keys.dart';

String _kr(num? v) => v == null ? '—' : 'kr ${v % 1 == 0 ? v.toInt() : v}';

// ── Room overflow actions ────────────────────────────────────────────────────

/// The room "⋮" menu: multi-device control, orders, Media Push, extend /
/// end / cancel.
Future<void> showRoomActions(BuildContext context, AuctionRoomController ctrl) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.inputBorder,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 6),
          _Tile(
            icon: Icons.devices_rounded,
            label: TKeys.rsDevicesControl.tr,
            onTap: () {
              Navigator.of(sctx).pop();
              showDevicesSheet(context, ctrl);
            },
          ),
          _Tile(
            icon: Icons.receipt_long_rounded,
            label: TKeys.ordersLabel.tr,
            onTap: () {
              Navigator.of(sctx).pop();
              showOrdersSheet(context, ctrl);
            },
          ),
          _Tile(
            icon: Icons.podcasts_rounded,
            label: TKeys.rsMediaPush.tr,
            subtitle: _mediaPushSubtitle(ctrl),
            onTap: () {
              Navigator.of(sctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MediaPushView(room: ctrl),
                ),
              );
            },
          ),
          _Tile(
            icon: Icons.campaign_rounded,
            label: TKeys.rsStreamAnnouncement.tr,
            subtitle: ctrl.announcement.value ?? TKeys.rsNoActiveAnnouncement.tr,
            onTap: () {
              Navigator.of(sctx).pop();
              showAnnouncementSheet(context, ctrl);
            },
          ),
          _Tile(
            icon: Icons.more_time_rounded,
            label: TKeys.rsExtendStream.tr,
            subtitle: _endsAtSubtitle(ctrl),
            onTap: () {
              Navigator.of(sctx).pop();
              showExtendDialog(context, ctrl);
            },
          ),
          const Divider(height: 8),
          _Tile(
            icon: Icons.stop_circle_outlined,
            label: TKeys.rsEndStream.tr,
            color: AppColors.vipps,
            onTap: () async {
              Navigator.of(sctx).pop();
              if (await _confirm(context, TKeys.rsEndStreamTitle.tr,
                  TKeys.rsEndStreamBody.tr, TKeys.rsEnd.tr)) {
                await ctrl.endStream();
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Sub-line for the Media Push tile — what the seller can expect to do on the
/// screen before they open it.
String _mediaPushSubtitle(AuctionRoomController ctrl) {
  if (!ctrl.isLive) return TKeys.rsSetupPlatforms.tr;
  return ctrl.isPrimaryDevice
      ? TKeys.rsRestreamToOthers.tr
      : TKeys.rsViewOnlyPrimary.tr;
}

/// "Ends 15:30 · 42 min left" for the ⋮ menu, or the planned length while the
/// stream hasn't started yet. Null when the room has no timing at all.
String? _endsAtSubtitle(AuctionRoomController ctrl) {
  final endsAt = ctrl.endsAtLabel;
  final left = ctrl.remaining;
  if (endsAt != null && left != null && !left.isNegative) {
    final mins = left.inMinutes;
    return TKeys.rsEndsAtLeft.trParams({
      'endsAt': endsAt,
      'left': mins < 1
          ? TKeys.rsUnderAMinute.tr
          : TKeys.rsMinsShort.trParams({'count': '$mins'}),
    });
  }
  final planned = ctrl.stream?.streamDurationMinutes;
  return planned == null
      ? null
      : TKeys.rsPlannedLength.trParams({'count': '$planned'});
}

// ── Stream announcement ──────────────────────────────────────────────────────

/// The announcement editor: the message buyers see in the stream banner.
/// Mobile take on the web card — a keyboard-aware bottom sheet rather than a
/// fixed panel, so the composer stays visible while typing on a phone.
Future<void> showAnnouncementSheet(
  BuildContext context,
  AuctionRoomController ctrl,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AnnouncementSheet(ctrl: ctrl),
  );
}

class _AnnouncementSheet extends StatefulWidget {
  const _AnnouncementSheet({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  State<_AnnouncementSheet> createState() => _AnnouncementSheetState();
}

class _AnnouncementSheetState extends State<_AnnouncementSheet> {
  late final TextEditingController _text =
      TextEditingController(text: widget.ctrl.announcement.value ?? '');

  AuctionRoomController get ctrl => widget.ctrl;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (await ctrl.saveAnnouncement(_text.text) && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _end() async {
    FocusScope.of(context).unfocus();
    if (await ctrl.endAnnouncement() && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The composer scales with the screen but never eats the sheet: roughly
    // four lines on a small phone, a little more on a tall one.
    final fieldHeight = (media.size.height * 0.16).clamp(96.0, 180.0);

    return Padding(
      // Lift the whole sheet above the keyboard.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHeader(title: TKeys.rsStreamAnnouncement.tr),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Obx(() => _AnnouncementStatus(
                            announcement: ctrl.announcement.value,
                          )),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: fieldHeight,
                        child: TextField(
                          controller: _text,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                TKeys.rsWriteBannerMessage.tr,
                            hintStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textMuted,
                            ),
                            filled: true,
                            fillColor: AppColors.inputFill,
                            contentPadding: const EdgeInsets.all(14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: AppColors.inputBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: AppColors.inputBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: AppColors.brandNavy, width: 1.4),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const CustomText(
                        'The announcement can only be managed while the stream '
                        'is live.',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      Obx(() {
                        final live = ctrl.isLive;
                        final busy = ctrl.announcementSaving.value;
                        final hasActive = ctrl.announcement.value != null;
                        return Row(
                          children: [
                            Expanded(
                              child: _SheetButton(
                                label: TKeys.stSaveAction.tr,
                                loading: busy,
                                enabled: live &&
                                    !busy &&
                                    _text.text.trim().isNotEmpty,
                                onTap: _save,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SheetButton(
                                label: TKeys.rsEnd.tr,
                                filled: false,
                                enabled: live && !busy && hasActive,
                                onTap: _end,
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Ingen aktiv annonsering" equivalent: either the live banner text or a
/// muted note that nothing is showing.
class _AnnouncementStatus extends StatelessWidget {
  const _AnnouncementStatus({required this.announcement});
  final String? announcement;

  @override
  Widget build(BuildContext context) {
    if (announcement == null) {
      return CustomText(
        TKeys.rsNoActiveAnnouncementDot.tr,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandYellow.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.campaign_rounded, size: 18, color: AppColors.brandNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(TKeys.rsShowingToBuyers.tr,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted),
                const SizedBox(height: 3),
                CustomText(announcement!,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: AppColors.textPrimary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Filled (primary) / outlined (secondary) sheet action, with a disabled state
/// that reads as unavailable rather than broken.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.loading = false,
    this.filled = true,
  });
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool loading;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final off = !enabled || loading;
    return Opacity(
      opacity: off ? 0.5 : 1,
      child: GestureDetector(
        onTap: off ? null : onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? AppColors.brandNavy : AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: filled
                ? null
                : Border.all(color: AppColors.brandNavy, width: 1.4),
          ),
          child: loading && filled
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(AppColors.white)),
                )
              : CustomText(label,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: filled ? AppColors.white : AppColors.brandNavy),
        ),
      ),
    );
  }
}

/// Raised automatically when the stream is [minutesLeft] minutes from ending.
/// One tap extends — quick presets only, since there's no time to fiddle with a
/// slider — and "Not now" leaves it alone until the next warning.
Future<void> showEndingSoonDialog(
  BuildContext context,
  AuctionRoomController ctrl, {
  required int minutesLeft,
}) async {
  final minutes = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (dctx) => AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.timer_outlined, color: AppColors.vipps, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: CustomText(
              minutesLeft <= 1
              ? TKeys.rsEndingInAMinute.tr
              : TKeys.rsEndingInMin.trParams({'count': '$minutesLeft'}),
              fontSize: 18, fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
      content: const CustomText(
        'Your live stream is about to end and buyers will be disconnected. '
        'Add more time to keep going.',
        fontSize: 14, fontWeight: FontWeight.w500, height: 1.4,
        color: AppColors.textSecondary,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      actions: [
        Row(
          children: [
            for (final m in const [15, 30, 60]) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(dctx).pop(m),
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.brandNavy,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CustomText(
                        TKeys.rsPlusMin.trParams({'count': '$m'}),
                        fontSize: 13,
                        fontWeight: FontWeight.w800, color: AppColors.white),
                  ),
                ),
              ),
              if (m != 60) const SizedBox(width: 8),
            ],
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: CustomText(TKeys.rsNotNow.tr, fontSize: 13.5,
                fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );
  if (minutes != null) await ctrl.extendStream(minutes);
}

Future<void> showExtendDialog(BuildContext context, AuctionRoomController ctrl) async {
  final minutes = await showDialog<int>(
    context: context,
    builder: (dctx) => _ExtendDialog(ctrl: ctrl),
  );
  if (minutes != null) await ctrl.extendStream(minutes);
}

class _ExtendDialog extends StatefulWidget {
  const _ExtendDialog({required this.ctrl});
  final AuctionRoomController ctrl;
  @override
  State<_ExtendDialog> createState() => _ExtendDialogState();
}

class _ExtendDialogState extends State<_ExtendDialog> {
  double _minutes = 30;

  /// Where the slider lands the stream: current end + the chosen minutes.
  String? get _newEndLabel {
    final end = widget.ctrl.endsAt;
    if (end == null) return null;
    final next = end.add(Duration(minutes: _minutes.round())).toLocal();
    return '${next.hour.toString().padLeft(2, '0')}:'
        '${next.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final endsAt = widget.ctrl.endsAtLabel;
    final newEnd = _newEndLabel;
    return AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: CustomText(TKeys.rsExtendStream.tr, fontSize: 18,
          fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (endsAt != null && newEnd != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: CustomText(
                TKeys.rsEndsArrow.trParams({'from': endsAt, 'to': newEnd}),
                fontSize: 13,
                  fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
          CustomText(
              TKeys.rsPlusMinutes.trParams({'count': '${_minutes.round()}'}),
              fontSize: 22,
              fontWeight: FontWeight.w800, color: AppColors.brandNavy),
          Slider(
            value: _minutes, min: 5, max: 120, divisions: 23,
            activeColor: AppColors.brandNavy,
            label: '${_minutes.round()}',
            onChanged: (v) => setState(() => _minutes = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: CustomText(TKeys.cancelAction.tr, fontSize: 14,
              fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_minutes.round()),
          child: CustomText(TKeys.rsExtend.tr, fontSize: 14,
              fontWeight: FontWeight.w800, color: AppColors.brandNavy),
        ),
      ],
    );
  }
}

// ── Devices & control ────────────────────────────────────────────────────────

Future<void> showDevicesSheet(BuildContext context, AuctionRoomController ctrl) {
  ctrl.loadDevices();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.9, expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _SheetHeader(title: TKeys.rsDevicesControl.tr),
            Expanded(
              child: Obx(() {
                final myDeviceId = ctrl.session.value?.deviceId;
                final controllerId = ctrl.auctionControllerDeviceId.value;

                // A request is only actionable by the device that currently
                // holds the matching role — and never by the device that made
                // it. Ours shows as "waiting" instead of approve/reject.
                List<ControlRequest> mine(List<ControlRequest> rs) =>
                    rs.where((r) => r.deviceId == myDeviceId).toList();
                List<ControlRequest> others(List<ControlRequest> rs) =>
                    rs.where((r) => r.deviceId != myDeviceId).toList();

                final myPrimaryReq = mine(ctrl.pendingPrimaryRequests);
                final otherPrimaryReqs = others(ctrl.pendingPrimaryRequests);
                final myControlReq = mine(ctrl.pendingControlRequests);
                final otherControlReqs = others(ctrl.pendingControlRequests);
                final devices = ctrl.devices;

                return ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    // ── Main device (PRIMARY) ─────────────────────────────
                    _SectionLabel(TKeys.cdMainDevice.tr),
                    if (!ctrl.isPrimaryDevice)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: myPrimaryReq.isEmpty
                            ? _WideButton(
                                label: TKeys.rsRequestMainDevice.tr,
                                icon: Icons.smartphone_rounded,
                                onTap: ctrl.requestPrimary,
                              )
                            : _WaitingRow(
                                label:
                                    TKeys.rsWaitingMainApproval.tr,
                              ),
                      ),
                    // Only the PRIMARY device may answer a PRIMARY request.
                    if (ctrl.isPrimaryDevice)
                      otherPrimaryReqs.isEmpty
                          ? _EmptyNote(TKeys.rsNoMainRequests.tr)
                          : Column(
                              children: otherPrimaryReqs
                                  .map((r) => _PendingRow(
                                        deviceId: r.deviceId,
                                        label: TKeys.rsWantsMainDevice.tr,
                                        onApprove: () =>
                                            ctrl.approvePrimary(r.requestId),
                                        onReject: () =>
                                            ctrl.rejectPrimary(r.requestId),
                                      ))
                                  .toList(),
                            ),
                    const SizedBox(height: 16),

                    // ── Auction control ───────────────────────────────────
                    _SectionLabel(TKeys.rsAuctionControl.tr),
                    if (!ctrl.isController)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: myControlReq.isEmpty
                            ? _WideButton(
                                label: TKeys.rsRequestAuctionControl.tr,
                                icon: Icons.pan_tool_alt_rounded,
                                onTap: ctrl.requestAuctionControl,
                              )
                            : _WaitingRow(
                                label:
                                    TKeys.rsWaitingControlApproval.tr,
                              ),
                      ),
                    if (ctrl.isController)
                      otherControlReqs.isEmpty
                          ? _EmptyNote(TKeys.rsNoControlRequests.tr)
                          : Column(
                              children: otherControlReqs
                                  .map((r) => _PendingRow(
                                        deviceId: r.deviceId,
                                        label: TKeys.rsWantsAuctionControl.tr,
                                        onApprove: () =>
                                            ctrl.approveControl(r.requestId),
                                        onReject: () =>
                                            ctrl.rejectControl(r.requestId),
                                      ))
                                  .toList(),
                            ),
                    const SizedBox(height: 16),

                    _SectionLabel(TKeys.rsConnectedDevices.tr),
                    if (devices.isEmpty)
                      _EmptyNote(TKeys.rsNoDevicesReported.tr),
                    ...devices.map((d) => _DeviceRow(
                          deviceId: d.deviceId,
                          role: d.role ?? 'SECONDARY',
                          hasControl: d.deviceId == controllerId,
                          isThisDevice: d.deviceId == myDeviceId,
                        )),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shown on the *requesting* device while its own request is outstanding —
/// deliberately without approve/reject, since only the controlling device may
/// answer it.
class _WaitingRow extends StatelessWidget {
  const _WaitingRow({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandYellow.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: CustomText(
              label,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Muted placeholder for a section with nothing in it.
class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: CustomText(text,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.deviceId,
    required this.label,
    required this.onApprove,
    required this.onReject,
  });
  final String deviceId;

  /// What the requesting device is asking for, e.g. "wants auction control".
  final String label;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.brandYellow.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: CustomText(
              TKeys.rsDeviceNamedRole
                  .trParams({'id': _short(deviceId), 'role': label}),
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          IconButton(
            onPressed: onReject,
            icon: const Icon(Icons.close_rounded, color: AppColors.vipps),
          ),
          IconButton(
            onPressed: onApprove,
            icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32)),
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.deviceId,
    required this.role,
    required this.hasControl,
    required this.isThisDevice,
  });
  final String deviceId;
  final String role;
  final bool hasControl;
  final bool isThisDevice;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.smartphone_rounded, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CustomText(
                TKeys.rsDeviceNamed.trParams({'id': _short(deviceId)}),
                fontSize: 13.5,
                        fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    if (isThisDevice) ...[
                      const SizedBox(width: 6),
                      CustomText(TKeys.rsThisDevice.tr, fontSize: 11,
                          fontWeight: FontWeight.w600, color: AppColors.textMuted),
                    ],
                  ],
                ),
                CustomText(role, fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppColors.textMuted),
              ],
            ),
          ),
          if (hasControl)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomText(TKeys.rsControlCaps.tr, fontSize: 9.5,
                  fontWeight: FontWeight.w800, color: const Color(0xFF2E7D32)),
            ),
        ],
      ),
    );
  }
}

// ── Orders ───────────────────────────────────────────────────────────────────

Future<void> showOrdersSheet(BuildContext context, AuctionRoomController ctrl) {
  ctrl.loadOrders();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.65, minChildSize: 0.4, maxChildSize: 0.92, expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _SheetHeader(title: TKeys.rsStreamOrders.tr),
            Expanded(
              child: Obx(() {
                if (ctrl.loadingOrders.value && ctrl.orders.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(AppColors.brandNavy)),
                  );
                }
                final orders = ctrl.orders;
                if (orders.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: CustomText(TKeys.rsNoOrdersYetDot.tr,
                          fontSize: 13, fontWeight: FontWeight.w500,
                          color: AppColors.textMuted),
                    ),
                  );
                }
                return ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final o = orders[i];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.inputBorder),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 44, height: 44, color: AppColors.inputFill,
                              child: o.image != null
                                  ? Image.network(o.image!, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                          Icons.image_outlined, color: AppColors.textMuted))
                                  : const Icon(Icons.shopping_bag_outlined,
                                      color: AppColors.textMuted),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CustomText(o.productTitle ?? TKeys.rsOrder.tr, fontSize: 14,
                                    fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                CustomText(
                                  '${o.buyerName ?? TKeys.saBuyer.tr}${o.status != null ? ' · ${o.status}' : ''}',
                                  fontSize: 12, fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          CustomText(_kr(o.amount), fontSize: 14,
                              fontWeight: FontWeight.w800, color: AppColors.brandNavy),
                        ],
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Pre-bids ─────────────────────────────────────────────────────────────────

Future<void> showPreBidsSheet(
  BuildContext context,
  AuctionRoomController ctrl, {
  required String productId,
  required String productTitle,
}) {
  final future = ctrl.fetchPreBids(productId);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.55, minChildSize: 0.35, maxChildSize: 0.9, expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _SheetHeader(
                  title: TKeys.rsPreBidsFor.trParams({'title': productTitle})),
            Expanded(
              child: FutureBuilder<List<PreBid>>(
                future: future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(AppColors.brandNavy)),
                    );
                  }
                  final bids = snap.data ?? const [];
                  if (bids.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: CustomText(TKeys.rsNoPreBids.tr,
                            fontSize: 13, fontWeight: FontWeight.w500,
                            color: AppColors.textMuted),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: bids.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final b = bids[i];
                      return Row(
                        children: [
                          const Icon(Icons.person_outline_rounded,
                              size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: CustomText(b.displayName ?? TKeys.saBuyer.tr, fontSize: 14,
                                fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                          CustomText(_kr(b.amount), fontSize: 14,
                              fontWeight: FontWeight.w800, color: AppColors.brandNavy),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Shared bits ──────────────────────────────────────────────────────────────

Future<bool> _confirm(
  BuildContext context,
  String title,
  String body,
  String confirmLabel,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: CustomText(title, fontSize: 18,
          fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      content: CustomText(body, fontSize: 14, fontWeight: FontWeight.w500,
          height: 1.4, color: AppColors.textSecondary),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: CustomText(TKeys.rsBack.tr, fontSize: 14,
              fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(true),
          child: CustomText(confirmLabel, fontSize: 14,
              fontWeight: FontWeight.w800, color: AppColors.vipps),
        ),
      ],
    ),
  );
  return ok == true;
}

String _short(String id) => id.length > 6 ? id.substring(0, 6) : id;

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.inputBorder,
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: CustomText(title, fontSize: 18,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: CustomText(text, fontSize: 12,
            fontWeight: FontWeight.w800, color: AppColors.textMuted),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.color = AppColors.textPrimary,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color),
        title: CustomText(label, fontSize: 15, fontWeight: FontWeight.w700, color: color),
        subtitle: subtitle == null
            ? null
            : CustomText(subtitle!, fontSize: 12, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
      );
}

class _WideButton extends StatelessWidget {
  const _WideButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brandNavy, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.brandYellow),
            const SizedBox(width: 8),
            CustomText(label, fontSize: 14,
                fontWeight: FontWeight.w800, color: AppColors.white),
          ],
        ),
      ),
    );
  }
}

// ── Incoming control request banner ──────────────────────────────────────────

/// Floating prompt shown on the Live tab when another device is waiting on
/// *this* one to approve a handoff.
///
/// Without it a request is only visible inside the Devices sheet, so a seller
/// who never opens that sheet — the normal case while broadcasting — silently
/// leaves the other device hanging. Covers both handoff systems: the PRIMARY
/// request takes precedence, since it reassigns the main device.
class ControlRequestBanner extends StatelessWidget {
  const ControlRequestBanner({super.key, required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final primary = ctrl.incomingPrimaryRequest.value;
      final control = ctrl.incomingControlRequest.value;
      final req = primary ?? control;
      if (req == null) return const SizedBox.shrink();

      final isPrimaryRequest = primary != null;
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.brandNavy,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.pan_tool_alt_rounded,
                size: 20, color: AppColors.brandYellow),
            const SizedBox(width: 10),
            Expanded(
              child: CustomText(
                isPrimaryRequest
                    ? TKeys.rsDeviceWantsMain
                        .trParams({'id': _short(req.deviceId)})
                    : TKeys.rsDeviceWantsControl
                        .trParams({'id': _short(req.deviceId)}),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: AppColors.white,
              ),
            ),
            IconButton(
              tooltip: TKeys.rsReject.tr,
              onPressed: () => isPrimaryRequest
                  ? ctrl.rejectPrimary(req.requestId)
                  : ctrl.rejectControl(req.requestId),
              icon: const Icon(Icons.close_rounded,
                  size: 22, color: AppColors.white),
            ),
            IconButton(
              tooltip: TKeys.rsApprove.tr,
              onPressed: () => isPrimaryRequest
                  ? ctrl.approvePrimary(req.requestId)
                  : ctrl.approveControl(req.requestId),
              icon: const Icon(Icons.check_circle_rounded,
                  size: 24, color: Color(0xFF7BD88F)),
            ),
          ],
        ),
      );
    });
  }
}
