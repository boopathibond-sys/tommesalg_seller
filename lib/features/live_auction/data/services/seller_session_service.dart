import 'dart:convert';
import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../models/seller_session.dart';
import '../models/session_device.dart';
import '../../../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

/// Thrown when a session endpoint returns a structured V1 error, so callers can
/// branch on [code] — one of `UNAUTHORIZED`, `AUTH_FORBIDDEN`, `NOT_FOUND`,
/// `CONFLICT`, `RATE_LIMITED`.
class AuctionApiException implements Exception {
  AuctionApiException({required this.code, required this.message, this.statusCode});
  final String code;
  final String message;
  final int? statusCode;

  /// The stream ended or the request conflicts with current state — the room
  /// should stop its session and show the ended UI rather than retry.
  bool get isTerminal => code == 'CONFLICT' || code == 'NOT_FOUND';

  @override
  String toString() => 'AuctionApiException($code): $message';
}

/// Owns the seller stream device-session lifecycle per the Seller Stream Device
/// Sessions guide: a stable per-install [deviceId], claiming a seat
/// (→ `sessionToken` + role), the heartbeat that keeps the lease, both handoff
/// systems (PRIMARY and auction control), and disconnect.
class SellerSessionService {
  final _api = ApiClient.instance;
  static const _uuid = Uuid();
  static const _deviceIdKey = 'seller_auction_device_id';
  static const _sessionCacheKey = 'seller_auction_session';

  /// Heartbeat cadence. The guide allows 10–15s and recommends 12s; going
  /// beyond 15s lets the server expire the lease mid-stream.
  static const heartbeatInterval = Duration(seconds: 12);

  /// Device-poll cadence when nothing is outstanding.
  static const pollInterval = Duration(seconds: 12);

  /// Device-poll cadence while a control request is pending, so the approving
  /// device sees it within a few seconds.
  static const pollIntervalPending = Duration(seconds: 5);

  String _base(String streamId) =>
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/session';

  /// Auth headers for a fire-and-forget session call, or null when there is no
  /// bearer to send. [AuthService.ensuredAuthHeaders] already waits out a token
  /// rotation and forces a refresh, so a null here means the session is really
  /// gone — sending the request anyway just buys an `AUTH_MISSING_TOKEN` 401.
  Future<Map<String, String>?> _bearerHeaders() async {
    final headers = await AuthService.instance.ensuredAuthHeaders();
    return headers.containsKey('Authorization') ? headers : null;
  }

  /// A stable UUID persisted per install — the same device identity across app
  /// launches so the server recognises reconnects.
  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = _uuid.v4();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// `POST /session/claim` — registers this device and returns the session
  /// token. The first device to claim becomes PRIMARY.
  Future<SellerSession> claim(String streamId) async {
    final id = await deviceId();
    final res = await _api.post(
      '${_base(streamId)}/claim',
      headers: await AuthService.instance.ensuredAuthHeaders(),
      body: {'deviceId': id},
    );
    final session = SellerSession.fromJson(_data(res), deviceId: id);
    await _cacheSession(streamId, session);
    return session;
  }

  /// `POST /session/heartbeat` — renews the lease. Call every
  /// [heartbeatInterval]. Never throws: a dropped beat is retried by the next
  /// tick rather than tearing the room down.
  Future<void> heartbeat(String streamId, String sessionId) async {
    final headers = await _bearerHeaders();
    // No bearer (signed out, or a refresh that couldn't complete): the call
    // would only come back AUTH_MISSING_TOKEN. Skip it — the next tick sends
    // one as soon as the token is back, and the server expires the lease on its
    // own if it never is.
    if (headers == null) {
      log('Session heartbeat skipped: no auth token');
      return;
    }
    try {
      await _api.post(
        '${_base(streamId)}/heartbeat',
        headers: headers,
        body: {'sessionId': sessionId},
      );
    } catch (e) {
      log('Session heartbeat error: $e');
    }
  }

  /// `POST /session/disconnect` — best-effort clean teardown on leaving.
  ///
  /// Teardown often races the end of the auth session (leaving the room as part
  /// of signing out, or during a token rotation), so a missing bearer is
  /// expected here rather than exceptional: without one the call is skipped and
  /// the lease is left to expire server-side. The local session cache is
  /// cleared either way.
  Future<void> disconnect(String streamId, SellerSession session) async {
    try {
      final headers = await _bearerHeaders();
      if (headers == null) {
        log('Session disconnect skipped: no auth token');
        return;
      }
      await _api.post(
        '${_base(streamId)}/disconnect',
        headers: headers,
        body: {...session.authBody, 'reason': 'user_left'},
      );
    } catch (e) {
      log('Session disconnect error: $e');
    } finally {
      await clearCachedSession();
    }
  }

  // ── Reads ─────────────────────────────────────────────────────────────────

  /// `GET /session/devices` — connected devices plus both pending-request lists.
  Future<SessionDevicesSnapshot> devices(String streamId) async {
    final res = await _api.get(
      '${_base(streamId)}/devices',
      headers: await AuthService.instance.ensuredAuthHeaders(),
    );
    return SessionDevicesSnapshot.fromJson(_data(res));
  }

  /// `GET /session/status?deviceId=…` — this device's PRIMARY flag plus the same
  /// snapshot `devices` returns. Cheaper than two calls when we need both.
  Future<({bool isPrimary, SessionDevicesSnapshot snapshot})> status(
    String streamId,
    String deviceId,
  ) async {
    final res = await _api.get(
      '${_base(streamId)}/status?deviceId=${Uri.encodeQueryComponent(deviceId)}',
      headers: await AuthService.instance.ensuredAuthHeaders(),
    );
    final data = _data(res);
    final snap = data['snapshot'];
    return (
      isPrimary: data['isPrimary'] as bool? ?? false,
      snapshot: SessionDevicesSnapshot.fromJson(
        snap is Map<String, dynamic> ? snap : const <String, dynamic>{},
      ),
    );
  }

  /// `POST /session/verify-primary` — authoritative check that this device still
  /// holds PRIMARY, for use right before an action only PRIMARY may take.
  Future<bool> verifyPrimary(String streamId, SellerSession session) async {
    final res = await _api.post(
      '${_base(streamId)}/verify-primary',
      headers: await AuthService.instance.ensuredAuthHeaders(),
      body: session.authBody,
    );
    return _data(res)['isPrimary'] as bool? ?? false;
  }

  // ── PRIMARY handoff ───────────────────────────────────────────────────────

  /// `POST /session/primary/request` — a SECONDARY device asks to become the
  /// main device. The current PRIMARY sees it in `pendingRequests`.
  Future<void> requestPrimary(String streamId, SellerSession session) async {
    final res = await _api.post(
      '${_base(streamId)}/primary/request',
      headers: await AuthService.instance.ensuredAuthHeaders(),
      body: session.authBody,
    );
    _data(res);
  }

  /// `POST /session/primary/approve` — the PRIMARY hands the role over. The
  /// previous PRIMARY becomes SECONDARY; the requester becomes PRIMARY.
  Future<SessionDevicesSnapshot> approvePrimary(
    String streamId,
    SellerSession session,
    String requestId,
  ) async {
    final res = await _api.post(
      '${_base(streamId)}/primary/approve',
      headers: await AuthService.instance.ensuredAuthHeaders(),
      body: {...session.authBody, 'requestId': requestId},
    );
    return SessionDevicesSnapshot.fromJson(_data(res));
  }

  /// `POST /session/primary/reject` — the PRIMARY denies the handoff.
  Future<SessionDevicesSnapshot> rejectPrimary(
    String streamId,
    SellerSession session,
    String requestId,
  ) async {
    final res = await _api.post(
      '${_base(streamId)}/primary/reject',
      headers: await AuthService.instance.ensuredAuthHeaders(),
      body: {...session.authBody, 'requestId': requestId},
    );
    return SessionDevicesSnapshot.fromJson(_data(res));
  }

  // ── Auction-control handoff ───────────────────────────────────────────────
  //
  // Independent of PRIMARY: a SECONDARY device may hold auction control.
  // `/auction-control/release` is reserved (501) and deliberately unused.

  /// `POST /session/auction-control/request` — ask the current controller for
  /// auction command authority.
  Future<void> requestControl(String streamId, SellerSession session) async {
    final res = await _api.post(
      '${_base(streamId)}/auction-control/request',
      headers: await AuthService.instance.ensuredAuthHeaders(),
      body: session.authBody,
    );
    _data(res);
  }

  /// `POST /session/auction-control/approve` — the controller grants a pending
  /// request from another device.
  Future<SessionDevicesSnapshot> approveControl(
    String streamId,
    SellerSession session,
    String requestId,
  ) async {
    final res = await _api.post(
      '${_base(streamId)}/auction-control/approve',
      headers: await AuthService.instance.ensuredAuthHeaders(),
      body: {...session.authBody, 'requestId': requestId},
    );
    return SessionDevicesSnapshot.fromJson(_data(res));
  }

  /// `POST /session/auction-control/reject` — the controller denies a request.
  Future<SessionDevicesSnapshot> rejectControl(
    String streamId,
    SellerSession session,
    String requestId,
  ) async {
    final res = await _api.post(
      '${_base(streamId)}/auction-control/reject',
      headers: await AuthService.instance.ensuredAuthHeaders(),
      body: {...session.authBody, 'requestId': requestId},
    );
    return SessionDevicesSnapshot.fromJson(_data(res));
  }

  // ── Session cache ─────────────────────────────────────────────────────────

  /// Keeps `sessionToken`/`sessionId` for [streamId] so the room can resume
  /// after the process is killed while the stream is still open.
  Future<void> _cacheSession(String streamId, SellerSession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _sessionCacheKey,
        jsonEncode({'streamId': streamId, ...session.toCache()}),
      );
    } catch (e) {
      log('Session cache write error: $e');
    }
  }

  /// The cached session for [streamId], or null when there is none (or it
  /// belongs to a different stream).
  Future<SellerSession?> cachedSession(String streamId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      if (json['streamId'] != streamId) return null;
      final session = SellerSession.fromCache(json);
      return session.sessionToken.isEmpty ? null : session;
    } catch (e) {
      log('Session cache read error: $e');
      return null;
    }
  }

  Future<void> clearCachedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionCacheKey);
    } catch (e) {
      log('Session cache clear error: $e');
    }
  }

  /// Unwraps the V1 `{ success, data }` envelope, throwing a typed error on the
  /// structured `{ success:false, error }` shape.
  Map<String, dynamic> _data(ApiResponse res) {
    Map<String, dynamic> body;
    try {
      body = res.json;
    } catch (_) {
      throw AuctionApiException(
        code: 'INTERNAL_ERROR',
        message: TKeys.svcUnexpectedResponse
            .trParams({'code': '${res.statusCode}'}),
        statusCode: res.statusCode,
      );
    }
    if (body['success'] == false || !res.isSuccess) {
      final err = body['error'];
      throw AuctionApiException(
        code: (err is Map ? err['code'] : null) as String? ??
            _codeForStatus(res.statusCode),
        message: (err is Map ? err['message'] : null) as String? ??
            'Request failed (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
    final data = body['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// Falls back to the guide's status→code mapping when the body omits `error`.
  String _codeForStatus(int status) {
    switch (status) {
      case 401:
        return 'UNAUTHORIZED';
      case 403:
        return 'AUTH_FORBIDDEN';
      case 404:
        return 'NOT_FOUND';
      case 409:
        return 'CONFLICT';
      case 429:
        return 'RATE_LIMITED';
      default:
        return 'INTERNAL_ERROR';
    }
  }
}
