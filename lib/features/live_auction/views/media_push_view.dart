import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../controllers/auction_room_controller.dart';
import '../controllers/media_push_controller.dart';
import '../data/models/media_push.dart';
import '../../../core/localization/translation_keys.dart';

/// Media Push screen — restream the live auction to TikTok, Facebook,
/// Instagram, YouTube or a custom RTMP target.
///
/// Opened from the auction room's ⋮ menu. The room owns the seller session, so
/// this page only reads PRIMARY / LIVE off it and drives `/media-push`:
/// destinations (PATCH), start (POST), stop (DELETE) and the status poll (GET).
class MediaPushView extends StatefulWidget {
  const MediaPushView({super.key, required this.room});

  final AuctionRoomController room;

  @override
  State<MediaPushView> createState() => _MediaPushViewState();
}

class _MediaPushViewState extends State<MediaPushView> {
  late final MediaPushController ctrl;

  /// Tag keeps one controller per stream, so two rooms can't share polls.
  String get _tag => 'media-push-${widget.room.streamId}';

  @override
  void initState() {
    super.initState();
    ctrl = Get.put(MediaPushController(room: widget.room), tag: _tag);
  }

  @override
  void dispose() {
    Get.delete<MediaPushController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: CustomText(
          TKeys.mpMediaPush.tr,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        actions: [
          Obx(() => IconButton(
                tooltip: TKeys.refreshAction.tr,
                onPressed: ctrl.refreshing.value ? null : () => ctrl.load(),
                icon: ctrl.refreshing.value
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.brandNavy),
                        ),
                      )
                    : const Icon(Icons.refresh_rounded,
                        color: AppColors.textPrimary),
              )),
          Obx(() {
            if (ctrl.converters.isEmpty) return const SizedBox.shrink();
            return PopupMenuButton<String>(
              tooltip: TKeys.mpMore.tr,
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textPrimary),
              onSelected: (value) {
                if (value == 'restart') _confirmRestart();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'restart',
                  child: CustomText(TKeys.mpRestartConverters.tr,
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            );
          }),
        ],
      ),
      body: Obx(() {
        // GetX only tracks Rx reads made *inside* this builder — a child
        // widget builds in its own element, outside the observer — so every
        // flag the cards below render from is read here and passed down.
        final starting = ctrl.starting.value;
        final stopping = ctrl.stopping.value;
        final saving = ctrl.saving.value;
        final busy = starting || stopping || saving;
        final isPrimary = ctrl.isPrimary;
        final canEdit = isPrimary && !busy;
        final startReason = ctrl.startDisabledReason;

        if (ctrl.loading.value && ctrl.config.value == null) {
          return const Center(
            child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.brandNavy)),
          );
        }

        return RefreshIndicator(
          color: AppColors.brandNavy,
          onRefresh: () => ctrl.load(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
            children: [
              if (ctrl.loadError.value != null) ...[
                _Banner(
                  icon: Icons.cloud_off_rounded,
                  color: AppColors.vipps,
                  message: ctrl.loadError.value!,
                  actionLabel: TKeys.retryAction.tr,
                  onAction: () => ctrl.load(),
                ),
                const SizedBox(height: 12),
              ],
              if (!isPrimary) ...[
                _Banner(
                  icon: Icons.lock_outline_rounded,
                  color: AppColors.brandNavy,
                  message: TKeys.mpSecondaryDeviceNote.tr,
                ),
                const SizedBox(height: 12),
              ],
              // Status card (LIVE / PRIMARY / publisher / destinations
              // checklist) is parked for now — re-enable together with
              // `_StatusCard` below.
              // _StatusCard(ctrl: ctrl, isLive: ctrl.isLive,
              //     isPrimary: isPrimary),
              // const SizedBox(height: 14),
              _DestinationsCard(
                ctrl: ctrl,
                enabled: canEdit,
                onAdd: () => _openForm(),
                onEdit: (i) => _openForm(index: i),
                onDelete: _confirmDelete,
              ),
              const SizedBox(height: 14),
              _AutoStartCard(ctrl: ctrl, enabled: canEdit),
              const SizedBox(height: 14),
              _ControlsCard(
                ctrl: ctrl,
                starting: starting,
                stopping: stopping,
                isPrimary: isPrimary,
                startDisabledReason: startReason,
                canStart: startReason == null && !busy,
                onStart: () => ctrl.start(),
                onStop: _confirmStop,
              ),
              if (ctrl.startWarning.value != null) ...[
                const SizedBox(height: 12),
                _Banner(
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFD08700),
                  message: '${TKeys.mpSomeDestFailed.tr}\n'
                      '${ctrl.startWarning.value!}',
                  actionLabel: TKeys.mpDismiss.tr,
                  onAction: () => ctrl.startWarning.value = null,
                ),
              ],
              if (ctrl.converters.isNotEmpty) ...[
                const SizedBox(height: 14),
                _ConvertersCard(ctrl: ctrl, onRestart: _confirmRestart),
              ],
              const SizedBox(height: 18),
              const _HelpNote(),
            ],
          ),
        );
      }),
    );
  }

  /// Add / edit sheet. Editing sends the whole list back, since the API
  /// replaces it wholesale.
  Future<void> _openForm({int? index}) async {
    if (!ctrl.isPrimary) {
      Get.snackbar(TKeys.mpMediaPush.tr,
          TKeys.mpOnlyPrimaryChange.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final existing = index == null ? null : ctrl.destinations[index];
    final result = await showModalBottomSheet<MediaPushDestination>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DestinationSheet(initial: existing),
    );
    if (result == null || !mounted) return;

    if (index == null) {
      await ctrl.addDestination(result);
    } else {
      await ctrl.updateDestination(index, result);
    }
  }

  Future<void> _confirmDelete(int index) async {
    final destination = ctrl.destinations[index];
    final ok = await _confirm(
      title: TKeys.mpRemoveDestTitle.tr,
      message: TKeys.mpRemoveDestBody.trParams(
          {'platform': MediaPushPlatform.labelOf(destination.platform)}),
      confirmLabel: TKeys.removeAction.tr,
      destructive: true,
    );
    if (ok && mounted) await ctrl.removeDestination(index);
  }

  Future<void> _confirmStop() async {
    final ok = await _confirm(
      title: TKeys.mpStopTitle.tr,
      message: TKeys.mpStopBody.tr,
      confirmLabel: TKeys.mpStop.tr,
      destructive: true,
    );
    if (ok && mounted) await ctrl.stop();
  }

  Future<void> _confirmRestart() async {
    final ok = await _confirm(
      title: TKeys.mpRestartTitle.tr,
      message: TKeys.mpRestartBody.tr,
      confirmLabel: TKeys.mpRestart.tr,
      destructive: false,
    );
    if (ok && mounted) await ctrl.restart();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required bool destructive,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: CustomText(title,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary),
        content: CustomText(message,
            fontSize: 13.5,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: CustomText(TKeys.cancelAction.tr,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: CustomText(confirmLabel,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: destructive ? AppColors.vipps : AppColors.brandNavy),
          ),
        ],
      ),
    );
    return result == true;
  }
}

// ── Cards ────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.brandYellow,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.brandNavy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CustomText(
              title,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Live / PRIMARY / publisher / active — the four preconditions the seller has
/// to satisfy before a start can work, each as a pass-fail line.
///
/// Currently not rendered (see the commented call in the page body); the
/// Start button still spells out whichever precondition is missing.
// ignore: unused_element
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.ctrl,
    required this.isLive,
    required this.isPrimary,
  });

  final MediaPushController ctrl;
  final bool isLive;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.podcasts_rounded,
            title: TKeys.statusLabel.tr,
            trailing: _StatePill(
              label: ctrl.isActive ? TKeys.mpPushing.tr : TKeys.mpIdle.tr,
              color: ctrl.isActive
                  ? const Color(0xFF2E9E5B)
                  : AppColors.textMuted,
            ),
          ),
          _Check(
            ok: isLive,
            label: TKeys.mpStreamIsLive.tr,
            hint: TKeys.mpGoLiveFirst.tr,
          ),
          _Check(
            ok: isPrimary,
            label: TKeys.mpThisDeviceIsPrimary.tr,
            hint: TKeys.mpTakeMainControl.tr,
          ),
          _Check(
            ok: ctrl.publisherDetected,
            label: TKeys.mpCameraDetected.tr,
            hint: TKeys.mpStartCameraHint.tr,
          ),
          _Check(
            ok: ctrl.destinations.isNotEmpty,
            label: TKeys.mpAtLeastOneDest.tr,
            hint: TKeys.mpAddPlatformBelow.tr,
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _Check extends StatelessWidget {
  const _Check({required this.ok, required this.label, required this.hint});

  final bool ok;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 17,
            color: ok ? const Color(0xFF2E9E5B) : AppColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  label,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: ok ? AppColors.textPrimary : AppColors.textSecondary,
                ),
                if (!ok) ...[
                  const SizedBox(height: 2),
                  CustomText(
                    hint,
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppColors.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The saved RTMP targets, each with edit / delete.
class _DestinationsCard extends StatelessWidget {
  const _DestinationsCard({
    required this.ctrl,
    required this.enabled,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final MediaPushController ctrl;

  /// PRIMARY and nothing in flight — the edit affordances are dead otherwise.
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final destinations = ctrl.destinations;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.share_rounded,
            title: TKeys.mpDestinations.tr,
            trailing: CustomText(
              '${destinations.length}',
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
            ),
          ),
          if (destinations.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const Icon(Icons.add_link_rounded,
                      size: 24, color: AppColors.textMuted),
                  const SizedBox(height: 8),
                  CustomText(
                    TKeys.mpNoDestinations.tr,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 4),
                  CustomText(
                    TKeys.mpAddPlatformsBody.tr,
                    fontSize: 11.5,
                    height: 1.4,
                    textAlign: TextAlign.center,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < destinations.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _DestinationTile(
                destination: destinations[i],
                enabled: enabled,
                onEdit: () => onEdit(i),
                onDelete: () => onDelete(i),
              ),
            ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: enabled ? onAdd : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandNavy,
                disabledBackgroundColor: AppColors.brandNavy.withOpacity(0.3),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_rounded,
                  size: 18, color: AppColors.brandYellow),
              label: CustomText(
                TKeys.mpAddDestination.tr,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.destination,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  final MediaPushDestination destination;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final platform = MediaPushPlatform.of(destination.platform);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.brandNavy,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconFor(destination.platform),
                size: 17, color: AppColors.brandYellow),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  platform.label,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 3),
                CustomText(
                  destination.rtmpUrl,
                  fontSize: 11.5,
                  height: 1.35,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  color: AppColors.textSecondary,
                ),
                if (destination.maskedKey != null) ...[
                  const SizedBox(height: 3),
                  CustomText(
                    TKeys.mpKeyPrefix.trParams({'key': destination.maskedKey!}),
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: enabled ? onEdit : null,
            tooltip: TKeys.edit.tr,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined,
                size: 18, color: AppColors.textSecondary),
          ),
          IconButton(
            onPressed: enabled ? onDelete : null,
            tooltip: TKeys.removeAction.tr,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline_rounded,
                size: 18, color: AppColors.vipps),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String platform) {
    switch (platform) {
      case 'youtube':
        return Icons.smart_display_rounded;
      case 'tiktok':
        return Icons.music_note_rounded;
      case 'facebook':
        return Icons.facebook_rounded;
      case 'instagram':
        return Icons.camera_alt_rounded;
      default:
        return Icons.rss_feed_rounded;
    }
  }
}

/// Auto-start arms the server for the next go-live; it never starts anything
/// on its own, which the copy has to make plain.
class _AutoStartCard extends StatelessWidget {
  const _AutoStartCard({required this.ctrl, required this.enabled});

  final MediaPushController ctrl;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  TKeys.mpAutoStart.tr,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 4),
                CustomText(
                  TKeys.mpAutoStartBody.tr,
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: ctrl.autoStart,
            activeColor: AppColors.brandNavy,
            onChanged: enabled ? (value) => ctrl.setAutoStart(value) : null,
          ),
        ],
      ),
    );
  }
}

/// Start / Stop, with the web console's disabled reasons spelled out.
class _ControlsCard extends StatelessWidget {
  const _ControlsCard({
    required this.ctrl,
    required this.starting,
    required this.stopping,
    required this.isPrimary,
    required this.startDisabledReason,
    required this.canStart,
    required this.onStart,
    required this.onStop,
  });

  final MediaPushController ctrl;
  final bool starting;
  final bool stopping;
  final bool isPrimary;

  /// Null when Start can run; otherwise the reason, shown under the button.
  final String? startDisabledReason;
  final bool canStart;

  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final reason = startDisabledReason;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ctrl.isActive)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: (stopping || !isPrimary) ? null : onStop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.vipps,
                  disabledBackgroundColor: AppColors.vipps.withOpacity(0.35),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: stopping
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.stop_circle_outlined,
                        size: 19, color: Colors.white),
                label: CustomText(
                  stopping ? TKeys.mpStopping.tr : TKeys.mpStopMediaPush.tr,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white,
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: canStart ? onStart : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandNavy,
                  disabledBackgroundColor: AppColors.brandNavy.withOpacity(0.3),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.brandYellow),
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded,
                        size: 21, color: AppColors.brandYellow),
                label: CustomText(
                  starting ? TKeys.mpStarting.tr : TKeys.mpStartMediaPush.tr,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white,
                ),
              ),
            ),
          if (starting) ...[
            const SizedBox(height: 10),
            CustomText(
              TKeys.mpStartWarning.tr,
              fontSize: 11.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ] else if (!ctrl.isActive && reason != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 15, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomText(
                    reason,
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Live converter status — one row per RTMP target Agora is pushing.
class _ConvertersCard extends StatelessWidget {
  const _ConvertersCard({required this.ctrl, required this.onRestart});

  final MediaPushController ctrl;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final converters = ctrl.converters;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.cell_tower_rounded,
            title: TKeys.mpLiveConverters.tr,
            trailing: CustomText(
              '${converters.length}',
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
            ),
          ),
          for (var i = 0; i < converters.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _ConverterTile(converter: converters[i]),
          ],
          if (ctrl.config.value?.hasDuplicateConverters == true) ...[
            const SizedBox(height: 12),
            _Banner(
              icon: Icons.copy_all_rounded,
              color: const Color(0xFFD08700),
              message: TKeys.mpDuplicateConverters.tr,
              actionLabel: TKeys.mpRestart.tr,
              onAction: onRestart,
            ),
          ],
        ],
      ),
    );
  }
}

class _ConverterTile extends StatelessWidget {
  const _ConverterTile({required this.converter});

  final MediaPushConverter converter;

  @override
  Widget build(BuildContext context) {
    final state = converter.effectiveState;
    final Color color;
    final String label;
    switch (state) {
      case 'running':
        color = const Color(0xFF2E9E5B);
        label = TKeys.mpStreaming.tr;
        break;
      case 'failed':
        color = AppColors.vipps;
        label = TKeys.mpFailed.tr;
        break;
      default:
        color = const Color(0xFFD08700);
        label = TKeys.mpConnecting.tr;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CustomText(
                  MediaPushPlatform.labelOf(converter.platform),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              _StatePill(label: label, color: color),
            ],
          ),
          const SizedBox(height: 6),
          CustomText(
            converter.rtmpUrl,
            fontSize: 11,
            height: 1.35,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            color: AppColors.textMuted,
          ),
          if (converter.displayNote != null &&
              converter.displayNote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Note(
              icon: Icons.info_outline_rounded,
              color: AppColors.textSecondary,
              text: converter.displayNote!,
            ),
          ],
          if (converter.audioOnlyRisk) ...[
            const SizedBox(height: 8),
            _Note(
              icon: Icons.volume_up_rounded,
              color: const Color(0xFFD08700),
              text: TKeys.mpNoVideoLayout.tr,
            ),
          ],
          if (converter.usingRawMode == true) ...[
            const SizedBox(height: 8),
            _Note(
              icon: Icons.bolt_rounded,
              color: AppColors.textSecondary,
              text: TKeys.mpPassthrough.tr,
            ),
          ],
          if (converter.statusError != null &&
              converter.statusError!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Note(
              icon: Icons.error_outline_rounded,
              color: AppColors.vipps,
              text: converter.statusError!,
            ),
          ],
          if (state == 'connecting') ...[
            const SizedBox(height: 8),
            _Note(
              icon: Icons.schedule_rounded,
              color: AppColors.textMuted,
              text: TKeys.mpStillConnecting.tr,
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: CustomText(
            text,
            fontSize: 11,
            height: 1.4,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          CustomText(
            label,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: CustomText(
              message,
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: CustomText(
                actionLabel!,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}

class _HelpNote extends StatelessWidget {
  const _HelpNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: CustomText(
        TKeys.mpFooterNote.tr,
        fontSize: 11.5,
        height: 1.45,
        textAlign: TextAlign.center,
        color: AppColors.textMuted,
      ),
    );
  }
}

// ── Add / edit destination sheet ─────────────────────────────────────────────

class _DestinationSheet extends StatefulWidget {
  const _DestinationSheet({this.initial});

  /// Null when adding.
  final MediaPushDestination? initial;

  @override
  State<_DestinationSheet> createState() => _DestinationSheetState();
}

class _DestinationSheetState extends State<_DestinationSheet> {
  late String _platform = widget.initial?.platform ?? 'youtube';
  late final TextEditingController _url =
      TextEditingController(text: widget.initial?.rtmpUrl ?? _defaultUrl());
  late final TextEditingController _key =
      TextEditingController(text: widget.initial?.streamKey ?? '');

  String? _error;

  String _defaultUrl() => MediaPushPlatform.of(_platform).defaultRtmpUrl ?? '';

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  /// Switching platform swaps in that platform's ingest URL, but never
  /// overwrites something the seller typed.
  void _selectPlatform(String platform) {
    final previousDefault = MediaPushPlatform.of(_platform).defaultRtmpUrl ?? '';
    setState(() {
      _platform = platform;
      _error = null;
      final typed = _url.text.trim();
      if (typed.isEmpty || typed == previousDefault) {
        _url.text = MediaPushPlatform.of(platform).defaultRtmpUrl ?? '';
      }
    });
  }

  void _submit() {
    final url = _url.text.trim();
    final key = _key.text.trim();

    final problem = validateMediaPushDestination(
      platform: _platform,
      rtmpUrl: url,
      streamKey: key,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    Navigator.of(context).pop(
      MediaPushDestination(
        platform: _platform,
        rtmpUrl: url,
        streamKey: key.isEmpty ? null : key,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final platform = MediaPushPlatform.of(_platform);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: media.size.height * 0.9 - media.viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.inputBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CustomText(
                    widget.initial == null
                        ? TKeys.mpAddDestination.tr
                        : TKeys.mpEditDestination.tr,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(height: 6),
                  CustomText(
                    TKeys.mpPasteIngest.tr,
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  _FieldLabel(TKeys.mpPlatform.tr),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in MediaPushPlatform.all)
                        _PlatformChip(
                          label: option.label,
                          selected: option.id == _platform,
                          onTap: () => _selectPlatform(option.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _FieldLabel(TKeys.mpRtmpUrl.tr),
                  const SizedBox(height: 6),
                  _SheetField(
                    controller: _url,
                    hint: TKeys.mpRtmpHint.tr,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 14),
                  _FieldLabel(
                    platform.requiresKey ? TKeys.mpStreamKey.tr : TKeys.mpStreamKeyOptional.tr,
                  ),
                  const SizedBox(height: 6),
                  _SheetField(
                    controller: _key,
                    hint: platform.keyHint ?? TKeys.mpPasteStreamKey.tr,
                  ),
                  if (platform.needsPublisher) ...[
                    const SizedBox(height: 12),
                    _Note(
                      icon: Icons.videocam_outlined,
                      color: AppColors.textMuted,
                      text: TKeys.mpPlatformNeedsCamera.tr,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 15, color: AppColors.vipps),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CustomText(
                            _error!,
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: AppColors.vipps,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandNavy,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: CustomText(
                        widget.initial == null
                            ? TKeys.mpAddDestination.tr
                            : TKeys.saveChanges.tr,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return CustomText(
      label.toUpperCase(),
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.9,
      color: AppColors.textMuted,
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandNavy : const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.brandNavy : AppColors.borderGrey,
          ),
        ),
        child: CustomText(
          label,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.brandYellow : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        ),
        filled: true,
        fillColor: const Color(0xFFF5F6F8),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderGrey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brandNavy, width: 1.4),
        ),
      ),
    );
  }
}
