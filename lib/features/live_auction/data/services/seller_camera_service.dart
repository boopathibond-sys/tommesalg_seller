import 'dart:developer' as dev;
import 'dart:io' show Platform;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../models/seller_camera_option.dart';

/// Camera / lens selection for the seller broadcast.
///
/// Mobile is **not** the web device-enumeration model: there is no
/// `getCameras() -> deviceId -> setDevice(deviceId)`. Agora exposes the
/// device's real optics through [RtcEngine.queryCameraFocalLengthCapability],
/// and a lens is chosen with `cameraDirection` + `cameraFocalLengthType`. This
/// service is the only place that knows that; everything above it works with
/// [SellerCameraOption].
///
/// It is deliberately independent of auction, bid, queue and chat state. A
/// camera error is a media error — it must never end an auction — so every
/// entry point here swallows failures and reports them as a `false` return or
/// an empty list rather than throwing into the room controller.
class SellerCameraService {
  RtcEngine? _engine;
  SellerCameraOption? _active;
  bool _switchInProgress = false;

  static const String _tag = 'SellerCamera';

  /// Order the lenses are offered in — the physical reading of the phone
  /// (rear optics widest-to-longest, then the selfie camera).
  static const List<SellerCameraMode> _displayOrder = [
    SellerCameraMode.rearStandard,
    SellerCameraMode.rearWideAngle,
    SellerCameraMode.rearUltraWide,
    SellerCameraMode.rearTelephoto,
    SellerCameraMode.front,
  ];

  /// The lens currently configured on the engine, once one has been applied.
  SellerCameraOption? get active => _active;

  bool get isSwitching => _switchInProgress;

  /// Binds the engine created by [AgoraRtcBroadcasterService]. No second
  /// [RtcEngine] is ever created for camera work.
  void attach(RtcEngine engine) => _engine = engine;

  void detach() {
    _engine = null;
    _active = null;
    _switchInProgress = false;
  }

  /// The lenses this handset actually reports, ready for the selector.
  ///
  /// Returns an empty list only when the device genuinely has nothing to
  /// offer — see [_fallbackOptions] for the empty-capability case.
  Future<List<SellerCameraOption>> queryOptions() async {
    final engine = _engine;
    if (engine == null) return const [];
    List<FocalLengthInfo> infos = const [];
    try {
      infos = await engine.queryCameraFocalLengthCapability();
    } catch (e) {
      dev.log('focal-length query failed: $e', name: _tag);
    }

    final byMode = <SellerCameraMode, SellerCameraOption>{};
    for (final info in infos) {
      final direction = _directionFromValue(info.cameraDirection);
      final focalLength = info.focalLengthType;
      if (direction == null || focalLength == null) continue;
      // Telephoto is an iOS-only capability; ignore an Android device that
      // reports it, since the configuration cannot take effect there.
      if (focalLength == CameraFocalLengthType.cameraFocalLengthTelephoto &&
          !Platform.isIOS) {
        continue;
      }
      final mode = _modeFromCapability(direction, focalLength);
      // First capability wins per mode — several entries can collapse onto the
      // same logical lens (e.g. two rear default entries on a dual-sensor rig).
      byMode.putIfAbsent(
        mode,
        () => SellerCameraOption(
          mode: mode,
          direction: direction,
          focalLengthType: focalLength,
        ),
      );
    }

    if (byMode.isEmpty) return _fallbackOptions();

    return [
      for (final mode in _displayOrder)
        if (byMode[mode] != null) byMode[mode]!,
    ];
  }

  /// Applies [option] **before** local capture starts (engine initialised, no
  /// preview running yet). This is the supported point for focal-length
  /// configuration, so the seller's first frame is already the right lens.
  Future<bool> applyConfiguration(SellerCameraOption option) async {
    final engine = _engine;
    if (engine == null) return false;
    try {
      await engine.setCameraCapturerConfiguration(option.config);
      _active = option;
      return true;
    } catch (e) {
      dev.log('initial camera configuration failed: $e', name: _tag);
      return false;
    }
  }

  /// Changes the lens while the seller may already be publishing.
  ///
  /// The Agora channel is **never** left and rejoined for a lens change — only
  /// the local capture source is reconfigured, so buyers keep receiving the
  /// stream (bar a brief local interruption) and no auction state is touched.
  ///
  /// Serialised: a second tap while a switch is in flight is dropped rather
  /// than queued. On failure the previous lens is restored, so an unsupported
  /// optional lens can never leave the seller without a working camera.
  Future<bool> switchTo(SellerCameraOption option) async {
    final engine = _engine;
    if (engine == null || _switchInProgress) return false;
    if (_active?.mode == option.mode) return true;

    _switchInProgress = true;
    final previous = _active;
    try {
      await _restartCapture(engine, option);
      _active = option;
      return true;
    } catch (e) {
      dev.log('camera switch failed: $e', name: _tag);
      // Put the working lens back. If even that fails there is nothing more
      // this service can do — the room keeps running on whatever the engine
      // has, and the caller shows the "current camera is still active" notice.
      if (previous != null) {
        try {
          await _restartCapture(engine, previous);
        } catch (e2) {
          dev.log('camera rollback failed: $e2', name: _tag);
        }
      }
      return false;
    } finally {
      _switchInProgress = false;
    }
  }

  /// Stop → reconfigure → start on the primary camera source.
  ///
  /// `setCameraCapturerConfiguration` is documented as a *capture* setting, so
  /// the capture has to be brought down for the new focal length to be picked
  /// up. The config is passed to `startCameraCapture` as well because Android
  /// reads it there; on iOS that argument is ignored and the
  /// `setCameraCapturerConfiguration` call above is the one that counts.
  Future<void> _restartCapture(
    RtcEngine engine,
    SellerCameraOption option,
  ) async {
    await engine.stopCameraCapture(VideoSourceType.videoSourceCameraPrimary);
    await engine.setCameraCapturerConfiguration(option.config);
    await engine.startCameraCapture(
      sourceType: VideoSourceType.videoSourceCameraPrimary,
      config: option.config,
    );
    // Bringing the capture source down can take the local preview with it, and
    // the seller must not be left staring at a frozen stage. Re-asserting the
    // preview is a no-op when it survived.
    await engine.startPreview();
  }

  /// Resolves a saved preference against what this device can do today.
  ///
  /// A stored lens the handset no longer offers (different phone, same
  /// account) falls back instead of failing — stream startup must never depend
  /// on an optional lens being present.
  static SellerCameraOption? resolvePreferred(
    String? savedMode,
    List<SellerCameraOption> available,
  ) {
    if (available.isEmpty) return null;
    if (savedMode != null) {
      for (final option in available) {
        if (option.mode.name == savedMode) return option;
      }
    }
    return selectDefault(available);
  }

  /// Rear standard → any rear lens → front → whatever exists. Nothing here
  /// assumes a particular camera is present.
  static SellerCameraOption selectDefault(List<SellerCameraOption> available) {
    for (final mode in _displayOrder) {
      for (final option in available) {
        if (option.mode == mode) return option;
      }
    }
    return available.first;
  }

  /// Front + back, used only when the capability query comes back empty.
  ///
  /// An empty response does not mean the phone has no cameras — older and
  /// low-end devices simply report no focal-length metadata — and a selector
  /// with nothing in it would strand a seller who just wants to flip to the
  /// selfie camera. Both directions are universally addressable through
  /// `cameraDirection`, so this is the safe floor, not a hard-coded lens list.
  List<SellerCameraOption> _fallbackOptions() => const [
        SellerCameraOption(
          mode: SellerCameraMode.rearStandard,
          direction: CameraDirection.cameraRear,
          focalLengthType: CameraFocalLengthType.cameraFocalLengthDefault,
        ),
        SellerCameraOption(
          mode: SellerCameraMode.front,
          direction: CameraDirection.cameraFront,
          focalLengthType: CameraFocalLengthType.cameraFocalLengthDefault,
        ),
      ];

  /// `FocalLengthInfo.cameraDirection` arrives as a raw int; decode it through
  /// the SDK's own extension rather than comparing against literal 0/1.
  static CameraDirection? _directionFromValue(int? value) {
    if (value == null) return null;
    try {
      return CameraDirectionExt.fromValue(value);
    } catch (_) {
      return null;
    }
  }

  static SellerCameraMode _modeFromCapability(
    CameraDirection direction,
    CameraFocalLengthType focalLength,
  ) {
    if (direction == CameraDirection.cameraFront) {
      return SellerCameraMode.front;
    }
    switch (focalLength) {
      case CameraFocalLengthType.cameraFocalLengthWideAngle:
        return SellerCameraMode.rearWideAngle;
      case CameraFocalLengthType.cameraFocalLengthUltraWide:
        return SellerCameraMode.rearUltraWide;
      case CameraFocalLengthType.cameraFocalLengthTelephoto:
        return SellerCameraMode.rearTelephoto;
      case CameraFocalLengthType.cameraFocalLengthDefault:
        return SellerCameraMode.rearStandard;
    }
  }
}
