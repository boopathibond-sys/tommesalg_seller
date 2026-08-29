import '../../../../core/config/env_config.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/services/auth_service.dart';
import 'seller_session_service.dart';
import '../../../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

/// REST surface for server-authoritative chat moderation
/// (`/api/v1/seller/streams/:id/chat/*`). These persist moderation server-side
/// and fan out to every viewer over the auction WebSocket — unlike the RTM
/// broadcast, which is a client-to-client echo only.
class ChatModerationApi {
  final _api = ApiClient.instance;

  String _chat(String streamId, String suffix) =>
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/chat$suffix';

  Future<Map<String, String>> get _headers => AuthService.instance.ensuredAuthHeaders();

  /// `GET /chat/muted-users` → the muted user ids for this stream.
  Future<List<String>> mutedUsers(String streamId) async {
    final res = await _api.get(_chat(streamId, '/muted-users'), headers: await _headers);
    final data = _data(res);
    final list = data['mutedUsers'] ?? data['users'] ?? data['userIds'] ?? data['items'];
    if (list is List) {
      return list
          .map((e) => e is Map ? (e['userId'] ?? e['id']) : e)
          .whereType<String>()
          .toList();
    }
    return const [];
  }

  Future<void> mute(String streamId, String userId) =>
      _post(_chat(streamId, '/mute'), {'userId': userId});

  Future<void> unmute(String streamId, String userId) =>
      _post(_chat(streamId, '/unmute'), {'userId': userId});

  Future<void> enableChat(String streamId) =>
      _post(_chat(streamId, '/enable'), const {});

  Future<void> disableChat(String streamId) =>
      _post(_chat(streamId, '/disable'), const {});

  Future<void> clear(String streamId) =>
      _post(_chat(streamId, '/clear'), const {});

  Future<void> deleteMessage(String streamId, String messageId) =>
      _post(_chat(streamId, '/messages/$messageId/delete'), const {});

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<void> _post(String url, Map<String, dynamic> body) async {
    final res = await _api.post(url, headers: await _headers, body: body);
    _data(res);
  }

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
