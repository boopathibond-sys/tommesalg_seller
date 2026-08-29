import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../controllers/auction_room_controller.dart';
import '../../data/models/auction_room_snapshot.dart';
import '../../data/services/auction_room_api.dart';
import '../widgets/room_sheets.dart';
import '../widgets/start_auction_sheet.dart';
import '../../../../core/localization/translation_keys.dart';

/// The Live tab: a full-bleed camera stage with floating, minimisable overlays.
///
/// Layout (TikTok-style):
///  • camera fills the whole tab, under everything;
///  • a "Go Live" pill floats top-left (only while the stream is scheduled);
///  • a vertical mic / camera / flip rail floats on the right;
///  • the start-auction / running-auction card floats bottom-left;
///  • a top-right toggle collapses every overlay down to just the camera.
class LiveTab extends StatefulWidget {
  const LiveTab({super.key, required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  bool _minimized = false;

  AuctionRoomController get ctrl => widget.ctrl;

  void _toggleMinimized() => setState(() => _minimized = !_minimized);

  @override
  Widget build(BuildContext context) {
    final maxCardHeight = MediaQuery.sizeOf(context).height * 0.5;
    const anim = Duration(milliseconds: 220);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera under everything.
        _VideoPreview(ctrl: ctrl),

        // Top + bottom scrims keep the white overlays legible over the feed.
        IgnorePointer(
          child: AnimatedOpacity(
            duration: anim,
            opacity: _minimized ? 0 : 1,
            child: const _EdgeScrim(),
          ),
        ),

        // ── Top bar: Go-Live pill (left) + minimise toggle (right) ──────────
        Positioned(
          top: 10,
          left: 16,
          right: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _MinimizeToggle(minimized: _minimized, onTap: _toggleMinimized),
                  Expanded(
                    child: AnimatedOpacity(
                      duration: anim,
                      opacity: _minimized ? 0 : 1,
                      child: IgnorePointer(
                        ignoring: _minimized,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _GoLivePill(ctrl: ctrl),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!_minimized) ...[
                // Another device is waiting on us to approve a handoff. Shown
                // here (not just in the Devices sheet) so a request raised from
                // another device — including the seller web console — is
                // actionable without digging through the ⋮ menu.
                ControlRequestBanner(ctrl: ctrl),
                Obx(() {
                  if (!ctrl.connectionLost.value) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _Banner(
                      icon: Icons.wifi_off_rounded,
                      text: TKeys.ltConnectionLost.tr,
                      onTap: ctrl.refreshSnapshot,
                    ),
                  );
                }),
                _StreamClock(ctrl: ctrl),
                // What buyers currently see in the stream banner — tap to edit
                // or take it down.
                Obx(() {
                  final text = ctrl.announcement.value;
                  if (text == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _AnnouncementBanner(
                      text: text,
                      onTap: () => showAnnouncementSheet(context, ctrl),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),

        // ── Right vertical rail: mic / camera / flip (TikTok-style) ─────────
        Positioned(
          right: 14,
          bottom: 20,
          child: AnimatedSlide(
            duration: anim,
            offset: _minimized ? const Offset(1.4, 0) : Offset.zero,
            child: AnimatedOpacity(
              duration: anim,
              opacity: _minimized ? 0 : 1,
              child: IgnorePointer(
                ignoring: _minimized,
                child: _BroadcastControls(ctrl: ctrl),
              ),
            ),
          ),
        ),

        // ── Bottom-left: start-auction / running-auction card ───────────────
        Positioned(
          left: 16,
          right: 86,
          bottom: 20,
          child: AnimatedSlide(
            duration: anim,
            offset: _minimized ? const Offset(0, 1.4) : Offset.zero,
            child: AnimatedOpacity(
              duration: anim,
              opacity: _minimized ? 0 : 1,
              child: IgnorePointer(
                ignoring: _minimized,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxCardHeight),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Obx(() {
                          final active = ctrl.activeAuction;
                          if (active != null) {
                            return _ActiveAuctionCard(ctrl: ctrl, auction: active);
                          }
                          return _IdleCard(ctrl: ctrl);
                        }),
                        Obx(() {
                          final result = ctrl.snap?.lastAuctionResult;
                          if (result == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _LastResultCard(result: result),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Soft dark gradients at the very top and bottom so white overlays keep
/// contrast over any scene.
class _EdgeScrim extends StatelessWidget {
  const _EdgeScrim();
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.18, 0.6, 1],
          colors: [
            Colors.black.withOpacity(0.28),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(0.42),
          ],
        ),
      ),
    );
  }
}

/// Collapses / restores every floating overlay, leaving just the camera.
class _MinimizeToggle extends StatelessWidget {
  const _MinimizeToggle({required this.minimized, required this.onTap});
  final bool minimized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.45),
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.5),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            minimized
                ? Icons.open_in_full_rounded
                : Icons.close_fullscreen_rounded,
            size: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Adaptive top pill: "Go Live" while the stream is scheduled (hits the
/// go-live endpoint once), then a "Stop Live" / "Go Live" broadcast toggle
/// once live. The live toggle is purely local (stop/resume publishing) — it
/// never re-calls the go-live API.
class _GoLivePill extends StatelessWidget {
  const _GoLivePill({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final s = ctrl.stream;
      if (s == null || s.isTerminal) return const SizedBox.shrink();
      // A secondary device can watch the room but must be handed control by
      // the primary before it can publish — otherwise two phones broadcast
      // into the same channel. Offer the request instead of a dead Go Live.
      if (ctrl.needsControl) return _requestControl();
      // Drive the pill by whether we're actually publishing, not the stream's
      // status. Entering the room never auto-publishes, so until the seller
      // taps Go Live (and we join the channel) we always show "Go Live" —
      // even when the stream is already LIVE server-side.
      if (!ctrl.rtcJoined.value) return _goLive();
      return _stopResume();
    });
  }

  Widget _requestControl() {
    final pending = ctrl.hasPendingControlRequest;
    return _Pill(
      color: Colors.black.withOpacity(0.55),
      onTap: pending ? null : ctrl.requestAuctionControl,
      loading: false,
      icon: Icons.pan_tool_alt_rounded,
      label: pending ? TKeys.ltWaitingForControl.tr : TKeys.ltRequestControl.tr,
    );
  }

  Widget _goLive() {
    final loading = ctrl.goLiveLoading.value;
    return _Pill(
      color: AppColors.vipps,
      onTap: loading ? null : ctrl.startGoLive,
      loading: loading,
      icon: Icons.sensors_rounded,
      label: TKeys.ltGoLive.tr,
    );
  }

  Widget _stopResume() {
    final paused = ctrl.broadcastPaused.value;
    return _Pill(
      color: paused ? AppColors.vipps : Colors.black.withOpacity(0.55),
      onTap: ctrl.togglePauseBroadcast,
      loading: false,
      icon: paused ? Icons.sensors_rounded : Icons.stop_rounded,
      label: paused ? TKeys.ltGoLive.tr : TKeys.ltStopLive.tr,
    );
  }
}

/// A rounded, shadowed action pill used for the Go Live / Pause / Resume states.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.color,
    required this.onTap,
    required this.loading,
    required this.icon,
    required this.label,
  });
  final Color color;
  final VoidCallback? onTap;
  final bool loading;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(Colors.white)),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  CustomText(label,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ],
              ),
      ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Depend on rtcJoined + cameraOff + paused + goLiveLoading so the
      // preview rebuilds. "Publishing to buyers" == joined && !paused.
      final joined = ctrl.rtcJoined.value;
      final camOff = ctrl.cameraOff.value;
      final paused = ctrl.broadcastPaused.value;
      final goingLive = ctrl.goLiveLoading.value;
      if (!ctrl.rtc.isInitialized) {
        return _previewPlaceholder(TKeys.ltStartingCamera.tr);
      }
      if (camOff) {
        return _previewPlaceholder(TKeys.ltCameraOff.tr);
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          AgoraVideoView(
            controller: VideoViewController(
              rtcEngine: ctrl.rtc.engine,
              canvas: const VideoCanvas(uid: 0),
            ),
          ),
          // Overlay reflects our *publishing* state, not the stream status:
          //  • going live  → connecting spinner;
          //  • stopped     → "buyers can't see you" (seller keeps preview);
          //  • not joined  → preview-only badge (covers scheduled AND an
          //    already-live stream we haven't started publishing to yet).
          if (goingLive)
            Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.white)),
            )
          else if (paused)
            const Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(child: _StoppedBadge()),
            )
          else if (!joined)
            const Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(child: _PreviewBadge()),
            ),
        ],
      );
    });
  }

  /// Stand-in for the camera feed. When the stream has a thumbnail we show it
  /// instead of a flat black stage, so "camera off" still looks like the
  /// seller's stream rather than a dead screen. The image is dimmed so the
  /// icon + label stay readable on top of any artwork.
  Widget _previewPlaceholder(String label) {
    final thumb = ctrl.stream?.thumbnailUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.brandNavy),
        if (thumb != null && thumb.isNotEmpty)
          Image.network(
            thumb,
            fit: BoxFit.cover,
            // Failures fall through to the plain navy backdrop underneath.
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const SizedBox.shrink(),
          ),
        // Scrim: keeps the copy legible whether the thumbnail is light or dark.
        Container(color: AppColors.brandNavy.withOpacity(thumb == null ? 0 : 0.45)),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 34),
              const SizedBox(height: 8),
              CustomText(label, fontSize: 13, fontWeight: FontWeight.w600,
                  color: Colors.white70),
            ],
          ),
        ),
      ],
    );
  }
}

/// A pill that reminds the seller they're only previewing — buyers don't
/// receive the feed until Go Live.
class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off_rounded, size: 14, color: Colors.white),
          SizedBox(width: 6),
          Text(
            'Preview only · buyers can’t see you yet',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while the seller has stopped the live feed — the local preview keeps
/// running, but buyers receive nothing until they Go Live again.
class _StoppedBadge extends StatelessWidget {
  const _StoppedBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.vipps.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pause_circle_filled_rounded, size: 14, color: Colors.white),
          SizedBox(width: 6),
          Text(
            'Live stopped · buyers can’t see you',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical mic / camera / flip rail (TikTok-style), floating over the camera.
class _BroadcastControls extends StatelessWidget {
  const _BroadcastControls({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CircleControl(
              icon: ctrl.micMuted.value ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: ctrl.micMuted.value ? TKeys.ltUnmute.tr : TKeys.ltMute.tr,
              active: !ctrl.micMuted.value,
              onTap: ctrl.toggleMic,
            ),
            const SizedBox(height: 18),
            _CircleControl(
              icon: ctrl.cameraOff.value
                  ? Icons.videocam_off_rounded
                  : Icons.videocam_rounded,
              label: TKeys.cameraSource.tr,
              active: !ctrl.cameraOff.value,
              onTap: ctrl.toggleCamera,
            ),
            const SizedBox(height: 18),
            _CircleControl(
              icon: Icons.cameraswitch_rounded,
              label: TKeys.ltFlip.tr,
              active: true,
              onTap: ctrl.switchCamera,
            ),
          ],
        ));
  }
}

/// A floating, shadowed circular control with a caption beneath it.
/// White = on; brand-red = off/muted. Elevation gives the shadow + hover,
/// InkWell gives the tap ripple.
class _CircleControl extends StatelessWidget {
  const _CircleControl({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active ? AppColors.white : AppColors.vipps,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: Colors.black.withOpacity(0.5),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 18,
                  color: active ? AppColors.brandNavy : AppColors.white),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
      ],
    );
  }
}

class _IdleCard extends StatelessWidget {
  const _IdleCard({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          const Icon(Icons.gavel_rounded, size: 30, color: AppColors.brandNavy),
          const SizedBox(height: 10),
          CustomText(TKeys.ltNoAuctionRunning.tr,
              fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          const SizedBox(height: 4),
          Obx(() => CustomText(
                ctrl.productQueue.isEmpty
                    ? TKeys.ltAddProductsFirst.tr
                    : TKeys.ltStartNextLot.tr,
                fontSize: 13, fontWeight: FontWeight.w500,
                textAlign: TextAlign.center, color: AppColors.textSecondary,
              )),
          const SizedBox(height: 14),
          Obx(() {
            // Only allow starting a lot while we're actually publishing to
            // buyers (gone live, not stopped). Entering the room or stopping
            // the feed keeps this disabled with a "Go live to start" hint.
            final publishing = ctrl.rtcJoined.value && !ctrl.broadcastPaused.value;
            final canStart = ctrl.isLive &&
                publishing &&
                ctrl.productQueue.isNotEmpty &&
                ctrl.isController;
            return _WideButton(
              label: publishing ? TKeys.ltStartAuction.tr : TKeys.ltGoLiveToStart.tr,
              icon: Icons.play_arrow_rounded,
              loading: ctrl.startLoading.value,
              enabled: canStart,
              onTap: () => _openStartSheet(context, ctrl),
            );
          }),
        ],
      ),
    );
  }
}

Future<void> _openStartSheet(BuildContext context, AuctionRoomController ctrl) async {
  final first = ctrl.productQueue.isNotEmpty ? ctrl.productQueue.first : null;
  final params = await showModalBottomSheet<StartAuctionParams>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StartAuctionSheet(nextProduct: first),
  );
  if (params != null) await ctrl.startAuction(params);
}

class _ActiveAuctionCard extends StatefulWidget {
  const _ActiveAuctionCard({required this.ctrl, required this.auction});
  final AuctionRoomController ctrl;
  final ActiveAuction auction;

  @override
  State<_ActiveAuctionCard> createState() => _ActiveAuctionCardState();
}

class _ActiveAuctionCardState extends State<_ActiveAuctionCard> {
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// A new lot (or a corrected `endsAt` from a fresh snapshot) reuses this
  /// State, so re-read immediately instead of showing the previous lot's
  /// number until the next tick.
  @override
  void didUpdateWidget(_ActiveAuctionCard old) {
    super.didUpdateWidget(old);
    if (old.auction.id != widget.auction.id ||
        old.auction.endsAt != widget.auction.endsAt) {
      _tick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Recomputes the displayed seconds. Three things matter here, and a 30 s
  /// auction reading "31s" at the start came from missing all of them:
  ///
  /// * The clock. `endsAt` is stamped by the server, so it's only meaningful
  ///   against server time — a device running a second or two behind makes a
  ///   plain `endsAt - DateTime.now()` overshoot by exactly that skew.
  ///   [AuctionRoomController.serverNow] applies the measured offset.
  /// * The rounding. Truncating (`Duration.inSeconds`) shows 29 for a full
  ///   second at the top of a 30 s lot and hits 0 with a second still to run;
  ///   ceiling gives each number its own second and starts at 30.
  /// * The cap. Whatever the offset estimate is worth, the lot cannot be
  ///   longer than the server scheduled it, so clamp to [totalDurationSec].
  void _tick() {
    final endsAt = widget.auction.endsAtUtc;
    var secs = 0;
    if (endsAt != null) {
      final left = endsAt.difference(widget.ctrl.serverNow.toUtc());
      secs = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
      final total = widget.auction.totalDurationSec;
      if (total != null && secs > total) secs = total;
    }
    if (mounted && secs != _secondsLeft) {
      setState(() => _secondsLeft = secs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.auction;
    final ctrl = widget.ctrl;
    final secs = _secondsLeft;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (a.isDutch ? const Color(0xFF6A1B9A) : AppColors.brandNavy)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CustomText(
                    a.isDutch
                        ? TKeys.auctionTypeDutchCaps.tr
                        : TKeys.auctionTypeNormalCaps.tr,
                    fontSize: 10, fontWeight: FontWeight.w800,
                    color: a.isDutch ? const Color(0xFF6A1B9A) : AppColors.brandNavy),
              ),
              const Spacer(),
              Icon(Icons.timer_outlined,
                  size: 15, color: secs <= 5 ? AppColors.vipps : AppColors.textSecondary),
              const SizedBox(width: 4),
              CustomText('${secs}s',
                  fontSize: 15, fontWeight: FontWeight.w800,
                  color: secs <= 5 ? AppColors.vipps : AppColors.textPrimary),
            ],
          ),
          const SizedBox(height: 10),
          CustomText(a.title ?? TKeys.ltCurrentLot.tr,
              fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(
            children: [
              _Stat(label: a.isDutch ? TKeys.ltCurrentPrice.tr : TKeys.ltHighestBid.tr,
                  value: _kr(a.displayPrice)),
              const SizedBox(width: 20),
              _Stat(label: TKeys.ltBids.tr, value: '${a.bidCount}'),
            ],
          ),
          if (a.winnerName != null) ...[
            const SizedBox(height: 8),
            CustomText(
                TKeys.ltLeading.trParams({'name': '${a.winnerName}'}),
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (a.isDutch && ctrl.isController) ...[
                Expanded(
                  child: _WideButton(
                    label: TKeys.ltReducePrice.tr,
                    icon: Icons.trending_down_rounded,
                    filled: false,
                    onTap: () => _openReduceSheet(context, ctrl, a),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Obx(() => _WideButton(
                      label: TKeys.ltEndLot.tr,
                      icon: Icons.stop_rounded,
                      loading: ctrl.endLoading.value,
                      enabled: ctrl.isController,
                      danger: true,
                      onTap: ctrl.endAuction,
                    )),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _openReduceSheet(
  BuildContext context,
  AuctionRoomController ctrl,
  ActiveAuction a,
) async {
  final controller = TextEditingController();
  final newPrice = await showDialog<num>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: CustomText(TKeys.ltReduceDutchPrice.tr, fontSize: 17,
          fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
              TKeys.ltCurrentColon.trParams({'price': _kr(a.displayPrice)}),
              fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              hintText: TKeys.ltNewPriceKr.tr,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(),
          child: CustomText(TKeys.cancelAction.tr, fontSize: 14,
              fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
        TextButton(
          onPressed: () {
            final v = num.tryParse(controller.text.trim());
            if (v != null) Navigator.of(dctx).pop(v);
          },
          child: CustomText(TKeys.ltReduce.tr, fontSize: 14,
              fontWeight: FontWeight.w800, color: AppColors.brandNavy),
        ),
      ],
    ),
  );
  if (newPrice != null) await ctrl.reduceDutchPrice(newPrice);
}

class _LastResultCard extends StatelessWidget {
  const _LastResultCard({required this.result});
  final LastAuctionResult result;
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Icon(result.hadWinner ? Icons.emoji_events_rounded : Icons.info_outline_rounded,
              color: result.hadWinner ? const Color(0xFFB8860B) : AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  TKeys.ltLastLot.trParams({'title': result.productTitle ?? '—'}),
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                CustomText(
                  result.hadWinner
                      ? TKeys.ltSoldToPrice.trParams({
                          'name': result.winnerName ?? TKeys.ltBuyerFallback.tr,
                          'price': _kr(result.finalPrice),
                        })
                      : TKeys.ltNoWinner.tr,
                  fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────────

String _kr(num? v) => v == null ? '—' : 'kr ${v % 1 == 0 ? v.toInt() : v}';

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(label, fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
        const SizedBox(height: 2),
        CustomText(value, fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 20, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Last-five-minutes warning. Hidden for the rest of the run so it doesn't eat
/// the room above the preview, then appears in red with the remaining time and
/// Extend one tap away.
class _StreamClock extends StatelessWidget {
  const _StreamClock({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final left = ctrl.timeLeft.value;
      if (!ctrl.isLive || !ctrl.endingSoon || left == null) {
        return const SizedBox.shrink();
      }
      final endsAt = ctrl.endsAtLabel;
      final label = endsAt == null
          ? TKeys.ltTimeLeft.trParams({'time': _fmtLeft(left)})
          : TKeys.ltLeftEndsAt
              .trParams({'time': _fmtLeft(left), 'endsAt': endsAt});
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
          decoration: BoxDecoration(
            color: AppColors.vipps.withOpacity(0.16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.vipps, width: 1.4),
          ),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16, color: AppColors.vipps),
              const SizedBox(width: 7),
              Expanded(
                child: CustomText(
                  label,
                  fontSize: 12.5, fontWeight: FontWeight.w800,
                  color: AppColors.vipps,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => showExtendDialog(context, ctrl),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.vipps,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: CustomText(TKeys.ltExtend.tr, fontSize: 12,
                      fontWeight: FontWeight.w800, color: AppColors.white),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// `4:07` \u2014 the countdown only ever shows inside the last five minutes.
String _fmtLeft(Duration d) {
  final total = d.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.vipps.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 14, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.vipps),
            const SizedBox(width: 10),
            Expanded(
              child: CustomText(text, fontSize: 12.5,
                  fontWeight: FontWeight.w600, color: AppColors.vipps),
            ),
            const Icon(Icons.refresh_rounded, size: 18, color: AppColors.vipps),
          ],
        ),
      ),
    );
  }
}

/// Compact read-out of the live announcement over the camera stage, so the
/// seller can see (and reach) what buyers are being shown without opening the
/// ⋮ menu.
class _AnnouncementBanner extends StatelessWidget {
  const _AnnouncementBanner({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.brandYellow.withOpacity(0.7)),
        ),
        child: Row(
          children: [
            const Icon(Icons.campaign_rounded, size: 16,
                color: AppColors.brandYellow),
            const SizedBox(width: 8),
            Expanded(
              child: CustomText(text,
                  fontSize: 12.5, fontWeight: FontWeight.w700,
                  color: AppColors.white,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.edit_rounded, size: 15, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
    this.filled = true,
    this.danger = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;
  final bool enabled;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = danger ? AppColors.vipps : AppColors.brandNavy;
    final disabled = !enabled || loading;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? bg : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: filled ? null : Border.all(color: AppColors.brandNavy, width: 1.4),
          ),
          child: loading
              ? SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(
                        filled ? Colors.white : AppColors.brandNavy),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18,
                        color: filled ? Colors.white : AppColors.brandNavy),
                    const SizedBox(width: 8),
                    CustomText(label, fontSize: 14, fontWeight: FontWeight.w800,
                        color: filled ? Colors.white : AppColors.brandNavy),
                  ],
                ),
        ),
      ),
    );
  }
}
