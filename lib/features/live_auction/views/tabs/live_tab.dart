import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../controllers/auction_room_controller.dart';
import '../../data/models/auction_room_snapshot.dart';
import '../../data/models/live_chat_message.dart';
import '../../data/services/auction_room_api.dart';
import '../widgets/live_chat_overlay.dart';
import '../widgets/room_sheets.dart';
import '../widgets/start_auction_sheet.dart';
import '../../../../core/localization/translation_keys.dart';

/// The Live tab: a full-bleed camera stage with floating, minimisable overlays.
///
/// Layout:
///  • camera fills the whole tab, under everything;
///  • a floating header — seller thumbnail, stream title, viewer count, ✕ —
///    rides over the feed instead of the room's white bar, so the camera runs
///    edge to edge;
///  • the live announcement, when there is one, sits directly under it;
///  • a "Go Live" pill floats below that, on the right;
///  • the Show Notes tab shares that row on the left;
///  • the "preview only" / "stopped" note hangs straight off that row;
///  • the start-auction / running-auction card sits along the bottom-left;
///  • a transparent rail carries mic / camera / flip up the right edge,
///    Instagram-style: bare icons with captions and no panel behind them, so
///    the camera keeps the whole stage;
///  • the chat overlay hangs off the bottom-left, under the auction card;
///  • the chevron at the foot of the rail collapses every overlay down to
///    just the camera, and is what brings them back.
class LiveTab extends StatefulWidget {
  const LiveTab({
    super.key,
    required this.ctrl,
    required this.onClose,
    required this.onOpenQueue,
  });
  final AuctionRoomController ctrl;

  /// Leaves the room — the ✕ in the floating header. The room owns the
  /// confirmation, the same one the hardware back button runs.
  final VoidCallback onClose;

  /// Switches the room to the Queue tab — the "Add" on the empty-queue note.
  final VoidCallback onOpenQueue;

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

        // ── Floating room header, over the feed ─────────────────────────────
        Positioned(
          top: 8,
          left: 12,
          right: 12,
          child: _RoomHeaderOverlay(ctrl: ctrl, onClose: widget.onClose),
        ),

        // ── Under the header: the announcement, then the Go-Live row ──────
        Positioned(
          top: 62,
          left: 16,
          right: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // What buyers currently see in the stream banner — tap to edit
              // or take it down. It leads the stack: it is the one thing here
              // that is being broadcast to the room right now, so it reads
              // before the controls, not after them — and it stays put under
              // the header in every state, because it is the seller's read-out
              // of live copy and not chrome to be pushed around.
              if (!_minimized)
                Obx(() {
                  final text = ctrl.announcement.value;
                  if (text == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AnnouncementBanner(
                      text: text,
                      onTap: () => showAnnouncementSheet(context, ctrl),
                    ),
                  );
                }),
              AnimatedOpacity(
                duration: anim,
                opacity: _minimized ? 0 : 1,
                child: IgnorePointer(
                  ignoring: _minimized,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // The sticky note buyers see on their side of the
                          // room — here it opens the notes. It shares the
                          // pill's row rather than sitting under the banners,
                          // which parked it a pill-height down the stage for
                          // no reason: the two never collide, one is hard
                          // left, the other hard right.
                          _ShowNotesTab(
                            onTap: (anchorBottom) => showShowNotesDialog(
                              context,
                              ctrl,
                              anchorBottom: anchorBottom,
                            ),
                          ),
                          _GoLivePill(ctrl: ctrl),
                        ],
                      ),
                      // "Preview only · buyers can't see you yet" — it answers
                      // the pill directly above it, so it reads straight after
                      // the row instead of floating on its own in the middle
                      // of the stage.
                      _PreviewNote(ctrl: ctrl),
                    ],
                  ),
                ),
              ),
              if (!_minimized) ...[
                // Another device is waiting on us to approve a handoff. Shown
                // here (not just in the Devices sheet) so a request raised from
                // another device — including the seller web console — is
                // actionable without digging through the ⋮ menu.
                ControlRequestBanner(ctrl: ctrl),
                Obx(() {
                  if (!ctrl.connectionLost.value) {
                    return const SizedBox.shrink();
                  }
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
              ],
            ],
          ),
        ),

        // ── Bottom: chat + rail on one row, the auction deck full-width under
        //    both ────────────────────────────────────────────────────────────
        //
        // Chat takes the width the vertical rail leaves; the lot itself — its
        // timer, its price and End lot — drops below the rail and runs edge to
        // edge, on a black gradient rather than in a floating card. The lot is
        // the one thing on this screen the seller reads at a glance mid-sale,
        // and boxing it into two thirds of the width was costing it the room it
        // needed.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: AnimatedOpacity(
                        duration: anim,
                        opacity: _minimized ? 0 : 1,
                        child: IgnorePointer(
                          ignoring: _minimized,
                          child: _ChatOverlaySection(
                            ctrl: ctrl,
                            onOpenQueue: widget.onOpenQueue,
                          ),
                        ),
                      ),
                    ),
                    // Outside the collapse on purpose: the chevron at the foot
                    // of the rail is what folds every overlay away, so it has
                    // to stay on screen to bring them back.
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _BroadcastRail(
                        ctrl: ctrl,
                        minimized: _minimized,
                        onToggle: _toggleMinimized,
                      ),
                    ),
                  ],
                ),
              ),
              // Who is winning, on its own plate between the chat and the
              // deck — the one line the seller calls out loud, so it gets a
              // place of its own rather than a run on the end of the price.
              AnimatedOpacity(
                duration: anim,
                opacity: _minimized ? 0 : 1,
                child: IgnorePointer(
                  ignoring: _minimized,
                  child: _WinningBidderPill(ctrl: ctrl),
                ),
              ),
              _AuctionDeck(
                ctrl: ctrl,
                onOpenQueue: widget.onOpenQueue,
                minimized: _minimized,
                anim: anim,
                maxHeight: maxCardHeight,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "<name> is winning" — the current high bidder, on a rounded plate hard left
/// between the chat and the auction deck.
///
/// The name carries the brand yellow and the verb stays muted grey, so the one
/// word the seller reads mid-sale is the one that changes. Nothing shows until
/// a bid has actually named someone, so an untouched lot leaves the gap closed.
class _WinningBidderPill extends StatelessWidget {
  const _WinningBidderPill({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final name = ctrl.activeAuction?.winnerName;
      if (name == null || name.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 3, 12, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            // A long display name would otherwise stretch the plate the whole
            // way across and stop reading as a pill.
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.7,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: name,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandYellow,
                    ),
                  ),
                  TextSpan(
                    text: ' ${TKeys.ltIsWinning.tr}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// The full-width strip along the foot of the stage that carries whatever the
/// auction is doing: the running lot (ring, price, End lot), the Start auction
/// button while idle, or the "you are watching" card on a second device.
///
/// It is a gradient, not a card. The running lot used to sit in a rounded black
/// box inside the chat column, which both fenced it off from the stage and left
/// it sharing its width with the broadcast rail. Fading the video into black
/// underneath instead gives every control the whole width and reads as part of
/// the picture.
///
/// It pads itself for the home indicator: the room's `SafeArea` opts out at the
/// bottom so the camera runs to the very edge of the screen, so this is the
/// thing that has to keep the End lot button off it.
class _AuctionDeck extends StatelessWidget {
  const _AuctionDeck({
    required this.ctrl,
    required this.onOpenQueue,
    required this.minimized,
    required this.anim,
    required this.maxHeight,
  });

  final AuctionRoomController ctrl;
  final VoidCallback onOpenQueue;
  final bool minimized;
  final Duration anim;

  /// Ceiling for the deck's content, so a tall card (the watching state) can
  /// never grow over the camera.
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    // `padding`, not `viewPadding`: it collapses to 0 once the keyboard is up,
    // so the deck sits flush on the keyboard instead of floating a home
    // indicator's worth of gradient above it.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return AnimatedSlide(
      duration: anim,
      offset: minimized ? const Offset(0, 1.4) : Offset.zero,
      child: AnimatedOpacity(
        duration: anim,
        opacity: minimized ? 0 : 1,
        child: IgnorePointer(
          ignoring: minimized,
          child: Obx(() {
            final active = ctrl.activeAuction;
            final Widget content;
            if (active != null) {
              // Shown to watchers too — read-only, since its actions are
              // already control-gated. Watching a lot run is half the reason
              // for a second screen.
              content = _ActiveAuctionCard(ctrl: ctrl, auction: active);
            } else if (ctrl.isController) {
              // Nothing to start until the feed is actually publishing, and the
              // idle card collapses to nothing then — so does the deck, rather
              // than shading the bottom of the stage for an empty strip. It
              // still holds the home-indicator inset open, which is what keeps
              // the chat field and the rail above it off the screen edge.
              final publishing =
                  ctrl.rtcJoined.value && !ctrl.broadcastPaused.value;
              if (!publishing) return SizedBox(height: bottomInset + 12);
              content = _IdleCard(ctrl: ctrl, onOpenQueue: onOpenQueue);
            } else {
              content = _WatchingCard(ctrl: ctrl);
            }
            return Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(14, 14, 14, 10 + bottomInset),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.45, 1],
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.62),
                    Colors.black.withOpacity(0.86),
                  ],
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: content,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// The room header, floating over the camera.
///
/// It replaced the white bar the room used to stack above this tab, which cost
/// the feed ~60px and framed a full-bleed stage in a card. Same information,
/// laid out like the buyer's room: the stream thumbnail as a round avatar, the
/// title beside it in a regular weight (it is a label, not a headline), then
/// the live viewer count and the ✕ that leaves.
class _RoomHeaderOverlay extends StatelessWidget {
  const _RoomHeaderOverlay({required this.ctrl, required this.onClose});
  final AuctionRoomController ctrl;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final stream = ctrl.stream;
      final title = stream?.title ?? TKeys.arAuctionRoom.tr;
      return Row(
        children: [
          _HeaderAvatar(url: stream?.thumbnailUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    // Regular, not bold: the title sits over a moving picture,
                    // and the shadow is what keeps it legible.
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                  ),
                ),
                _HeaderCountdown(ctrl: ctrl),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ViewerPill(
            live: ctrl.isLive,
            count: ctrl.audienceCount.value,
          ),
          const SizedBox(width: 8),
          _HeaderCircleButton(icon: Icons.close_rounded, onTap: onClose),
        ],
      );
    });
  }
}

/// How long the stream has left, as a sub-line under its title — the same
/// countdown the white header carries on the other tabs, so the seller doesn't
/// lose sight of it just because the Live tab dropped that bar.
///
/// Hidden until the stream is running and the server has given us an end time:
/// a scheduled stream has nothing to count down yet, and inventing "—" under
/// the title would read as a clock that has stopped.
class _HeaderCountdown extends StatelessWidget {
  const _HeaderCountdown({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final left = ctrl.timeLeft.value;
      if (!ctrl.isLive || left == null || left.isNegative) {
        return const SizedBox.shrink();
      }
      // Red in the last stretch, matching the clock banner below it.
      final color = ctrl.endingSoon ? AppColors.vipps : Colors.white70;
      return Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 12, color: color, shadows: const [
              Shadow(color: Colors.black87, blurRadius: 6),
            ]),
            const SizedBox(width: 4),
            Text(
              _fmtRemaining(left),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// `1h 20m` while there's plenty of time, `4:07` once inside the last hour —
/// the same shape the room header uses on the other tabs.
String _fmtRemaining(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '$m:${(total % 60).toString().padLeft(2, '0')}';
}

/// The stream thumbnail as a ringed avatar, falling back to a store glyph
/// while the snapshot has no image (or it fails to load).
class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    final hasUrl = url != null && url!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.45),
        border: Border.all(color: Colors.white, width: 1.6),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 8),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasUrl
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _AvatarFallback(),
            )
          : const _AvatarFallback(),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();
  @override
  Widget build(BuildContext context) => const Center(
        child: Icon(Icons.storefront_rounded, size: 20, color: Colors.white),
      );
}

/// Viewer count as a dark pill with a red dot — red and pulsing-bright while
/// the stream is live, muted grey before it starts.
class _ViewerPill extends StatelessWidget {
  const _ViewerPill({required this.live, required this.count});
  final bool live;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: live ? AppColors.vipps : AppColors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// A round translucent button for the header — currently just the ✕.
class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

/// The Show Notes tab: the same sticky note buyers tap on their side of the
/// room, drawn from the supplied art (it carries its own wordmark, so nothing
/// is lettered over it). Tapping opens the editor.
class _ShowNotesTab extends StatefulWidget {
  const _ShowNotesTab({required this.onTap});

  /// Called with the screen y the note's bottom edge sits at, so the panel can
  /// drop straight out of the tab instead of floating mid-screen.
  final ValueChanged<double> onTap;

  @override
  State<_ShowNotesTab> createState() => _ShowNotesTabState();
}

class _ShowNotesTabState extends State<_ShowNotesTab> {
  final GlobalKey _key = GlobalKey();

  /// Where the note ends on screen. Null before the first layout (or if the
  /// box has gone), and the caller falls back to a fixed inset then.
  void _handleTap() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    widget.onTap(box.localToGlobal(Offset.zero).dy + box.size.height);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _key,
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      // Sized to the art's own 431x177 (aspect 2.435) so the note is never
      // stretched, and fixed rather than intrinsic so it lays out on the first
      // frame instead of arriving a frame late over live video.
      child: SizedBox(
        width: 92,
        height: 38,
        child: Image.asset(kShowNotesAsset, fit: BoxFit.contain),
      ),
    );
  }
}

/// Binds the room controller to the prop-driven [LiveChatOverlay].
///
/// One Obx around the whole overlay: the lists it reads are lazily built inside
/// the child, and an observable touched there registers with nothing — so every
/// value the chat depends on is read here, where Obx can see it.
class _ChatOverlaySection extends StatelessWidget {
  const _ChatOverlaySection({required this.ctrl, required this.onOpenQueue});
  final AuctionRoomController ctrl;

  /// Opens the queue page from the round button that leads the say-field row.
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Copied, not referenced: iterating the RxList/RxMap here is the read
      // that makes a new line — or a name that just finished resolving —
      // repaint the chat.
      final messages = List<LiveChatMessage>.of(ctrl.messages);
      final names = Map<String, String>.of(ctrl.displayNames);
      final disabled = ctrl.chatDisabled;
      final ended = ctrl.streamEnded.value;
      final ready = ctrl.chatReady.value;
      return LiveChatOverlay(
        messages: messages,
        displayNames: names,
        canSend: ready && !disabled && !ended,
        // The field says why it is dead rather than just greying out.
        hint: disabled ? TKeys.ctChatDisabled.tr : TKeys.ctMessageHint.tr,
        showInput: !ended,
        onSend: ctrl.sendChat,
        onLongPressMessage: (m) => showChatModerationSheet(context, ctrl, m),
        onOpenQueue: onOpenQueue,
        // Read here, inside the same Obx: the button is built by the overlay,
        // where an observable touched lazily would register with nothing.
        queueCount: ctrl.queueView.length,
      );
    });
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
      // Control has just moved and the camera is still coming up. Offering Go
      // Live here would join the channel before capture is running.
      if (ctrl.mediaRoleSwitching.value) {
        return _Pill(
          color: Colors.black.withOpacity(0.55),
          onTap: null,
          loading: true,
          icon: Icons.sensors_rounded,
          label: TKeys.ltSwitchingRole.tr,
        );
      }
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
      // A device without auction control has no camera of its own on air: it
      // watches the controlling device's feed instead. Also covers the moment
      // a handoff is being applied, when neither role is fully up yet.
      if (ctrl.watching.value || ctrl.mediaRoleSwitching.value) {
        return _WatchStage(ctrl: ctrl);
      }
      // Depend on cameraOff + goLiveLoading so the preview rebuilds. Join and
      // pause state no longer belong here: the "preview only" / "stopped" note
      // they used to draw now hangs off the Show Notes row instead, and this
      // stage is the same local camera either way — see [_PreviewNote].
      final camOff = ctrl.cameraOff.value;
      final goingLive = ctrl.goLiveLoading.value;
      // The local capture source is torn down and rebuilt for a lens change,
      // so the stage blanks for a moment. Cover it rather than showing the
      // seller a frozen frame.
      final switchingCamera = ctrl.cameraSwitching.value;
      // Read here so the preview rebuilds on a mirror change — and so the
      // canvas below is rebuilt carrying the new mode. `setLocalRenderMode`
      // alone wasn't enough: this Obx recreates its [VideoViewController] on
      // every rebuild, and a fresh canvas with no mirrorMode drops back to
      // Agora's "auto" (front camera mirrored, rear not), quietly undoing the
      // seller's choice the next time anything else in here changed.
      final mirrored = ctrl.videoMirrored.value;
      if (!ctrl.rtc.isInitialized) {
        return _StageBackdrop(ctrl: ctrl, label: TKeys.ltStartingCamera.tr);
      }
      if (camOff) {
        return _StageBackdrop(ctrl: ctrl, label: TKeys.ltCameraOff.tr);
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          AgoraVideoView(
            controller: VideoViewController(
              rtcEngine: ctrl.rtc.engine,
              canvas: VideoCanvas(
                uid: 0,
                mirrorMode: mirrored
                    ? VideoMirrorModeType.videoMirrorModeEnabled
                    : VideoMirrorModeType.videoMirrorModeDisabled,
              ),
            ),
          ),
          // The one overlay the stage still owns: a scrim + spinner while the
          // channel is being joined or the lens swapped, when there is nothing
          // worth showing behind it. The publishing-state notes ("preview
          // only", "stopped") moved out to [_PreviewNote], which rides under
          // the Show Notes / Go Live row rather than floating at a hardcoded
          // 116 that had to be re-tuned every time that row moved.
          if (goingLive || switchingCamera)
            Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.white)),
            ),
        ],
      );
    });
  }
}

/// Stand-in for a camera feed — the local one before it comes up, or the main
/// device's before it arrives.
///
/// When the stream has a thumbnail we show it instead of a flat black stage, so
/// "camera off" still looks like the seller's stream rather than a dead screen.
/// The image is dimmed so the icon + copy stay readable on top of any artwork.
class _StageBackdrop extends StatelessWidget {
  const _StageBackdrop({
    required this.ctrl,
    required this.label,
    this.sublabel,
    this.icon = Icons.videocam_off_rounded,
    this.busy = false,
    this.onTap,
  });

  final AuctionRoomController ctrl;
  final String label;
  final String? sublabel;
  final IconData icon;

  /// Shows a spinner in place of [icon] — a state that is resolving itself
  /// (connecting, switching roles) rather than one waiting on the seller.
  final bool busy;

  /// Makes the whole stage a retry target. Only set where tapping actually does
  /// something, so the stage never invites a tap that goes nowhere.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final thumb = ctrl.stream?.thumbnailUrl;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
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
          Container(
              color: AppColors.brandNavy.withOpacity(thumb == null ? 0 : 0.45)),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation(Colors.white70)),
                    )
                  else
                    Icon(icon, color: Colors.white70, size: 34),
                  const SizedBox(height: 10),
                  CustomText(label,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      textAlign: TextAlign.center,
                      color: Colors.white70),
                  if (sublabel != null) ...[
                    const SizedBox(height: 5),
                    CustomText(sublabel!,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        textAlign: TextAlign.center,
                        color: Colors.white54),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The stage a seller device sees when it is *not* the one broadcasting: the
/// controlling device's live picture, exactly as buyers receive it.
///
/// Every state it can be in says which one it is, because on a black screen
/// "the main device hasn't gone live", "its camera is off" and "we never
/// connected" look identical — and only the last one is worth tapping.
class _WatchStage extends StatelessWidget {
  const _WatchStage({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.mediaRoleSwitching.value) {
        return _StageBackdrop(
            ctrl: ctrl, label: TKeys.ltSwitchingRole.tr, busy: true);
      }

      final error = ctrl.watchError.value;
      if (error != null) {
        return _StageBackdrop(
          ctrl: ctrl,
          label: error,
          icon: Icons.refresh_rounded,
          onTap: ctrl.retryWatching,
        );
      }

      // Still connecting until the join callback has actually landed — between
      // `joinAsAudience` returning and that callback there is no channel to
      // have a host in, and "waiting for the main device" would be a guess.
      final channel = ctrl.rtcChannel;
      if (ctrl.watchConnecting.value ||
          !ctrl.watchJoined.value ||
          channel == null ||
          !ctrl.rtc.isInitialized) {
        return _StageBackdrop(
            ctrl: ctrl, label: TKeys.ltWatchConnecting.tr, busy: true);
      }

      final uid = ctrl.watchedUid.value;
      if (uid == null) {
        return _StageBackdrop(
          ctrl: ctrl,
          label: TKeys.ltWaitingMainLive.tr,
          sublabel: TKeys.ltWaitingMainLiveSub.tr,
          icon: Icons.sensors_off_rounded,
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          _RemoteStage(
            key: ValueKey('$channel:$uid'),
            engine: ctrl.rtc.engine,
            uid: uid,
            channelName: channel,
          ),
          // The host is in the channel but sending no pictures — its camera is
          // off, or its feed is stopped. Cover the frozen last frame rather
          // than letting it read as a live picture that has stalled.
          if (!ctrl.remoteVideoLive.value)
            _StageBackdrop(ctrl: ctrl, label: TKeys.ltMainCameraOff.tr),
          const Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(child: _WatchingBadge()),
          ),
        ],
      );
    });
  }
}

/// Renders the controlling device's video track full-bleed.
///
/// Stateful on purpose: the Agora plugin builds one native renderer per
/// [VideoViewController], so recreating the controller on every rebuild — which
/// an `Obx` around it would do — tears the renderer down and back up, and the
/// stage flashes black each time an unrelated bit of room state changes. The
/// controller is built once here and only replaced when the host uid or the
/// channel genuinely changes.
class _RemoteStage extends StatefulWidget {
  const _RemoteStage({
    super.key,
    required this.engine,
    required this.uid,
    required this.channelName,
  });

  final RtcEngine engine;
  final int uid;
  final String channelName;

  @override
  State<_RemoteStage> createState() => _RemoteStageState();
}

class _RemoteStageState extends State<_RemoteStage> {
  late VideoViewController _controller = _build();

  VideoViewController _build() => VideoViewController.remote(
        rtcEngine: widget.engine,
        canvas: VideoCanvas(
          uid: widget.uid,
          renderMode: RenderModeType.renderModeHidden,
        ),
        connection: RtcConnection(channelId: widget.channelName),
        // A Flutter external texture rather than a native view: the room keeps
        // this stage mounted inside an IndexedStack while the seller moves
        // between tabs, and a native surface re-parented like that can come
        // back transparent.
        useFlutterTexture: true,
      );

  @override
  void didUpdateWidget(covariant _RemoteStage old) {
    super.didUpdateWidget(old);
    if (old.uid == widget.uid &&
        old.channelName == widget.channelName &&
        identical(old.engine, widget.engine)) {
      return;
    }
    setState(() => _controller = _build());
  }

  @override
  Widget build(BuildContext context) {
    // The texture produces a new frame 30–60 times a second; its own layer
    // keeps that from dirtying the overlays composited on top of it.
    return RepaintBoundary(child: AgoraVideoView(controller: _controller));
  }
}

/// Marks the stage as somebody else's picture, so a seller glancing at a second
/// handset doesn't take it for their own camera.
class _WatchingBadge extends StatelessWidget {
  const _WatchingBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          CustomText(TKeys.ltViewingMain.tr,
              fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
        ],
      ),
    );
  }
}

/// Whichever publishing-state note belongs under the Show Notes / Go Live row
/// right now — the preview pill, the stopped pill, or nothing at all.
///
/// This used to be two `Positioned(top: 116)` entries on the camera stage,
/// which meant the number had to be re-tuned every time the row above it
/// moved. Sitting in the same column as the row, it simply follows it.
class _PreviewNote extends StatelessWidget {
  const _PreviewNote({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // This device is on someone else's feed, so there is no local preview to
      // caption — the watch stage says its own piece.
      if (ctrl.watching.value || ctrl.mediaRoleSwitching.value) {
        return const SizedBox.shrink();
      }
      // The stage is under a spinner in both of these; a pill on top of it
      // would just be noise.
      if (ctrl.goLiveLoading.value || ctrl.cameraSwitching.value) {
        return const SizedBox.shrink();
      }
      // "Publishing to buyers" == joined && !paused. Stopped is the louder of
      // the two states, so it wins when both could apply.
      final Widget? note = ctrl.broadcastPaused.value
          ? const _StoppedBadge()
          : (ctrl.rtcJoined.value ? null : const _PreviewBadge());
      if (note == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        // Centred rather than stretched: these are pills, and the column they
        // sit in stretches its children edge to edge.
        child: Center(child: note),
      );
    });
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
          Icon(Icons.pause_circle_filled_rounded,
              size: 14, color: Colors.white),
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

/// Transparent vertical rail carrying the broadcast controls (mic / camera /
/// flip / ⋮) up the right edge of the stage.
///
/// It replaced a full-width frosted dock along the bottom: that dock ate a
/// whole strip of the camera and stacked a panel under the auction card. The
/// rail is Instagram-style — bare white icons with a caption under each, no
/// fill, no blur, no border — so the stage reads as camera with controls
/// floating over it, and the auction card keeps the bottom to itself.
///
/// The chevron at its foot clears the stage: it folds the rail, the auction
/// card and every banner away, leaving just the camera and a single arrow in
/// the corner to bring them back. That used to be a separate toggle in the
/// top-left; parking it at the end of the rail keeps one control for one job
/// and gives the header its corner back.
class _BroadcastRail extends StatelessWidget {
  const _BroadcastRail({
    required this.ctrl,
    required this.minimized,
    required this.onToggle,
  });
  final AuctionRoomController ctrl;

  /// Whether the stage is currently cleared — owned by [LiveTab], since the
  /// same tap hides the overlays around this rail.
  final bool minimized;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      // Both states live in the bottom-right corner, so the rail shrinks into
      // (and grows back out of) the spot the chevron was tapped.
      alignment: Alignment.bottomRight,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: minimized
            ? _RailHandle(key: const ValueKey('collapsed'), onTap: onToggle)
            : _expanded(context),
      ),
    );
  }

  Widget _expanded(BuildContext context) {
    // Transparent Material so the controls' ink splashes paint over the camera
    // rather than on the Scaffold under it.
    return Material(
      key: const ValueKey('expanded'),
      type: MaterialType.transparency,
      child: Obx(() => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ⋮ heads the rail: it is the room's menu (devices, orders,
              // show notes, media push, mirror, extend, end), not a broadcast
              // control, so it sits above the ones that are — and it is where
              // the header's ⋮ went when that bar came off the stage.
              _DockControl(
                icon: Icons.more_horiz_rounded,
                label: TKeys.ltMore.tr,
                active: true,
                onTap: () => showRoomActions(context, ctrl),
              ),
              // Mic / camera / flip drive *this* device's capture. A watcher
              // has none — showing them would offer control over a picture
              // coming from another phone — so a watcher gets the ⋮ and the
              // chevron only.
              if (ctrl.isController) ...[
                _DockControl(
                  icon: ctrl.micMuted.value
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  label:
                      ctrl.micMuted.value ? TKeys.ltUnmute.tr : TKeys.ltMute.tr,
                  active: !ctrl.micMuted.value,
                  onTap: ctrl.toggleMic,
                ),
                // Not `videocam`: that is the Live tab's own icon in the bottom
                // nav, and the same glyph meaning two things one above the
                // other read as a second way into the tab.
                _DockControl(
                  icon: ctrl.cameraOff.value
                      ? Icons.no_photography_rounded
                      : Icons.photo_camera_rounded,
                  label: TKeys.cameraSource.tr,
                  active: !ctrl.cameraOff.value,
                  onTap: ctrl.toggleCamera,
                ),
                _DockControl(
                  icon: Icons.flip_camera_ios_rounded,
                  label: TKeys.ltFlip.tr,
                  active: true,
                  onTap: ctrl.switchCamera,
                ),
                // Mirror sits under flip because they are the same question
                // asked twice — which way round the picture goes. It is local
                // media state, so it works whether or not the seller has gone
                // live: framing is usually settled during the preview.
                _DockControl(
                  icon: Icons.flip_rounded,
                  label: TKeys.ltMirror.tr,
                  active: true,
                  // On is brand yellow rather than the muted-red "off air"
                  // treatment: mirroring is a preference, not a fault.
                  tint: ctrl.videoMirrored.value ? AppColors.brandYellow : null,
                  onTap: () => ctrl.setMirrored(!ctrl.videoMirrored.value),
                ),
              ],
              InkWell(
                onTap: onToggle,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 44,
                  height: 32,
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
                ),
              ),
            ],
          )),
    );
  }
}

/// The collapsed rail: a single chevron parked in the bottom-right corner,
/// with no panel behind it. Tapping it restores the mic / camera / flip / ⋮
/// controls.
class _RailHandle extends StatelessWidget {
  const _RailHandle({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 44,
          height: 40,
          child: Icon(Icons.keyboard_arrow_up_rounded,
              size: 26,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
        ),
      ),
    );
  }
}

/// One rail control: a bare icon with its caption beneath — no tile, no fill.
/// The icon is white while the input is on and brand-red once it is muted or
/// switched off, so "something is off air" reads at a glance, and a soft drop
/// shadow keeps both legible over a bright scene.
class _DockControl extends StatelessWidget {
  const _DockControl({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.tint,
  });
  final IconData icon;
  final String label;
  final bool active;

  /// Overrides the icon colour for a control that reports a preference rather
  /// than an on-air state — [active]'s red would read as "something is off".
  final Color? tint;

  /// Null when an ancestor already owns the gesture — the ⋮ tile hands its
  /// taps to the [PopupMenuButton] wrapped around it.
  final VoidCallback? onTap;

  static const _shadows = [Shadow(color: Colors.black87, blurRadius: 8)];

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: SizedBox(
          width: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 26,
                color: tint ?? (active ? Colors.white : AppColors.vipps),
                shadows: _shadows,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: _shadows,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The idle state: one control, with no card behind it — the Start auction
/// button when there is something to start, the empty-queue note when there
/// isn't.
///
/// It used to be a white panel headlining "No auction running" plus a go-live
/// hint — a large box over the camera saying what the empty stage already
/// says. Only the action is left, and only once the feed is publishing: before
/// that there is nothing to start, and the Go Live pill at the top of the
/// stage already carries that step. The two states never show together: a
/// greyed-out button under the note only repeats what the note just said.
class _IdleCard extends StatelessWidget {
  const _IdleCard({required this.ctrl, required this.onOpenQueue});
  final AuctionRoomController ctrl;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Only allow starting a lot while we're actually publishing to buyers
      // (gone live, not stopped).
      final publishing = ctrl.rtcJoined.value && !ctrl.broadcastPaused.value;
      if (!publishing) return const SizedBox.shrink();
      // Nothing queued → there is no lot to start, so the note takes the slot
      // outright instead of sitting above a dead button. A disabled "Start
      // auction now" says only that the tap won't work; the note says why and
      // carries the one tap that fixes it.
      if (ctrl.productQueue.isEmpty) return _EmptyQueueNote(onAdd: onOpenQueue);
      return _WideButton(
        label: TKeys.ltStartAuctionNow.tr,
        icon: Icons.play_arrow_rounded,
        // The one red thing on the stage: it is the tap that puts a lot in
        // front of buyers, and on a plate this pale a navy triangle read as
        // decoration.
        iconColor: AppColors.white,
        loading: ctrl.startLoading.value,
        // The queue is non-empty by here, so what's left is the stream being
        // live and this device holding control.
        enabled: ctrl.isLive && ctrl.isController,
        height: 42,
        light: true,
        onTap: () => _openStartSheet(context, ctrl),
      );
    });
  }
}

/// "Add products to start" + an Add that jumps to the Queue tab.
///
/// A dark pill rather than a white card: it sits over the camera for as long
/// as the queue is empty, and the stage already carries the auction card's
/// weight below it.
class _EmptyQueueNote extends StatelessWidget {
  const _EmptyQueueNote({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 15, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              TKeys.ltAddProductsFirst.tr,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded,
                        size: 15, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      TKeys.ltAddNow.tr,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stands in for [_IdleCard] on a device that isn't running the auction.
///
/// It says plainly what this device *is* — a second screen onto someone else's
/// broadcast — and offers the one action that changes that, so the seller is
/// never left tapping a disabled "Start auction" wondering what is wrong.
class _WatchingCard extends StatelessWidget {
  const _WatchingCard({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.all(11),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.phonelink_rounded,
                  size: 18, color: AppColors.brandNavy),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(TKeys.ltWatchingTitle.tr,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                    const SizedBox(height: 2),
                    CustomText(TKeys.ltWatchingBody.tr,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Obx(() {
            final pending = ctrl.hasPendingControlRequest;
            return _WideButton(
              label: pending
                  ? TKeys.ltWaitingForControl.tr
                  : TKeys.ltRequestControl.tr,
              icon: Icons.pan_tool_alt_rounded,
              enabled: !pending,
              height: 38,
              onTap: ctrl.requestAuctionControl,
            );
          }),
        ],
      ),
    );
  }
}

Future<void> _openStartSheet(
    BuildContext context, AuctionRoomController ctrl) async {
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
    final urgent = secs <= 5;
    final total = a.totalDurationSec;

    // No box of its own: [_AuctionDeck] shades the whole foot of the stage
    // black behind this, so a rounded panel on top of it only drew a frame
    // around the width it was trying to use.
    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [
          // The clock is the countdown *and* the progress bar — a ring that
          // empties as the lot runs, so how much time is left reads before the
          // number does.
          _CountdownRing(
            seconds: secs,
            total: total,
            urgent: urgent,
            dutch: a.isDutch,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (a.isDutch) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kDutch.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _kDutch.withOpacity(0.7)),
                        ),
                        child: Text(
                          TKeys.auctionTypeDutchCaps.tr,
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        a.title ?? TKeys.ltCurrentLot.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // Price leads, with the bid count trailing behind it in one
                // muted line that simply truncates when the title is long. The
                // winner's name used to trail here too and was the first thing
                // the ellipsis ate — it has its own plate above the deck now.
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: _kr(a.displayPrice),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    TextSpan(
                      text:
                          '  ·  ${a.bidCount} ${TKeys.ltBids.tr.toLowerCase()}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.75),
                      ),
                    ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Shipping gets its own line rather than a fourth run on the
                // price line: that line is capped at one and already truncates
                // once a title is long, so appending here would simply have
                // pushed the winner's name out of sight. The card grows by a
                // line instead — the deck scrolls under its own height cap, so
                // there is room to give.
                if (a.shippingPrice != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_shipping_outlined,
                          size: 12, color: Colors.white.withOpacity(0.75)),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          TKeys.ltShippingAmount
                              .trParams({'price': _kr(a.shippingPrice)}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Reduce is icon-only: on a Dutch lot it is pressed repeatedly and
          // already labelled by the sheet it opens, so a second worded button
          // beside End lot only crowded the row.
          if (a.isDutch && ctrl.isController) ...[
            _RoundAction(
              icon: Icons.trending_down_rounded,
              tooltip: TKeys.ltReducePrice.tr,
              onTap: () => _openReduceSheet(context, ctrl, a),
            ),
            const SizedBox(width: 6),
          ],
          Obx(() => _EndLotButton(
                loading: ctrl.endLoading.value,
                enabled: ctrl.isController,
                onTap: ctrl.endAuction,
              )),
        ],
      ),
    );
  }
}

/// Dutch lots are marked in purple throughout the room.
const Color _kDutch = Color(0xFF9C5BD1);

/// The lot clock: seconds inside a ring that empties as the lot runs.
///
/// The ring is the innovation the old card lacked — it had the number alone,
/// which tells the seller how long is left but not how far through they are.
/// It turns red for the last five seconds, when the number alone was the only
/// warning.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({
    required this.seconds,
    required this.total,
    required this.urgent,
    required this.dutch,
  });
  final int seconds;

  /// The lot's full length, for the sweep. Null on a payload that doesn't
  /// carry it — the ring then sits full rather than guessing a fraction.
  final int? total;
  final bool urgent;
  final bool dutch;

  @override
  Widget build(BuildContext context) {
    final progress = (total != null && total! > 0)
        ? (seconds / total!).clamp(0.0, 1.0)
        : 1.0;
    final color =
        urgent ? AppColors.vipps : (dutch ? _kDutch : AppColors.brandYellow);
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: TweenAnimationBuilder<double>(
              // Animated so the ring glides between ticks instead of stepping
              // once a second.
              duration: const Duration(milliseconds: 900),
              tween: Tween(end: progress),
              builder: (_, value, __) => CircularProgressIndicator(
                value: value,
                strokeWidth: 3,
                backgroundColor: Colors.white.withOpacity(0.18),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          Text(
            '$seconds',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: urgent ? AppColors.vipps : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// The red End lot pill — the one destructive action on the stage, so it keeps
/// its word rather than becoming another glyph.
class _EndLotButton extends StatelessWidget {
  const _EndLotButton({
    required this.loading,
    required this.enabled,
    required this.onTap,
  });
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final off = !enabled || loading;
    return Opacity(
      opacity: off ? 0.5 : 1,
      child: Material(
        color: AppColors.vipps,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: off ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stop_rounded,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        TKeys.ltEndLot.tr,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
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

/// A translucent round button for a secondary action beside [_EndLotButton].
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withOpacity(0.16),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
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
      title: CustomText(TKeys.ltReduceDutchPrice.tr,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
              TKeys.ltCurrentColon.trParams({'price': _kr(a.displayPrice)}),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary),
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
          child: CustomText(TKeys.cancelAction.tr,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary),
        ),
        TextButton(
          onPressed: () {
            final v = num.tryParse(controller.text.trim());
            if (v != null) Navigator.of(dctx).pop(v);
          },
          child: CustomText(TKeys.ltReduce.tr,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy),
        ),
      ],
    ),
  );
  if (newPrice != null) await ctrl.reduceDutchPrice(newPrice);
}

// ── Shared bits ──────────────────────────────────────────────────────────────

String _kr(num? v) => v == null ? '—' : 'kr ${v % 1 == 0 ? v.toInt() : v}';

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;

  /// Overrides the default roomy inset for cards that need to stay small.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
              const Icon(Icons.timer_outlined,
                  size: 16, color: AppColors.vipps),
              const SizedBox(width: 7),
              Expanded(
                child: CustomText(
                  label,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.vipps,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                  child: CustomText(TKeys.ltExtend.tr,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.white),
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
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.vipps),
            const SizedBox(width: 10),
            Expanded(
              child: CustomText(text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.vipps),
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
            const Icon(Icons.campaign_rounded,
                size: 16, color: AppColors.brandYellow),
            const SizedBox(width: 8),
            Expanded(
              child: CustomText(text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
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
    this.height = 48,
    this.light = false,
    this.iconColor,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;
  final bool enabled;
  final double height;

  /// A half-transparent white with black text instead of the navy fill — for
  /// the button that sits straight on the camera, where a solid slab hides the
  /// picture and a dark one reads as part of it. Disabled, it drops to a
  /// shaded grey so "not yet" is obvious at a glance.
  final bool light;

  /// Colours the glyph on its own, leaving the label alone — for a button
  /// whose action wants a signal colour the text shouldn't borrow (the red
  /// play triangle on "Start auction now"). Null keeps it the label's colour.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final disabled = !enabled || loading;
    final bg = light
        ? (disabled
            ? AppColors.grey.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.0))
        : AppColors.brandNavy;
    final fg = light
        ? (disabled ? Colors.white.withOpacity(0.5) : AppColors.white)
        : Colors.white;
    final button = GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(12),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color:  fg),
                  const SizedBox(width: 8),
                  CustomText(label,
                      fontSize: 14, fontWeight: FontWeight.w800, color: fg),
                ],
              ),
      ),
    );
    // A light button carries "off" in its plate alone — the alpha is already
    // in `bg`, and the label and glyph stay at full strength. Fading the whole
    // widget took the copy down with it, which over live video left the one
    // line that explains the state unreadable.
    if (light) return button;
    // The navy one has no translucency of its own, so it still fades bodily.
    return Opacity(opacity: disabled ? 0.5 : 1, child: button);
  }
}
