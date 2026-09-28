import 'dart:async';
import 'dart:developer';
import 'dart:math' hide log;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/env_config.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/media_permission_service.dart';
import '../data/models/auction_room_snapshot.dart';
import '../data/models/catalog_product.dart';
import '../data/models/display_name_entry.dart';
import '../data/models/live_chat_message.dart';
import '../data/models/pre_bid.dart';
import '../data/models/seller_session.dart';
import '../data/models/session_device.dart';
import '../data/models/stream_order.dart';
import '../data/models/seller_camera_option.dart';
import '../data/services/agora_rtc_broadcaster_service.dart';
import '../data/services/agora_rtm_service.dart';
import '../data/services/agora_token_service.dart';
import '../data/services/auction_room_api.dart';
import '../data/services/auction_ws_service.dart';
import '../data/services/chat_moderation_api.dart';
import '../data/services/display_name_service.dart';
import '../data/services/seller_camera_service.dart';
import '../data/services/seller_camera_storage.dart';
import '../data/services/seller_session_service.dart';
import '../views/widgets/control_request_dialog.dart';
import '../../../core/localization/translation_keys.dart';

/// The figures a bid event carries, once [AuctionRoomController._readBidUpdate]
/// has found them in whatever envelope the backend used.
class _BidUpdate {
  const _BidUpdate({
    required this.amount,
    this.auctionId,
    this.bidCount,
    this.bidderName,
  });
  final num amount;

  /// Who placed it, when the frame named them — what the winning-bidder pill
  /// shows. Null simply leaves the last known name in place.
  final String? bidderName;

  /// Null when the frame didn't name a lot; the update is then taken as being
  /// about whichever one is running.
  final String? auctionId;
  final int? bidCount;
}

/// A product the seller can add to the queue (sourced from the stream's
/// prepared product requests).
class AddableProduct {
  const AddableProduct({required this.productId, required this.name, this.image});
  final String productId;
  final String name;
  final String? image;
}

/// Orchestrates the whole seller auction room: camera/mic broadcast (Agora
/// RTC), live chat (Agora RTM), the session lease + heartbeat, the snapshot
/// WebSocket, and every REST mutation.
///
/// Snapshot is truth: local state is never optimistically patched. Mutations
/// wait for the fresh snapshot (mutation response or a newer WS SNAPSHOT), and
/// incoming snapshots are applied only when their [snapshotVersion] is newer.
class AuctionRoomController extends GetxController {
  AuctionRoomController({required this.streamId});

  final String streamId;
  static const _uuid = Uuid();

  // ── Services ───────────────────────────────────────────────────────────────
  final _tokenService = AgoraTokenService();
  final _rtc = AgoraRtcBroadcasterService();
  final _camera = SellerCameraService();
  final _rtm = AgoraRtmService();
  final _sessionService = SellerSessionService();
  final _api = AuctionRoomApi();
  final _chatApi = ChatModerationApi();
  final _nameService = DisplayNameService();
  AuctionWebSocketService? _ws;

  AgoraRtcBroadcasterService get rtc => _rtc;

  /// The Agora channel this room is on, once bootstrap has resolved it. The
  /// watcher's remote video view needs it to name the connection it renders
  /// from.
  String? get rtcChannel => _rtcChannel;

  // ── Reactive state ───────────────────────────────────────────────────────
  final Rxn<AuctionRoomSnapshot> snapshot = Rxn<AuctionRoomSnapshot>();
  final Rxn<SellerSession> session = Rxn<SellerSession>();
  final RxList<LiveChatMessage> messages = <LiveChatMessage>[].obs;

  /// Resolved chat-sender names, `userId -> display name`. Filled once per new
  /// sender by a batched lookup and read by every bubble from that id — a buyer
  /// who sends twenty lines costs exactly one request.
  final RxMap<String, String> displayNames = <String, String>{}.obs;

  final RxList<AddableProduct> addableProducts = <AddableProduct>[].obs;
  final RxList<CatalogProduct> catalogProducts = <CatalogProduct>[].obs;

  /// Queue as rendered by the draggable list. Mirrors the snapshot's product
  /// queue, but can be optimistically reordered during a drag so the move feels
  /// instant; reconciled with server truth once the position PATCHes land.
  final RxList<AuctionProduct> queueView = <AuctionProduct>[].obs;
  bool _reorderingQueue = false;
  bool _verifyingQueueWipe = false;

  final RxBool isBootstrapping = true.obs;
  final RxnString bootstrapError = RxnString();
  final RxBool permissionDenied = false.obs;

  /// True when camera/mic can no longer be granted from a system prompt (iOS
  /// after any refusal, Android after "Don't ask again") — the only way back is
  /// the app's settings page.
  final RxBool permissionPermanentlyDenied = false.obs;

  final RxBool wsConnected = false.obs;
  final RxBool connectionLost = false.obs;
  final RxBool rtcJoined = false.obs;
  final RxBool streamEnded = false.obs;

  // ── Watch mode (a seller device without auction control) ──────────────────
  // Exactly one seller device publishes. Every other device in the room joins
  // the same Agora channel as an *audience member* and watches that feed, so a
  // second phone shows what buyers are seeing instead of a second camera that
  // can never go on air. The axis is auction control, not PRIMARY: a PRIMARY
  // device that handed control away is a watcher too, and the device that holds
  // control is the one whose picture everyone else sees.

  /// True while this device is watching the controlling device's camera rather
  /// than running its own. Drives the whole room UI: no broadcast dock, no
  /// start-auction, no queue edits.
  final RxBool watching = false.obs;

  /// True once the audience join has landed. Distinct from [rtcJoined], which
  /// stays false on a watcher — nothing is being published from here.
  final RxBool watchJoined = false.obs;

  /// The controlling device's RTC uid, once it shows up in the channel. Null
  /// means nobody is broadcasting yet ("waiting for the main device").
  final RxnInt watchedUid = RxnInt();

  /// Whether the watched host is actually sending frames right now — false
  /// while its camera is off or its feed is stopped, so the watcher is told
  /// which of the two it is instead of staring at a black stage.
  final RxBool remoteVideoLive = false.obs;

  /// Set when the audience join itself failed (token, network). The Live tab
  /// offers a retry rather than leaving a permanently blank stage.
  final RxnString watchError = RxnString();

  /// True while an audience join is in flight, so the stage can say
  /// "connecting" instead of "waiting for the main device".
  final RxBool watchConnecting = false.obs;

  /// Which role the RTC engine is actually running in — true publishing, false
  /// watching, null before the first start. Compared against [isController] to
  /// notice a handoff and swap the engine over; kept separate from [watching]
  /// so the flag the UI reads is only ever flipped by a switch that ran.
  bool? _broadcastingMedia;

  /// Serialises the role switches, so two polls landing together can't run a
  /// swap twice or interleave a leave with a join.
  Future<void>? _mediaRoleTask;

  /// True while a swap is running — the stage shows a spinner rather than a
  /// half-torn-down camera.
  final RxBool mediaRoleSwitching = false.obs;

  // Chat (Agora RTM) connection state — surfaced so a silent RTM failure shows
  // a retry affordance instead of an empty, dead chat.
  final RxBool chatReady = false.obs;
  final RxnString chatError = RxnString();

  final RxBool micMuted = false.obs;
  final RxBool cameraOff = false.obs;

  /// Whether the outgoing picture is mirrored left↔right. Off by default: a
  /// seller holding up a label wants buyers to be able to read it.
  final RxBool videoMirrored = false.obs;
  final RxInt audienceCount = 0.obs;

  // ── Camera / lens selection ───────────────────────────────────────────────
  // Built from what the handset actually reports, never a hard-coded lens list,
  // so a phone with one rear camera shows two entries and an iPhone Pro shows
  // five. Purely local media state: none of it touches auction, bid or queue
  // state, and a camera failure here can never end a stream.
  final RxList<SellerCameraOption> cameraOptions = <SellerCameraOption>[].obs;
  final Rxn<SellerCameraOption> selectedCamera = Rxn<SellerCameraOption>();
  final RxBool cameraSwitching = false.obs;

  /// Set when a lens change failed, cleared on the next attempt. The selector
  /// surfaces it as "the current camera is still active" — never as an error
  /// that implies the broadcast is down.
  final RxnString cameraError = RxnString();

  // "Stop Live" = mic + camera cut to buyers only. Since Agora's
  // muteLocal*Stream stops the outgoing tracks but leaves local capture /
  // preview running, the seller keeps seeing themselves while stopped. There
  // is no server pause endpoint, so this is purely the local publish state —
  // the stream stays LIVE and Go Live resumes without any API call.
  final RxBool broadcastPaused = false.obs;

  /// The seller's live banner text, or null when nothing is showing.
  ///
  /// Held here rather than read straight off the snapshot: a partial frame
  /// replaces the whole `stream` object without necessarily mentioning the
  /// announcement, which would blank a banner that is still up. Only frames
  /// that actually talk about it update this (see [_syncAnnouncement]), and the
  /// PUT / DELETE results are applied immediately.
  final RxnString announcement = RxnString();
  final RxBool announcementSaving = false.obs;

  /// The stream's description — the "Show Notes" the seller writes for buyers,
  /// or null when none is set. Held here for the same reason as [announcement]:
  /// a partial frame that never mentions `description` must not blank it.
  final RxnString showNotes = RxnString();
  final RxBool showNotesSaving = false.obs;

  final RxBool queueActionLoading = false.obs;
  final RxBool creatingRandomProduct = false.obs;
  final RxBool startLoading = false.obs;
  final RxBool endLoading = false.obs;
  final RxBool goLiveLoading = false.obs;
  final RxBool loadingProducts = false.obs;
  final RxBool loadingCatalog = false.obs;

  // ── Stream end countdown ──────────────────────────────────────────────────
  // Time left until `stream.streamEndsAt`, ticked once a second off the
  // server-corrected clock. Null when the stream has no end time yet.
  final Rxn<Duration> timeLeft = Rxn<Duration>();

  /// Set to the threshold (in minutes) the countdown just crossed — 5, then 1 —
  /// so the room can prompt the seller to extend before the stream cuts out.
  /// The view clears it once handled; extending re-arms both thresholds.
  final RxnInt extendPrompt = RxnInt();

  /// End time learned from the go-live / extend responses. Kept as a fallback
  /// (and an instant update) for snapshots that don't carry `streamEndsAt`.
  final RxnString reportedEndsAt = RxnString();

  /// Remaining-minute marks that raise [extendPrompt], largest first.
  static const _extendPromptThresholds = [5, 1];

  Timer? _countdownTimer;
  int? _countdownEndsAt;
  int? _lastPromptedThreshold;

  // Multi-device control + moderation state. The two pending lists back
  // independent handoff systems and are kept apart: a PRIMARY requestId is only
  // valid on /primary/*, an auction one only on /auction-control/*.
  final RxList<SessionDevice> devices = <SessionDevice>[].obs;
  final RxList<ControlRequest> pendingPrimaryRequests = <ControlRequest>[].obs;
  final RxList<ControlRequest> pendingControlRequests = <ControlRequest>[].obs;
  final RxList<StreamOrder> orders = <StreamOrder>[].obs;
  final RxBool loadingOrders = false.obs;

  /// Device holding auction control, straight from the server snapshot, so the
  /// devices list can badge the right row rather than infer it.
  final RxnString auctionControllerDeviceId = RxnString();

  /// Request ids we've already surfaced as a prompt, so the poll loop nags the
  /// seller exactly once per incoming request.
  final Set<String> _announcedRequestIds = {};

  /// Request currently shown in the accept / decline dialog, so a second poll
  /// doesn't stack another one and a request that stops being answerable takes
  /// its prompt down with it.
  String? _promptedRequestId;

  /// Set when another device is waiting on *this* device to answer. The Live tab
  /// renders it as a banner so a request is visible without opening the Devices
  /// sheet — polling is pointless if nothing surfaces the result.
  final Rxn<ControlRequest> incomingPrimaryRequest = Rxn<ControlRequest>();
  final Rxn<ControlRequest> incomingControlRequest = Rxn<ControlRequest>();

  int _serverOffsetMs = 0;
  int get serverOffsetMs => _serverOffsetMs;

  // RTC identity, stable across token renewals.
  final int _rtcUid = Random().nextInt(1 << 30) + 1;
  String? _rtcChannel;
  String? _rtmChannel;
  String? _rtmUserId;

  Timer? _heartbeatTimer;
  Timer? _devicePollTimer;
  final Set<String> _seenMessageIds = {};

  // Chat display-name resolution: ids waiting for the next batch, and every id
  // we've already asked about (so a repeat sender never triggers a second call).
  final Set<String> _pendingNameIds = {};
  final Set<String> _requestedNameIds = {};
  Timer? _nameDebounce;

  // Convenience getters for the UI.
  AuctionRoomSnapshot? get snap => snapshot.value;
  StreamSnapshot? get stream => snapshot.value?.stream;
  ActiveAuction? get activeAuction => snapshot.value?.activeAuction;
  List<AuctionProduct> get productQueue => snapshot.value?.productQueue ?? const [];
  bool get isController => session.value?.isAuctionController ?? false;

  /// True when this device owns the session (the "main device"). Distinct from
  /// [isController]: a SECONDARY device can hold auction control, and a PRIMARY
  /// device can have handed auction control away.
  bool get isPrimaryDevice => session.value?.isPrimary ?? false;

  /// True once we know we're a *secondary* device without auction control —
  /// i.e. the session is claimed but the primary device still owns the room.
  /// Drives the "Request control" pill in place of Go Live.
  bool get needsControl => session.value != null && !isController;

  /// Whether the local camera / mic controls apply to this device at all.
  ///
  /// False on a watcher, whose engine is an audience member with no capture
  /// source: the dock these drive is hidden there, and this is the backstop
  /// that keeps a stale callback or a pending gesture from restarting a camera
  /// the device has deliberately put away.
  bool get _canDriveMedia =>
      isController && !watching.value && !mediaRoleSwitching.value;
  bool get isLive => stream?.isLive ?? false;
  bool get chatDisabled => stream?.chatDisabled ?? false;
  List<String> get mutedUserIds => snapshot.value?.mutedUserIds ?? const [];
  bool isMuted(String userId) => mutedUserIds.contains(userId);
  /// Whether the queue may be edited from *this* device.
  ///
  /// The stream has to be in a state that has a queue at all, and this device
  /// has to hold auction control. The backend accepts queue writes from any
  /// device with a live session, but two sellers rearranging the same queue
  /// from two handsets is how a lot gets started on the wrong product — so the
  /// app keeps the queue with whoever is actually running the auction. A
  /// watcher sees the queue read-only and can ask for control to change it.
  bool get canManageQueue {
    final s = stream;
    return s != null &&
        !s.isTerminal &&
        (s.isLive || s.isScheduled) &&
        isController;
  }

  @override
  void onInit() {
    super.onInit();
    _startCountdown();
    enterRoom();
  }

  // ── Bootstrap ──────────────────────────────────────────────────────────────

  Future<void> enterRoom() async {
    isBootstrapping.value = true;
    bootstrapError.value = null;
    permissionDenied.value = false;
    // This is the retry path as well as the first entry — the error screen, the
    // permission screen and a resume from settings all land here. Anything a
    // previous attempt managed to bring up is torn down first, so a retry never
    // stacks a second websocket, a second RTM login or an RTC engine stuck in
    // the wrong role on top of the first.
    await _teardownRealtime();
    try {
      // 1) Claim the seller session (deviceId + sessionToken + control).
      //    This comes first because the answer decides whether this device
      //    needs a camera at all: a device that joins as a watcher never opens
      //    one, so asking it for camera/mic up front would be prompting for
      //    hardware it will not touch.
      session.value = await _sessionService.claim(streamId);
      _startHeartbeat();
      // Poll for role changes + incoming control requests. Must not wait on the
      // WS: a request raised from the seller web console reaches us only here.
      _startDevicePolling();

      // 2) Camera + mic, but only for the device that will publish. If it
      //    refuses, hand the session straight back rather than sitting on the
      //    controlling seat with no picture to give — another device can then
      //    claim it and run the stream.
      if (isController) {
        final granted = await _ensurePermissions();
        if (!granted) {
          permissionDenied.value = true;
          await _abandonSession();
          isBootstrapping.value = false;
          return;
        }
      }

      // 3) Load the authoritative snapshot.
      final snap = await _api.getSnapshot(streamId);
      _applySnapshot(snap, authoritative: true);

      // 4) Connect realtime transports.
      await _connectRealtime(snap);

      // 5) Prepare addable products + device panel in the background, and make
      //    sure an empty Queue tab really means an empty queue.
      unawaited(fetchAddableProducts());
      unawaited(loadDevices());
      unawaited(_verifyQueueAgainstCatalog());
    } on AuctionApiException catch (e) {
      bootstrapError.value = e.message;
      log('Auction room bootstrap error: $e');
    } catch (e) {
      bootstrapError.value = 'Could not open the auction room. Please try again.';
      log('Auction room bootstrap error: $e');
    } finally {
      isBootstrapping.value = false;
    }
  }

  /// Camera + mic, asked for one at a time (see [MediaPermissionService]) so an
  /// iPhone doesn't swallow the second system alert. Records whether the
  /// refusal is recoverable in-app, so the room's permission screen can offer
  /// the settings shortcut instead of a "Try again" that can no longer prompt.
  Future<bool> _ensurePermissions() async {
    final outcome = await MediaPermissionService.ensureCameraAndMic();
    permissionPermanentlyDenied.value =
        outcome == MediaPermissionOutcome.permanentlyDenied;
    return outcome == MediaPermissionOutcome.granted;
  }

  /// Opens the system settings page for the app. Nothing is awaited on the way
  /// back — the room view re-checks on resume and bootstraps itself once both
  /// grants are in place.
  Future<void> openPermissionSettings() => MediaPermissionService.openSettings();

  /// Drops every realtime transport this room owns, leaving the session alone.
  ///
  /// The RTC engine is released rather than reused: it carries a client role
  /// (publisher or audience) and, for a publisher, a live capture source, and
  /// the next attempt may well need the other one. Rebuilding it costs a moment
  /// on a screen that is already showing a spinner.
  Future<void> _teardownRealtime() async {
    _ws?.dispose();
    _ws = null;
    wsConnected.value = false;
    await _rtm.dispose();
    chatReady.value = false;
    chatError.value = null;
    _camera.detach();
    cameraOptions.clear();
    selectedCamera.value = null;
    await _rtc.release();
    rtcJoined.value = false;
    watching.value = false;
    watchJoined.value = false;
    watchedUid.value = null;
    remoteVideoLive.value = false;
    watchError.value = null;
    watchConnecting.value = false;
    broadcastPaused.value = false;
    micMuted.value = false;
    cameraOff.value = false;
    // Nothing is running, so the next device-snapshot must not mistake this for
    // a role that needs switching — [_startMedia] owns the next start.
    _broadcastingMedia = null;
  }

  /// Hands a just-claimed session back and forgets it, so [enterRoom] can claim
  /// again on the next attempt.
  ///
  /// Used when a claim succeeds but the device turns out to be unable to do the
  /// job it claimed the seat for (camera/mic refused). Without the reset the
  /// device would hold PRIMARY — and with it the right to broadcast — while
  /// showing the permission screen, locking every other device out of a stream
  /// nobody can then put on air.
  Future<void> _abandonSession() async {
    await _releaseSession();
    _sessionReleased = false;
    session.value = null;
    _heartbeatTimer?.cancel();
    _devicePollTimer?.cancel();
  }

  Future<void> _connectRealtime(AuctionRoomSnapshot snap) async {
    // The RTC channel name IS the stream id (same as the web client), which
    // already carries the `stream_` prefix — e.g. `stream_1783668733749_…`.
    // Never prefix it again, or the token is minted for `stream_stream_…`
    // while we join `stream_…`, and the seller loses publisher rights.
    // Prefer the backend's snapshot hint (now un-double-prefixed), but collapse
    // any lingering `stream_stream_` and fall back to the raw stream id.
    final rtcHint = snap.realtime?.rtcChannelName;
    _rtcChannel = (rtcHint != null && rtcHint.isNotEmpty)
        ? rtcHint.replaceFirst('stream_stream_', 'stream_')
        : streamId;
    // Chat channel MUST match the buyer app exactly, or the two sit on
    // different RTM channels and never see each other's messages. The buyer
    // hardcodes `auction:<streamId>` (LiveStreamController._chatChannel) and
    // ignores any backend hint, so we do the same rather than trusting
    // `realtime.rtmChannelName`.
    _rtmChannel = 'auction:$streamId';
    _rtmUserId = AuthService.instance.currentUser?.id;

    await Future.wait([
      _startMedia(),
      _startChat(),
      _connectWs(snap),
    ]);
  }

  // ── Agora RTC (broadcast / watch) ────────────────────────────────────────

  /// Brings the RTC engine up in whichever role this device holds: publisher
  /// (camera preview, ready to go live) or watcher (audience, showing the
  /// controlling device's feed).
  Future<void> _startMedia() =>
      isController ? _startBroadcast() : _startWatching();

  /// Brings up the local camera **preview only** — the seller sees themselves,
  /// but we do NOT join the RTC channel yet, so buyers receive nothing. Joining
  /// (and thus publishing) is deferred to [startPublishing], called on Go Live.
  /// The one exception is reconnecting to an already-LIVE stream, where we join
  /// immediately so the broadcast resumes.
  Future<void> _startBroadcast() async {
    watching.value = false;
    _broadcastingMedia = true;
    try {
      final channel = _rtcChannel!;
      final token = await _tokenService.fetchRtcToken(
        channelName: channel,
        uid: _rtcUid,
      );
      await _rtc.initialize(
        appId: token.appId,
        onJoinSuccess: _onRtcJoined,
        onRemoteHostJoined: _onRemoteHostJoined,
        onRemoteHostOffline: _onRemoteHostOffline,
        onRemoteVideoChanged: _onRemoteVideoChanged,
        onConnectionStateChanged: (_, __) {},
        onTokenWillExpire: _renewRtcToken,
        onError: (msg) => log('RTC error: $msg'),
        beforePreview: _initCameraSelection,
      );
      // initialize() has already started the local *preview* (seller sees
      // themselves). We deliberately do NOT join the channel here — not even
      // when the stream is already LIVE — so entering the room never publishes
      // to buyers. Publishing begins only when the seller taps Go Live
      // (startPublishing()).
    } catch (e) {
      log('startBroadcast error: $e');
    }
  }

  /// Joins the stream's channel as an audience member and renders whatever the
  /// controlling device is broadcasting.
  ///
  /// Nothing here publishes, opens the camera or asks for a permission: a
  /// watcher is, to Agora, an ordinary viewer of the same channel buyers watch.
  /// It is safe to call before the controlling device has gone live — the join
  /// simply sits in an empty channel until a host appears, and
  /// [_onRemoteHostJoined] picks the feed up the moment it does.
  Future<void> _startWatching() async {
    final channel = _rtcChannel;
    if (channel == null) return;
    watching.value = true;
    _broadcastingMedia = false;
    watchError.value = null;
    watchConnecting.value = true;
    try {
      final token = await _tokenService.fetchRtcToken(
        channelName: channel,
        uid: _rtcUid,
      );
      await _rtc.initialize(
        appId: token.appId,
        publisher: false,
        onJoinSuccess: _onRtcJoined,
        onRemoteHostJoined: _onRemoteHostJoined,
        onRemoteHostOffline: _onRemoteHostOffline,
        onRemoteVideoChanged: _onRemoteVideoChanged,
        onConnectionStateChanged: (_, __) {},
        onTokenWillExpire: _renewRtcToken,
        onError: (msg) => log('RTC error: $msg'),
      );
      await _rtc.joinAsAudience(
        token: token.token,
        channelName: channel,
        uid: _rtcUid,
      );
    } catch (e) {
      log('startWatching error: $e');
      watchError.value = TKeys.ltWatchFailed.tr;
    } finally {
      watchConnecting.value = false;
    }
  }

  /// Retry for a failed audience join (the tap target on the watcher's stage).
  ///
  /// The engine usually survives a failed attempt, so this throws away whatever
  /// half-join it is holding and asks for a fresh token: rejoining a channel
  /// the engine still thinks it is in is refused by the SDK, and the stage
  /// would sit on the same error it was just tapped to clear.
  Future<void> retryWatching() async {
    if (isController || watchConnecting.value) return;
    watchError.value = null;
    watchJoined.value = false;
    watchedUid.value = null;
    remoteVideoLive.value = false;
    await _rtc.leaveChannel();
    await _startWatching();
  }

  /// A join landed. Which flag it sets depends on the role: a publisher is now
  /// on air, a watcher is merely connected.
  void _onRtcJoined() {
    if (watching.value) {
      watchJoined.value = true;
      rtcJoined.value = false;
    } else {
      rtcJoined.value = true;
    }
  }

  /// A remote *host* appeared in the channel.
  ///
  /// As a watcher that is the controlling device's feed — adopt it as the one
  /// we render. As the publisher it is another broadcaster, which is what the
  /// viewer counter has always been counting.
  void _onRemoteHostJoined(int uid) {
    if (watching.value) {
      // First host wins. A second one would only appear during a handoff, and
      // switching stages mid-swap would flicker for no gain.
      watchedUid.value ??= uid;
      return;
    }
    audienceCount.value++;
  }

  void _onRemoteHostOffline(int uid) {
    if (watching.value) {
      if (watchedUid.value != uid) return;
      // The controlling device left (ended, backgrounded, lost the network).
      // Drop the canvas so the stage explains itself instead of freezing on the
      // last frame; the next host to appear is picked up automatically.
      watchedUid.value = null;
      remoteVideoLive.value = false;
      return;
    }
    audienceCount.value = max(0, audienceCount.value - 1);
  }

  void _onRemoteVideoChanged(int uid, bool hasVideo) {
    if (!watching.value) return;
    // A host can start sending video before onUserJoined is processed.
    watchedUid.value ??= uid;
    if (watchedUid.value != uid) return;
    remoteVideoLive.value = hasVideo;
  }

  // ── Role switching (auction control moved) ───────────────────────────────

  /// Brings the RTC engine in line with who holds auction control now.
  ///
  /// Called after every device-snapshot that changed this device's control
  /// flag. Queued behind any switch already running, and a no-op when the
  /// engine is already in the right role — including before bootstrap has
  /// started one at all, which [_startMedia] owns.
  Future<void> _applyMediaRole() {
    final next = (_mediaRoleTask ?? Future<void>.value())
        .then((_) => _syncMediaRole())
        .catchError((Object e) => log('media role switch error: $e'));
    _mediaRoleTask = next;
    return next;
  }

  Future<void> _syncMediaRole() async {
    final current = _broadcastingMedia;
    if (current == null) return; // bootstrap owns the first start
    final want = isController;
    if (current == want) return;
    if (streamEnded.value || isClosed) return;
    _broadcastingMedia = want;
    mediaRoleSwitching.value = true;
    try {
      if (want) {
        await _switchToBroadcasting();
      } else {
        await _switchToWatching();
      }
    } finally {
      mediaRoleSwitching.value = false;
    }
  }

  /// This device was handed auction control: stop watching and bring its own
  /// camera up as a preview.
  ///
  /// Publishing is *not* started here. Taking control mid-stream is usually a
  /// seller picking a second phone up before it is pointed at anything, so the
  /// picture buyers get stays the seller's decision — the Go Live pill is
  /// waiting for them.
  Future<void> _switchToBroadcasting() async {
    await _rtc.leaveChannel();
    watching.value = false;
    watchJoined.value = false;
    watchedUid.value = null;
    remoteVideoLive.value = false;
    watchError.value = null;

    // Watchers never asked for camera/mic, so this is the first time this
    // device needs them. A refusal leaves it with control it cannot use, so
    // say so through the room's permission screen rather than a dead stage.
    final granted = await _ensurePermissions();
    if (!granted) {
      // Control without a camera is a dead room. Release the engine so the
      // permission screen's "Try again" re-bootstraps from scratch rather than
      // reusing an audience engine that can never preview.
      await _teardownRealtime();
      permissionDenied.value = true;
      return;
    }

    if (_rtc.isInitialized) {
      await _rtc.becomePublisher();
      // The engine was created without the lens hook (watchers don't capture),
      // so resolve the seller's saved camera now that capture is running.
      await _initCameraSelection(_rtc.engine);
      await _rtc.reapplyMirror();
    } else {
      // The watch path never got an engine up (a failed join). Build one.
      await _startBroadcast();
    }
    _broadcastingMedia = true;
    // Manual mute state is per-device and meaningless while watching; start
    // the publisher role from a clean, un-muted, un-paused slate.
    micMuted.value = false;
    cameraOff.value = false;
    broadcastPaused.value = false;
    _showInfo(TKeys.acControlNowYours.tr);
  }

  /// Auction control moved to another device: take this one off air and put it
  /// on the controlling device's feed.
  Future<void> _switchToWatching() async {
    // Leaving the channel is what actually stops buyers receiving this device.
    await _rtc.leaveChannel();
    rtcJoined.value = false;
    broadcastPaused.value = false;
    if (_rtc.isInitialized) {
      _camera.detach();
      cameraOptions.clear();
      selectedCamera.value = null;
      await _rtc.becomeAudience();
    }
    _showInfo(TKeys.acControlNowElsewhere.tr);
    await _startWatching();
  }

  /// Joins the RTC channel and begins publishing camera + mic to buyers. Called
  /// when the seller taps Go Live. Fetches a fresh token at join time so a long
  /// pre-live preview can't join with an expired one. No-op if already joined.
  Future<void> startPublishing() async {
    final channel = _rtcChannel;
    if (channel == null || _rtc.isJoined) return;
    // Last line of defence: never publish from a device that doesn't hold
    // auction control (callers already check, so no snackbar here).
    if (!isController) {
      log('startPublishing blocked — this device has no auction control.');
      return;
    }
    try {
      final token = await _tokenService.fetchRtcToken(
        channelName: channel,
        uid: _rtcUid,
      );
      await _rtc.joinAsBroadcaster(
        token: token.token,
        channelName: channel,
        uid: _rtcUid,
      );
    } catch (e) {
      log('startPublishing error: $e');
    }
  }

  Future<void> _renewRtcToken() async {
    try {
      final channel = _rtcChannel;
      if (channel == null) return;
      final token = await _tokenService.fetchRtcToken(
        channelName: channel,
        uid: _rtcUid,
      );
      await _rtc.renewToken(token.token);
    } catch (e) {
      log('renewRtcToken error: $e');
    }
  }

  Future<void> toggleMic() async {
    if (!_canDriveMedia) return;
    final next = !micMuted.value;
    await _rtc.setMuted(next);
    micMuted.value = next;
  }

  Future<void> toggleCamera() async {
    if (!_canDriveMedia) return;
    final next = !cameraOff.value;
    await _rtc.setCameraOff(next);
    cameraOff.value = next;
  }

  /// The Mirror control: swaps the picture left↔right for buyers, and mirrors
  /// the seller's own stage to match so the preview never disagrees with what
  /// is going out.
  ///
  /// Purely a media setting — no channel is left, no capture source is
  /// restarted and no auction state is touched, so it is safe to flip mid-lot.
  /// The service swallows its own failures, so the flag only follows what the
  /// engine actually accepted.
  ///
  /// Takes the state to move *to* rather than flipping whatever it finds: the
  /// menu reads the flag when it opens and acts when it closes, so a toggle
  /// would act on a value that is already a moment old.
  Future<void> setMirrored(bool mirrored) async {
    if (!_canDriveMedia) return;
    if (videoMirrored.value == mirrored) return;
    await _rtc.setMirrored(mirrored);
    videoMirrored.value = _rtc.isMirrored;
  }

  Future<void> toggleMirror() => setMirrored(!videoMirrored.value);

  /// The Flip control. Jumps to the opposite-facing lens through the same
  /// selection path as the picker, so the two never disagree about which
  /// camera is live; falls back to Agora's plain flip when we have no
  /// capability list to reason about.
  Future<void> switchCamera() async {
    if (!_canDriveMedia) return;
    final current = selectedCamera.value;
    final options = cameraOptions;
    if (current == null || options.isEmpty) {
      await _rtc.switchCamera();
      return;
    }
    final wantFront = current.mode != SellerCameraMode.front;
    for (final option in options) {
      if ((option.mode == SellerCameraMode.front) == wantFront) {
        await selectCamera(option);
        return;
      }
    }
    // Only one facing available on this device — nothing to flip to.
    await _rtc.switchCamera();
  }

  // ── Camera / lens selection ──────────────────────────────────────────────

  /// Runs between engine init and the first camera frame: discover the lenses,
  /// resolve the seller's saved preference against them, and configure capture
  /// before it starts.
  ///
  /// Every step is best-effort. If the query fails, or the stored lens no
  /// longer exists on this handset, the stream still comes up on the device
  /// default — startup must never hinge on an optional lens.
  Future<void> _initCameraSelection(RtcEngine engine) async {
    _camera.attach(engine);
    final options = await _camera.queryOptions();
    cameraOptions.assignAll(options);
    if (options.isEmpty) return;
    final saved = await SellerCameraStorage.readMode(streamId);
    final resolved = SellerCameraService.resolvePreferred(saved, options);
    if (resolved == null) return;
    if (await _camera.applyConfiguration(resolved)) {
      selectedCamera.value = resolved;
    }
  }

  /// Switches the seller to [option] mid-stream.
  ///
  /// The Agora channel is kept: only local capture is reconfigured, so the
  /// seller stays in the same room, buyers keep receiving the feed, and the
  /// auction, its timer and its bids are untouched. Repeat taps while a switch
  /// is in flight are dropped, and a failure leaves the previous lens running.
  Future<void> selectCamera(SellerCameraOption option) async {
    if (!_canDriveMedia) return;
    if (cameraSwitching.value) return;
    if (selectedCamera.value?.mode == option.mode) return;
    cameraSwitching.value = true;
    cameraError.value = null;
    try {
      final ok = await _camera.switchTo(option);
      if (!ok) {
        cameraError.value = TKeys.csSwitchFailed.tr;
        return;
      }
      selectedCamera.value = option;
      // Capture was torn down and rebuilt; make sure the channel still counts
      // the camera as published before trusting that buyers can see it.
      await _rtc.ensureCameraPublishing();
      // The new capture source comes up unmirrored, so a seller who had chosen
      // Mirror would otherwise see it silently undone by picking another lens.
      await _rtc.reapplyMirror();
      // The rail's manual mute states survive a capture restart on the SDK
      // side, but re-assert them so a restart can never silently un-hide a
      // seller who had the camera off or the broadcast stopped.
      if (cameraOff.value || broadcastPaused.value) {
        await _rtc.setCameraOff(true);
      }
      await SellerCameraStorage.writeMode(streamId, option.mode);
    } finally {
      cameraSwitching.value = false;
    }
  }

  /// Re-runs capability discovery — for a seller who plugged in / unlocked a
  /// lens, or simply to retry after a failed query.
  Future<void> refreshCameraCapabilities() async {
    if (!_canDriveMedia) return;
    final options = await _camera.queryOptions();
    cameraOptions.assignAll(options);
    final current = selectedCamera.value;
    if (current != null && !options.any((o) => o.mode == current.mode)) {
      selectedCamera.value =
          options.isEmpty ? null : SellerCameraService.selectDefault(options);
    }
  }

  /// Stops / resumes broadcasting to buyers in one tap ("Stop Live" / "Go
  /// Live"). Stopping cuts the outgoing camera + mic so buyers stop seeing and
  /// hearing us, while the seller's own local preview keeps running. Resuming
  /// restores whatever manual mic/camera state was set before. No server call —
  /// the stream stays LIVE, so this never re-hits the go-live endpoint.
  Future<void> togglePauseBroadcast() async {
    if (!_ensureControl(TKeys.actStartStopFeed.tr)) return;
    if (broadcastPaused.value) {
      // Resume: restore the manual mic/camera state the rail still reflects.
      await _rtc.setMuted(micMuted.value);
      await _rtc.setCameraOff(cameraOff.value);
      broadcastPaused.value = false;
    } else {
      // Stop live: cut both outgoing tracks. We deliberately leave
      // micMuted/cameraOff untouched so the local preview stays visible to the
      // seller (muteLocalVideoStream doesn't stop local capture).
      await _rtc.setMuted(true);
      await _rtc.setCameraOff(true);
      broadcastPaused.value = true;
    }
  }

  // ── Agora RTM (chat) ─────────────────────────────────────────────────────

  Future<void> _startChat() async {
    chatError.value = null;
    try {
      final userId = _rtmUserId;
      if (userId == null || userId.isEmpty) {
        chatReady.value = false;
        chatError.value = 'Chat unavailable — no signed-in user.';
        return;
      }
      final token = await _tokenService.fetchRtmToken(userId: userId);
      await _rtm.initAndLogin(
        appId: token.appId,
        userId: userId,
        token: token.token,
        onMessage: _onChatMessage,
        onModerationDelete: _onModerationDelete,
        onModerationClear: _onModerationClear,
        onTokenWillExpire: _renewRtmToken,
        onError: (msg) => log('RTM error: $msg'),
      );
      await _rtm.subscribe(_rtmChannel!);
      chatReady.value = true;
    } catch (e) {
      chatReady.value = false;
      chatError.value = 'Chat failed to connect. Tap to retry.';
      log('startChat error: $e');
    }
  }

  /// Tears down and re-runs the RTM connect after a chat failure (the retry
  /// affordance in the Chat tab). No-op once chat is live.
  Future<void> retryChat() async {
    if (chatReady.value) return;
    await _rtm.dispose();
    await _startChat();
  }

  Future<void> _renewRtmToken() async {
    try {
      final userId = _rtmUserId;
      if (userId == null) return;
      final token = await _tokenService.fetchRtmToken(userId: userId);
      await _rtm.renewToken(token.token);
    } catch (e) {
      log('renewRtmToken error: $e');
    }
  }

  void _onChatMessage(LiveChatMessage message) {
    if (_seenMessageIds.contains(message.id)) return;
    _seenMessageIds.add(message.id);
    final isMine = message.senderId == _rtmUserId;
    messages.add(message.copyWith(isMine: isMine));
    if (messages.length > 300) messages.removeRange(0, messages.length - 300);

    // RTM only carries the publisher id, so the real name comes from the API —
    // once per sender, batched (see [_scheduleNameResolve]).
    if (!isMine) _scheduleNameResolve(message.senderId);

    // Sender identity diagnostics: RTM hands us only the publisher id, so log
    // exactly what a buyer message carries while we work out where a real name
    // can come from. Debug builds only.
    if (!isMine && kDebugMode) {
      log('CHAT from buyer → senderId="${message.senderId}" '
          'name=${message.senderName ?? '(none in payload)'} '
          'id=${message.id} ts=${message.timestamp} text="${message.text}"');
    }
  }

  // ── Chat display names ──────────────────────────────────────────────────────

  /// Queues [senderId] for a batched name lookup, debounced ~250 ms so a burst
  /// of arrivals (ten buyers joining at once) collapses into a single request.
  ///
  /// Ids already resolved — or already asked about — are dropped here, which is
  /// what keeps repeat messages from the same buyer free.
  void _scheduleNameResolve(String senderId) {
    if (senderId.isEmpty || senderId == _rtmUserId) return;
    if (displayNames.containsKey(senderId)) return;
    if (!_requestedNameIds.add(senderId)) return;
    _pendingNameIds.add(senderId);
    _nameDebounce?.cancel();
    _nameDebounce =
        Timer(const Duration(milliseconds: 250), _flushNameResolve);
  }

  Future<void> _flushNameResolve() async {
    if (_pendingNameIds.isEmpty) return;
    // One request per 50 ids — the server's cap. Anything over stays queued and
    // goes out on the next flush.
    final batch =
        _pendingNameIds.take(DisplayNameService.maxIdsPerRequest).toList();
    _pendingNameIds.removeAll(batch);
    try {
      final entries = await _nameService.fetch(batch);
      // Only ids the server knew go in the cache — an id it doesn't recognise
      // keeps the chat's own "User abc123" placeholder. Either way it stays in
      // [_requestedNameIds], so the next message from them costs no call.
      final resolved = <String, String>{
        for (final id in batch)
          if (entries.containsKey(id)) id: resolveDisplayName(id, entries),
      };
      if (resolved.isNotEmpty) displayNames.addAll(resolved);
    } catch (e) {
      log('display-name resolve failed: $e');
      // Non-fatal — bubbles fall back to the short id. Allow a later retry.
      _requestedNameIds.removeAll(batch);
    }
    if (_pendingNameIds.isNotEmpty) {
      _nameDebounce?.cancel();
      _nameDebounce = Timer(Duration.zero, _flushNameResolve);
    }
  }

  void _onModerationDelete(String messageId) {
    messages.removeWhere((m) => m.id == messageId);
  }

  void _onModerationClear() {
    messages.clear();
    _seenMessageIds.clear();
  }

  Future<void> sendChat(String text) async {
    final trimmed = text.trim();
    final userId = _rtmUserId;
    if (trimmed.isEmpty || userId == null) return;
    final id = _uuid.v4();
    final ts = DateTime.now().millisecondsSinceEpoch;
    // Echo locally so the seller sees their own line immediately (RTM does not
    // deliver a publisher's own messages back).
    _seenMessageIds.add(id);
    messages.add(LiveChatMessage(
      id: id,
      senderId: userId,
      text: trimmed,
      timestamp: ts,
      senderName: 'You',
      isMine: true,
    ));
    if (messages.length > 300) messages.removeRange(0, messages.length - 300);
    try {
      await _rtm.sendMessage(id: id, text: trimmed, ts: ts);
    } catch (e) {
      log('sendChat error: $e');
    }
  }

  /// Deletes a message server-side (persisted + fanned out over the auction WS
  /// to every viewer). The RTM broadcast is a best-effort echo for instant
  /// local removal on other seller devices.
  Future<void> deleteChatMessage(String messageId) async {
    messages.removeWhere((m) => m.id == messageId);
    try {
      await _chatApi.deleteMessage(streamId, messageId);
      unawaited(_rtm.sendModeration(type: 'MODERATION_DELETE', messageId: messageId));
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
    } catch (e) {
      log('deleteChatMessage error: $e');
    }
  }

  Future<void> clearChat() async {
    _onModerationClear();
    try {
      await _chatApi.clear(streamId);
      unawaited(_rtm.sendModeration(type: 'MODERATION_CLEAR'));
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
    } catch (e) {
      log('clearChat error: $e');
    }
  }

  /// Enables / disables the whole chat (`chatDisabled` in the snapshot). Blocks
  /// buyers from posting until re-enabled.
  Future<void> toggleChatEnabled() async {
    final disable = !chatDisabled;
    try {
      if (disable) {
        await _chatApi.disableChat(streamId);
      } else {
        await _chatApi.enableChat(streamId);
      }
      await refreshSnapshot();
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
    } catch (e) {
      log('toggleChatEnabled error: $e');
    }
  }

  /// Mutes / unmutes a single viewer, then refreshes so `mutedUserIds` reflects
  /// the server truth.
  Future<void> muteUser(String userId) async {
    try {
      await _chatApi.mute(streamId, userId);
      await refreshSnapshot();
      _showInfo('User muted.');
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
    } catch (e) {
      log('muteUser error: $e');
    }
  }

  Future<void> unmuteUser(String userId) async {
    try {
      await _chatApi.unmute(streamId, userId);
      await refreshSnapshot();
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
    } catch (e) {
      log('unmuteUser error: $e');
    }
  }

  // ── WebSocket ──────────────────────────────────────────────────────────────

  Future<void> _connectWs(AuctionRoomSnapshot snap) async {
    final wsBase = EnvConfig.baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    _ws = AuctionWebSocketService(
      wsBaseUrl: wsBase,
      wsPath: '/ws/auction',
      accessTokenParam: snap.realtime?.accessTokenQueryParam ?? 'access_token',
      getAccessToken: () async => AuthService.instance.accessToken,
      refreshSession: AuthService.instance.refreshSessionSafe,
      onMessage: _onWsMessage,
      onConnected: (c) {
        wsConnected.value = c;
        if (c) connectionLost.value = false;
      },
      onConnectionLost: () => connectionLost.value = true,
    );
    await _ws!.connect(streamId);
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    final type = msg['type'];
    switch (type) {
      case 'SNAPSHOT':
        final data = _extractSnapshot(msg);
        if (data != null) _applySnapshot(AuctionRoomSnapshot.fromJson(data));
        break;
      case 'STREAM_ENDED':
        streamEnded.value = true;
        break;
      case 'CHAT_CLEARED':
        _onModerationClear();
        break;
      case 'MESSAGE_DELETED':
        final id = msg['payload'] is Map
            ? (msg['payload'] as Map)['messageId'] as String?
            : msg['messageId'] as String?;
        if (id != null) _onModerationDelete(id);
        break;
      case 'CONTROL_REQUESTS_UPDATED':
        // Multi-device control changes — refresh the devices panel + snapshot.
        unawaited(loadDevices());
        unawaited(refreshSnapshot());
        break;
      case 'AUCTION_ENDED':
      case 'AUCTION_RESULT':
      case 'PRODUCT_SOLD':
      case 'ORDER_CREATED':
        // The room normally learns about a sale from the SNAPSHOT frame, but
        // honour a dedicated event too so the queue + orders still catch up if
        // the backend announces the sale without a full snapshot.
        unawaited(_refreshAfterSale());
        break;
      default:
        _handleUnmodelledEvent(msg);
        break;
    }
  }

  /// Anything the room doesn't model by name.
  ///
  /// This used to be a bare `default: break`, and that is what made a bid take
  /// seconds to show: the backend announces one with its own event type, and
  /// dropping it left the card sitting on the last `SNAPSHOT` until the next
  /// one happened along. The event carries the figures already — there is no
  /// reason to wait for a round trip that has nothing new in it.
  ///
  /// Rather than guessing at type names (the contract in `lib/raw` documents
  /// the resume handshake and `SNAPSHOT`, never the broadcast events), the
  /// payload is mined by shape: an amount plus an auction id is a bid whatever
  /// the frame is called. A wrong guess costs nothing — [_applyBidUpdate] is
  /// forward-only, and the next snapshot overwrites everything regardless.
  void _handleUnmodelledEvent(Map<String, dynamic> msg) {
    // Keep-alives and the resume handshake are expected traffic, not events —
    // naming them would bury the frames worth looking at.
    const quiet = {'pong', 'ping', 'WS_RESUME_ACK', 'RESUME_ACK'};
    if (quiet.contains(msg['type'])) return;
    final payload = msg['payload'] is Map<String, dynamic>
        ? msg['payload'] as Map<String, dynamic>
        : (msg['data'] is Map<String, dynamic>
            ? msg['data'] as Map<String, dynamic>
            : msg);
    final bid = _readBidUpdate(payload);
    if (bid != null) _applyBidUpdate(bid);
    if (kReleaseMode) return;
    log('WS "${msg['type']}" — '
        '${bid == null ? 'no bid figures in payload' : 'read as a bid: '
            '${bid.amount} (${bid.bidCount ?? '?'} bids)'}');
  }

  /// Posts a bid read off a WS event straight onto the running lot.
  ///
  /// Forward-only in both figures independently: an amount that doesn't beat
  /// what the card already shows, and a count that doesn't exceed it, are
  /// dropped. That is what makes it safe to apply an event we only inferred —
  /// an out-of-order or speculative frame can never walk the price backwards,
  /// and a `SNAPSHOT` remains the authority the moment one arrives.
  void _applyBidUpdate(_BidUpdate bid) {
    final snap = snapshot.value;
    final active = snap?.activeAuction;
    if (snap == null || active == null) return;
    // A frame about some other lot — a late one from the auction we just
    // ended, say — is not ours to apply.
    if (bid.auctionId != null &&
        active.id != null &&
        bid.auctionId != active.id) {
      return;
    }
    final shown = active.highestBid ?? active.currentPrice ?? 0;
    final beatsPrice = bid.amount > shown;
    final beatsCount = bid.bidCount != null && bid.bidCount! > active.bidCount;
    if (!beatsPrice && !beatsCount) return;
    snapshot.value = snap.copyWith(
      activeAuction: active.copyWith(
        highestBid: beatsPrice ? bid.amount : null,
        bidCount: beatsCount ? bid.bidCount : null,
        // Only when this bid actually took the lead: a frame that lost the
        // forward-only race must not rename the seller's winner.
        winnerName: beatsPrice ? bid.bidderName : null,
      ),
    );
  }

  /// Pulls a bid out of an arbitrary event payload, or null when there isn't
  /// one. The figures may sit at the top level or one wrapper down.
  static _BidUpdate? _readBidUpdate(Map<String, dynamic> payload) {
    for (final scope in [
      payload,
      if (payload['bid'] is Map)
        Map<String, dynamic>.from(payload['bid'] as Map),
      if (payload['auction'] is Map)
        Map<String, dynamic>.from(payload['auction'] as Map),
      if (payload['activeAuction'] is Map)
        Map<String, dynamic>.from(payload['activeAuction'] as Map),
    ]) {
      // `price` is deliberately not in this list: on this backend a product's
      // `price` is its retail figure, not a bid, and it is typically *higher*
      // than the live one — reading it as a bid would sail past the
      // forward-only guard and post a fictional price.
      final amount = _firstNum(
        scope,
        const ['highestBid', 'amount', 'currentBid', 'bidAmount'],
      );
      final auctionId = _firstText(scope, const ['auctionId', 'id']) ??
          _firstText(payload, const ['auctionId']);
      if (amount == null || amount <= 0) continue;
      // The bidder may be named flat or inside a `winner` / `bidder` map,
      // and that map uses the same display-name keys the snapshot does.
      final who = scope['winner'] ?? scope['bidder'] ?? payload['winner'];
      final whoMap =
          who is Map ? Map<String, dynamic>.from(who) : const <String, dynamic>{};
      return _BidUpdate(
        auctionId: auctionId,
        amount: amount,
        bidCount: _firstNum(scope, const ['bidCount', 'bids'])?.toInt(),
        bidderName: _firstText(whoMap, const ['displayName', 'name']) ??
            _firstText(scope, const ['bidderName', 'winnerName']),
      );
    }
    return null;
  }

  static num? _firstNum(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final raw = json[key];
      if (raw is num) return raw;
      if (raw is Map && raw['amount'] is num) return raw['amount'] as num;
    }
    return null;
  }

  static String? _firstText(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final raw = json[key];
      if (raw is String && raw.isNotEmpty) return raw;
    }
    return null;
  }

  /// The WS SNAPSHOT payload may sit at the message root or under a wrapper.
  Map<String, dynamic>? _extractSnapshot(Map<String, dynamic> msg) {
    for (final key in ['snapshot', 'payload', 'data']) {
      final v = msg[key];
      if (v is Map<String, dynamic> && v['stream'] is Map) return v;
    }
    if (msg['stream'] is Map) return msg;
    return null;
  }

  // ── Snapshot application (version-gated) ─────────────────────────────────

  void _applySnapshot(AuctionRoomSnapshot incoming, {bool authoritative = false}) {
    final current = snapshot.value?.snapshotVersion ?? 0;
    // Versioned WS SNAPSHOT frames apply only when strictly newer, so
    // out-of-order delivery can't regress the room. Mutation responses come
    // back as an unversioned partial (snapshotVersion == 0, no
    // realtime/serverTimestamp — see Appendix B); we always apply those local
    // echoes and preserve the current version as the ordering baseline so a
    // later stale WS frame can't overwrite them.
    //
    // An [authoritative] fetch — the explicit REST GET in bootstrap /
    // refreshSnapshot — is the freshest truth we have, so it also applies when
    // the version merely *equals* current. Without this, a partial echo that
    // emptied (say) the product queue while keeping the same version baseline
    // would strand the room on stale data that a same-version refresh could
    // never override.
    final drop = authoritative
        ? (incoming.snapshotVersion > 0 && incoming.snapshotVersion < current)
        : (incoming.snapshotVersion > 0 && incoming.snapshotVersion <= current);
    if (drop) return;

    final queueBefore = productQueue;
    final merged =
        _keepLotDetails(_mergeMissing(incoming, snapshot.value), snapshot.value);
    snapshot.value = merged;

    _trackAuctionConclusion(incoming, merged);

    // Keep the draggable queue view in sync with server truth — except while a
    // local drag-reorder is mid-flight, where the optimistic order must hold
    // until the sequential position PATCHes finish.
    if (!_reorderingQueue) queueView.assignAll(merged.productQueue);

    // A frame that wipes a queue we were holding is nearly always a lightweight
    // server frame rather than a real "queue is now empty" — the room used to
    // enter showing an empty Queue tab because the first WS SNAPSHOT after the
    // REST bootstrap cleared it. Partial frames can no longer do that (the
    // queue is carried forward in _mergeMissing); an *explicit* empty queue
    // still applies, but when it didn't come from an authoritative GET or one
    // of our own queue mutations we re-check against the REST snapshot.
    if (queueBefore.isNotEmpty &&
        merged.productQueue.isEmpty &&
        !authoritative &&
        !queueActionLoading.value &&
        !_verifyingQueueWipe) {
      log('Snapshot v${incoming.snapshotVersion} emptied a queue of '
          '${queueBefore.length} — re-verifying against REST '
          '(keys: ${incoming.raw.keys.toList()})');
      _verifyingQueueWipe = true;
      unawaited(refreshSnapshot().whenComplete(() => _verifyingQueueWipe = false));
    }

    _syncAnnouncement(incoming);
    _syncShowNotes(incoming);

    final ts = merged.serverTimestamp;
    if (ts != null) {
      final serverMs = DateTime.tryParse(ts)?.millisecondsSinceEpoch;
      if (serverMs != null) {
        _serverOffsetMs = serverMs - DateTime.now().millisecondsSinceEpoch;
      }
    }
    if (merged.stream.isTerminal) streamEnded.value = true;
  }

  /// Carries forward realtime hints / serverTimestamp — and the product queue —
  /// when a (partial) mutation or WS snapshot omits them, so the room never
  /// loses its WS/Agora wiring or its lineup to a frame that simply didn't
  /// mention them. An explicitly empty `productQueue: []` still clears.
  AuctionRoomSnapshot _mergeMissing(
    AuctionRoomSnapshot incoming,
    AuctionRoomSnapshot? prev,
  ) {
    if (prev == null) return incoming;
    final keepQueue = !incoming.hasProductQueue;
    if (!keepQueue &&
        incoming.realtime != null &&
        incoming.serverTimestamp != null) {
      return incoming;
    }
    return AuctionRoomSnapshot(
      stream: incoming.stream,
      activeAuction: incoming.activeAuction,
      productQueue: keepQueue ? prev.productQueue : incoming.productQueue,
      hasProductQueue: incoming.hasProductQueue || prev.hasProductQueue,
      mutedUserIds: incoming.mutedUserIds,
      lastAuctionResult: incoming.lastAuctionResult ?? prev.lastAuctionResult,
      // Unversioned mutation echo → keep prev's version as the ordering baseline.
      snapshotVersion: incoming.snapshotVersion > 0
          ? incoming.snapshotVersion
          : prev.snapshotVersion,
      generatedAt: incoming.generatedAt ?? prev.generatedAt,
      auctionId: incoming.auctionId ?? prev.auctionId,
      serverTimestamp: incoming.serverTimestamp ?? prev.serverTimestamp,
      realtime: incoming.realtime ?? prev.realtime,
      raw: incoming.raw,
    );
  }

  /// Carries the running lot's details forward when the next frame is about
  /// the same lot but says nothing about them.
  ///
  /// The `/start` echo and the lightweight frames that follow it come back with
  /// the money fields blank, and taking that at face value made the card show
  /// the starting price for an instant and then drop straight to "—". A frame
  /// that is silent about a figure is not a frame saying the figure is gone —
  /// the lot cannot lose the price it started at, or un-take a bid.
  ///
  /// Only same-lot frames merge. A different auction id, or no active auction
  /// at all, replaces everything exactly as before, so the card never carries
  /// one lot's numbers onto the next.
  AuctionRoomSnapshot _keepLotDetails(
    AuctionRoomSnapshot merged,
    AuctionRoomSnapshot? prev,
  ) {
    final incoming = merged.activeAuction;
    final previous = prev?.activeAuction;
    if (incoming == null || previous == null) return merged;
    if (incoming.id != null &&
        previous.id != null &&
        incoming.id != previous.id) {
      return merged;
    }
    // `copyWith` keeps the incoming value for every null it is handed, so
    // `incoming.x ?? previous.x` is a no-op whenever the frame did carry x.
    final titleBlank = incoming.title == null || incoming.title!.isEmpty;
    return merged.copyWith(
      activeAuction: incoming.copyWith(
        title: titleBlank ? previous.title : null,
        image: incoming.image ?? previous.image,
        startingPrice: incoming.startingPrice ?? previous.startingPrice,
        currentPrice: incoming.currentPrice ?? previous.currentPrice,
        highestBid: incoming.highestBid ?? previous.highestBid,
        // Non-nullable, so a silent frame reads as 0 rather than as absent —
        // hence forward-only rather than a null check.
        bidCount: incoming.bidCount >= previous.bidCount
            ? null
            : previous.bidCount,
        shippingPriceNok:
            incoming.shippingPriceNok ?? previous.shippingPriceNok,
        winnerName: incoming.winnerName ?? previous.winnerName,
      ),
    );
  }

  Future<void> refreshSnapshot() async {
    try {
      final snap = await _api.getSnapshot(streamId);
      _applySnapshot(snap, authoritative: true);
    } catch (e) {
      log('refreshSnapshot error: $e');
    }
  }

  // ── Post-sale refresh ─────────────────────────────────────────────────────

  /// Id of the lot that was running when we last saw an `activeAuction`, so the
  /// frame where it disappears (or is replaced) can be recognised as "that lot
  /// just finished".
  String? _lastActiveAuctionId;
  bool _refreshingAfterSale = false;
  bool _saleRefreshPending = false;

  /// How long to wait before re-pulling, when the first post-sale fetch came
  /// back before the backend had written the order row.
  static const _postSaleRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  /// Notices an auction ending — sold, passed, or replaced by the next lot —
  /// and kicks off the post-sale refresh.
  ///
  /// The concluding frame is typically a light one: it drops `activeAuction`
  /// but says nothing about the queue (so [_mergeMissing] carries the old,
  /// now-stale lineup forward) and the order row is written server-side a beat
  /// later. Without this the seller had to pull-to-refresh both tabs by hand.
  ///
  /// A frame that merely *omits* `activeAuction` (any partial mutation echo
  /// does) must not count as a conclusion, so we require the frame to speak
  /// about the auction explicitly — `activeAuction` present as a key, or a
  /// `lastAuctionResult` attached.
  void _trackAuctionConclusion(
    AuctionRoomSnapshot incoming,
    AuctionRoomSnapshot merged,
  ) {
    final previousId = _lastActiveAuctionId;
    final currentId = merged.activeAuction?.id;
    final explicit = incoming.raw.containsKey('activeAuction') ||
        incoming.lastAuctionResult != null;

    // Only let an explicit frame clear the tracked lot; a silent partial one
    // would otherwise drop the id and we'd miss the real conclusion later.
    if (currentId != null || explicit) _lastActiveAuctionId = currentId;

    if (previousId == null || currentId == previousId || !explicit) return;
    log('Auction $previousId concluded — refreshing queue + orders');
    unawaited(_refreshAfterSale());
  }

  /// Pulls the authoritative snapshot (fresh product queue) and the orders list
  /// after a lot finishes, retrying briefly while the winning order is still
  /// being written.
  Future<void> _refreshAfterSale() async {
    // A lot that finishes while a previous refresh is still retrying queues one
    // more pass rather than being swallowed.
    if (_refreshingAfterSale) {
      _saleRefreshPending = true;
      return;
    }
    _refreshingAfterSale = true;
    try {
      do {
        _saleRefreshPending = false;
        final ordersBefore = orders.length;
        await refreshSnapshot();
        await loadOrders();
        for (final delay in _postSaleRetryDelays) {
          // Stop as soon as the new order shows up.
          if (orders.length > ordersBefore || streamEnded.value) break;
          await Future.delayed(delay);
          await refreshSnapshot();
          await loadOrders();
        }
      } while (_saleRefreshPending && !streamEnded.value);
    } finally {
      _refreshingAfterSale = false;
      _saleRefreshPending = false;
    }
  }

  /// Patches the current snapshot's stream status to LIVE without touching the
  /// version, so the UI reflects go-live even if the server snapshot lags.
  void _markLiveLocally() {
    final snap = snapshot.value;
    if (snap == null || snap.stream.isLive) return;
    snapshot.value = snap.copyWith(stream: snap.stream.copyWith(status: 'LIVE'));
  }

  // ── Queue mutations ────────────────────────────────────────────────────────

  Future<void> addProduct(
    String productId, {
    String auctionType = 'NORMAL',
  }) async {
    await _runQueueMutation(() => _api.enqueue(
          streamId: streamId,
          session: session.value!,
          productId: productId,
          auctionType: auctionType,
        ));
  }

  Future<void> removeProduct(String productId) async {
    await _runQueueMutation(() => _api.dequeue(
          streamId: streamId,
          session: session.value!,
          productId: productId,
        ));
  }

  Future<void> reorderProduct(String productId, String direction) async {
    await _runQueueMutation(() => _api.reorder(
          streamId: streamId,
          session: session.value!,
          productId: productId,
          direction: direction,
        ));
  }

  /// Drag-and-drop reorder from [oldIndex] to [newIndex] (ReorderableListView
  /// indices). Optimistically reorders [queueView] for instant feedback, then
  /// persists by issuing the required single-step position PATCHes — the API
  /// only moves a product up/down one slot at a time — and finally reconciles
  /// with the authoritative snapshot.
  Future<void> moveProduct(int oldIndex, int newIndex) async {
    if (session.value == null || !canManageQueue) return;
    if (!_ensureControl(TKeys.actManageQueue.tr)) return;
    // ReorderableListView reports newIndex as the insertion slot; when dragging
    // downward the target shifts by one once the item is removed.
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= queueView.length) return;
    if (newIndex < 0 || newIndex >= queueView.length) return;
    if (_reorderingQueue) return;

    final item = queueView[oldIndex];

    // Optimistic reorder so the row settles into place immediately.
    _reorderingQueue = true;
    final optimistic = queueView.toList();
    optimistic.removeAt(oldIndex);
    optimistic.insert(newIndex, item);
    queueView.assignAll(optimistic);

    final direction = newIndex > oldIndex ? 'down' : 'up';
    final steps = (newIndex - oldIndex).abs();
    try {
      for (var i = 0; i < steps; i++) {
        final result = await _api.reorder(
          streamId: streamId,
          session: session.value!,
          productId: item.productId,
          direction: direction,
        );
        _applySnapshot(result.snapshot);
      }
      await refreshSnapshot();
    } on AuctionApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      log('moveProduct error: $e');
      _showError('Network error. Please try again.');
    } finally {
      // Reconcile the view with server truth now the drag has been persisted.
      _reorderingQueue = false;
      queueView.assignAll(productQueue);
    }
  }

  Future<void> clearQueue() async {
    await _runQueueMutation(() => _api.clearQueue(
          streamId: streamId,
          session: session.value!,
        ));
  }

  Future<void> _runQueueMutation(Future<MutationResult> Function() op) async {
    if (queueActionLoading.value) return;
    if (session.value == null) return;
    // The queue belongs to whoever is running the auction (see
    // [canManageQueue]). The buttons are already hidden on a watcher; this is
    // what makes a stale one — a sheet left open through a handoff — inert.
    if (!_ensureControl(TKeys.actManageQueue.tr)) return;
    queueActionLoading.value = true;
    try {
      final result = await op();
      _applySnapshot(result.snapshot);
      // Queue endpoints return a partial snapshot; pull the full one so
      // version + realtime stay consistent (matches the web client).
      unawaited(refreshSnapshot());
    } on AuctionApiException catch (e) {
      // Surface the backend's exact message verbatim (e.g. AUTH_FORBIDDEN
      // "Only the device with auction control may perform this action") rather
      // than a rewritten one, so the seller sees the real reason the action was
      // rejected.
      _showError(e.message);
    } catch (e) {
      log('queue mutation error: $e');
      _showError('Network error. Please try again.');
    } finally {
      queueActionLoading.value = false;
    }
  }

  // ── Auction lifecycle ──────────────────────────────────────────────────────

  Future<bool> startAuction(StartAuctionParams params) async {
    if (session.value == null || startLoading.value) return false;
    if (!_ensureControl(TKeys.actStartLot.tr)) return false;
    startLoading.value = true;
    // The lot we're about to start is the queue head. Capture it now — the
    // start mutation removes it from the queue, and its name/price let us fill
    // in a sparse start echo below.
    final head = productQueue.isNotEmpty ? productQueue.first : null;
    try {
      final result = await _api.start(
        streamId: streamId,
        session: session.value!,
        params: params,
      );
      _applySnapshot(result.snapshot);
      // The /start response is a partial echo that often omits the product
      // name and price, so the running-auction card would show "Current lot"
      // with a "—" price. Enrich the active auction from the queue head for an
      // instant, complete card, then pull the full snapshot so title + current
      // bid reconcile with the server (mirrors the queue mutations).
      _enrichActiveAuction(head, params);
      unawaited(refreshSnapshot());
      return true;
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
      return false;
    } catch (e) {
      log('startAuction error: $e');
      _showError('Network error. Please try again.');
      return false;
    } finally {
      startLoading.value = false;
    }
  }

  /// Patches the just-started [ActiveAuction] with the queue head's name and
  /// starting price when the /start echo left them blank, so the running card
  /// shows the product and current bid immediately (before the full snapshot
  /// arrives). No-op once the server data is complete.
  void _enrichActiveAuction(AuctionProduct? head, StartAuctionParams params) {
    final snap = snapshot.value;
    final active = snap?.activeAuction;
    if (snap == null || active == null) return;

    final needsTitle = active.title == null || active.title!.isEmpty;
    final needsPrice = active.displayPrice == null;
    // Shipping rides the same gap: the seller picked it in the start sheet a
    // moment ago, so the card can show it straight away rather than blank
    // until the server echoes it back.
    final needsShipping = active.shippingPrice == null;
    if (!needsTitle && !needsPrice && !needsShipping) return;

    final enriched = active.copyWith(
      title: needsTitle ? head?.title : null,
      image: active.image == null ? head?.image : null,
      startingPrice: needsPrice
          ? (params.startingPrice ?? head?.startingPrice ?? head?.dutchPrice)
          : null,
      shippingPriceNok: needsShipping
          ? (params.shippingPriceNok ?? head?.shippingPriceNok)
          : null,
    );
    snapshot.value = snap.copyWith(activeAuction: enriched);
  }

  Future<void> endAuction() async {
    if (session.value == null || endLoading.value) return;
    if (!_ensureControl(TKeys.actEndLot.tr)) return;
    endLoading.value = true;
    try {
      final result = await _api.endAuction(
        streamId: streamId,
        session: session.value!,
      );
      _applySnapshot(result.snapshot);
      if (result.depletedRandomProductId != null) {
        _showInfo('A random product ran out of stock and was removed.');
      }
      // The /end echo is a partial snapshot: it may not mention the queue at
      // all and the winning order lands a moment later. Pull both rather than
      // leaving the seller to refresh the Queue / Orders tabs by hand.
      unawaited(_refreshAfterSale());
    } on AuctionApiException catch (e) {
      // "No active product auction to end" is a benign no-op (per the guide).
      final m = e.message.toLowerCase();
      if (!m.contains('no active')) _showError(_friendly(e));
    } catch (e) {
      log('endAuction error: $e');
    } finally {
      endLoading.value = false;
    }
  }

  Future<bool> cancelRoom() async {
    if (session.value == null) return false;
    try {
      final result = await _api.cancelRoom(
        streamId: streamId,
        session: session.value!,
      );
      _applySnapshot(result.snapshot);
      return true;
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
      return false;
    } catch (e) {
      log('cancelRoom error: $e');
      return false;
    }
  }

  Future<bool> reduceDutchPrice(num newPrice, {int? offerDurationSec}) async {
    if (session.value == null) return false;
    if (!_ensureControl(TKeys.actReducePrice.tr)) return false;
    try {
      final result = await _api.reduceDutchPrice(
        streamId: streamId,
        session: session.value!,
        newPrice: newPrice,
        offerDurationSec: offerDurationSec,
      );
      _applySnapshot(result.snapshot);
      return true;
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
      return false;
    } catch (e) {
      log('reduceDutchPrice error: $e');
      return false;
    }
  }

  Future<bool> goLive() async {
    if (goLiveLoading.value) return false;
    if (!_ensureControl(TKeys.actTakeStreamLive.tr)) return false;
    goLiveLoading.value = true;
    try {
      reportedEndsAt.value = await _api.goLive(streamId) ?? reportedEndsAt.value;
      // Flip the local stream status to LIVE immediately. A version-gated
      // refresh can drop the post-go-live snapshot when its snapshotVersion
      // hasn't advanced, leaving the UI stuck on SCHEDULED — this guarantees
      // the pill/badge/gating update regardless.
      _markLiveLocally();
      await refreshSnapshot();
      _markLiveLocally();
      // Now that we're LIVE, join the channel and start publishing to buyers.
      await startPublishing();
      return true;
    } on AuctionApiException catch (e) {
      // A stream pending admin approval can't go live yet — surface the
      // backend's exact message under a clear, non-alarming title instead of
      // the generic "Something went wrong".
      if (e.code == 'WAITING_FOR_APPROVAL') {
        Get.snackbar(TKeys.acWaitingApproval.tr, e.message);
      } else {
        _showError(_friendly(e));
      }
      return false;
    } catch (e) {
      log('goLive error: $e');
      _showError('Could not go live. Please try again.');
      return false;
    } finally {
      goLiveLoading.value = false;
    }
  }

  /// The Go Live button. Starts publishing our camera + mic to buyers.
  ///
  /// - If the stream is still SCHEDULED, this flips it LIVE via the go-live
  ///   endpoint (which already starts publishing).
  /// - If the stream is already LIVE (e.g. the seller re-entered the room, or
  ///   we never auto-published on entry), this only joins + publishes — no API
  ///   call, since the stream is live already.
  ///
  /// Entering the room never triggers this; the seller must tap Go Live.
  Future<void> startGoLive() async {
    if (goLiveLoading.value) return;
    // A role switch is still bringing this device's camera up; joining now
    // would publish before there is anything to capture.
    if (mediaRoleSwitching.value) return;
    final s = stream;
    if (s == null || s.isTerminal) return;
    // Publishing is a control action — a secondary device must be granted
    // control by the primary first (checked here as well as in goLive(), so
    // the already-LIVE branch below is covered too).
    if (!_ensureControl(TKeys.actTakeStreamLive.tr)) return;
    if (s.isScheduled) {
      await goLive(); // manages its own loading flag + startPublishing()
      return;
    }
    // Already LIVE — just (re)join and publish; no go-live API call.
    goLiveLoading.value = true;
    try {
      await startPublishing();
    } finally {
      goLiveLoading.value = false;
    }
  }

  Future<void> endStream() async {
    if (!_ensureControl(TKeys.actEndStream.tr)) return;
    try {
      await _api.endStream(streamId);
      streamEnded.value = true;
    } catch (e) {
      log('endStream error: $e');
    }
  }

  /// Extends the live stream's end time by [minutes] (5–120).
  Future<bool> extendStream(int minutes) async {
    try {
      final newEndsAt = await _api.extend(streamId, minutes);
      // Apply the new deadline immediately — the countdown and the "ends at"
      // label update on the spot, before the snapshot catches up.
      if (newEndsAt != null) {
        reportedEndsAt.value = newEndsAt;
      } else {
        // No end time in the response — push the one we know forward ourselves
        // (never invent one from scratch, or the countdown would run short).
        final base = endsAt;
        if (base != null) {
          reportedEndsAt.value =
              base.add(Duration(minutes: minutes)).toIso8601String();
        }
      }
      await refreshSnapshot();
      _showInfo('Stream extended by $minutes min.');
      return true;
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
      return false;
    } catch (e) {
      log('extendStream error: $e');
      return false;
    }
  }

  // ── Stream announcement ────────────────────────────────────────────────────

  /// Takes the announcement from a snapshot, but only when the payload actually
  /// carried one of the announcement keys — a frame that is silent about it
  /// leaves the current banner alone.
  void _syncAnnouncement(AuctionRoomSnapshot incoming) {
    final streamJson = incoming.raw['stream'];
    if (streamJson is! Map) return;
    final hasSeller = streamJson.containsKey('sellerAnnouncement');
    final hasEffective = streamJson.containsKey('effectiveAnnouncement');
    if (!hasSeller && !hasEffective) return;
    // Prefer the seller's own text; `effectiveAnnouncement` is the fallback for
    // payloads that only report what buyers see.
    announcement.value = hasSeller
        ? incoming.stream.sellerAnnouncement
        : incoming.stream.effectiveAnnouncement;
  }

  /// Publishes [content] to the stream banner buyers see. Empty text is a no-op
  /// — clearing the banner is [endAnnouncement].
  Future<bool> saveAnnouncement(String content) async {
    final text = content.trim();
    if (text.isEmpty || announcementSaving.value) return false;
    announcementSaving.value = true;
    try {
      await _api.setAnnouncement(streamId, text);
      // Show it straight away; the refresh below reconciles with the server.
      announcement.value = text;
      unawaited(refreshSnapshot());
      _showInfo('Announcement is live.');
      return true;
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
      return false;
    } catch (e) {
      log('saveAnnouncement error: $e');
      _showError('Network error. Please try again.');
      return false;
    } finally {
      announcementSaving.value = false;
    }
  }

  // ── Show notes (stream description) ────────────────────────────────────────

  /// Takes the show notes from a snapshot, but only when the payload actually
  /// carried `description` — a frame that is silent about it leaves the notes
  /// the seller can see standing.
  void _syncShowNotes(AuctionRoomSnapshot incoming) {
    final streamJson = incoming.raw['stream'];
    if (streamJson is! Map || !streamJson.containsKey('description')) return;
    final text = incoming.stream.description?.trim();
    showNotes.value = (text == null || text.isEmpty) ? null : text;
  }

  /// Whether the notes can still be written.
  ///
  /// Only while the stream is scheduled: they are what buyers read to decide
  /// whether to join, so rewriting them mid-stream would move the pitch under
  /// buyers who are already bidding on the strength of it. Once it is running
  /// the notes are read-only, for the seller as well as for buyers.
  bool get canEditShowNotes => stream?.isScheduled ?? false;

  /// Saves [content] as the stream's description. Blank text clears the notes,
  /// which is a legitimate edit here (unlike the announcement banner), so it is
  /// sent through rather than rejected.
  ///
  /// Refused once the stream is live — see [canEditShowNotes]. The UI hides the
  /// editor then, so this is the backstop for a stream that goes live while the
  /// sheet is open.
  Future<bool> saveShowNotes(String content) async {
    if (showNotesSaving.value) return false;
    if (!canEditShowNotes) {
      _showError('Show notes can only be edited before the stream goes live.');
      return false;
    }
    final text = content.trim();
    showNotesSaving.value = true;
    try {
      await _api.updateShowNotes(
        streamId,
        title: stream?.title ?? '',
        description: text,
      );
      // Show it straight away; the refresh below reconciles with the server.
      showNotes.value = text.isEmpty ? null : text;
      unawaited(refreshSnapshot());
      _showInfo(text.isEmpty ? 'Show notes cleared.' : 'Show notes updated.');
      return true;
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
      return false;
    } catch (e) {
      log('saveShowNotes error: $e');
      _showError('Network error. Please try again.');
      return false;
    } finally {
      showNotesSaving.value = false;
    }
  }

  /// Takes the banner down.
  Future<bool> endAnnouncement() async {
    if (announcementSaving.value) return false;
    announcementSaving.value = true;
    try {
      await _api.clearAnnouncement(streamId);
      announcement.value = null;
      unawaited(refreshSnapshot());
      _showInfo('Announcement ended.');
      return true;
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
      return false;
    } catch (e) {
      log('endAnnouncement error: $e');
      _showError('Network error. Please try again.');
      return false;
    } finally {
      announcementSaving.value = false;
    }
  }

  // ── Stream end countdown ───────────────────────────────────────────────────

  /// "Now" on the server's clock (the snapshot's `serverTimestamp` gives us the
  /// device drift), so the countdown matches what the backend will act on.
  DateTime get serverNow =>
      DateTime.now().add(Duration(milliseconds: _serverOffsetMs));

  /// When the stream auto-ends. The snapshot is the usual source; go-live /
  /// extend responses are a fallback for payloads without `streamEndsAt`. An
  /// end time only ever moves forward, so the later of the two wins and a
  /// lagging snapshot can never drag the countdown back.
  DateTime? get endsAt {
    final fromSnapshot = stream?.endsAt;
    final iso = reportedEndsAt.value;
    final reported = iso == null ? null : DateTime.tryParse(iso);
    if (fromSnapshot == null) return reported;
    if (reported == null) return fromSnapshot;
    return reported.isAfter(fromSnapshot) ? reported : fromSnapshot;
  }

  /// Local time the stream ends, in 12-hour form — `3:30 PM` when that lands
  /// today, `26 Aug, 3:30 PM` when it doesn't, so a stream running past
  /// midnight can't be misread as tonight.
  String? get endsAtLabel => _dayTimeLabel(endsAt);

  /// When a scheduled stream is planned to start, e.g. `26 Aug, 3:30 PM`. The
  /// date is always spelled out — a plan is read ahead of time, so "today" is
  /// exactly the assumption not worth letting the seller make.
  String? get plannedAtLabel {
    final at = stream?.scheduledStartAt?.toLocal();
    if (at == null) return null;
    return '${at.day} ${_monthAbbr[at.month]}, ${_clockLabel(at)}';
  }

  /// `3:30 PM` when [utc] falls today, `26 Aug, 3:30 PM` on any other day.
  String? _dayTimeLabel(DateTime? utc) {
    final t = utc?.toLocal();
    if (t == null) return null;
    final now = DateTime.now();
    final isToday =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return isToday
        ? _clockLabel(t)
        : '${t.day} ${_monthAbbr[t.month]}, ${_clockLabel(t)}';
  }

  /// 12-hour wall clock, e.g. `3:30 PM`.
  String _clockLabel(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$hour:${t.minute.toString().padLeft(2, '0')} '
        '${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Time left before the stream auto-ends, or null when there's no end time.
  Duration? get remaining => endsAt?.difference(serverNow);

  /// True in the last 5 minutes — the header countdown turns urgent and the
  /// room surfaces the red extend warning. Matches the 5-minute prompt
  /// threshold exactly, so both fire on the same tick.
  bool get endingSoon {
    final left = timeLeft.value;
    return left != null && !left.isNegative && left.inSeconds <= 300;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
    _tickCountdown();
  }

  void _tickCountdown() {
    final left = remaining;
    timeLeft.value = left;

    // A new end time (go-live, or an extension that just landed) re-arms every
    // threshold, so the seller is warned again before the new deadline.
    final end = endsAt?.millisecondsSinceEpoch;
    if (end != _countdownEndsAt) {
      _countdownEndsAt = end;
      _lastPromptedThreshold = null;
    }

    if (left == null || !isLive || streamEnded.value) return;
    if (left.isNegative) return;

    // Smallest threshold the remaining time now falls inside (≤1 min → 1,
    // ≤5 min → 5). Only prompt when we drop into a *tighter* bucket than the
    // last one we warned about, so entering the room late warns exactly once.
    int? bucket;
    for (final t in _extendPromptThresholds) {
      if (left.inSeconds <= t * 60) bucket = t;
    }
    if (bucket == null) return;
    if (_lastPromptedThreshold != null && bucket >= _lastPromptedThreshold!) {
      return;
    }
    _lastPromptedThreshold = bucket;
    extendPrompt.value = bucket;
  }

  // ── Multi-device control ────────────────────────────────────────────────────

  Future<void> loadDevices() async {
    try {
      _applyDeviceSnapshot(await _sessionService.devices(streamId));
    } on AuctionApiException catch (e) {
      // A 409 means the stream is gone — stop polling rather than hammer on.
      if (e.isTerminal) {
        streamEnded.value = true;
        _devicePollTimer?.cancel();
      }
      log('loadDevices error: $e');
    } catch (e) {
      log('loadDevices error: $e');
    }
  }

  /// Polls `GET /session/devices` on the cadence the integration guide calls
  /// for: ~12s idle, ~5s while any request is outstanding.
  ///
  /// This is the transport that actually delivers control requests. The WS
  /// `CONTROL_REQUESTS_UPDATED` frame is a latency optimisation on top — when
  /// the request originates outside this app (the seller web console), that
  /// frame may never arrive, and without polling the device would never learn
  /// a request exists.
  void _startDevicePolling() {
    _devicePollTimer?.cancel();
    _scheduleDevicePoll(SellerSessionService.pollInterval);
  }

  void _scheduleDevicePoll(Duration every) {
    _devicePollTimer?.cancel();
    _devicePollTimer = Timer.periodic(every, (_) async {
      if (streamEnded.value) return;
      await loadDevices();
      // Re-arm faster while something is pending, and back off once it clears.
      final wanted = _hasAnyPendingRequest
          ? SellerSessionService.pollIntervalPending
          : SellerSessionService.pollInterval;
      if (wanted != every) _scheduleDevicePoll(wanted);
    });
  }

  bool get _hasAnyPendingRequest =>
      pendingPrimaryRequests.isNotEmpty || pendingControlRequests.isNotEmpty;

  /// Applies a fresh device snapshot: the two pending lists, this device's
  /// PRIMARY + auction-control flags, and any request we should prompt about.
  void _applyDeviceSnapshot(SessionDevicesSnapshot snap) {
    devices.assignAll(snap.devices);
    pendingPrimaryRequests.assignAll(snap.pendingPrimaryRequests);
    pendingControlRequests.assignAll(snap.pendingAuctionControlRequests);
    // Null means unassigned — the PRIMARY device holds control by default.
    auctionControllerDeviceId.value =
        snap.auctionControllerDeviceId ?? snap.primaryDeviceId;
    _syncRolesFromDevices(snap);
    _surfaceIncomingRequests();
  }

  /// Keeps [session]'s PRIMARY and auction-control flags in step with the
  /// server.
  ///
  /// `claim` only reports who held what at claim time; both roles move later
  /// (a handoff is approved, or the lease expires). Every refresh re-reads
  /// them, so neither flag can go stale in either direction.
  void _syncRolesFromDevices(SessionDevicesSnapshot snap) {
    final s = session.value;
    if (s == null) return;
    // An empty device list means a failed/partial read — don't demote ourselves
    // on the strength of it.
    if (snap.devices.isEmpty) return;

    final mine = snap.devices.where((d) => d.deviceId == s.deviceId).toList();
    final isPrimary = mine.isEmpty ? s.isPrimary : mine.first.isPrimary;

    final controllerId = snap.auctionControllerDeviceId;
    // A null controller means the server hasn't assigned auction control; the
    // PRIMARY device holds it by default.
    final holdsControl = (controllerId == null || controllerId.isEmpty)
        ? isPrimary
        : controllerId == s.deviceId;

    if (isPrimary != s.isPrimary || holdsControl != s.isAuctionController) {
      final wasPrimary = s.isPrimary;
      session.value =
          s.copyWith(isPrimary: isPrimary, isAuctionController: holdsControl);
      if (wasPrimary && !isPrimary) {
        _showInfo('Another device is now the main device for this stream.');
      }
      // Control moving is what decides which camera this device shows and
      // whether it may touch the auction at all — swap the engine over to
      // match. Fire-and-forget: the switch is queued and self-serialising.
      if (holdsControl != s.isAuctionController) unawaited(_applyMediaRole());
    }
  }

  /// Raises a one-shot prompt for each request this device is responsible for
  /// answering, so an incoming request is visible without the seller happening
  /// to have the Devices sheet open.
  void _surfaceIncomingRequests() {
    final myDeviceId = session.value?.deviceId;
    if (myDeviceId == null) return;

    ControlRequest? firstActionable(List<ControlRequest> requests, bool mayAct) {
      if (!mayAct) return null;
      for (final r in requests) {
        if (r.deviceId != myDeviceId) return r;
      }
      return null;
    }

    // Only the PRIMARY answers PRIMARY requests; only the auction controller
    // answers auction-control requests.
    incomingPrimaryRequest.value =
        firstActionable(pendingPrimaryRequests, isPrimaryDevice);
    incomingControlRequest.value =
        firstActionable(pendingControlRequests, isController);

    // Forget ids that are no longer pending, so a later request re-prompts.
    final live = {
      ...pendingPrimaryRequests.map((r) => r.requestId),
      ...pendingControlRequests.map((r) => r.requestId),
    };
    _announcedRequestIds.removeWhere((id) => !live.contains(id));

    // A request answered elsewhere (another device took it, or the asker gave
    // up) must not leave a stale prompt on screen asking about it.
    final open = _promptedRequestId;
    if (open != null && !live.contains(open)) _dismissRequestPrompt();

    // One prompt at a time; the next poll raises the next unanswered request.
    if (_promptedRequestId != null) return;
    for (final r in [incomingPrimaryRequest.value, incomingControlRequest.value]) {
      if (r == null || !_announcedRequestIds.add(r.requestId)) continue;
      _promptForRequest(r, isPrimaryRequest: r == incomingPrimaryRequest.value);
      break;
    }
  }

  /// Raises the accept / decline dialog for [request] and remembers it, so the
  /// poll loop can take it back down if the request stops being answerable.
  void _promptForRequest(ControlRequest request, {required bool isPrimaryRequest}) {
    if (Get.context == null) return;
    // Never stack on top of another modal (a confirm sheet, an earlier prompt).
    if (Get.isDialogOpen ?? false) {
      // Not shown after all — drop the id so a later poll retries.
      _announcedRequestIds.remove(request.requestId);
      return;
    }
    _promptedRequestId = request.requestId;
    showControlRequestDialog(
      ctrl: this,
      request: request,
      isPrimaryRequest: isPrimaryRequest,
    ).whenComplete(() {
      if (_promptedRequestId == request.requestId) _promptedRequestId = null;
    });
  }

  /// Closes the prompt we raised — only ours, so a dialog the seller opened in
  /// the meantime is left alone.
  void _dismissRequestPrompt() {
    final wasOpen = _promptedRequestId;
    _promptedRequestId = null;
    if (wasOpen != null && (Get.isDialogOpen ?? false)) Get.back<void>();
  }

  /// Guard for the actions that own the broadcast (go live, stop live, end the
  /// stream). Without this a *secondary* device could publish into the same
  /// RTC channel as the primary — two phones broadcasting the same stream —
  /// having never asked the primary for control.
  ///
  /// Returns true when this device may proceed; otherwise it explains why and
  /// returns false. The "Request control" pill on the Live tab is the one-tap
  /// way out of this state.
  bool _ensureControl(String action) {
    if (isController) return true;
    Get.snackbar(
      TKeys.acControlNeeded.tr,
      TKeys.acControlNeededBody.trParams({'action': action}),
    );
    return false;
  }

  /// Guard for the actions only the *main* device may take — answering a
  /// PRIMARY handoff request. Mirrors [_ensureControl] for the other system.
  bool _ensurePrimary(String action) {
    if (isPrimaryDevice) return true;
    Get.snackbar(
      TKeys.acPrimaryNeeded.tr,
      TKeys.acPrimaryNeededBody.trParams({'action': action}),
    );
    return false;
  }

  /// True when [requestId] is this device's own pending request — a device can
  /// never self-approve its way to control.
  bool _isOwnRequest(List<ControlRequest> requests, String requestId) {
    final myDeviceId = session.value?.deviceId;
    return requests.any(
      (r) => r.requestId == requestId && r.deviceId == myDeviceId,
    );
  }

  /// True while this device is waiting on its own auction-control request, so
  /// the UI can show "waiting" instead of offering the request again.
  bool get hasPendingControlRequest {
    final myDeviceId = session.value?.deviceId;
    return myDeviceId != null &&
        pendingControlRequests.any((r) => r.deviceId == myDeviceId);
  }

  /// True while this device is waiting on its own PRIMARY request.
  bool get hasPendingPrimaryRequest {
    final myDeviceId = session.value?.deviceId;
    return myDeviceId != null &&
        pendingPrimaryRequests.any((r) => r.deviceId == myDeviceId);
  }

  // ── PRIMARY handoff ───────────────────────────────────────────────────────

  /// Asks the current main device to hand PRIMARY over to this one.
  Future<void> requestPrimary() async {
    final s = session.value;
    if (s == null || isPrimaryDevice) return;
    if (hasPendingPrimaryRequest) {
      _showInfo('Your main-device request is still waiting for approval.');
      return;
    }
    try {
      await _sessionService.requestPrimary(streamId, s);
      _showInfo('Main-device request sent.');
      await loadDevices();
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
    } catch (e) {
      log('requestPrimary error: $e');
    }
  }

  /// Approves a PRIMARY handoff. On success *this* device drops to SECONDARY,
  /// so the response snapshot is applied immediately rather than assumed.
  Future<void> approvePrimary(String requestId) async {
    final s = session.value;
    if (s == null) return;
    if (!_ensurePrimary(TKeys.actApproveMainRequests.tr)) return;
    if (_isOwnRequest(pendingPrimaryRequests, requestId)) return;
    try {
      _applyDeviceSnapshot(
        await _sessionService.approvePrimary(streamId, s, requestId),
      );
      await refreshSnapshot();
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
      await loadDevices();
    } catch (e) {
      log('approvePrimary error: $e');
    }
  }

  Future<void> rejectPrimary(String requestId) async {
    final s = session.value;
    if (s == null) return;
    if (!_ensurePrimary(TKeys.actRejectMainRequests.tr)) return;
    if (_isOwnRequest(pendingPrimaryRequests, requestId)) return;
    try {
      _applyDeviceSnapshot(
        await _sessionService.rejectPrimary(streamId, s, requestId),
      );
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
      await loadDevices();
    } catch (e) {
      log('rejectPrimary error: $e');
    }
  }

  // ── Auction-control handoff ───────────────────────────────────────────────

  Future<void> requestAuctionControl() async {
    final s = session.value;
    if (s == null) return;
    if (isController) return; // already in control — nothing to request
    if (hasPendingControlRequest) {
      _showInfo('Your control request is still waiting for approval.');
      return;
    }
    try {
      await _sessionService.requestControl(streamId, s);
      _showInfo('Control requested from the controlling device.');
      // Reflect the pending request locally (the pill flips to "Waiting…")
      // without waiting for the next poll to come back to us.
      await loadDevices();
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
    } catch (e) {
      log('requestAuctionControl error: $e');
    }
  }

  Future<void> approveControl(String requestId) async {
    final s = session.value;
    if (s == null) return;
    // Only the device holding control may answer a request — and never its own.
    if (!_ensureControl(TKeys.actApproveControlRequests.tr)) return;
    if (_isOwnRequest(pendingControlRequests, requestId)) return;
    try {
      _applyDeviceSnapshot(
        await _sessionService.approveControl(streamId, s, requestId),
      );
      await refreshSnapshot();
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
      await loadDevices();
    } catch (e) {
      log('approveControl error: $e');
    }
  }

  Future<void> rejectControl(String requestId) async {
    final s = session.value;
    if (s == null) return;
    if (!_ensureControl(TKeys.actRejectControlRequests.tr)) return;
    if (_isOwnRequest(pendingControlRequests, requestId)) return;
    try {
      _applyDeviceSnapshot(
        await _sessionService.rejectControl(streamId, s, requestId),
      );
    } on AuctionApiException catch (e) {
      _showError(_friendly(e));
      await loadDevices();
    } catch (e) {
      log('rejectControl error: $e');
    }
  }

  // ── Read helpers ────────────────────────────────────────────────────────────

  /// Pre-bids for a queued product (fetched on demand for the pre-bid sheet).
  Future<List<PreBid>> fetchPreBids(String productId) async {
    try {
      return await _api.preBids(streamId, productId);
    } catch (e) {
      log('fetchPreBids error: $e');
      return const [];
    }
  }

  /// Reloads the winning orders. Concurrent callers (the Orders tab opening
  /// while a post-sale refresh is running) share the in-flight request instead
  /// of being dropped, so nobody awaits a fetch that never happened.
  Future<void> loadOrders() {
    return _ordersInFlight ??=
        _fetchOrders().whenComplete(() => _ordersInFlight = null);
  }

  Future<void>? _ordersInFlight;

  Future<void> _fetchOrders() async {
    loadingOrders.value = true;
    try {
      orders.assignAll(await _api.orders(streamId));
    } catch (e) {
      log('loadOrders error: $e');
    } finally {
      loadingOrders.value = false;
    }
  }

  // ── Queue catalog (multi-select add) ─────────────────────────────────────

  /// Loads `GET /auction-room/queue/catalog` — the products the seller can add
  /// to the queue, each flagged with whether it's already `inQueue`.
  /// Set [silent] for background loads (room entry), where a failed catalog
  /// fetch shouldn't greet the seller with a snackbar.
  Future<void> fetchCatalog({bool silent = false}) async {
    if (loadingCatalog.value) return;
    loadingCatalog.value = true;
    try {
      catalogProducts.assignAll(await _api.queueCatalog(streamId));
    } on AuctionApiException catch (e) {
      if (!silent) _showError(_friendly(e));
    } catch (e) {
      log('fetchCatalog error: $e');
    } finally {
      loadingCatalog.value = false;
    }
  }

  /// Cross-checks an empty queue against `queue/catalog` on room entry. The
  /// catalog flags every product that is already lined up (`inQueue`), so
  /// "catalog says queued, snapshot says empty" can only mean the entry
  /// snapshot lost the lineup — refetch it rather than leaving the Queue tab
  /// showing "Queue is empty" on a stream that has products waiting.
  Future<void> _verifyQueueAgainstCatalog() async {
    if (productQueue.isNotEmpty) return;
    await fetchCatalog(silent: true);
    // Another snapshot may have filled the queue while the catalog loaded.
    if (productQueue.isNotEmpty) return;
    if (!catalogProducts.any((p) => p.inQueue)) return;
    log('Catalog reports queued products but the snapshot queue is empty — '
        'refetching the snapshot');
    await refreshSnapshot();
  }

  /// Adds several catalog products to the queue in one request, then reloads
  /// the catalog so `inQueue` flags reflect the new server state.
  ///
  /// Unlike [_runQueueMutation], failures here surface the server's exact
  /// message (e.g. "Only the device with auction control may perform this
  /// action") rather than the generic "Something went wrong" fallback.
  Future<void> addCatalogProducts(
    List<String> productIds, {
    String auctionType = 'NORMAL',
  }) async {
    if (productIds.isEmpty || session.value == null) return;
    if (queueActionLoading.value) return;
    queueActionLoading.value = true;
    try {
      final result = await _api.enqueueBatch(
        streamId: streamId,
        session: session.value!,
        products: [
          for (final id in productIds)
            {
              'productId': id,
              'auctionType': auctionType,
              'sourceType': 'CATALOG',
            },
        ],
      );
      _applySnapshot(result.snapshot);
      // Queue endpoints return a partial snapshot; pull the full one so
      // version + realtime stay consistent (matches the web client).
      unawaited(refreshSnapshot());
      await fetchCatalog();
    } on AuctionApiException catch (e) {
      Get.snackbar(TKeys.acCouldNotAddProducts.tr, e.message);
    } catch (e) {
      log('addCatalogProducts error: $e');
      _showError('Network error. Please try again.');
    } finally {
      queueActionLoading.value = false;
    }
  }

  // ── Random products ────────────────────────────────────────────────────────

  /// Creates a mystery lot (multipart: title + description + stock + image) and
  /// queues it.
  ///
  /// The create call does not enqueue, so the two steps run back to back here.
  /// If the enqueue is the part that fails, the product still exists — say so
  /// rather than implying nothing happened, since it's now in the catalog and
  /// can be added from the picker.
  Future<bool> createRandomProduct({
    required String title,
    required String description,
    required int stock,
    required String imagePath,
  }) async {
    final s = session.value;
    if (s == null || creatingRandomProduct.value) return false;
    // Checked before the upload, not after: this creates the product and then
    // queues it, and a watcher refused at the enqueue would have paid for an
    // image upload and be left with a stray catalog entry.
    if (!_ensureControl(TKeys.actManageQueue.tr)) return false;

    creatingRandomProduct.value = true;
    String? productId;
    try {
      productId = await _api.createRandomProduct(
        streamId: streamId,
        title: title,
        description: description,
        stock: stock,
        imagePath: imagePath,
      );

      final result = await _api.enqueue(
        streamId: streamId,
        session: s,
        productId: productId,
        sourceType: 'RANDOM',
      );
      _applySnapshot(result.snapshot);
      // The enqueue echo is partial — pull the full snapshot, and refresh the
      // catalog so the new lot shows up flagged as already queued.
      unawaited(refreshSnapshot());
      unawaited(fetchCatalog(silent: true));
      return true;
    } on AuctionApiException catch (e) {
      _showError(productId == null
          ? e.message
          : '"$title" was created but could not be queued: ${e.message}');
      return false;
    } catch (e) {
      log('createRandomProduct error: $e');
      _showError(productId == null
          ? 'Could not create the product. Please try again.'
          : '"$title" was created but could not be queued. Add it from the '
              'product list.');
      return false;
    } finally {
      creatingRandomProduct.value = false;
    }
  }

  // ── Addable products (candidates for the queue) ──────────────────────────

  Future<void> fetchAddableProducts() async {
    if (loadingProducts.value) return;
    loadingProducts.value = true;
    try {
      final res = await ApiClient.instance.get(
        '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/product-requests',
        headers: await AuthService.instance.ensuredAuthHeaders(),
      );
      if (!res.isSuccess) return;
      final body = res.json;
      final data = body['data'];
      final items = data is Map ? data['items'] as List? : null;
      if (items == null) return;

      final products = <AddableProduct>[];
      final seen = <String>{};
      for (final requestSummary in items) {
        if (requestSummary is! Map) continue;
        final requestId = requestSummary['id'] as String?;
        if (requestId == null) continue;
        final detail = await ApiClient.instance.get(
          '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/product-requests/$requestId',
          headers: await AuthService.instance.ensuredAuthHeaders(),
        );
        if (!detail.isSuccess) continue;
        final detailData = detail.json['data'];
        final lineItems = detailData is Map ? detailData['items'] as List? : null;
        if (lineItems == null) continue;
        for (final item in lineItems) {
          if (item is! Map) continue;
          final product = item['product'];
          final pid = (product is Map ? product['id'] : item['productId'])
              as String?;
          if (pid == null || pid.isEmpty || !seen.add(pid)) continue;
          products.add(AddableProduct(
            productId: pid,
            name: (product is Map
                    ? (product['name'] ?? item['requestedName'])
                    : item['requestedName']) as String? ??
                'Product',
            image: product is Map
                ? (product['thumbnailUrl'] ?? product['image']) as String?
                : null,
          ));
        }
      }
      addableProducts.assignAll(products);
    } catch (e) {
      log('fetchAddableProducts error: $e');
    } finally {
      loadingProducts.value = false;
    }
  }

  /// Products not already queued — what the Add-product picker should offer.
  List<AddableProduct> get availableToAdd {
    final queued = productQueue.map((p) => p.productId).toSet();
    return addableProducts.where((p) => !queued.contains(p.productId)).toList();
  }

  // ── Session heartbeat ──────────────────────────────────────────────────────

  /// Renews the lease on the cadence the guide requires (10–15s). At the old
  /// 20s the server could expire the lease between beats.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(SellerSessionService.heartbeatInterval, (_) {
      final s = session.value;
      if (s != null) _sessionService.heartbeat(streamId, s.sessionId);
    });
  }

  // ── Feedback + teardown ────────────────────────────────────────────────────

  String _friendly(AuctionApiException e) {
    switch (e.code) {
      case 'AUTH_FORBIDDEN':
        return 'This device cannot control the auction. Request control from the controlling device.';
      case 'UNAUTHORIZED':
      case 'AUTH_EXPIRED':
        return 'Session expired — please try again.';
      case 'NOT_FOUND':
        return 'This stream is no longer available.';
      case 'CONFLICT':
        return 'The stream has ended.';
      case 'RATE_LIMITED':
        return 'Too many requests — wait a moment.';
      default:
        return e.message;
    }
  }

  void _showError(String message) =>
      Get.snackbar(TKeys.acSomethingWentWrong.tr, message);
  void _showInfo(String message) => Get.snackbar(TKeys.acHeadsUp.tr, message);

  /// Guards [_releaseSession] so the lease is handed back exactly once.
  bool _sessionReleased = false;

  /// `POST /session/disconnect`, at most once per room visit.
  ///
  /// The room tears down from [onClose] alone (`AuctionRoomView.dispose()`
  /// calls `Get.delete`), but a re-entered room can still race a disconnect
  /// that is already in flight. Without this guard the second call disconnects
  /// a session the first already tore down, and the backend answers
  /// `403 AUTH_FORBIDDEN "Valid seller session required for this action"`.
  Future<void> _releaseSession() async {
    if (_sessionReleased) return;
    final s = session.value;
    if (s == null) return;
    _sessionReleased = true;
    await _sessionService.disconnect(streamId, s);
  }

  @override
  void onClose() {
    _heartbeatTimer?.cancel();
    _devicePollTimer?.cancel();
    _countdownTimer?.cancel();
    _nameDebounce?.cancel();
    // Leaving the room takes any outstanding handoff prompt with it — it would
    // otherwise sit over the next screen with no session behind it.
    _dismissRequestPrompt();
    unawaited(_releaseSession());
    _ws?.dispose();
    unawaited(_rtm.dispose());
    _camera.detach();
    unawaited(_rtc.release());
    super.onClose();
  }
}

const _monthAbbr = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
