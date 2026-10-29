/// An item from `GET /auction-room/queue/catalog` — a product the seller can
/// add to the queue. `inQueue` flags the ones already lined up.
class CatalogProduct {
  const CatalogProduct({
    required this.productId,
    required this.name,
    this.upc,
    this.type = 'USUAL',
    this.inQueue = false,
    this.randomStock,
    this.stockCount,
    this.soldOut = false,
    this.startingPrice,
    this.veilPris,
    this.images = const [],
  });

  final String productId;
  final String name;
  final String? upc;
  final String type; // USUAL | RANDOM
  final bool inQueue;
  final int? randomStock;

  /// Shared sellable stock of a `USUAL` product (null for `RANDOM`, or on a
  /// server that doesn't send it yet). Each lot sold takes one; at 0 the
  /// server drops the product from every queue.
  final int? stockCount;

  /// A `USUAL` product with no stock left — it can't be queued or started.
  final bool soldOut;
  final num? startingPrice;

  /// Recommended retail price ("Veil. pris"). Null when the server doesn't
  /// send it.
  final num? veilPris;
  final List<String> images;

  bool get isRandom => type == 'RANDOM';

  /// Units left to auction: [randomStock] for a random lot, [stockCount]
  /// otherwise. Null when the server didn't report it.
  int? get unitsLeft => isRandom ? randomStock : stockCount;

  /// First image usable as-is. Relative storage keys (e.g. `products/…/0.jpg`)
  /// arrive un-presigned and can't be loaded directly, so only absolute URLs
  /// count — everything else falls back to a placeholder icon in the UI.
  String? get displayImage {
    for (final img in images) {
      if (img.startsWith('http')) return img;
    }
    return null;
  }

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
        productId: (json['productId'] ?? '') as String,
        name: (json['name'] ?? 'Product') as String,
        upc: json['upc'] as String?,
        type: (json['type'] ?? 'USUAL') as String,
        inQueue: json['inQueue'] as bool? ?? false,
        randomStock: (json['randomStock'] as num?)?.toInt(),
        stockCount: (json['stockCount'] as num?)?.toInt(),
        soldOut: json['soldOut'] as bool? ?? false,
        startingPrice: json['startingPrice'] as num?,
        veilPris: (json['veilPris'] ?? json['originalPrice']) as num?,
        images: (json['images'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}
