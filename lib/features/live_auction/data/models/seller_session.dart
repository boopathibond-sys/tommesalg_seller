/// Result of `POST /api/v1/seller/streams/:id/session/claim`.
///
/// The [sessionToken] + a stable [deviceId] authorize every session mutation.
/// The first device to claim becomes `PRIMARY`.
///
/// Two independent control types live on a session and both can change while
/// the room is open, so neither is treated as fixed after claim:
///  * [isPrimary] — main device ownership (`/primary/*` handoff)
///  * [isAuctionController] — auction room command authority
///    (`/auction-control/*` handoff)
///
/// A SECONDARY device may hold auction control; the two are not tied.
class SellerSession {
  const SellerSession({
    required this.sessionId,
    required this.deviceId,
    required this.sessionToken,
    required this.role,
    required this.isPrimary,
    required this.isAuctionController,
  });

  final String sessionId;
  final String deviceId;
  final String sessionToken;
  final String role; // PRIMARY | SECONDARY
  final bool isPrimary;
  final bool isAuctionController;

  factory SellerSession.fromJson(
    Map<String, dynamic> json, {
    required String deviceId,
  }) {
    final session = json['session'];
    final sessionMap =
        session is Map<String, dynamic> ? session : const <String, dynamic>{};
    final snapshot = json['snapshot'];
    final snapshotMap =
        snapshot is Map<String, dynamic> ? snapshot : const <String, dynamic>{};

    final controllerDeviceId =
        snapshotMap['auctionControllerDeviceId'] as String?;
    final role =
        (json['role'] ?? sessionMap['sessionRole'] ?? 'PRIMARY') as String;
    final isPrimary = json['isPrimary'] as bool? ?? role == 'PRIMARY';

    return SellerSession(
      sessionId: (sessionMap['id'] ?? json['sessionId'] ?? '') as String,
      deviceId: deviceId,
      sessionToken: (json['sessionToken'] ?? '') as String,
      role: role,
      isPrimary: isPrimary,
      // We hold control when the snapshot's controller device is us, or (on a
      // fresh PRIMARY claim) the server hasn't populated the snapshot yet.
      isAuctionController:
          controllerDeviceId == null ? isPrimary : controllerDeviceId == deviceId,
    );
  }

  SellerSession copyWith({
    bool? isPrimary,
    bool? isAuctionController,
    String? sessionId,
  }) =>
      SellerSession(
        sessionId: sessionId ?? this.sessionId,
        deviceId: deviceId,
        sessionToken: sessionToken,
        role: (isPrimary ?? this.isPrimary) ? 'PRIMARY' : 'SECONDARY',
        isPrimary: isPrimary ?? this.isPrimary,
        isAuctionController: isAuctionController ?? this.isAuctionController,
      );

  /// The auth body every session mutation must carry.
  Map<String, dynamic> get authBody => {
        'deviceId': deviceId,
        'sessionToken': sessionToken,
      };

  /// Persisted so the room can resume after the process is killed, per the
  /// guide's "retain sessionToken/sessionId/streamId while the room is active".
  Map<String, dynamic> toCache() => {
        'sessionId': sessionId,
        'deviceId': deviceId,
        'sessionToken': sessionToken,
        'role': role,
        'isPrimary': isPrimary,
        'isAuctionController': isAuctionController,
      };

  factory SellerSession.fromCache(Map<String, dynamic> json) => SellerSession(
        sessionId: (json['sessionId'] ?? '') as String,
        deviceId: (json['deviceId'] ?? '') as String,
        sessionToken: (json['sessionToken'] ?? '') as String,
        role: (json['role'] ?? 'SECONDARY') as String,
        isPrimary: json['isPrimary'] as bool? ?? false,
        isAuctionController: json['isAuctionController'] as bool? ?? false,
      );
}
