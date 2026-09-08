import 'dart:convert';
import 'dart:developer' as dev;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/seller_camera_option.dart';

/// Per-stream storage of the seller's preferred camera/lens.
///
/// Key and value shape match the web client (`stream_<id>_camera` holding
/// `{"mode": "rearUltraWide"}`) so the two implementations stay conceptually
/// interchangeable. What is stored is the *logical* lens, never a platform
/// camera id — device identifiers differ across iOS/Android and even across
/// OS upgrades on the same handset, so an id would be a preference that
/// silently stops resolving.
class SellerCameraStorage {
  const SellerCameraStorage._();

  static String _key(String streamId) => 'stream_${streamId}_camera';

  /// The saved mode name, or null when nothing is stored / the value is junk.
  /// Never throws: a broken preference must not stop a stream from starting.
  static Future<String?> readMode(String streamId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(streamId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['mode'] is String) {
        return decoded['mode'] as String;
      }
    } catch (e) {
      dev.log('camera preference read failed: $e', name: 'SellerCameraStorage');
    }
    return null;
  }

  static Future<void> writeMode(String streamId, SellerCameraMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(streamId),
        jsonEncode({'mode': mode.name}),
      );
    } catch (e) {
      dev.log('camera preference write failed: $e', name: 'SellerCameraStorage');
    }
  }
}
