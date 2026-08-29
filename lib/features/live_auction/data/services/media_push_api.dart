import 'dart:async';
import 'dart:developer';

import '../../../../core/config/env_config.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../models/media_push.dart';
import '../models/seller_session.dart';
import 'seller_session_service.dart';
import '../../../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

/// REST surface for Seller Media Push V1 —
/// `/api/v1/seller/streams/{streamId}/media-push`.
///
/// GET is open to any owned-stream seller session; PATCH / POST / DELETE are
/// PRIMARY-only and carry the session auth body. Timeouts follow the
/// integration guide: the start call does a ~30s publisher lookup server-side
/// before it creates converters, so it gets a full minute.
///
/// The legacy `/api/seller/...` paths use a different envelope and are never
/// called from the app.
class MediaPushApi {
  final _api = ApiClient.instance;

  static const Duration _readTimeout = Duration(seconds: 15);
  static const Duration _writeTimeout = Duration(seconds: 15);
  static const Duration _startTimeout = Duration(seconds: 60);
  static const Duration _stopTimeout = Duration(seconds: 30);

  String _url(String streamId) =>
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/media-push';

  Future<Map<String, String>> get _headers =>
      AuthService.instance.ensuredAuthHeaders();

  /// `GET …/media-push` — destinations, `autoStart`, `isActive`, the publisher
  /// flag and the live converters.
  Future<MediaPushConfig> get(String streamId) async {
    final res = await _api
        .get(_url(streamId), headers: await _headers)
        .timeout(_readTimeout, onTimeout: _timeout('GET'));
    return MediaPushConfig.fromJson(_data(res));
  }

  /// `PATCH …/media-push` — saves the **whole** destination list (the server
  /// replaces it) and/or `autoStart`.
  ///
  /// [removedDestination] must be sent when a destination is being deleted,
  /// otherwise its converter keeps running on Agora.
  Future<void> save({
    required String streamId,
    required SellerSession session,
    required List<MediaPushDestination> destinations,
    bool? autoStart,
    MediaPushDestination? removedDestination,
  }) async {
    final res = await _api
        .patch(
          _url(streamId),
          headers: await _headers,
          body: {
            ...session.authBody,
            'destinations': destinations.map((d) => d.toJson()).toList(),
            if (autoStart != null) 'autoStart': autoStart,
            if (removedDestination != null)
              'removedDestination': removedDestination.toJson(),
          },
        )
        .timeout(_writeTimeout, onTimeout: _timeout('PATCH'));
    _data(res);
  }

  /// `POST …/media-push` — creates the converters. The stream has to be LIVE.
  ///
  /// This replaces any existing converters (stop-then-create), so it is safe
  /// to call again after a failed run. A run with at least one converter is a
  /// success even when [MediaPushStartResult.errors] is non-empty.
  Future<MediaPushStartResult> start({
    required String streamId,
    required SellerSession session,
    required List<MediaPushDestination> destinations,
    required bool autoStart,
  }) async {
    final res = await _api
        .post(
          _url(streamId),
          headers: await _headers,
          body: {
            ...session.authBody,
            'destinations': destinations.map((d) => d.toJson()).toList(),
            'autoStart': autoStart,
          },
        )
        .timeout(_startTimeout, onTimeout: _timeout('POST'));
    return MediaPushStartResult.fromJson(_data(res));
  }

  /// `DELETE …/media-push` — stops every converter for the stream. The body is
  /// mandatory; an empty DELETE is a validation error.
  Future<int> stop({
    required String streamId,
    required SellerSession session,
  }) async {
    final res = await _api
        .delete(
          _url(streamId),
          headers: await _headers,
          body: session.authBody,
        )
        .timeout(_stopTimeout, onTimeout: _timeout('DELETE'));
    final data = _data(res);
    return (data['deletedConverters'] as num?)?.toInt() ?? 0;
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /// A timed-out call is surfaced as the same structured error every other
  /// failure uses, so callers only handle one exception type.
  Future<ApiResponse> Function() _timeout(String method) => () {
        log('Media push $method timed out', name: 'MediaPush');
        throw AuctionApiException(
          code: 'TIMEOUT',
          message: method == 'POST'
              ? 'Starting Media Push took too long. Check the destinations '
                  'below before trying again — some may already be live.'
              : 'The request timed out. Please try again.',
        );
      };

  /// Unwraps `{ success, data }`, throwing [AuctionApiException] on the
  /// structured error shape.
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
        code: (err is Map ? err['code'] : null) as String? ?? 'INTERNAL_ERROR',
        message: (err is Map ? err['message'] : null) as String? ??
            'Request failed (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }

    final data = body['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }
}
