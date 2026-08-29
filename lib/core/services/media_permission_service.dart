import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../widgets/confirm_dialog.dart';

/// How camera + microphone access stands after asking for it.
///
/// [denied] means the OS will still show its prompt if we ask again (Android's
/// first refusal), while [permanentlyDenied] means only the system settings
/// screen can turn it back on — on iOS that is *every* refusal, since iOS shows
/// its permission alert exactly once per install.
enum MediaPermissionOutcome { granted, denied, permanentlyDenied }

/// Camera + microphone grants for the live auction broadcast.
///
/// Both platforms are declared for it already — `NSCameraUsageDescription` /
/// `NSMicrophoneUsageDescription` in `ios/Runner/Info.plist`, `CAMERA` /
/// `RECORD_AUDIO` in the Android manifest — so all that is left is the runtime
/// grant, which this asks for before Agora ever touches the devices.
class MediaPermissionService {
  const MediaPermissionService._();

  /// Asks for camera *and* microphone and reports the worst of the two results.
  ///
  /// The two are requested one after the other rather than as a batched
  /// `[Permission.camera, Permission.microphone].request()`: on iOS the system
  /// alerts are presented one at a time, and asking for the second while the
  /// first is still on screen can leave it unanswered — which is what makes an
  /// iPhone look like it "never asked" and then refuse to open the room.
  ///
  /// Both are always asked, even when the first is refused, so the seller gets
  /// every prompt in one pass instead of one per attempt.
  static Future<MediaPermissionOutcome> ensureCameraAndMic() async {
    final camera = await _ensure(Permission.camera);
    final mic = await _ensure(Permission.microphone);
    return _worst(camera, mic);
  }

  /// True when both are already granted — a pure status read, no prompts.
  static Future<bool> hasCameraAndMic() async {
    final camera = await Permission.camera.status;
    final mic = await Permission.microphone.status;
    return _isOk(camera) && _isOk(mic);
  }

  /// Opens the app's own page in the system settings so a permanently denied
  /// grant can be switched back on.
  static Future<bool> openSettings() => openAppSettings();

  static Future<MediaPermissionOutcome> _ensure(Permission permission) async {
    final current = await permission.status;
    if (_isOk(current)) return MediaPermissionOutcome.granted;
    // Asking again here would be a no-op the user never sees, so send them to
    // settings instead of silently failing.
    if (current.isPermanentlyDenied || current.isRestricted) {
      return MediaPermissionOutcome.permanentlyDenied;
    }

    final result = await permission.request();
    if (_isOk(result)) return MediaPermissionOutcome.granted;
    if (result.isPermanentlyDenied || result.isRestricted) {
      return MediaPermissionOutcome.permanentlyDenied;
    }
    return MediaPermissionOutcome.denied;
  }

  /// `limited` only ever applies to photos, but treat it as usable rather than
  /// locking the seller out on a status we didn't expect.
  static bool _isOk(PermissionStatus s) => s.isGranted || s.isLimited;

  static MediaPermissionOutcome _worst(
    MediaPermissionOutcome a,
    MediaPermissionOutcome b,
  ) {
    if (a == MediaPermissionOutcome.permanentlyDenied ||
        b == MediaPermissionOutcome.permanentlyDenied) {
      return MediaPermissionOutcome.permanentlyDenied;
    }
    if (a == MediaPermissionOutcome.denied ||
        b == MediaPermissionOutcome.denied) {
      return MediaPermissionOutcome.denied;
    }
    return MediaPermissionOutcome.granted;
  }
}

/// Gate in front of the auction room: asks for camera + mic and, when they are
/// refused, explains why they are needed and offers the way to fix it — the OS
/// prompt again when it can still appear, the settings screen when it can't.
///
/// Returns `true` only when both are granted, so callers can use it as a
/// straight "may I open the room?" check.
Future<bool> ensureAuctionMediaAccess(BuildContext context) async {
  var outcome = await MediaPermissionService.ensureCameraAndMic();
  if (outcome == MediaPermissionOutcome.granted) return true;
  if (!context.mounted) return false;

  final toSettings = outcome == MediaPermissionOutcome.permanentlyDenied;
  final proceed = await showConfirmDialog(
    context: context,
    title: 'Camera & microphone needed',
    message: toSettings
        ? 'To broadcast your live auction we need access to your camera and '
            'microphone. Turn them on in Settings, then come back and enter '
            'the room again.'
        : 'To broadcast your live auction we need access to your camera and '
            'microphone. Tap Allow on the next prompts.',
    confirmLabel: toSettings ? 'Open settings' : 'Allow',
    icon: Icons.videocam_off_rounded,
    destructive: false,
  );
  if (!proceed) return false;

  if (toSettings) {
    // Nothing to wait for here: the grant is made in another app, so the room
    // stays closed and the seller re-taps "Enter room" when they come back.
    await MediaPermissionService.openSettings();
    return false;
  }

  outcome = await MediaPermissionService.ensureCameraAndMic();
  return outcome == MediaPermissionOutcome.granted;
}
