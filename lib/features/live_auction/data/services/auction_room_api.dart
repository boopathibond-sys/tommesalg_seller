import '../../../../core/config/env_config.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../models/auction_room_snapshot.dart';
import '../models/catalog_product.dart';
import '../models/pre_bid.dart';
import '../models/seller_session.dart';
import '../models/stream_order.dart';
import 'seller_session_service.dart';
import '../../../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

/// Result of a mutation: the fresh (possibly partial) snapshot plus the
/// `meta.depletedRandomProductId` alert the server may raise on auction end.
class MutationResult {
  const MutationResult({required this.snapshot, this.depletedRandomProductId});
  final AuctionRoomSnapshot snapshot;
  final String? depletedRandomProductId;
}

/// Parameters for `POST /auction-room/start`.
class StartAuctionParams {
  const StartAuctionParams({
    this.auctionType = 'NORMAL',
    this.durationSec = 60,
    this.startingPrice,
    this.bidIncrement,
    this.shippingPriceNok,
    this.sellerAnnouncement,
  });

  final String auctionType; // NORMAL | DUTCH
  final int durationSec; // 10–60
  final num? startingPrice;
  final num? bidIncrement;
  final num? shippingPriceNok;
  final String? sellerAnnouncement;

  Map<String, dynamic> toBody() => {
        'auctionType': auctionType,
        'durationSec': durationSec,
        if (startingPrice != null) 'startingPrice': startingPrice,
        if (bidIncrement != null) 'bidIncrement': bidIncrement,
        if (shippingPriceNok != null) 'shippingPriceNok': shippingPriceNok,
        if (sellerAnnouncement != null && sellerAnnouncement!.trim().isNotEmpty)
          'sellerAnnouncement': sellerAnnouncement!.trim(),
      };
}

/// REST surface for the Seller Auction Room V1 (snapshot + mutations + go-live).
/// All auction mutations carry the session auth body (`deviceId`,
/// `sessionToken`) and require auction control.
class AuctionRoomApi {
  final _api = ApiClient.instance;

  String _room(String streamId, [String suffix = '']) =>
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/auction-room$suffix';

  Future<Map<String, String>> get _headers => AuthService.instance.ensuredAuthHeaders();

  // ── Reads ────────────────────────────────────────────────────────────────

  /// `GET /auction-room` — the full authoritative snapshot.
  Future<AuctionRoomSnapshot> getSnapshot(String streamId) async {
    final res = await _api.get(_room(streamId), headers: await _headers);
    return AuctionRoomSnapshot.fromJson(_data(res));
  }

  /// `GET /auction-room/queue/catalog` — every product the seller can add to
  /// the queue (with `inQueue` marking the ones already lined up).
  Future<List<CatalogProduct>> queueCatalog(String streamId) async {
    final res = await _api.get(
      _room(streamId, '/queue/catalog'),
      headers: await _headers,
    );
    final data = _data(res);
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(CatalogProduct.fromJson)
        .toList();
  }

  // ── Queue mutations ────────────────────────────────────────────────────────

  /// `POST /auction-room/queue` (batch) — add several catalog products at once.
  /// Each entry is `{ productId, auctionType, sourceType }`.
  Future<MutationResult> enqueueBatch({
    required String streamId,
    required SellerSession session,
    required List<Map<String, dynamic>> products,
  }) {
    return _mutate(_room(streamId, '/queue'), {
      ...session.authBody,
      'products': products,
    });
  }

  Future<MutationResult> enqueue({
    required String streamId,
    required SellerSession session,
    required String productId,
    String auctionType = 'NORMAL',
    String sourceType = 'CATALOG',
  }) {
    return _mutate(_room(streamId, '/queue'), {
      ...session.authBody,
      'productId': productId,
      'auctionType': auctionType,
      'sourceType': sourceType,
    });
  }

  Future<MutationResult> dequeue({
    required String streamId,
    required SellerSession session,
    required String productId,
  }) {
    return _mutate(
      _room(streamId, '/queue/$productId'),
      session.authBody,
      method: 'DELETE',
    );
  }

  Future<MutationResult> reorder({
    required String streamId,
    required SellerSession session,
    required String productId,
    required String direction, // up | down
  }) {
    return _mutate(
      _room(streamId, '/queue/$productId/position'),
      {...session.authBody, 'direction': direction},
      method: 'PATCH',
    );
  }

  Future<MutationResult> clearQueue({
    required String streamId,
    required SellerSession session,
  }) {
    return _mutate(_room(streamId, '/queue/clear'), session.authBody);
  }

  // ── Random products ────────────────────────────────────────────────────────

  /// `POST /api/v1/seller/streams/:id/random-products` — creates a mystery lot
  /// from a title, description, stock count and one image.
  ///
  /// The whole record goes as `multipart/form-data` (the image is a real file
  /// part, not a pre-uploaded key), so the auth headers are passed without a
  /// `Content-Type` and the client sets the boundary itself.
  ///
  /// Returns the new product's id. Creating it does **not** queue it — the
  /// caller enqueues with `sourceType: 'RANDOM'`.
  Future<String> createRandomProduct({
    required String streamId,
    required String title,
    required String description,
    required int stock,
    required String imagePath,
  }) async {
    final res = await _api.uploadFile(
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/random-products',
      fieldName: 'image',
      filePath: imagePath,
      fields: {
        'title': title,
        'description': description,
        'stock': '$stock',
      },
      headers: await _headers,
    );

    final data = _data(res);
    final product = data['product'];
    final id = product is Map ? product['id'] as String? : null;
    if (id == null || id.isEmpty) {
      throw AuctionApiException(
        code: 'INTERNAL_ERROR',
        message: TKeys.svcNoProductId.tr,
        statusCode: res.statusCode,
      );
    }
    return id;
  }

  // ── Auction lifecycle ──────────────────────────────────────────────────────

  Future<MutationResult> start({
    required String streamId,
    required SellerSession session,
    required StartAuctionParams params,
  }) {
    return _mutate(_room(streamId, '/start'), {
      ...session.authBody,
      ...params.toBody(),
    });
  }

  Future<MutationResult> endAuction({
    required String streamId,
    required SellerSession session,
  }) {
    return _mutate(_room(streamId, '/end'), session.authBody);
  }

  Future<MutationResult> cancelRoom({
    required String streamId,
    required SellerSession session,
  }) {
    return _mutate(_room(streamId, '/cancel-room'), session.authBody);
  }

  Future<MutationResult> reduceDutchPrice({
    required String streamId,
    required SellerSession session,
    required num newPrice,
    int? offerDurationSec,
  }) {
    return _mutate(_room(streamId, '/dutch/reduce-price'), {
      ...session.authBody,
      'newPrice': newPrice,
      if (offerDurationSec != null) 'offerDurationSec': offerDurationSec,
    });
  }

  // ── Stream lifecycle (adjacent) ────────────────────────────────────────────

  /// `POST /api/v1/seller/streams/:id/go-live` — SCHEDULED → LIVE. Returns the
  /// stream's end time (ISO) when the response carries it, so the room can show
  /// a countdown even if the snapshot is missing `streamEndsAt`.
  Future<String?> goLive(String streamId) async {
    final res = await _api.post(
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/go-live',
      headers: await _headers,
      body: const <String, dynamic>{},
    );
    return _pickEndsAt(_data(res));
  }

  /// `POST /api/v1/seller/streams/:id/end` — end the whole stream.
  Future<void> endStream(String streamId) async {
    final res = await _api.post(
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/end',
      headers: await _headers,
      body: const <String, dynamic>{},
    );
    _data(res);
  }

  /// `POST /api/v1/seller/streams/:id/extend` — push back the stream end time.
  /// [extendMinutes] must be 5–120. Returns the new end time (ISO) if present.
  Future<String?> extend(String streamId, int extendMinutes) async {
    final res = await _api.post(
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/extend',
      headers: await _headers,
      body: {'extendMinutes': extendMinutes},
    );
    return _pickEndsAt(_data(res));
  }

  // ── Stream announcement ────────────────────────────────────────────────────

  /// `PUT /api/v1/seller/streams/:id/announcement` — sets the banner buyers see
  /// during the live. Only controllable while the stream is live.
  Future<void> setAnnouncement(String streamId, String content) async {
    final res = await _api.put(
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/announcement',
      headers: await _headers,
      body: {'content': content},
    );
    _data(res);
  }

  /// `DELETE /api/v1/seller/streams/:id/announcement` — takes the banner down.
  Future<void> clearAnnouncement(String streamId) async {
    final res = await _api.delete(
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/announcement',
      headers: await _headers,
    );
    _data(res);
  }

  /// Digs the stream end time out of a lifecycle response, which returns it
  /// either flat or wrapped in the updated stream object.
  String? _pickEndsAt(Map<String, dynamic> data) {
    for (final map in [data, data['stream'], data['data']]) {
      if (map is! Map) continue;
      final v = map['streamEndsAt'] ?? map['endsAt'] ?? map['endTime'];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  // ── Read helpers (auction-room adjacent) ────────────────────────────────────

  /// `GET /api/v1/seller/streams/:id/pre-bids?productId=` — pre-bids for a lot.
  Future<List<PreBid>> preBids(String streamId, String productId) async {
    final res = await _api.get(
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/pre-bids'
      '?productId=${Uri.encodeComponent(productId)}',
      headers: await _headers,
    );
    if (!res.isSuccess) return const [];
    final body = res.json;
    return PreBid.listFrom(body['data'] ?? body);
  }

  /// `GET /api/v1/seller/streams/:id/orders` — orders placed in the stream.
  Future<List<StreamOrder>> orders(String streamId) async {
    final res = await _api.get(
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/orders',
      headers: await _headers,
    );
    if (!res.isSuccess) return const [];
    final body = res.json;
    return StreamOrder.listFrom(body['data'] ?? body);
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<MutationResult> _mutate(
    String url,
    Map<String, dynamic> body, {
    String method = 'POST',
  }) async {
    late final ApiResponse res;
    switch (method) {
      case 'DELETE':
        res = await _api.delete(url, headers: await _headers, body: body);
        break;
      case 'PATCH':
        res = await _api.patch(url, headers: await _headers, body: body);
        break;
      default:
        res = await _api.post(url, headers: await _headers, body: body);
    }
    final full = _fullBody(res);
    final data = full.$1;
    final meta = full.$2;
    return MutationResult(
      snapshot: AuctionRoomSnapshot.fromJson(data),
      depletedRandomProductId: meta['depletedRandomProductId'] as String?,
    );
  }

  /// Unwraps `{ success, data }`, throwing [AuctionApiException] on the
  /// structured error shape.
  Map<String, dynamic> _data(ApiResponse res) => _fullBody(res).$1;

  (Map<String, dynamic>, Map<String, dynamic>) _fullBody(ApiResponse res) {
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
    final meta = body['meta'];
    return (
      data is Map<String, dynamic> ? data : <String, dynamic>{},
      meta is Map<String, dynamic> ? meta : <String, dynamic>{},
    );
  }
}
