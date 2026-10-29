/// A row of the seller's product list — `GET /api/v1/seller/products` (the
/// "Mine produkter" page, all streams) or `GET /api/v1/seller/streams/:id/products`
/// (one stream; adds the request fields and `editable`).
///
/// `images` comes back mixed: some entries are already pre-signed S3 URLs,
/// most are bare object keys (`products/<id>/0.jpg`) that can't be loaded
/// directly. [remoteImageUrls] keeps only the ones that are usable as-is;
/// the rest are resolved lazily through the product preview endpoint (see
/// `SellerProductsController.imagesFor`).
class SellerProduct {
  final String id;
  final String name;
  final String status;
  final bool isVisible;
  final num? originalPrice;
  final num? buyNowPrice;

  /// RRP shown on the card; null → a dash.
  final num? msrp;

  /// The product's size bucket (`S`, `M`, …), when set.
  final String? sizeFilter;
  final DateTime? createdAt;
  final List<String> images;

  /// `scanned` (a line on one of the seller's product requests) or `created`
  /// (a seller-made random product). Null on rows built locally.
  final String? source;
  final String? requestId;
  final String? requestItemId;

  /// Status of the request the line belongs to (`draft`, `submitted`, …).
  final String? requestStatus;
  final int? quantityRequested;

  /// Server verdict on whether the Edit button should show: true only for a
  /// scanned line on a `draft` request. Null when unknown (a row built from
  /// another screen) — the edit endpoint still enforces the rule with a 403.
  final bool? editable;

  SellerProduct({
    required this.id,
    required this.name,
    required this.status,
    required this.isVisible,
    this.originalPrice,
    this.buyNowPrice,
    this.msrp,
    this.sizeFilter,
    this.createdAt,
    this.images = const [],
    this.source,
    this.requestId,
    this.requestItemId,
    this.requestStatus,
    this.quantityRequested,
    this.editable,
  });

  factory SellerProduct.fromJson(Map<String, dynamic> json) {
    return SellerProduct(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      status: json['status'] as String? ?? '',
      isVisible: json['isVisible'] as bool? ?? false,
      originalPrice: (json['veilPris'] ?? json['originalPrice']) as num?,
      buyNowPrice: json['buyNowPrice'] as num?,
      msrp: json['msrp'] as num?,
      sizeFilter: json['sizeFilter'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      images: (json['images'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      source: json['source'] as String?,
      requestId: json['requestId'] as String?,
      requestItemId: json['requestItemId'] as String?,
      requestStatus: json['requestStatus'] as String?,
      quantityRequested: (json['quantityRequested'] as num?)?.toInt(),
      editable: json['editable'] as bool?,
    );
  }

  /// Images that can go straight into `Image.network`.
  List<String> get remoteImageUrls =>
      images.where((e) => e.startsWith('http')).toList();

  /// Price the buyer actually pays, falling back to the list price.
  num? get effectivePrice => buyNowPrice ?? originalPrice;

  /// True when a discount is on — used to strike through [originalPrice].
  bool get hasDiscount =>
      buyNowPrice != null &&
      originalPrice != null &&
      buyNowPrice! < originalPrice!;
}
