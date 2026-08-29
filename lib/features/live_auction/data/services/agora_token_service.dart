import '../../../../core/config/env_config.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../models/agora_token.dart';

/// Fetches Agora RTC + RTM tokens from the backend. The server owns the Agora
/// App ID and certificate, so the client ships neither — every join uses a
/// freshly-issued, backend-signed token authorized by the seller's Supabase
/// bearer.
class AgoraTokenService {
  final _api = ApiClient.instance;

  /// `POST /api/v1/agora/token` → RTC token for the video channel.
  Future<RtcTokenResponse> fetchRtcToken({
    required String channelName,
    required int uid,
  }) async {
    final res = await _api.post(
      '${EnvConfig.baseUrl}/api/v1/agora/token',
      headers: await AuthService.instance.ensuredAuthHeaders(),
      body: {'channelName': channelName, 'uid': uid},
    );
    return RtcTokenResponse.fromJson(_unwrap(res));
  }

  /// `POST /api/v1/agora/rtm-token` → RTM token for chat/signaling.
  Future<RtmTokenResponse> fetchRtmToken({required String userId}) async {
    final res = await _api.post(
      '${EnvConfig.baseUrl}/api/v1/agora/rtm-token',
      headers: await AuthService.instance.ensuredAuthHeaders(),
      body: {'userId': userId},
    );
    return RtmTokenResponse.fromJson(_unwrap(res));
  }

  /// Endpoints return their fields at the top level, but some wrap them in
  /// `{ "data": { ... } }` — accept both, and surface a clear error otherwise.
  Map<String, dynamic> _unwrap(ApiResponse res) {
    if (!res.isSuccess) {
      throw StateError('Agora token request failed (${res.statusCode})');
    }
    final body = res.json;
    final inner = body['data'];
    if (inner is Map<String, dynamic>) return inner;
    return body;
  }
}
