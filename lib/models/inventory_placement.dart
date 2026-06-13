/// One product assigned to a SKU, from
/// `GET /api/v1/seller/inventory/locations/{id}/placements` (guide §5.4).
///
/// Maps one `data.items[]` entry of shape
/// `{ type: 'product', product: {id,name,upc}, placements: [...],
/// primaryPlacement: {...} }`. [quantity] sums the placement rows at this
/// location; [placementId] points at the primary (or first) placement so the
/// row can be edited.
class InventoryPlacement {
  const InventoryPlacement({
    required this.productId,
    required this.productName,
    this.upc,
    this.image,
    required this.quantity,
    required this.isPrimary,
    this.placementId,
  });

  final String productId;
  final String productName;
  final String? upc;

  /// Raw product image reference (e.g. `products/{id}/0.jpg`), as returned by
  /// the placements endpoint. May be a full URL or a relative storage key.
  final String? image;
  final int quantity;
  final bool isPrimary;
  final String? placementId;

  factory InventoryPlacement.fromJson(Map<String, dynamic> json) {
    final product = (json['product'] as Map?)?.cast<String, dynamic>() ?? {};
    final placements = (json['placements'] as List?) ?? const [];
    final primary =
        (json['primaryPlacement'] as Map?)?.cast<String, dynamic>();

    final rows = placements.whereType<Map>().toList();

    var quantity = 0;
    for (final p in rows) {
      quantity += (p['quantity'] as num?)?.toInt() ?? 0;
    }

    final firstId = rows.isNotEmpty ? rows.first['id'] as String? : null;

    return InventoryPlacement(
      productId: product['id'] as String? ?? '',
      productName: product['name'] as String? ?? '',
      upc: product['upc'] as String?,
      image: product['image'] as String?,
      quantity: quantity,
      isPrimary: primary != null || rows.any((p) => p['isPrimary'] == true),
      placementId: primary?['id'] as String? ?? firstId,
    );
  }
}
