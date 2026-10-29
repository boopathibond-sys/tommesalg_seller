/// One row of the cross-stream request inbox
/// (`GET /api/v1/seller/product-requests`): a product request plus enough of
/// its stream to render it without a second call.
class SellerProductRequestSummary {
  const SellerProductRequestSummary({
    required this.id,
    required this.liveStreamId,
    required this.status,
    this.submittedAt,
    this.updatedAt,
    required this.itemCount,
    required this.streamTitle,
    required this.streamStatus,
    this.streamScheduledStartTime,
    required this.openForProductRequests,
  });

  final String id;
  final String liveStreamId;

  /// Request status: DRAFT / SUBMITTED / FULFILLED / CANCELLED.
  final String status;
  final DateTime? submittedAt;
  final DateTime? updatedAt;
  final int itemCount;

  final String streamTitle;

  /// Stream status: DRAFT / SCHEDULED / LIVE / ENDED / CANCELLED.
  final String streamStatus;
  final DateTime? streamScheduledStartTime;
  final bool openForProductRequests;

  /// The stream still takes products — the request is live. Anything else
  /// (ended, cancelled, closed for requests) reads as discontinued.
  bool get isActive =>
      openForProductRequests &&
      streamStatus != 'ENDED' &&
      streamStatus != 'CANCELLED';

  bool get isStreamLive => streamStatus == 'LIVE';

  /// The moment the seller sent it — falls back to the last update for a
  /// draft that was never submitted.
  DateTime? get sentAt => submittedAt ?? updatedAt;

  static DateTime? _date(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory SellerProductRequestSummary.fromJson(Map<String, dynamic> json) {
    final stream = json['stream'] is Map<String, dynamic>
        ? json['stream'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return SellerProductRequestSummary(
      id: json['id'] as String? ?? '',
      liveStreamId:
          json['liveStreamId'] as String? ?? stream['id'] as String? ?? '',
      status: (json['status'] as String? ?? '').toUpperCase(),
      submittedAt: _date(json['submittedAt']),
      updatedAt: _date(json['updatedAt']),
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      streamTitle: (stream['title'] as String?)?.trim() ?? '',
      streamStatus: (stream['status'] as String? ?? '').toUpperCase(),
      streamScheduledStartTime: _date(stream['scheduledStartTime']),
      openForProductRequests: stream['openForProductRequests'] == true,
    );
  }
}
