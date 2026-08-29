import 'dart:developer' as dev;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// Wraps the Agora RTC engine for the **seller/broadcaster** side of the live
/// auction room.
///
/// Unlike the buyer (audience-only), the seller *publishes*: [joinAsBroadcaster]
/// sets the client role to broadcaster, starts the local camera preview, and
/// enables the camera + microphone tracks in [ChannelMediaOptions]. The local
/// video is rendered via [VideoViewController.local]; there is no remote track
/// to subscribe to.
///
/// One engine per room screen is fine here (no reels-style pager on the seller
/// side), so this service owns its own native engine and tears it down in
/// [release]. It stays transport-only — token renewal and state policy live in
/// the controller.
class AgoraRtcBroadcasterService {
  RtcEngine? _engine;
  RtcEngineEventHandler? _handler;
  bool _joined = false;
  bool _muted = false;
  bool _cameraOff = false;

  static const String _tag = 'AgoraRtcBroadcaster';

  RtcEngine get engine {
    final e = _engine;
    if (e == null) {
      throw StateError('AgoraRtcBroadcasterService used before initialize()');
    }
    return e;
  }

  bool get isInitialized => _engine != null;
  bool get isJoined => _joined;
  bool get isMuted => _muted;
  bool get isCameraOff => _cameraOff;

  /// Creates the engine, configures broadcasting, and registers handlers.
  Future<void> initialize({
    required String appId,
    required void Function() onJoinSuccess,
    required void Function(int remoteUid) onAudienceJoined,
    required void Function(int remoteUid) onAudienceOffline,
    required void Function(
      ConnectionStateType state,
      ConnectionChangedReasonType reason,
    ) onConnectionStateChanged,
    required Future<void> Function() onTokenWillExpire,
    required void Function(String message) onError,
  }) async {
    if (_engine != null) return;

    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ),
    );
    await engine.enableVideo();
    // Seller is the broadcaster for this channel.
    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await engine.startPreview();

    final handler = RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        dev.log('broadcasting on ${connection.channelId} '
            'as uid ${connection.localUid}', name: _tag);
        onJoinSuccess();
      },
      // Audience members (buyers) joining/leaving — useful for a viewer count.
      onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
        onAudienceJoined(remoteUid);
      },
      onUserOffline: (
        RtcConnection connection,
        int remoteUid,
        UserOfflineReasonType reason,
      ) {
        onAudienceOffline(remoteUid);
      },
      onConnectionStateChanged: (
        RtcConnection connection,
        ConnectionStateType state,
        ConnectionChangedReasonType reason,
      ) {
        dev.log('connection state: $state ($reason)', name: _tag);
        onConnectionStateChanged(state, reason);
      },
      onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
        dev.log('rtc token will expire — renewing', name: _tag);
        onTokenWillExpire();
      },
      onError: (ErrorCodeType err, String msg) {
        dev.log('rtc error: $err $msg', name: _tag);
        onError('$err: $msg');
      },
    );
    engine.registerEventHandler(handler);

    _engine = engine;
    _handler = handler;
  }

  /// Joins [channelName] as a broadcaster, publishing camera + microphone.
  Future<void> joinAsBroadcaster({
    required String token,
    required String channelName,
    required int uid,
  }) async {
    final engine = _engine;
    if (engine == null) return;
    await engine.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
      ),
    );
    _joined = true;
  }

  /// Mutes / unmutes the seller's outgoing microphone.
  Future<void> setMuted(bool muted) async {
    final engine = _engine;
    if (engine == null) return;
    await engine.muteLocalAudioStream(muted);
    _muted = muted;
  }

  /// Enables / disables the seller's outgoing camera track (audio stays live).
  Future<void> setCameraOff(bool off) async {
    final engine = _engine;
    if (engine == null) return;
    await engine.muteLocalVideoStream(off);
    _cameraOff = off;
  }

  /// Flips between front and rear cameras.
  Future<void> switchCamera() async {
    final engine = _engine;
    if (engine == null) return;
    await engine.switchCamera();
  }

  /// Swaps in a freshly-issued RTC token without interrupting the broadcast.
  Future<void> renewToken(String token) async {
    final engine = _engine;
    if (engine == null) return;
    await engine.renewToken(token);
  }

  /// Leaves the channel and fully tears down the native engine.
  Future<void> release() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      if (_handler != null) {
        engine.unregisterEventHandler(_handler!);
        _handler = null;
      }
      if (_joined) {
        await engine.leaveChannel();
        _joined = false;
      }
      await engine.stopPreview();
      await engine.release();
    } catch (e) {
      dev.log('release error: $e', name: _tag);
    } finally {
      _engine = null;
    }
  }
}
