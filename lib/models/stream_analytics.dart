/// The post-mortem payload of `GET /api/v1/seller/streams/:id/analytics`.
///
/// The server returns everything the analysis page needs in one read: stream
/// identity + status, real broadcast/auction durations, product and viewer
/// counters, the money totals and a per-buyer breakdown. Parsed defensively —
/// the counters are optional in older payloads, and `productAuctionDetails`
/// rows are loosely specified, so unknown keys are probed rather than assumed.
class StreamAnalytics {
  const StreamAnalytics({
    required this.streamId,
    this.streamTitle,
    this.streamStatus,
    this.startTime,
    this.endTime,
    this.streamDurationSeconds,
    this.streamDurationFormatted,
    this.totalAuctionDurationSeconds,
    this.totalAuctionDurationFormatted,
    this.productsAuctioned = 0,
    this.productsSold = 0,
    this.productsNotSold = 0,
    this.totalSales = 0,
    this.totalPaid = 0,
    this.totalPending = 0,
    this.peakViewerCount = 0,
    this.averageViewerCount = 0,
    this.currentViewerCount = 0,
    this.productAuctionDetails = const [],
    this.buyerDetails = const [],
    this.totalBuyers = 0,
    this.generatedAt,
  });

  final String streamId;
  final String? streamTitle;
  final String? streamStatus;
  final DateTime? startTime;
  final DateTime? endTime;

  final int? streamDurationSeconds;
  final String? streamDurationFormatted;
  final int? totalAuctionDurationSeconds;
  final String? totalAuctionDurationFormatted;

  final int productsAuctioned;
  final int productsSold;
  final int productsNotSold;

  final num totalSales;
  final num totalPaid;
  final num totalPending;

  final num peakViewerCount;
  final num averageViewerCount;
  final num currentViewerCount;

  final List<AuctionedProduct> productAuctionDetails;
  final List<AnalyticsBuyer> buyerDetails;
  final int totalBuyers;
  final DateTime? generatedAt;

  Duration? get streamDuration => streamDurationSeconds == null
      ? null
      : Duration(seconds: streamDurationSeconds!);

  Duration? get auctionDuration => totalAuctionDurationSeconds == null
      ? null
      : Duration(seconds: totalAuctionDurationSeconds!);

  factory StreamAnalytics.fromJson(Map<String, dynamic> json) {
    return StreamAnalytics(
      streamId: _str(json['streamId']) ?? '',
      streamTitle: _str(json['streamTitle']),
      streamStatus: _str(json['streamStatus']),
      startTime: _date(json['startTime']),
      endTime: _date(json['endTime']),
      streamDurationSeconds: _int(json['streamDurationSeconds']),
      streamDurationFormatted: _str(json['streamDurationFormatted']),
      totalAuctionDurationSeconds: _int(json['totalAuctionDurationSeconds']),
      totalAuctionDurationFormatted: _str(json['totalAuctionDurationFormatted']),
      productsAuctioned: _int(json['productsAuctioned']) ?? 0,
      productsSold: _int(json['productsSold']) ?? 0,
      productsNotSold: _int(json['productsNotSold']) ?? 0,
      totalSales: _num(json['totalSales']) ?? 0,
      totalPaid: _num(json['totalPaid']) ?? 0,
      totalPending: _num(json['totalPending']) ?? 0,
      peakViewerCount: _num(json['peakViewerCount']) ?? 0,
      averageViewerCount: _num(json['averageViewerCount']) ?? 0,
      currentViewerCount: _num(json['currentViewerCount']) ?? 0,
      productAuctionDetails: _list(json['productAuctionDetails'])
          .map(AuctionedProduct.fromJson)
          .toList(),
      buyerDetails:
          _list(json['buyerDetails']).map(AnalyticsBuyer.fromJson).toList(),
      totalBuyers: _int(json['totalBuyers']) ?? 0,
      generatedAt: _date(json['generatedAt']),
    );
  }

  /// Unwraps the `{ data: { analytics: {...} } }` envelope; also accepts the
  /// bare analytics object so the caller can pass either shape.
  static StreamAnalytics? fromResponse(dynamic body) {
    if (body is! Map) return null;
    final data = body['data'];
    Map<String, dynamic>? json;
    if (data is Map<String, dynamic>) {
      final analytics = data['analytics'];
      json = analytics is Map<String, dynamic> ? analytics : data;
    } else if (body['analytics'] is Map<String, dynamic>) {
      json = body['analytics'] as Map<String, dynamic>;
    } else if (body['streamId'] != null) {
      json = body.cast<String, dynamic>();
    }
    if (json == null) return null;
    return StreamAnalytics.fromJson(json);
  }
}

/// One row of `productAuctionDetails` — a product that went under the hammer.
class AuctionedProduct {
  const AuctionedProduct({
    this.productId,
    this.productName,
    this.productImage,
    this.auctionType,
    this.startingPrice,
    this.finalPrice,
    this.sold,
    this.paymentStatus,
    this.buyerName,
    this.orderId,
    this.bidCount,
    this.durationSeconds,
    this.durationFormatted,
    required this.raw,
  });

  final String? productId;
  final String? productName;
  final String? productImage;
  final String? auctionType;
  final num? startingPrice;
  final num? finalPrice;
  final bool? sold;
  final String? paymentStatus;
  final String? buyerName;
  final String? orderId;
  final int? bidCount;
  final int? durationSeconds;
  final String? durationFormatted;
  final Map<String, dynamic> raw;

  factory AuctionedProduct.fromJson(Map<String, dynamic> json) {
    final soldRaw = json['sold'] ?? json['isSold'] ?? json['wasSold'];
    bool? sold;
    if (soldRaw is bool) sold = soldRaw;
    if (soldRaw is String) sold = soldRaw.toLowerCase() == 'true';
    // No explicit flag? A winner or a final price means it moved.
    sold ??= (json['buyerId'] ?? json['buyerName']) != null ? true : null;

    return AuctionedProduct(
      productId: _str(json['productId'] ?? json['id']),
      productName: _str(json['productName'] ?? json['productTitle'] ?? json['name']),
      productImage:
          _str(json['productImage'] ?? json['image'] ?? json['thumbnailUrl']),
      auctionType: _str(json['auctionType']),
      startingPrice: _num(json['startingPrice'] ?? json['startPrice']),
      finalPrice: _num(json['finalPrice'] ?? json['soldPrice'] ?? json['price']),
      sold: sold,
      paymentStatus: _str(json['paymentStatus'] ?? json['status']),
      buyerName: _str(json['buyerName'] ?? json['winnerName']),
      orderId: _str(json['orderId'] ?? json['orderNumber']),
      bidCount: _int(json['bidCount'] ?? json['totalBids']),
      durationSeconds:
          _int(json['auctionDurationSeconds'] ?? json['durationSeconds']),
      durationFormatted: _str(
          json['auctionDurationFormatted'] ?? json['durationFormatted']),
      raw: json,
    );
  }
}

/// One row of `buyerDetails` — who bought, what, and how much is still owed.
class AnalyticsBuyer {
  const AnalyticsBuyer({
    this.buyerId,
    this.buyerName,
    this.buyerEmail,
    this.productsPurchased = const [],
    this.totalSpent = 0,
    this.paid = 0,
    this.pending = 0,
  });

  final String? buyerId;
  final String? buyerName;
  final String? buyerEmail;
  final List<BuyerPurchase> productsPurchased;
  final num totalSpent;
  final num paid;
  final num pending;

  factory AnalyticsBuyer.fromJson(Map<String, dynamic> json) {
    final status = json['paymentStatus'];
    final statusMap =
        status is Map<String, dynamic> ? status : const <String, dynamic>{};
    return AnalyticsBuyer(
      buyerId: _str(json['buyerId'] ?? json['id']),
      buyerName: _str(json['buyerName'] ?? json['name']),
      buyerEmail: _str(json['buyerEmail'] ?? json['email']),
      productsPurchased: _list(json['productsPurchased'])
          .map(BuyerPurchase.fromJson)
          .toList(),
      totalSpent: _num(json['totalSpent']) ?? 0,
      paid: _num(statusMap['paid']) ?? 0,
      pending: _num(statusMap['pending']) ?? 0,
    );
  }
}

/// A single product inside a buyer's basket.
class BuyerPurchase {
  const BuyerPurchase({
    this.productId,
    this.productName,
    this.finalPrice,
    this.paymentStatus,
    this.orderId,
    this.auctionType,
  });

  final String? productId;
  final String? productName;
  final num? finalPrice;
  final String? paymentStatus;
  final String? orderId;
  final String? auctionType;

  bool get isPaid => (paymentStatus ?? '').toUpperCase() == 'PAID';

  factory BuyerPurchase.fromJson(Map<String, dynamic> json) {
    return BuyerPurchase(
      productId: _str(json['productId']),
      productName: _str(json['productName'] ?? json['productTitle']),
      finalPrice: _num(json['finalPrice'] ?? json['price']),
      paymentStatus: _str(json['paymentStatus'] ?? json['status']),
      orderId: _str(json['orderId'] ?? json['orderNumber']),
      auctionType: _str(json['auctionType']),
    );
  }
}

// ── Parsing helpers ──────────────────────────────────────────────────────────

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

num? _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

int? _int(dynamic v) => _num(v)?.round();

DateTime? _date(dynamic v) {
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  return null;
}

List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];
