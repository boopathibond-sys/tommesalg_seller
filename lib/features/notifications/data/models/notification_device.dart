import 'dart:io' show Platform;

/// The body sent to `POST {BASE_URL}/api/notification-devices`.
///
/// ⚠️ **Single source of truth for the wire format.** Every field name the
/// backend sees is spelled out once, in [toJson]. If the integration guide
/// names a field differently (`fcmToken` instead of `token`, `os` instead of
/// `platform`, snake_case instead of camelCase, …) this class is the only
/// file that needs editing — nothing else in the app hard-codes a key.
class NotificationDevice {
  const NotificationDevice({
    required this.token,
    required this.platform,
    required this.deviceId,
    this.deviceName,
    this.appVersion,
    this.locale,
  });

  /// The FCM registration token. On iOS this is still the *FCM* token, not the
  /// raw APNs token — Firebase swaps the APNs token underneath.
  final String token;

  /// `'ios'` or `'android'`. See [currentPlatform].
  final String platform;

  /// Stable per-install identifier, so re-registering after a token rotation
  /// updates the existing row instead of creating a second one for the same
  /// handset. Survives app restarts; regenerated on reinstall.
  final String deviceId;

  /// Human-readable model, e.g. `iPhone 15 Pro` / `Pixel 8`. Purely for the
  /// backend's "your logged-in devices" UI — never used for targeting.
  final String? deviceName;

  /// App version string (`1.0.0+1`), so the backend can withhold payload
  /// shapes an older build can't render.
  final String? appVersion;

  /// BCP-47 tag (`nb`, `en`) so the backend can localise the notification copy
  /// it renders.
  final String? locale;

  /// `'ios'` on iOS, `'android'` elsewhere. Kept here rather than at the call
  /// site so the platform vocabulary lives with the rest of the wire format.
  static String get currentPlatform => Platform.isIOS ? 'ios' : 'android';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'token': token,
        'platform': platform,
        'deviceId': deviceId,
        if (deviceName != null) 'deviceName': deviceName,
        if (appVersion != null) 'appVersion': appVersion,
        if (locale != null) 'locale': locale,
      };

  /// Two registrations are equivalent when the backend would treat them as the
  /// same row *and* nothing it stores has changed. Used to skip a redundant
  /// POST on every cold start.
  String get fingerprint => '$deviceId|$token|$platform|$locale';
}
