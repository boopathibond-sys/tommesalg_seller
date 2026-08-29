import 'dart:convert';
import 'dart:developer';

/// Where a tapped push (or a tapped inbox row) should take the seller.
///
/// The backend spreads the same few ids across several keys of the FCM data
/// block — a flat `dest_*` copy, a flat `meta_*` copy, a flat `payload_*` copy,
/// the raw `payloadJson` string, and a web `clickUrl`:
///
/// ```json
/// {
///   "type": "STREAM_APPROVED",
///   "destinationType": "AUCTION_ROOM",
///   "clickUrl": "/auctions/stream_1785300979073_xvjixmk44",
///   "dest_streamId": "stream_1785300979073_xvjixmk44",
///   "meta_streamId": "stream_1785300979073_xvjixmk44",
///   "payload_streamId": "stream_1785300979073_xvjixmk44",
///   "payloadJson": "{\"sellerId\":\"…\",\"streamId\":\"stream_…\"}"
/// }
/// ```
///
/// [parse] reads every one of those in turn rather than trusting a single key,
/// because FCM data values are always strings and which copies a given template
/// emits varies by notification type. Nothing here throws: an unparseable
/// payload yields `null` and the tap simply leaves the seller where they are.
class PushDestination {
  const PushDestination({
    required this.destinationType,
    required this.type,
    this.streamId,
    this.sellerId,
    this.orderId,
    this.productId,
    this.offerId,
    this.locationId,
  });

  /// Backend routing verb — `AUCTION_ROOM`, `PAYMENT_ACTION`, etc. Upper-cased.
  final String destinationType;

  /// Template id (`STREAM_APPROVED`, `AUCTION_ENDED`, …). Upper-cased.
  final String type;

  final String? streamId;
  final String? sellerId;
  final String? orderId;
  final String? productId;
  final String? offerId;

  /// Warehouse SKU / location id — the seller-only routing target the buyer
  /// payloads never carry.
  final String? locationId;

  /// True when this tap should drop the seller into their live auction room.
  ///
  /// `destinationType` is authoritative, but a payload that carries a stream id
  /// with no destination (older templates) is treated as a room link too —
  /// there is nothing else a bare `streamId` could mean for a seller.
  bool get opensAuctionRoom =>
      (streamId?.isNotEmpty ?? false) &&
      (destinationType.isEmpty ||
          destinationType == 'AUCTION_ROOM' ||
          destinationType == 'STREAM' ||
          destinationType == 'STREAM_DETAIL' ||
          destinationType == 'LIVE_ROOM');

  /// True when this tap should open one warehouse SKU.
  bool get opensSku =>
      !opensAuctionRoom &&
      (locationId?.isNotEmpty ?? false) &&
      (destinationType.isEmpty ||
          destinationType == 'SKU' ||
          destinationType == 'LOCATION' ||
          destinationType == 'INVENTORY' ||
          destinationType.startsWith('STOCK'));

  /// Nothing in the seller app can be opened from this payload. The caller
  /// tells the seller rather than navigating somewhere arbitrary.
  bool get isDeadEnd => !opensAuctionRoom && !opensSku;

  static PushDestination? parse(Map<String, dynamic> data) {
    if (data.isEmpty) return null;

    // `payloadJson` is a JSON *string*, not a nested object — FCM data values
    // can only ever be strings, so the backend serialises it.
    final payload = _decodeJsonObject(data['payloadJson']);
    final meta = _decodeJsonObject(data['metadataJson']);

    String? pick(List<String> keys, {String? fromUrl}) {
      return _firstNonEmpty([
        for (final key in keys) ...[
          data['dest_$key'],
          data['payload_$key'],
          data['meta_$key'],
          data[key],
          payload[key],
          meta[key],
        ],
        if (fromUrl != null) _segmentAfter(data['clickUrl'], fromUrl),
      ]);
    }

    final streamId = _firstNonEmpty([
      pick(const ['streamId', 'auctionId']),
      _streamIdFromClickUrl(data['clickUrl']),
    ]);
    final sellerId   = pick(const ['sellerId']);
    final orderId    = pick(const ['orderId'], fromUrl: 'orders');
    final productId  = pick(const ['productId'], fromUrl: 'products');
    final offerId    = pick(const ['offerId']);
    final locationId = pick(
      const ['locationId', 'skuId', 'inventoryLocationId'],
      fromUrl: 'locations',
    );

    final destination = PushDestination(
      destinationType:
          (_firstNonEmpty([data['destinationType']]) ?? '').toUpperCase(),
      type: (_firstNonEmpty([data['type'], meta['templateKey']]) ?? '')
          .toUpperCase(),
      streamId: streamId,
      sellerId: sellerId,
      orderId: orderId,
      productId: productId,
      offerId: offerId,
      locationId: locationId,
    );

    if (destination.destinationType.isEmpty &&
        destination.type.isEmpty &&
        streamId == null &&
        orderId == null &&
        productId == null &&
        locationId == null) {
      return null;
    }
    return destination;
  }

  /// `/auctions/stream_1785300979073_xvjixmk44` → `stream_1785300979073_…`.
  /// The last non-empty path segment; query/fragment are ignored.
  static String? _streamIdFromClickUrl(dynamic clickUrl) {
    if (clickUrl is! String || clickUrl.isEmpty) return null;
    try {
      final uri = Uri.parse(clickUrl);
      final segments =
          uri.pathSegments.where((s) => s.isNotEmpty).toList(growable: false);
      if (segments.length < 2) return null;
      // Only trust the URL when it actually points at an auction route.
      final parent = segments[segments.length - 2].toLowerCase();
      if (parent != 'auctions' && parent != 'streams') return null;
      return segments.last;
    } catch (_) {
      return null;
    }
  }

  /// The path segment right after [after] in a `clickUrl`:
  ///
  ///   * `/account/orders/0215/payment`, `orders`   → `0215`
  ///   * `/products/19b04ed9-…`,         `products` → `19b04ed9-…`
  ///
  /// Trailing segments (`/payment`) are ignored, so both the bare and the
  /// action-suffixed web routes resolve to the same id.
  static String? _segmentAfter(dynamic clickUrl, String after) {
    if (clickUrl is! String || clickUrl.isEmpty) return null;
    try {
      final segments = Uri.parse(clickUrl)
          .pathSegments
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      final i = segments.indexWhere((s) => s.toLowerCase() == after);
      if (i < 0 || i + 1 >= segments.length) return null;
      return segments[i + 1];
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _decodeJsonObject(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (e) {
      log('push: bad JSON in payload — $e');
      return const {};
    }
  }

  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final candidate in candidates) {
      if (candidate is String && candidate.isNotEmpty) return candidate;
      if (candidate != null && candidate is! String) {
        final text = candidate.toString();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'PushDestination(type: $type, destination: $destinationType, '
      'streamId: $streamId, sellerId: $sellerId, orderId: $orderId, '
      'productId: $productId, offerId: $offerId, locationId: $locationId)';
}
