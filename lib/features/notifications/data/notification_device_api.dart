import 'dart:developer';

import '../../../core/config/env_config.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/auth_service.dart';
import 'models/notification_device.dart';

/// Outcome of a device registration.
///
/// Deliberately separates "the backend accepted this" from "the backend gave
/// us a row id" — the two are independent, and collapsing them into a nullable
/// id (the obvious shortcut) makes a successful-but-idless registration
/// indistinguishable from a network failure. The caller uses [ok] to decide
/// whether to cache the payload fingerprint, and [id] only to address a later
/// DELETE.
class DeviceRegistrationResult {
  const DeviceRegistrationResult({required this.ok, this.id});

  const DeviceRegistrationResult.failed()
      : ok = false,
        id = null;

  /// The backend returned 2xx.
  final bool ok;

  /// Server-assigned row id, when the response carried one.
  final String? id;
}

/// Networking for the notification-device registry.
///
/// Note the path has **no `/v1` segment**, unlike the seller routes elsewhere
/// in the app: `{BASE_URL}/api/notification-devices`.
///
/// Every method is **best-effort**: a failed registration must never surface
/// as an error to the user or block sign-in. Push is an enhancement, not a
/// precondition, so failures are logged and swallowed, and the next app launch
/// retries.
class NotificationDeviceApi {
  final _api = ApiClient.instance;

  static const String _path = '/api/notification-devices';

  /// `POST /api/notification-devices`.
  ///
  /// Never throws. See [DeviceRegistrationResult] for why the return type
  /// isn't just a nullable id.
  Future<DeviceRegistrationResult> register(NotificationDevice device) async {
    try {
      // `ensuredAuthHeaders` rather than `authHeaders`: this runs right after
      // sign-in / cold start, exactly when the SDK may be mid-rotation and the
      // synchronous getter would hand us a bearer-less header set.
      final response = await _api.post(
        '${EnvConfig.baseUrl}$_path',
        headers: await AuthService.instance.ensuredAuthHeaders(),
        body: device.toJson(),
      );

      if (!response.isSuccess) {
        log('push: register failed (${response.statusCode}) ${response.body}');
        return const DeviceRegistrationResult.failed();
      }
      log('push: device registered');
      return DeviceRegistrationResult(ok: true, id: _extractId(response));
    } catch (e) {
      log('push: register error — $e');
      return const DeviceRegistrationResult.failed();
    }
  }

  /// `DELETE /api/notification-devices/{id}`.
  ///
  /// Called on logout. Silently no-ops when [deviceRowId] is null (the register
  /// response never gave us one) — in that case the backend is expected to reap
  /// the row itself, or the next user's registration overwrites it via the
  /// `deviceId` upsert key.
  Future<bool> unregister(String? deviceRowId) async {
    if (deviceRowId == null || deviceRowId.isEmpty) return false;

    try {
      // Plain `authHeaders` here, not the ensured variant: this runs inside the
      // logout path, where forcing a token refresh for a bookkeeping DELETE
      // would be both pointless and slow. No token → the call is skipped.
      final headers = AuthService.instance.authHeaders;
      if (!headers.containsKey('Authorization')) {
        log('push: no access token — skipping unregister');
        return false;
      }

      final response = await _api.delete(
        '${EnvConfig.baseUrl}$_path/$deviceRowId',
        headers: headers,
      );
      if (!response.isSuccess) {
        log('push: unregister failed (${response.statusCode}) ${response.body}');
      }
      return response.isSuccess;
    } catch (e) {
      log('push: unregister error — $e');
      return false;
    }
  }

  /// Digs the created row's id out of whatever envelope the backend used.
  ///
  /// Tries, in order: `data.id`, `data.deviceId`, top-level `id`. Returns null
  /// if none are present — see [unregister] for why that is tolerable.
  static String? _extractId(ApiResponse response) {
    try {
      if (response.body.trim().isEmpty) return null;
      final body = response.json;
      final data = body['data'];
      if (data is Map) {
        final id = data['id'] ?? data['deviceId'] ?? data['_id'];
        if (id != null) return id.toString();
      }
      final id = body['id'] ?? body['deviceId'] ?? body['_id'];
      return id?.toString();
    } catch (_) {
      return null;
    }
  }
}
