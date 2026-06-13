/// One pending / unknown product for a SKU, from
/// `GET /api/v1/seller/inventory/locations/{id}/pending-unknown`.
///
/// Maps one `data.items[]` entry of shape
/// `{ itemId, upc, name, quantity, imageUrls: [...], submittedAt, updatedAt }`.
class PendingProduct {
  const PendingProduct({
    required this.itemId,
    required this.name,
    this.upc,
    required this.quantity,
    this.imageUrls = const [],
    this.submittedAt,
    this.updatedAt,
  });

  final String itemId;
  final String name;
  final String? upc;
  final int quantity;

  /// Raw image references. May be full URLs or relative storage keys
  /// (e.g. `assets/request-products/.../file.png`).
  final List<String> imageUrls;
  final DateTime? submittedAt;
  final DateTime? updatedAt;

  /// First image that looks like a usable network URL, or `null`.
  String? get displayImage {
    for (final url in imageUrls) {
      if (url.startsWith('http')) return url;
    }
    return null;
  }

  factory PendingProduct.fromJson(Map<String, dynamic> json) {
    return PendingProduct(
      itemId: json['itemId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      upc: json['upc'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      imageUrls:
          (json['imageUrls'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      submittedAt: json['submittedAt'] != null
          ? DateTime.tryParse(json['submittedAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}
