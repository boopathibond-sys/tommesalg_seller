class ProductRequestProduct {
  final String id;
  final String name;
  final String? brand;
  final String? shortDescription;
  final String? image;
  final String? thumbnailUrl;
  final List<String> images;
  final String? colour;
  final List<String> sizesAvailable;
  final List<String> colorsAvailable;
  final num? originalPrice;
  final num? regularPrice;

  /// Per-product shipping tier in NOK. Null (or 0) means the seller never
  /// picked one — the UI treats that as the 99 kr standard tier.
  final num? shippingPriceNok;

  ProductRequestProduct({
    required this.id,
    required this.name,
    this.brand,
    this.shortDescription,
    this.image,
    this.thumbnailUrl,
    this.images = const [],
    this.colour,
    this.sizesAvailable = const [],
    this.colorsAvailable = const [],
    this.originalPrice,
    this.regularPrice,
    this.shippingPriceNok,
  });

  factory ProductRequestProduct.fromJson(Map<String, dynamic> json) {
    return ProductRequestProduct(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String?,
      shortDescription: json['shortDescription'] as String?,
      image: json['image'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      images: (json['images'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      colour: json['colour'] as String?,
      sizesAvailable: (json['sizesAvailable'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      colorsAvailable: (json['colorsAvailable'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      originalPrice: json['originalPrice'] as num?,
      regularPrice: json['regularPrice'] as num?,
      shippingPriceNok: json['shippingPriceNok'] is num
          ? json['shippingPriceNok'] as num
          : num.tryParse('${json['shippingPriceNok'] ?? ''}'),
    );
  }

  ProductRequestProduct copyWith({num? shippingPriceNok}) {
    return ProductRequestProduct(
      id: id,
      name: name,
      brand: brand,
      shortDescription: shortDescription,
      image: image,
      thumbnailUrl: thumbnailUrl,
      images: images,
      colour: colour,
      sizesAvailable: sizesAvailable,
      colorsAvailable: colorsAvailable,
      originalPrice: originalPrice,
      regularPrice: regularPrice,
      shippingPriceNok: shippingPriceNok ?? this.shippingPriceNok,
    );
  }
}

class ProductRequestIssue {
  final String message;
  final List<String> imageUrls;
  final DateTime? reportedAt;

  ProductRequestIssue({
    required this.message,
    this.imageUrls = const [],
    this.reportedAt,
  });

  factory ProductRequestIssue.fromJson(Map<String, dynamic> json) {
    return ProductRequestIssue(
      message: json['message'] as String? ?? '',
      imageUrls:
          (json['imageUrls'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      reportedAt: json['reportedAt'] != null
          ? DateTime.tryParse(json['reportedAt'] as String)
          : null,
    );
  }
}

class ProductRequestItem {
  final String id;
  final String productId;
  final int quantityRequested;
  final int reservedQuantity;
  final int pendingQuantity;
  final String lineStatus;
  final bool isUnknownUpc;
  final String? requestedUpc;
  final String? requestedName;
  final List<String> requestedImageUrls;
  final int sortOrder;
  final ProductRequestProduct? product;

  ProductRequestItem({
    required this.id,
    required this.productId,
    required this.quantityRequested,
    required this.reservedQuantity,
    required this.pendingQuantity,
    required this.lineStatus,
    required this.isUnknownUpc,
    this.requestedUpc,
    this.requestedName,
    this.requestedImageUrls = const [],
    required this.sortOrder,
    this.product,
  });

  factory ProductRequestItem.fromJson(Map<String, dynamic> json) {
    return ProductRequestItem(
      id: json['id'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      quantityRequested: json['quantityRequested'] as int? ?? 0,
      reservedQuantity: json['reservedQuantity'] as int? ?? 0,
      pendingQuantity: json['pendingQuantity'] as int? ?? 0,
      lineStatus: json['lineStatus'] as String? ?? '',
      isUnknownUpc: json['isUnknownUpc'] as bool? ?? false,
      requestedUpc: json['requestedUpc'] as String?,
      requestedName: json['requestedName'] as String?,
      requestedImageUrls: (json['requestedImageUrls'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sortOrder: json['sortOrder'] as int? ?? 0,
      product: json['product'] is Map<String, dynamic>
          ? ProductRequestProduct.fromJson(
              json['product'] as Map<String, dynamic>)
          : null,
    );
  }

  ProductRequestItem copyWith({ProductRequestProduct? product}) {
    return ProductRequestItem(
      id: id,
      productId: productId,
      quantityRequested: quantityRequested,
      reservedQuantity: reservedQuantity,
      pendingQuantity: pendingQuantity,
      lineStatus: lineStatus,
      isUnknownUpc: isUnknownUpc,
      requestedUpc: requestedUpc,
      requestedName: requestedName,
      requestedImageUrls: requestedImageUrls,
      sortOrder: sortOrder,
      product: product ?? this.product,
    );
  }

  /// Best-effort image to display in the list/quick view.
  String get displayImageUrl =>
      product?.thumbnailUrl ??
      product?.image ??
      (requestedImageUrls.isNotEmpty ? requestedImageUrls.first : '');

  /// Best-effort name to display.
  String get displayName =>
      product?.name ?? requestedName ?? requestedUpc ?? 'Unknown product';
}
