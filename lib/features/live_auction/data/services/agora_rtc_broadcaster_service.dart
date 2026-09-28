import 'dart:developer' as dev;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// Wraps the Agora RTC engine for the **seller** side of the live auction room,
/// in either of the two roles a seller device can take.
///
/// * **Publisher** — the device holding auction control. [joinAsBroadcaster]
///   sets the client role to broadcaster, starts the local camera preview and
///   enables the camera + microphone tracks in [ChannelMediaOptions]. The local
///   video is rendered via [VideoViewController.local].
/// * **Watcher** — every other seller device in the room. [joinAsAudience]
///   joins the *same* channel as an audience member with publishing switched
///   off, so a second phone can see exactly what the controlling device is
///   sending to buyers without ever putting a second camera on air. Its video
///   is rendered via [VideoViewController.remote] against the host's uid.
///
/// A device moves between the two roles while the room is open (a handoff is
/// approved, or control is taken away), so the role is not fixed at
/// initialisation: [becomePublisher] and [becomeAudience] switch the live
/// engine over, and [leaveChannel] lets the controller rejoin in the new role
/// without tearing the engine down.
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
  bool _mirrored = false;

  /// True while the engine is configured as an audience member (watching the
  /// controlling device) rather than as the publisher.
  bool _audience = false;

  /// True while the local camera preview is running. Tracked so a role switch
  /// never calls `startPreview`/`stopPreview` twice, and so a watcher device
  /// keeps its camera physically off.
  bool _previewing = false;

  /// Kept so a role switch can re-apply the seller's lens choice when this
  /// device becomes the publisher.
  Future<void> Function(RtcEngine engine)? _beforePreview;

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
  bool get isMirrored => _mirrored;

  /// True while this device is watching the controlling device instead of
  /// publishing. The controller mirrors this as room state; read it here only
  /// to decide whether a media call applies.
  bool get isAudience => _audience;
  bool get isPreviewing => _previewing;

  /// Creates the engine, configures the starting role, and registers handlers.
  ///
  /// [publisher] decides whether this device comes up owning the camera. A
  /// watcher passes false: the client role is audience, no capture source is
  /// opened and `startPreview` is never called, so a second seller phone in the
  /// room never lights its camera. Either role can be switched to later through
  /// [becomePublisher] / [becomeAudience].
  Future<void> initialize({
    required String appId,
    required void Function() onJoinSuccess,
    required void Function(int remoteUid) onRemoteHostJoined,
    required void Function(int remoteUid) onRemoteHostOffline,
    required void Function(
      ConnectionStateType state,
      ConnectionChangedReasonType reason,
    ) onConnectionStateChanged,
    required Future<void> Function() onTokenWillExpire,
    required void Function(String message) onError,
    Future<void> Function(RtcEngine engine)? beforePreview,
    bool publisher = true,
    void Function(int remoteUid, bool hasVideo)? onRemoteVideoChanged,
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
    _beforePreview = beforePreview;
    _audience = !publisher;

    final handler = RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        dev.log('${_audience ? 'watching' : 'broadcasting on'} '
            '${connection.channelId} as uid ${connection.localUid}', name: _tag);
        onJoinSuccess();
      },
      // Remote *hosts* only — in the live-broadcasting profile an audience
      // member never raises these. As the publisher that means another
      // broadcaster; as a watcher it is the controlling device's feed arriving.
      onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
        onRemoteHostJoined(remoteUid);
      },
      onUserOffline: (
        RtcConnection connection,
        int remoteUid,
        UserOfflineReasonType reason,
      ) {
        onRemoteHostOffline(remoteUid);
      },
      // Whether the host we are watching is actually sending pictures right
      // now. Without this a watcher cannot tell "the main device has its camera
      // off" from "the feed hasn't arrived yet", and would sit on a black stage
      // with no explanation.
      onRemoteVideoStateChanged: (
        RtcConnection connection,
        int remoteUid,
        RemoteVideoState state,
        RemoteVideoStateReason reason,
        int elapsed,
      ) {
        onRemoteVideoChanged?.call(
          remoteUid,
          state == RemoteVideoState.remoteVideoStateStarting ||
              state == RemoteVideoState.remoteVideoStateDecoding ||
              state == RemoteVideoState.remoteVideoStateFrozen,
        );
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

    if (publisher) {
      await _startPublisherCapture(engine);
    } else {
      await _configureAudience(engine);
    }
  }

  /// Sets the broadcaster role and brings the local capture source up.
  ///
  /// [_beforePreview] is the last chance to configure capture before it starts:
  /// Agora's focal-length selection is a *capture* setting, so the lens the
  /// seller last chose has to be applied here to be live on the very first
  /// frame. Guarded, because a camera problem must never stop the broadcast
  /// from coming up — worst case the device's default lens is used.
  Future<void> _startPublisherCapture(RtcEngine engine) async {
    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    // Undo the watcher's blanket remote-audio mute (see [joinAsAudience]) —
    // a publisher that kept it would be deaf to the channel it now owns.
    if (_audience) {
      try {
        await engine.muteAllRemoteAudioStreams(false);
      } catch (e) {
        dev.log('unmuting remote audio failed: $e', name: _tag);
      }
    }
    final hook = _beforePreview;
    if (hook != null) {
      try {
        await hook(engine);
      } catch (e) {
        dev.log('beforePreview hook failed: $e', name: _tag);
      }
    }
    await engine.startPreview();
    _previewing = true;
    _audience = false;
  }

  /// Sets the audience role and makes sure no capture source is running.
  Future<void> _configureAudience(RtcEngine engine) async {
    if (_previewing) {
      try {
        await engine.stopPreview();
      } catch (e) {
        dev.log('stopPreview failed: $e', name: _tag);
      }
      _previewing = false;
    }
    await engine.setClientRole(
      role: ClientRoleType.clientRoleAudience,
      options: const ClientRoleOptions(
        audienceLatencyLevel:
            AudienceLatencyLevelType.audienceLatencyLevelUltraLowLatency,
      ),
    );
    // The controlling device publishes a single video layer, so there is no low
    // stream to fall back to: letting the SDK "fall back" on a pessimistic
    // first-seconds downlink estimate would cost the watcher their picture and
    // buy nothing. Best-effort — an SDK that doesn't support it still watches.
    try {
      await engine.setRemoteSubscribeFallbackOption(
        StreamFallbackOptions.streamFallbackOptionDisabled,
      );
    } catch (e) {
      dev.log('subscribe-fallback tuning unsupported: $e', name: _tag);
    }
    _audience = true;
  }

  /// Switches a running engine to the publisher role (this device was handed
  /// auction control). The camera comes up as a local preview only — joining
  /// and publishing stay the controller's decision.
  Future<void> becomePublisher() async {
    final engine = _engine;
    if (engine == null) return;
    await _startPublisherCapture(engine);
  }

  /// Switches a running engine to the watcher role (auction control moved to
  /// another device). Stops the local camera so this device is off air.
  Future<void> becomeAudience() async {
    final engine = _engine;
    if (engine == null) return;
    await _configureAudience(engine);
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

  /// Joins [channelName] as an audience member: subscribes to the controlling
  /// device's camera and publishes nothing at all, so no second picture can
  /// ever reach buyers from this handset.
  ///
  /// **Video only, deliberately.** The two devices are almost always the same
  /// seller's, side by side on the same table: playing the controlling device's
  /// microphone out of this one's speaker puts its own audio straight back into
  /// that microphone, and the stream howls. The picture is what a second screen
  /// is for, so audio is left unsubscribed — and muted as well, since a later
  /// `updateChannelMediaOptions` elsewhere must not be able to turn it on by
  /// accident.
  Future<void> joinAsAudience({
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
        clientRoleType: ClientRoleType.clientRoleAudience,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        audienceLatencyLevel:
            AudienceLatencyLevelType.audienceLatencyLevelUltraLowLatency,
        autoSubscribeVideo: true,
        autoSubscribeAudio: false,
        publishCameraTrack: false,
        publishMicrophoneTrack: false,
        publishScreenCaptureVideo: false,
        publishScreenCaptureAudio: false,
      ),
    );
    try {
      await engine.muteAllRemoteAudioStreams(true);
    } catch (e) {
      dev.log('muting remote audio failed: $e', name: _tag);
    }
    _joined = true;
  }

  /// Leaves the channel but keeps the engine alive, so the controller can
  /// rejoin in the other role. A no-op when we are not in a channel.
  Future<void> leaveChannel() async {
    final engine = _engine;
    if (engine == null || !_joined) return;
    try {
      await engine.leaveChannel();
    } catch (e) {
      dev.log('leaveChannel failed: $e', name: _tag);
    }
    _joined = false;
  }

  /// Mutes / unmutes the seller's outgoing microphone. A watcher has no
  /// outgoing track, so this is a no-op there rather than a silent failure.
  Future<void> setMuted(bool muted) async {
    final engine = _engine;
    if (engine == null || _audience) return;
    await engine.muteLocalAudioStream(muted);
    _muted = muted;
  }

  /// Enables / disables the seller's outgoing camera track (audio stays live).
  Future<void> setCameraOff(bool off) async {
    final engine = _engine;
    if (engine == null || _audience) return;
    await engine.muteLocalVideoStream(off);
    _cameraOff = off;
  }

  /// Flips between front and rear cameras.
  Future<void> switchCamera() async {
    final engine = _engine;
    if (engine == null || _audience) return;
    await engine.switchCamera();
  }

  /// Mirrors the picture left↔right — what is on the seller's right hand
  /// arrives on the buyer's left.
  ///
  /// Two calls, because Agora keeps the two sides of the mirror separate:
  ///  • the encoder's [VideoEncoderConfiguration.mirrorMode] is the only one
  ///    that reaches buyers, and is what this control is actually for;
  ///  • [RtcEngine.setLocalRenderMode] mirrors the seller's own stage, so the
  ///    preview keeps showing exactly what is going out rather than silently
  ///    disagreeing with it.
  ///
  /// The mode is set explicitly to `disabled` rather than `auto` when turning
  /// this off: `auto` re-introduces Agora's own front-camera mirroring, which
  /// would leave the toggle unable to actually un-mirror a selfie-camera feed.
  ///
  /// The encoder profile is spelled out rather than left to the fields we omit.
  /// `setVideoEncoderConfiguration` replaces the whole configuration, and the
  /// Dart object drops its null fields on the way across — so the native side
  /// would fall back to *its* struct defaults for resolution and frame rate,
  /// not to whatever the engine is currently running. Naming Agora's own
  /// documented defaults (960×540 @ 15fps, adaptive orientation) keeps a
  /// mirror toggle from quietly re-profiling the seller's broadcast.
  Future<void> setMirrored(bool mirrored) async {
    final engine = _engine;
    if (engine == null || _audience) return;
    final mode = mirrored
        ? VideoMirrorModeType.videoMirrorModeEnabled
        : VideoMirrorModeType.videoMirrorModeDisabled;
    try {
      await engine.setVideoEncoderConfiguration(
        VideoEncoderConfiguration(
          dimensions: const VideoDimensions(width: 960, height: 540),
          frameRate: 15,
          orientationMode: OrientationMode.orientationModeAdaptive,
          mirrorMode: mode,
        ),
      );
      await engine.setLocalRenderMode(
        renderMode: RenderModeType.renderModeHidden,
        mirrorMode: mode,
      );
      _mirrored = mirrored;
    } catch (e) {
      // A mirror is a cosmetic media setting: log it and leave the broadcast
      // exactly as it was rather than letting it reach the auction.
      dev.log('setMirrored($mirrored) failed: $e', name: _tag);
    }
  }

  /// Re-applies the current mirror choice after the capture source has been
  /// torn down and rebuilt for a lens change. A no-op while unmirrored, since
  /// that is already the SDK's starting state for the encoder.
  Future<void> reapplyMirror() async {
    if (!_mirrored) return;
    await setMirrored(true);
  }

  /// Re-asserts that the camera track is published, after the local capture
  /// source has been torn down and restarted for a lens change.
  ///
  /// Only the publish flags are sent: every other field stays null, so Agora
  /// leaves the rest of the joined channel's options exactly as they were. A
  /// no-op before Go Live, when there is no channel to update.
  Future<void> ensureCameraPublishing() async {
    final engine = _engine;
    if (engine == null || !_joined || _audience) return;
    try {
      await engine.updateChannelMediaOptions(
        const ChannelMediaOptions(publishCameraTrack: true),
      );
    } catch (e) {
      dev.log('ensureCameraPublishing failed: $e', name: _tag);
    }
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
      // Only a publisher ever started one; calling this on a watcher engine
      // that never opened the camera just logs a native error.
      if (_previewing) await engine.stopPreview();
      await engine.release();
    } catch (e) {
      dev.log('release error: $e', name: _tag);
    } finally {
      _engine = null;
      // The next engine starts unmirrored and previewing nothing, so neither
      // flag may outlive this one — otherwise [reapplyMirror] would trust a
      // mirror that isn't set, and release() would stop a preview that isn't
      // running.
      _mirrored = false;
      _previewing = false;
      _audience = false;
      _beforePreview = null;
    }
  }
}
