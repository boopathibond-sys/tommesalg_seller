/// One row of `GET /api/v1/seller/orders` — a buyer's order for one of the
/// seller's products.
///
/// The payload keys everything at the top level (`buyerName`, `productName`,
/// `amount`, …) and splits the total into `productAmountNok` + the freight the
/// buyer paid (`shippingAmountNok`).
class SellerOrder {
  const SellerOrder({
    required this.id,
    required this.orderNumber,
    required this.buyerName,
    required this.buyerEmail,
    required this.productName,
    required this.amount,
    required this.shippingAmount,
    required this.productAmount,
    required this.paymentStatus,
    required this.shippingStatus,
    this.trackingUrl,
    this.createdAt,
  });

  final String id;
  final String orderNumber;
  final String buyerName;
  final String buyerEmail;
  final String productName;

  /// Total the buyer paid — product + freight.
  final num? amount;
  final num? shippingAmount;
  final num? productAmount;

  /// `PAID`, `PENDING_PAYMENT`, … — server-defined, so never switched on
  /// exhaustively in the UI.
  final String paymentStatus;

  /// Freight state: `NOT_CREATED` until a label exists.
  final String shippingStatus;

  final String? trackingUrl;
  final DateTime? createdAt;

  factory SellerOrder.fromJson(Map<String, dynamic> json) {
    final id = _str(json['id']) ?? _str(json['orderId']) ?? '';
    return SellerOrder(
      id: id,
      orderNumber: _str(json['orderNumber']) ?? id,
      buyerName: _str(json['buyerName']) ?? '—',
      buyerEmail: _str(json['buyerEmail']) ?? '',
      productName: _str(json['productName']) ?? '—',
      amount: _num(json['amount']),
      shippingAmount: _num(json['shippingAmountNok']),
      productAmount: _num(json['productAmountNok']),
      paymentStatus: _str(json['paymentStatus'])?.toUpperCase() ?? 'UNKNOWN',
      shippingStatus: _str(json['shippingStatus'])?.toUpperCase() ?? 'UNKNOWN',
      trackingUrl: _str(json['trackingUrl']),
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  static String? _str(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static num? _num(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }
}
