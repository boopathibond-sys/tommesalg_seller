/// One order as returned by `GET /api/v1/seller/orders/{orderId}` — the list
/// row plus buyer/seller contacts, the shipping (or in-store pickup) address
/// and the payment timeline.
class SellerOrderDetail {
  const SellerOrderDetail({
    required this.id,
    required this.orderNumber,
    required this.buyerName,
    required this.productName,
    required this.amount,
    required this.shippingAmount,
    required this.productAmount,
    required this.paymentStatus,
    required this.shippingStatus,
    required this.refundStatus,
    required this.refundedAmount,
    required this.paymentAttempts,
    this.fulfillmentType,
    this.trackingUrl,
    this.createdAt,
    this.paidAt,
    this.deliveredAt,
    this.buyer,
    this.seller,
    this.shippingAddress,
    this.pickupAddress,
  });

  final String id;
  final String orderNumber;
  final String buyerName;
  final String productName;

  final num? amount;
  final num? shippingAmount;
  final num? productAmount;

  final String paymentStatus;
  final String shippingStatus;

  /// `NONE` when nothing was refunded.
  final String refundStatus;
  final num? refundedAmount;

  /// `LOCAL_PICKUP` when the buyer collects in store — [pickupAddress] then
  /// carries the shop to collect from.
  final String? fulfillmentType;
  final String? trackingUrl;

  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? deliveredAt;

  final OrderParty? buyer;
  final OrderParty? seller;
  final OrderAddress? shippingAddress;
  final PickupLocation? pickupAddress;

  final List<PaymentAttempt> paymentAttempts;

  bool get isLocalPickup =>
      fulfillmentType?.toUpperCase() == 'LOCAL_PICKUP' || pickupAddress != null;

  bool get wasRefunded =>
      refundStatus.isNotEmpty && refundStatus.toUpperCase() != 'NONE';

  factory SellerOrderDetail.fromJson(Map<String, dynamic> json) {
    final id = str(json['id']) ?? str(json['orderId']) ?? '';
    return SellerOrderDetail(
      id: id,
      orderNumber: str(json['orderNumber']) ?? id,
      buyerName: str(json['buyerName']) ?? '—',
      productName: str(json['productName']) ?? '—',
      amount: numOf(json['amount']),
      shippingAmount: numOf(json['shippingAmountNok']),
      productAmount: numOf(json['productAmountNok']),
      paymentStatus: str(json['paymentStatus'])?.toUpperCase() ?? 'UNKNOWN',
      shippingStatus: str(json['shippingStatus'])?.toUpperCase() ?? 'UNKNOWN',
      refundStatus: str(json['refundStatus'])?.toUpperCase() ?? 'NONE',
      refundedAmount: numOf(json['refundedAmount']),
      fulfillmentType: str(json['fulfillmentType']),
      trackingUrl: str(json['trackingUrl']),
      createdAt: dateOf(json['createdAt']),
      paidAt: dateOf(json['paidAt']),
      deliveredAt: dateOf(json['deliveredAt']),
      buyer: OrderParty.fromJson(json['buyer']),
      seller: OrderParty.fromJson(json['seller']),
      shippingAddress: OrderAddress.fromJson(json['shippingAddress']),
      pickupAddress: PickupLocation.fromJson(json['localPickupAddress']),
      paymentAttempts: (json['paymentAttempts'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PaymentAttempt.fromJson)
          .toList(),
    );
  }

  // Shared parsing helpers — the payload mixes nulls, numbers-as-strings and
  // optional blocks, so every field is probed rather than cast.
  static String? str(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static num? numOf(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  static DateTime? dateOf(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;
}

/// Buyer or seller contact block.
class OrderParty {
  const OrderParty({this.id, this.displayName, this.email, this.phone});

  final String? id;
  final String? displayName;
  final String? email;
  final String? phone;

  static OrderParty? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return OrderParty(
      id: SellerOrderDetail.str(json['id']),
      displayName: SellerOrderDetail.str(json['displayName']) ??
          SellerOrderDetail.str(json['name']),
      email: SellerOrderDetail.str(json['email']),
      phone: SellerOrderDetail.str(json['phone']),
    );
  }
}

/// The buyer's delivery address (snake_case keys, straight from the DB row).
class OrderAddress {
  const OrderAddress({
    this.name,
    this.phone,
    this.line1,
    this.line2,
    this.city,
    this.state,
    this.postalCode,
    this.country,
  });

  final String? name;
  final String? phone;
  final String? line1;
  final String? line2;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;

  /// Address lines under the name, blanks dropped: street, then
  /// "1607 Fredrikstad", then the state when there is one.
  List<String> get lines {
    final postalCity =
        [postalCode, city].where((v) => (v ?? '').isNotEmpty).join(' ');
    return [
      line1,
      line2,
      postalCity.isEmpty ? null : postalCity,
      state,
    ].whereType<String>().where((v) => v.isNotEmpty).toList();
  }

  static OrderAddress? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return OrderAddress(
      name: SellerOrderDetail.str(json['name']),
      phone: SellerOrderDetail.str(json['phone']),
      line1: SellerOrderDetail.str(json['address_line1']),
      line2: SellerOrderDetail.str(json['address_line2']),
      city: SellerOrderDetail.str(json['city']),
      state: SellerOrderDetail.str(json['state']),
      postalCode: SellerOrderDetail.str(json['postal_code']),
      country: SellerOrderDetail.str(json['country']),
    );
  }
}

/// The shop a `LOCAL_PICKUP` order is collected from.
class PickupLocation {
  const PickupLocation({
    this.name,
    this.phone,
    this.line1,
    this.line2,
    this.city,
    this.postalCode,
    this.country,
  });

  final String? name;
  final String? phone;
  final String? line1;
  final String? line2;
  final String? city;
  final String? postalCode;
  final String? country;

  /// `Max Brands For Less, Torvbyen Brochs gate 8 , 1607 Fredrikstad` — the
  /// one-line form the pickup banner shows.
  String get summary {
    final postalCity =
        [postalCode, city].where((v) => (v ?? '').isNotEmpty).join(' ');
    return [line1, postalCity]
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .join(' , ');
  }

  static PickupLocation? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return PickupLocation(
      name: SellerOrderDetail.str(json['name']),
      phone: SellerOrderDetail.str(json['phone']),
      line1: SellerOrderDetail.str(json['address_line1']),
      line2: SellerOrderDetail.str(json['address_line2']),
      city: SellerOrderDetail.str(json['city']),
      postalCode: SellerOrderDetail.str(json['postal_code']),
      country: SellerOrderDetail.str(json['country']),
    );
  }
}

/// One entry of the payment timeline. Loosely specified server-side, so the
/// common keys are probed and the rest ignored.
class PaymentAttempt {
  const PaymentAttempt({this.status, this.amount, this.provider, this.at});

  final String? status;
  final num? amount;
  final String? provider;
  final DateTime? at;

  factory PaymentAttempt.fromJson(Map<String, dynamic> json) {
    return PaymentAttempt(
      status: SellerOrderDetail.str(json['status']) ??
          SellerOrderDetail.str(json['state']),
      amount: SellerOrderDetail.numOf(json['amount']) ??
          SellerOrderDetail.numOf(json['amountNok']),
      provider: SellerOrderDetail.str(json['provider']) ??
          SellerOrderDetail.str(json['paymentMethod']),
      at: SellerOrderDetail.dateOf(json['createdAt']) ??
          SellerOrderDetail.dateOf(json['attemptedAt']) ??
          SellerOrderDetail.dateOf(json['updatedAt']),
    );
  }
}
