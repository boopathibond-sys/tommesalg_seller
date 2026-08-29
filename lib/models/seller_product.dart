/// A row of `GET /api/v1/seller/products` — the seller's own catalog list.
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
  final DateTime? createdAt;
  final List<String> images;

  SellerProduct({
    required this.id,
    required this.name,
    required this.status,
    required this.isVisible,
    this.originalPrice,
    this.buyNowPrice,
    this.createdAt,
    this.images = const [],
  });

  factory SellerProduct.fromJson(Map<String, dynamic> json) {
    return SellerProduct(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      status: json['status'] as String? ?? '',
      isVisible: json['isVisible'] as bool? ?? false,
      originalPrice: json['originalPrice'] as num?,
      buyNowPrice: json['buyNowPrice'] as num?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      images: (json['images'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
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
