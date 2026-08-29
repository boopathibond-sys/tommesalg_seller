import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Resolves the stable per-install identity attached to a device registration.
///
/// Deliberately *not* a hardware id. `androidId` / `identifierForVendor` are
/// either unavailable, unstable across OS versions, or restricted on the
/// stores. A random UUID persisted in shared preferences is stable for as long
/// as the install lives, which is exactly the lifetime an FCM token has too —
/// a reinstall mints a new token anyway, so a new device row is correct.
class DeviceIdentity {
  DeviceIdentity._();

  static const String _prefsKey = 'push.device_id';

  static String? _cachedId;
  static String? _cachedName;

  /// Stable identifier for this install. Generated on first call and reused
  /// forever after.
  static Future<String> id() async {
    final cached = _cachedId;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getString(_prefsKey);
    if (value == null || value.isEmpty) {
      value = const Uuid().v4();
      await prefs.setString(_prefsKey, value);
    }
    return _cachedId = value;
  }

  /// Marketing-ish model name for the backend's device list. Best-effort:
  /// device_info_plus can throw on unusual OEM builds, and a missing name must
  /// never block registration, so failures degrade to `null`.
  static Future<String?> name() async {
    if (_cachedName != null) return _cachedName;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return _cachedName = ios.utsname.machine;
      }
      final android = await info.androidInfo;
      return _cachedName = '${android.manufacturer} ${android.model}'.trim();
    } catch (_) {
      return null;
    }
  }

  /// Drops the persisted id. Only for tests / a deliberate "forget this
  /// device" flow — normal logout keeps the id so the same handset re-registers
  /// as itself when the next user signs in.
  static Future<void> reset() async {
    _cachedId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
