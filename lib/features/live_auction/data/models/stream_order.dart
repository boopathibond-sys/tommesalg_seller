/// A sold order from the stream (`GET /orders`). Loosely specified, so parse
/// defensively and keep [raw] for anything not surfaced here.
class StreamOrder {
  const StreamOrder({
    this.id,
    this.orderNumber,
    this.productTitle,
    this.buyerName,
    this.buyerEmail,
    this.amount,
    this.status,
    this.image,
    this.createdAt,
    required this.raw,
  });

  final String? id;
  final String? orderNumber;
  final String? productTitle;
  final String? buyerName;
  final String? buyerEmail;
  final num? amount;
  final String? status;
  final String? image;
  final String? createdAt;
  final Map<String, dynamic> raw;

  factory StreamOrder.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    final productMap =
        product is Map<String, dynamic> ? product : const <String, dynamic>{};
    final buyer = json['buyer'];
    final buyerMap = buyer is Map<String, dynamic> ? buyer : const <String, dynamic>{};
    // The seller `/orders` payload uses `totalAmount`; older/other shapes use
    // amount/price. Probe them all so the price never renders as "—".
    num? amount;
    final a = json['totalAmount'] ??
        json['amount'] ??
        json['totalPrice'] ??
        json['price'] ??
        json['soldPrice'];
    if (a is num) amount = a;
    if (a is String) amount = num.tryParse(a);
    return StreamOrder(
      id: (json['id'] ?? json['orderId']) as String?,
      orderNumber: (json['orderNumber'] ?? json['id'] ?? json['orderId']) as String?,
      // The seller `/orders` payload uses `productName`; keep the nested/other
      // keys as fallbacks.
      productTitle: (json['productName'] ??
              json['productTitle'] ??
              productMap['title'] ??
              productMap['name']) as String?,
      buyerName: (json['buyerName'] ?? buyerMap['displayName'] ?? buyerMap['name'])
          as String?,
      buyerEmail: (json['buyerEmail'] ?? buyerMap['email']) as String?,
      amount: amount,
      // Payment state comes back as `paymentStatus` (PAID / …); fall back to
      // a generic `status` if present.
      status: (json['paymentStatus'] ?? json['status']) as String?,
      image: (json['productImage'] ??
          json['image'] ??
          productMap['thumbnailUrl'] ??
          productMap['image']) as String?,
      createdAt: (json['createdAt'] ?? json['placedAt']) as String?,
      raw: json,
    );
  }

  static List<StreamOrder> listFrom(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().map(StreamOrder.fromJson).toList();
    }
    if (data is Map) {
      final items = data['orders'] ?? data['items'];
      if (items is List) {
        return items.whereType<Map<String, dynamic>>().map(StreamOrder.fromJson).toList();
      }
    }
    return const [];
  }
}
