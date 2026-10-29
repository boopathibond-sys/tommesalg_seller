import 'dart:convert';
import 'dart:developer';

/// The seller-app screen a [PushDestination] resolves to.
enum PushTarget { auctionRoom, streamAnalytics, streamList, order, sku, none }

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

  static const _orderDestinations = {
    'ORDER', 'ORDERS', 'ORDER_DETAIL', 'PAYMENT', 'PAYMENT_ACTION',
    'SHIPPING', 'SHIPMENT',
  };
  static const _roomDestinations = {
    'AUCTION_ROOM', 'STREAM', 'STREAM_DETAIL', 'LIVE_ROOM',
  };
  static const _skuDestinations = {'SKU', 'LOCATION', 'INVENTORY'};

  /// The one screen this tap should open. Checked in priority order:
  ///
  ///  1. An order — when the payload says so (`destinationType`) or the
  ///     template is an order/payment/shipping one. Checked before the stream
  ///     because orders won in a live auction carry that stream's id as well.
  ///  2. A stream — the live room, unless the template says the stream is
  ///     over (→ its analytics) or never went ahead (→ the Streams tab, which
  ///     shows the rejection). A room for a closed stream is a dead screen.
  ///  3. A warehouse SKU.
  ///  4. A bare order id from an older template with no destination at all.
  ///
  /// [PushTarget.none] means nothing in the seller app can be opened from this
  /// payload; the caller tells the seller rather than navigating somewhere
  /// arbitrary.
  PushTarget get target {
    final dest = destinationType;
    final hasOrder = orderId?.isNotEmpty ?? false;

    if (hasOrder &&
        (_orderDestinations.contains(dest) || (dest.isEmpty && _isOrderType))) {
      return PushTarget.order;
    }

    if (streamId?.isNotEmpty ?? false) {
      if (dest == 'STREAM_ANALYTICS' || dest == 'STREAM_SUMMARY' ||
          _isStreamType(const ['_ENDED', '_COMPLETED', '_SUMMARY'])) {
        return PushTarget.streamAnalytics;
      }
      if (dest == 'STREAMS' || dest == 'STREAM_LIST' ||
          _isStreamType(const ['_REJECTED', '_CANCELLED', '_CANCELED'])) {
        return PushTarget.streamList;
      }
      if (dest.isEmpty || _roomDestinations.contains(dest)) {
        return PushTarget.auctionRoom;
      }
    }

    if ((locationId?.isNotEmpty ?? false) &&
        (dest.isEmpty ||
            _skuDestinations.contains(dest) ||
            dest.startsWith('STOCK'))) {
      return PushTarget.sku;
    }

    if (hasOrder && dest.isEmpty) return PushTarget.order;
    return PushTarget.none;
  }

  bool get _isOrderType =>
      type.startsWith('ORDER_') ||
      type.startsWith('PAYMENT_') ||
      type.startsWith('SHIPPING_') ||
      type.startsWith('SHIPMENT_');

  /// `STREAM_ENDED`, `STREAM_REJECTED`, … — stream-level templates only, so a
  /// per-lot `AUCTION_ENDED` still opens the (still running) room.
  bool _isStreamType(List<String> suffixes) =>
      type.startsWith('STREAM_') && suffixes.any(type.endsWith);

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
      'PushDestination(target: ${target.name}, type: $type, '
      'destination: $destinationType, '
      'streamId: $streamId, sellerId: $sellerId, orderId: $orderId, '
      'productId: $productId, offerId: $offerId, locationId: $locationId)';
}
