import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:get/get.dart';

import '../../../../core/localization/translation_keys.dart';

/// A camera/lens the seller can pick, as the *product* thinks of it.
///
/// Deliberately an app-level abstraction rather than Agora's [FocalLengthInfo]:
/// the UI, the persisted preference and the fallback logic all speak
/// [SellerCameraMode], so nothing outside [SellerCameraService] has to know
/// that a lens is really a `cameraDirection` + `cameraFocalLengthType` pair.
enum SellerCameraMode {
  front,
  rearStandard,
  rearWideAngle,
  rearUltraWide,
  rearTelephoto,
}

/// One selectable camera, built from a capability the device actually reported.
class SellerCameraOption {
  const SellerCameraOption({
    required this.mode,
    required this.direction,
    required this.focalLengthType,
  });

  final SellerCameraMode mode;
  final CameraDirection direction;
  final CameraFocalLengthType focalLengthType;

  /// Seller-facing name. A getter, not a stored field: `.tr` must re-resolve
  /// when the seller switches language, and options are built once per stream.
  String get label {
    switch (mode) {
      case SellerCameraMode.front:
        return TKeys.csFront.tr;
      case SellerCameraMode.rearStandard:
        return TKeys.csBack.tr;
      case SellerCameraMode.rearWideAngle:
        return TKeys.csWide.tr;
      case SellerCameraMode.rearUltraWide:
        return TKeys.csUltraWide.tr;
      case SellerCameraMode.rearTelephoto:
        return TKeys.csTelephoto.tr;
    }
  }

  /// Agora capture configuration for this lens.
  ///
  /// `cameraDirection` + `cameraFocalLengthType` only — never `cameraId`, which
  /// is the desktop/Windows device mechanism and is documented as incompatible
  /// with focal-length selection.
  CameraCapturerConfiguration get config => CameraCapturerConfiguration(
        cameraDirection: direction,
        cameraFocalLengthType: focalLengthType,
      );

  @override
  bool operator ==(Object other) =>
      other is SellerCameraOption && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;

  @override
  String toString() => 'SellerCameraOption(${mode.name})';
}
