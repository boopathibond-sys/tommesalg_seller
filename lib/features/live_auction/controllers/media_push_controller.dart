import 'dart:async';
import 'dart:developer';

import 'package:get/get.dart';

import '../data/models/media_push.dart';
import '../data/services/media_push_api.dart';
import '../data/services/seller_session_service.dart';
import 'auction_room_controller.dart';
import '../../../core/localization/translation_keys.dart';

/// Drives the Media Push screen opened from the auction room's ⋮ menu.
///
/// Owns nothing about the session: the room already claims it and runs the
/// heartbeat, so this controller reads `session` / `isPrimaryDevice` /
/// `isLive` off [room] and only talks to `/media-push`.
///
/// Polling follows the integration guide — 10s while converters are live, 5s
/// while LIVE and waiting for the publisher UID, 15s otherwise — which keeps
/// the screen inside the endpoint's 60/min read budget.
class MediaPushController extends GetxController {
  MediaPushController({required this.room});

  final AuctionRoomController room;

  final _api = MediaPushApi();

  String get streamId => room.streamId;

  final Rxn<MediaPushConfig> config = Rxn<MediaPushConfig>();

  /// First load only — later reloads happen under the existing content.
  final RxBool loading = true.obs;
  final RxBool refreshing = false.obs;
  final RxBool saving = false.obs;
  final RxBool starting = false.obs;
  final RxBool stopping = false.obs;

  /// Last load failure, shown as an inline banner with a retry.
  final RxnString loadError = RxnString();

  /// Warning kept on screen after a partial start (some platforms failed).
  final RxnString startWarning = RxnString();

  Timer? _poll;

  // ── Derived state ──────────────────────────────────────────────────────────

  List<MediaPushDestination> get destinations =>
      config.value?.destinations ?? const [];

  List<MediaPushConverter> get converters =>
      config.value?.converters ?? const [];

  bool get autoStart => config.value?.autoStart ?? false;
  bool get isActive => config.value?.isActive ?? false;
  bool get publisherDetected => config.value?.sellerPublisherDetected ?? false;

  bool get isPrimary => room.isPrimaryDevice;
  bool get isLive => room.isLive;

  /// True while any mutation is in flight — the whole form goes read-only.
  bool get busy =>
      saving.value || starting.value || stopping.value;

  /// Why Start is disabled, in the same order (and words) the web console uses.
  /// Null means it can run.
  String? get startDisabledReason {
    if (!isLive) return 'Stream must be LIVE';
    if (!isPrimary) return 'Only the PRIMARY device can start Media Push';
    if (destinations.isEmpty) return 'Add at least one destination';
    if (!publisherDetected) {
      return 'Publisher not detected yet — start your camera on the Live tab, '
          'then retry';
    }
    return null;
  }

  bool get canStart => startDisabledReason == null && !busy;

  /// Mutating anything (destinations, auto-start, start/stop) needs PRIMARY
  /// plus a claimed session.
  bool get canMutate => isPrimary && room.session.value != null && !busy;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    load(initial: true);
    // Background polling is off for now: it re-fired GET every 5–15s, which
    // spun the app bar's refresh indicator and burned the endpoint's 60/min
    // budget. The screen refreshes on open, on pull-to-refresh, on the app bar
    // button and after every mutation. Re-enable with `_schedulePoll()` (and
    // the `_poll` timer below) when live converter status needs to tick on its
    // own again.
    // _schedulePoll();
  }

  @override
  void onClose() {
    _poll?.cancel();
    super.onClose();
  }

  /// Reschedules on the cadence the current state calls for. Called after
  /// every load so a state change (converters came up, publisher appeared)
  /// takes effect immediately instead of at the next tick.
  void _schedulePoll() {
    final interval = _pollInterval;
    _poll?.cancel();
    _poll = Timer.periodic(interval, (_) {
      if (busy) return; // don't race a mutation's own refresh
      load(silent: true);
    });
  }

  Duration get _pollInterval {
    if (isActive) return const Duration(seconds: 10);
    if (isLive && !publisherDetected) return const Duration(seconds: 5);
    return const Duration(seconds: 15);
  }

  // ── Reads ──────────────────────────────────────────────────────────────────

  /// Named [load] rather than `refresh` so it doesn't collide with
  /// [GetxController.refresh], which notifies builders instead.
  ///
  /// [silent] skips the app bar spinner — used by the reloads that follow a
  /// mutation (which already show their own progress) and by any background
  /// poll, so the refresh icon only spins when the seller asked for it.
  Future<void> load({bool initial = false, bool silent = false}) async {
    if (!initial && !silent) refreshing.value = true;
    try {
      config.value = await _api.get(streamId);
      loadError.value = null;
      // Only reschedule when polling is actually running (see [onInit]).
      if (_poll != null && _poll!.isActive) _schedulePoll();
    } on AuctionApiException catch (e) {
      // A rate-limited poll isn't worth wiping the screen for — keep the last
      // good config and let the next tick recover.
      if (e.code != 'RATE_LIMITED' || config.value == null) {
        loadError.value = e.message;
      }
      log('Media push load failed: $e', name: 'MediaPush');
    } catch (e) {
      if (config.value == null) {
        loadError.value = 'Network error. Please try again.';
      }
      log('Media push load error: $e', name: 'MediaPush');
    } finally {
      loading.value = false;
      refreshing.value = false;
    }
  }

  // ── Destination edits (PATCH) ──────────────────────────────────────────────

  /// Appends a destination and saves the full list.
  Future<bool> addDestination(MediaPushDestination destination) {
    return _saveDestinations([...destinations, destination]);
  }

  /// Replaces the destination at [index] and saves the full list.
  Future<bool> updateDestination(int index, MediaPushDestination destination) {
    if (index < 0 || index >= destinations.length) return Future.value(false);
    final next = [...destinations]..[index] = destination;
    return _saveDestinations(next);
  }

  /// Removes one destination. `removedDestination` goes along so Agora tears
  /// its converter down — without it the RTMP push keeps running.
  Future<bool> removeDestination(int index) {
    if (index < 0 || index >= destinations.length) return Future.value(false);
    final removed = destinations[index];
    final next = [...destinations]..removeAt(index);
    return _saveDestinations(next, removed: removed);
  }

  Future<bool> setAutoStart(bool enabled) {
    return _saveDestinations(destinations, autoStart: enabled);
  }

  Future<bool> _saveDestinations(
    List<MediaPushDestination> next, {
    bool? autoStart,
    MediaPushDestination? removed,
  }) async {
    if (!canMutate) {
      _error(isPrimary
          ? 'The room session is still connecting. Try again in a moment.'
          : 'Only the PRIMARY device can change Media Push.');
      return false;
    }

    saving.value = true;
    try {
      await _api.save(
        streamId: streamId,
        session: room.session.value!,
        destinations: next,
        autoStart: autoStart ?? this.autoStart,
        removedDestination: removed,
      );
      await load(silent: true);
      return true;
    } on AuctionApiException catch (e) {
      _error(_friendly(e));
      return false;
    } catch (e) {
      log('Media push save error: $e', name: 'MediaPush');
      _error('Network error. Please try again.');
      return false;
    } finally {
      saving.value = false;
    }
  }

  // ── Start / stop ───────────────────────────────────────────────────────────

  /// `POST …/media-push`. Guard-railed the same way the button is, so a stale
  /// tap can't fire an impossible start.
  Future<bool> start() async {
    final reason = startDisabledReason;
    if (reason != null) {
      _error(reason);
      return false;
    }
    if (!canMutate) return false;

    starting.value = true;
    startWarning.value = null;
    try {
      final result = await _api.start(
        streamId: streamId,
        session: room.session.value!,
        destinations: destinations,
        autoStart: autoStart,
      );

      // Partial success: at least one converter came up, but some platforms
      // were rejected — keep the reasons on screen rather than in a snackbar
      // that disappears.
      if (result.errors.isNotEmpty) {
        startWarning.value = result.errorSummary;
        _info('Media Push started for '
            '${result.converters.length} of '
            '${result.converters.length + result.errors.length} destinations.');
      } else {
        _info('Media Push started.');
      }

      await load(silent: true);
      return true;
    } on AuctionApiException catch (e) {
      _error(_friendly(e));
      return false;
    } catch (e) {
      log('Media push start error: $e', name: 'MediaPush');
      _error('Network error. Please try again.');
      return false;
    } finally {
      starting.value = false;
    }
  }

  /// `DELETE …/media-push` — disconnects every external platform.
  Future<bool> stop() async {
    if (!canMutate) {
      _error('Only the PRIMARY device can stop Media Push.');
      return false;
    }

    stopping.value = true;
    try {
      final deleted = await _api.stop(
        streamId: streamId,
        session: room.session.value!,
      );
      startWarning.value = null;
      _info(deleted > 0
          ? 'Media Push stopped ($deleted ${deleted == 1 ? 'converter' : 'converters'}).'
          : 'Media Push stopped.');
      await load(silent: true);
      return true;
    } on AuctionApiException catch (e) {
      _error(_friendly(e));
      return false;
    } catch (e) {
      log('Media push stop error: $e', name: 'MediaPush');
      _error('Network error. Please try again.');
      return false;
    } finally {
      stopping.value = false;
    }
  }

  /// Stop, then start again with the same destinations — the guide's fix for
  /// duplicate or stuck converters.
  Future<void> restart() async {
    if (!await stop()) return;
    if (destinations.isEmpty) return;
    await start();
  }

  // ── Messaging ──────────────────────────────────────────────────────────────

  /// Turns the V1 error code into copy the seller can act on. Branching is on
  /// `code`, never on the message text.
  String _friendly(AuctionApiException e) {
    switch (e.code) {
      case 'AUTH_FORBIDDEN':
        return 'Only the PRIMARY device can change Media Push. Take main '
            'device control from Devices & control, then try again.';
      case 'AUTH_ROLE_REQUIRED':
        return 'Sign in with your seller account to use Media Push.';
      case 'AUTH_EXPIRED':
        return 'Your session expired. Reopen the room and try again.';
      case 'NOT_FOUND':
        return 'This stream is no longer available.';
      case 'RATE_LIMITED':
        return 'Too many attempts. Wait a few seconds and try again.';
      case 'TIMEOUT':
        return e.message;
      default:
        return e.message;
    }
  }

  void _info(String message) {
    Get.snackbar(TKeys.mpMediaPush.tr, message,
        snackPosition: SnackPosition.BOTTOM);
  }

  void _error(String message) {
    Get.snackbar(TKeys.mpMediaPush.tr, message,
        snackPosition: SnackPosition.BOTTOM);
  }
}
