import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/services/media_permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../views/home/home_view.dart';
import '../controllers/auction_room_controller.dart';
import 'tabs/live_tab.dart';
import 'tabs/queue_tab.dart';
import 'widgets/room_sheets.dart';
import '../../../core/localization/translation_keys.dart';

/// Entry point for the seller live auction room. Owns the [AuctionRoomController]
/// lifecycle (scoped to [streamId]) and hosts the full-screen [LiveTab].
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
        // A watcher has no broadcast to stop — telling it that one will stop
        // reads as "leaving will take the stream down", which is the opposite
        // of what happens.
        content: CustomText(
          ctrl.isController
              ? TKeys.arLeaveBodyBroadcast.tr
              : TKeys.arLeaveBodyWatching.tr,
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

  /// Opens the lot queue as a route over the room.
  ///
  /// It used to be a bottom-nav tab. The nav is gone — the camera owns the
  /// whole screen now — so the queue is reached from the round button beside
  /// the chat field and pushed on top, which also means the broadcast keeps
  /// running underneath instead of being swapped out of an `IndexedStack`.
  void _openQueue() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => QueuePage(ctrl: ctrl)),
    );
  }

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
          // `bottom: false` so the camera stage runs all the way down to the
          // screen edge. The Live tab's auction deck pads itself for the home
          // indicator, so nothing tappable ends up under it.
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

            // The room is the camera, full screen: the queue is a pushed page
            // and the orders are a sheet off the ⋮ menu, so there is no bottom
            // nav and no white header left to frame the feed.
            return LiveTab(
              ctrl: ctrl,
              onClose: _confirmLeaveAndClose,
              onOpenQueue: _openQueue,
            );
          }),
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
