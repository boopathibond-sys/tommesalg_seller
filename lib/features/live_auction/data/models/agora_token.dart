/// Response models for the two Agora token endpoints.
///
/// `appId` is returned by the server so the client never ships a hard-coded
/// Agora App ID. Both are immutable value types parsed straight from JSON.
library;

/// Response of `POST /api/v1/agora/token` — an RTC token used to join the
/// live-stream **video** channel. The seller joins this channel as a
/// broadcaster (publishes camera + mic).
class RtcTokenResponse {
  const RtcTokenResponse({
    required this.token,
    required this.appId,
    required this.channelName,
    required this.uid,
  });

  final String token;
  final String appId;
  final String channelName;
  final int uid;

  factory RtcTokenResponse.fromJson(Map<String, dynamic> json) {
    return RtcTokenResponse(
      token: (json['token'] ?? '') as String,
      appId: (json['appId'] ?? '') as String,
      channelName: (json['channelName'] ?? '') as String,
      uid: json['uid'] is int
          ? json['uid'] as int
          : int.tryParse('${json['uid']}') ?? 0,
    );
  }

  @override
  String toString() =>
      'RtcTokenResponse(appId: $appId, channelName: $channelName, uid: $uid, '
      'token: ${token.isEmpty ? '<empty>' : '<${token.length} chars>'})';
}

/// Response of `POST /api/v1/agora/rtm-token` — a Signaling (RTM) token used
/// to log into Agora RTM and exchange live chat messages.
class RtmTokenResponse {
  const RtmTokenResponse({
    required this.token,
    required this.appId,
    required this.userId,
  });

  final String token;
  final String appId;
  final String userId;

  factory RtmTokenResponse.fromJson(Map<String, dynamic> json) {
    return RtmTokenResponse(
      token: (json['token'] ?? '') as String,
      appId: (json['appId'] ?? '') as String,
      userId: (json['userId'] ?? '') as String,
    );
  }

  @override
  String toString() =>
      'RtmTokenResponse(appId: $appId, userId: $userId, '
      'token: ${token.isEmpty ? '<empty>' : '<${token.length} chars>'})';
}
