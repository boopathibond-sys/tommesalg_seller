import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/services/media_permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../views/home/home_view.dart';
import '../controllers/auction_room_controller.dart';
import 'tabs/chat_tab.dart';
import 'tabs/live_tab.dart';
import 'tabs/orders_tab.dart';
import 'tabs/queue_tab.dart';
import 'widgets/room_sheets.dart';
import '../../../core/localization/translation_keys.dart';

/// Entry point for the seller live auction room. Owns the [AuctionRoomController]
/// lifecycle (scoped to [streamId]) and hosts the Live / Queue / Chat tabs.
class AuctionRoomView extends StatefulWidget {
  const AuctionRoomView({super.key, required this.streamId, this.title});

  final String streamId;
  final String? title;

  @override
  State<AuctionRoomView> createState() => _AuctionRoomViewState();
}

class _AuctionRoomViewState extends State<AuctionRoomView>
    with WidgetsBindingObserver {
  late final AuctionRoomController ctrl;
  late final Worker _extendPromptWorker;
  int _tab = 0;
  bool _extendPromptOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ctrl = Get.put(
      AuctionRoomController(streamId: widget.streamId),
      tag: widget.streamId,
    );
    // The controller raises this when the stream is 5 (then 1) minutes from
    // auto-ending, so the seller is asked to extend instead of being cut off.
    _extendPromptWorker = ever<int?>(ctrl.extendPrompt, _onExtendPrompt);
  }

  Future<void> _onExtendPrompt(int? minutesLeft) async {
    if (minutesLeft == null || _extendPromptOpen || !mounted) return;
    // Clear it right away so the next threshold (and any re-arm after an
    // extension) fires cleanly.
    ctrl.extendPrompt.value = null;
    _extendPromptOpen = true;
    try {
      await showEndingSoonDialog(context, ctrl, minutesLeft: minutesLeft);
    } finally {
      _extendPromptOpen = false;
    }
  }

  /// Coming back from the system settings page is the only way an iPhone can
  /// grant camera/mic after a refusal, and the app gets no callback for it — so
  /// re-check on resume and bootstrap the room the moment both are in place.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    if (!ctrl.permissionDenied.value) return;
    MediaPermissionService.hasCameraAndMic().then((granted) {
      if (granted && mounted && ctrl.permissionDenied.value) ctrl.enterRoom();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _extendPromptWorker.dispose();
    Get.delete<AuctionRoomController>(tag: widget.streamId);
    super.dispose();
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: CustomText(TKeys.arLeaveRoomTitle.tr,
            fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        content: const CustomText(
          'Your broadcast will stop and this device will disconnect. The stream '
          'itself stays live until you end it.',
          fontSize: 14, fontWeight: FontWeight.w500, height: 1.4,
          color: AppColors.textSecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: CustomText(TKeys.stay.tr, fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: CustomText(TKeys.arLeave.tr, fontSize: 14,
                fontWeight: FontWeight.w800, color: AppColors.vipps),
          ),
        ],
      ),
    );
    return leave == true;
  }

  /// Prompts to leave and, if confirmed (and still mounted), closes the route.
  /// Captures the navigator before the await so no `BuildContext` crosses it.
  Future<void> _confirmLeaveAndClose() async {
    final navigator = Navigator.of(context);
    if (await _confirmLeave() && mounted) _close(navigator);
  }

  /// Closes the room (used from the "stream ended" screen and the back arrow).
  ///
  /// The route goes first and the teardown follows: `dispose()` deletes the
  /// controller, whose `onClose` releases the session, the sockets and the RTC
  /// engine. Releasing the engine *before* popping tears the camera down while
  /// [LiveTab]'s `AgoraVideoView` is still mounted, which leaves its native
  /// surface behind as a black screen over whatever comes next.
  ///
  /// The pop result is `true` when the stream is over (ended here, timed out,
  /// or a `STREAM_ENDED` push arrived) — the streams list uses it to flip the
  /// card to "Ended" straight away instead of keeping a dead "Live" row that
  /// errors when tapped.
  void _close(NavigatorState navigator) {
    final ended = ctrl.streamEnded.value;
    // Opened straight from a push tap on a cold start there may be nothing
    // underneath; popping the last route would leave an empty (black) window,
    // so land on Home instead.
    if (navigator.canPop()) {
      navigator.pop(ended);
    } else {
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeView()),
      );
    }
  }

  /// Leaves from the "stream ended" screen — the same close path, with no
  /// confirmation (there is no broadcast left to interrupt).
  void _leaveAndClose() => _close(Navigator.of(context));

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmLeaveAndClose();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          // `bottom: false` so [_RoomBottomNav] can paint its own surface all
          // the way down to the screen edge and pad itself for the home
          // indicator, instead of floating above a white gap.
          bottom: false,
          child: Obx(() {
            if (ctrl.permissionDenied.value) {
              return _PermissionDenied(
                ctrl: ctrl,
                // Read inside the Obx so the screen swaps its action if the
                // state changes under it.
                permanent: ctrl.permissionPermanentlyDenied.value,
              );
            }
            if (ctrl.isBootstrapping.value) return const _Bootstrapping();
            if (ctrl.bootstrapError.value != null) {
              return _RoomError(
                message: ctrl.bootstrapError.value!,
                onRetry: ctrl.enterRoom,
              );
            }
            if (ctrl.streamEnded.value) {
              return _StreamEnded(onLeave: _leaveAndClose);
            }

            return Column(
              children: [
                _RoomHeader(
                  title: widget.title ?? ctrl.stream?.title ?? TKeys.arAuctionRoom.tr,
                  ctrl: ctrl,
                  onBack: _confirmLeaveAndClose,
                ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      LiveTab(ctrl: ctrl),
                      QueueTab(ctrl: ctrl),
                      OrdersTab(ctrl: ctrl),
                      ChatTab(ctrl: ctrl),
                    ],
                  ),
                ),
                _RoomBottomNav(
                  ctrl: ctrl,
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.title, required this.ctrl, required this.onBack});
  final String title;
  final AuctionRoomController ctrl;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(title,
                    fontSize: 17, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Obx(() {
                  final live = ctrl.isLive;
                  final left = ctrl.timeLeft.value;
                  final urgent = ctrl.endingSoon;
                  // A scheduled stream has no countdown yet, so spell out when
                  // it's planned to start rather than when it would end.
                  final planned = (ctrl.stream?.isScheduled ?? false)
                      ? ctrl.plannedAtLabel
                      : null;
                  return Row(
                    children: [
                      Container(
                        width: 7, height: 7,
                        decoration: BoxDecoration(
                          color: live ? AppColors.vipps : AppColors.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      CustomText(
                        live ? 'LIVE' : (ctrl.stream?.status ?? ''),
                        fontSize: 11, fontWeight: FontWeight.w800,
                        color: live ? AppColors.vipps : AppColors.textMuted,
                      ),
                      if (!live && planned != null) ...[
                        const SizedBox(width: 5),
                        // Flexible, not bare: the date makes this the longest
                        // item in the row, and it's the one that should ellipsis
                        // rather than push the viewer count off screen.
                        Flexible(
                          child: CustomText(
                            TKeys.arPlannedAt.trParams({'time': planned}),
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      const SizedBox(width: 10),
                      const Icon(Icons.remove_red_eye_outlined,
                          size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      CustomText('${ctrl.audienceCount.value}',
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppColors.textMuted),
                      // Time left before the stream auto-ends — tap to add more.
                      if (live && left != null && !left.isNegative) ...[
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => showExtendDialog(context, ctrl),
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              Icon(Icons.timer_outlined, size: 13,
                                  color: urgent
                                      ? AppColors.vipps
                                      : AppColors.textMuted),
                              const SizedBox(width: 3),
                              CustomText(
                                _fmtRemaining(left),
                                fontSize: 11, fontWeight: FontWeight.w700,
                                color: urgent
                                    ? AppColors.vipps
                                    : AppColors.textMuted,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                }),
              ],
            ),
          ),
          IconButton(
            onPressed: () => showRoomActions(context, ctrl),
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// `1h 20m` while there's plenty of time, `4:07` once inside the last hour.
String _fmtRemaining(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '$m:${(total % 60).toString().padLeft(2, '0')}';
}

/// Full-bleed bottom navigation for the room's Live / Queue / Orders / Chat
/// tabs.
///
/// It sits at the very bottom of the screen (the room's `SafeArea` opts out of
/// the bottom inset so this bar paints its own surface behind the home
/// indicator) and spans the full width. The Live tab is a full-bleed camera
/// stage, and the floating segmented control this replaced read as one more
/// overlay competing with the broadcast controls.
class _RoomBottomNav extends StatelessWidget {
  const _RoomBottomNav({
    required this.ctrl,
    required this.index,
    required this.onChanged,
  });

  final AuctionRoomController ctrl;
  final int index;
  final ValueChanged<int> onChanged;

  // Getter, not a stored field: `.tr` must re-resolve when the seller
  // switches language, and a field initialiser only ever runs once.
  static List<String> get _labels => [
        TKeys.arTabLive.tr,
        TKeys.arTabQueue.tr,
        TKeys.ordersLabel.tr,
        TKeys.arTabChat.tr,
      ];
  // Filled while selected, outlined while not — the usual bottom-nav cue.
  static const _icons = [
    Icons.videocam_rounded,
    Icons.inventory_2_rounded,
    Icons.receipt_long_rounded,
    Icons.chat_bubble_rounded,
  ];
  static const _iconsOutline = [
    Icons.videocam_outlined,
    Icons.inventory_2_outlined,
    Icons.receipt_long_outlined,
    Icons.chat_bubble_outline_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    // `padding`, not `viewPadding`: it collapses to 0 once the keyboard is up
    // (Chat tab), so the bar sits flush on the keyboard instead of floating a
    // home-indicator's worth of white above it.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(top: 8, bottom: 6 + bottomInset),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: const Border(
            top: BorderSide(color: AppColors.borderGrey, width: 1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.06),
            blurRadius: 18, offset: const Offset(0, -6),
          ),
        ],
      ),
      // Transparent Material so the items' ink splashes paint above this
      // container's white fill instead of on the Scaffold beneath it.
      child: Material(
        type: MaterialType.transparency,
        // One Obx around the whole row, reading both counts up front. Wrapping
        // each item instead threw "improper use of a GetX": the Live and Chat
        // items carry no badge, so their Obx touched no observable at all.
        child: Obx(() {
          // Counts the seller acts on: lots lined up, and orders the stream
          // has produced so far.
          final badges = [0, ctrl.queueView.length, ctrl.orders.length, 0];
          return Row(
            children: List.generate(_labels.length, (i) {
              return Expanded(
                child: _NavItem(
                  label: _labels[i],
                  icon: i == index ? _icons[i] : _iconsOutline[i],
                  selected: i == index,
                  badge: badges[i],
                  onTap: () => onChanged(i),
                ),
              );
            }),
          );
        }),
      ),
    );
  }
}

/// One bottom-nav destination: an icon in a pill that fills with brand navy
/// when selected, its label beneath, and an optional count badge.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.badge,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: 52, height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.brandNavy : Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, size: 19,
                      color: selected
                          ? AppColors.brandYellow
                          : AppColors.textMuted),
                ),
                if (badge > 0)
                  Positioned(
                    top: -3, right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      constraints: const BoxConstraints(minWidth: 17),
                      height: 17,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.vipps,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: AppColors.white, width: 1.5),
                      ),
                      child: CustomText(badge > 99 ? '99+' : '$badge',
                          fontSize: 9, fontWeight: FontWeight.w800,
                          color: AppColors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            CustomText(label, fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                color: selected ? AppColors.textPrimary : AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Bootstrapping extends StatelessWidget {
  const _Bootstrapping();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppColors.brandNavy)),
          const SizedBox(height: 16),
          CustomText(TKeys.arOpeningRoom.tr,
              fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

/// Shown when camera/mic were refused. [permanent] decides which way out is
/// offered: asking again is pointless once the OS has stopped prompting (always
/// the case on iOS after a refusal), so that state leads to the settings page —
/// and the resume check in [_AuctionRoomViewState] picks the room back up when
/// the seller returns with the grants in place.
class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied({required this.ctrl, required this.permanent});
  final AuctionRoomController ctrl;
  final bool permanent;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_rounded, size: 48, color: AppColors.vipps),
          const SizedBox(height: 16),
          CustomText(TKeys.arPermissionTitle.tr,
              fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          CustomText(
            permanent
                ? 'To broadcast your live auction we need access to your camera '
                    'and microphone. Turn them on in Settings — the room opens '
                    'by itself when you come back.'
                : 'To broadcast your live auction we need access to your camera '
                    'and microphone. Tap Allow on the prompts to continue.',
            fontSize: 13, fontWeight: FontWeight.w500, height: 1.4,
            textAlign: TextAlign.center, color: AppColors.textSecondary,
          ),
          const SizedBox(height: 20),
          _PrimaryButton(
            label: permanent ? TKeys.arOpenSettings.tr : TKeys.arAllowAccess.tr,
            onTap: () {
              if (permanent) {
                ctrl.openPermissionSettings();
              } else {
                ctrl.enterRoom();
              }
            },
          ),
          if (permanent) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: ctrl.enterRoom,
              child: CustomText(TKeys.tryAgain.tr, fontSize: 13.5,
                  fontWeight: FontWeight.w700, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoomError extends StatelessWidget {
  const _RoomError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.vipps),
          const SizedBox(height: 16),
          CustomText(TKeys.arCouldNotOpenRoom.tr,
              fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          const SizedBox(height: 8),
          CustomText(message, fontSize: 13, fontWeight: FontWeight.w500,
              height: 1.4, textAlign: TextAlign.center, color: AppColors.textSecondary),
          const SizedBox(height: 20),
          _PrimaryButton(label: TKeys.retryAction.tr, onTap: onRetry),
        ],
      ),
    );
  }
}

class _StreamEnded extends StatelessWidget {
  const _StreamEnded({required this.onLeave});
  final VoidCallback onLeave;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 48, color: AppColors.brandNavy),
            const SizedBox(height: 16),
            CustomText(TKeys.arStreamEnded.tr,
                fontSize: 18, fontWeight: FontWeight.w800,
                textAlign: TextAlign.center, color: AppColors.textPrimary),
            const SizedBox(height: 8),
            CustomText(TKeys.arStreamFinished.tr,
                fontSize: 13, fontWeight: FontWeight.w500,
                textAlign: TextAlign.center, color: AppColors.textSecondary),
            const SizedBox(height: 20),
            _PrimaryButton(label: TKeys.arBackToStreams.tr, onTap: onLeave),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.brandNavy,
          borderRadius: BorderRadius.circular(12),
        ),
        child: CustomText(label, fontSize: 14,
            fontWeight: FontWeight.w800, color: AppColors.white),
      ),
    );
  }
}
