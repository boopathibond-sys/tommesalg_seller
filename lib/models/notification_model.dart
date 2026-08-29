/// Inbox notification — one stored row of `GET /api/notifications`.
///
/// ```json
/// {
///   "id": "7c0f…",
///   "type": "STREAM_APPROVED",
///   "category": "stream",
///   "priority": "high",
///   "title": "Your stream was approved",
///   "body": "You can go live at 18:00",
///   "readAt": null,
///   "archivedAt": null,
///   "createdAt": "2026-07-31T18:04:11.000Z",
///   "destinationType": "AUCTION_ROOM",
///   "clickUrl": "/auctions/stream_1785300979073_xvjixmk44",
///   "data": { "streamId": "stream_1785300979073_xvjixmk44" }
/// }
/// ```
///
/// The exact field spelling the backend uses is **not verified** against a
/// captured response — the API guide documents the routes but not the row
/// shape. So every getter reads a handful of plausible spellings
/// (`body`/`message`/`bodyText`, `readAt`/`isRead`/`read`, …) and nothing here
/// throws: an unrecognised shape yields a row with empty text rather than a
/// crashed list.
class NotificationModel {
  NotificationModel({
    required this.id,
    this.title,
    this.body,
    this.type,
    this.category,
    this.priority,
    this.imageUrl,
    this.createdAt,
    this.isRead = false,
    this.isArchived = false,
    this.routingData = const {},
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final readAt     = _dateOf(json, const ['readAt', 'read_at']);
    final archivedAt = _dateOf(json, const ['archivedAt', 'archived_at']);
    final status     = _stringOf(json, const ['status'])?.toLowerCase();

    return NotificationModel(
      id: _stringOf(json, const ['id', 'notificationId', '_id']) ?? '',
      title: _stringOf(json, const ['title', 'heading', 'subject']),
      body: _stringOf(
          json, const ['body', 'message', 'bodyText', 'text', 'description']),
      type: _stringOf(json, const ['type', 'templateKey', 'template_key']),
      category: _stringOf(json, const ['category']),
      priority: _stringOf(json, const ['priority']),
      imageUrl: _stringOf(
          json, const ['imageUrl', 'image_url', 'image', 'thumbnailUrl']),
      createdAt: _dateOf(
          json, const ['createdAt', 'created_at', 'sentAt', 'timestamp']),
      isRead: readAt != null ||
          json['isRead'] == true ||
          json['read'] == true ||
          status == 'read',
      isArchived: archivedAt != null ||
          json['isArchived'] == true ||
          json['archived'] == true ||
          status == 'archived',
      routingData: _routingDataOf(json),
    );
  }

  final String id;
  final String? title;
  final String? body;

  /// Template id — `STREAM_APPROVED`, `AUCTION_ENDED`, … Drives the row icon
  /// when [category] is missing.
  final String? type;

  /// `auction` | `order` | `offer` | `payment` | `shipping` | `stream` |
  /// `social` | `seller` | `buyer` | `admin` | `security` | `marketing`.
  final String? category;

  /// `critical` | `high` | `normal` | `low` | `marketing`.
  final String? priority;

  final String? imageUrl;
  final DateTime? createdAt;
  final bool isRead;
  final bool isArchived;

  /// Flattened payload fed to `PushDestination.parse`, so tapping a stored row
  /// navigates exactly where tapping the original push would have. Built by
  /// hoisting the nested `data` / `metadata` / `payload` objects up next to the
  /// routing fields the parser already knows (`type`, `destinationType`,
  /// `clickUrl`).
  final Map<String, dynamic> routingData;

  bool get isUnread => !isRead;

  /// Local echo of a read/unread/archive mutation — the endpoints answer with
  /// a bare success envelope, so the row is patched in place rather than
  /// re-fetched.
  NotificationModel copyWith({bool? isRead, bool? isArchived}) {
    return NotificationModel(
      id: id,
      title: title,
      body: body,
      type: type,
      category: category,
      priority: priority,
      imageUrl: imageUrl,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      isArchived: isArchived ?? this.isArchived,
      routingData: routingData,
    );
  }

  // ---------- Parsing helpers ----------

  static String? _stringOf(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static DateTime? _dateOf(Map<String, dynamic> json, List<String> keys) {
    final raw = _stringOf(json, keys);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Merges every nested payload object into one flat map alongside the
  /// routing fields. Later sources never overwrite earlier ones, so an id that
  /// appears in both `data` and `metadata` keeps the `data` copy.
  static Map<String, dynamic> _routingDataOf(Map<String, dynamic> json) {
    final flat = <String, dynamic>{};

    void put(String key, dynamic value) {
      if (value == null) return;
      if (flat[key] != null) return;
      flat[key] = value;
    }

    for (final key in const ['type', 'destinationType', 'clickUrl']) {
      put(key, json[key]);
    }
    // The parser also accepts the string forms the FCM data block uses.
    put('payloadJson', json['payloadJson']);
    put('metadataJson', json['metadataJson']);

    for (final key in const ['data', 'metadata', 'payload', 'destination']) {
      final nested = json[key];
      if (nested is! Map) continue;
      nested.forEach((k, v) => put(k.toString(), v));
    }

    // Bare ids sometimes sit at the row root instead of inside `data`.
    for (final key in const [
      'streamId',
      'sellerId',
      'orderId',
      'productId',
      'offerId',
      'locationId',
      'skuId',
    ]) {
      put(key, json[key]);
    }
    return flat;
  }
}

/// Cursor pagination envelope. The inbox pages on an opaque `nextCursor`
/// rather than a page number, so [hasMore] is simply "the server handed back
/// another cursor".
class NotificationListMeta {
  const NotificationListMeta({this.nextCursor, this.total});

  factory NotificationListMeta.fromJson(Map<String, dynamic> json) {
    final cursor = json['nextCursor'] ?? json['next_cursor'] ?? json['cursor'];
    final total  = json['total'] ?? json['totalCount'] ?? json['count'];
    return NotificationListMeta(
      nextCursor: (cursor == null || cursor.toString().isEmpty)
          ? null
          : cursor.toString(),
      total: total is num ? total.toInt() : int.tryParse('${total ?? ''}'),
    );
  }

  final String? nextCursor;
  final int? total;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}
