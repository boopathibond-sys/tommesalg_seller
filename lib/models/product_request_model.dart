import 'package:get/get.dart';

import '../core/localization/translation_keys.dart';

class ProductRequestProduct {
  final String id;
  final String name;
  final String? brand;
  final String? shortDescription;
  final String? image;
  final String? thumbnailUrl;
  final List<String> images;
  final String? colour;

  /// Norwegian colour name (e.g. "Hvit") — what the nb UI shows as Farge.
  final String? colourNorsk;
  final List<String> sizesAvailable;

  /// The product's own size ("L"), plus its US / EU equivalents.
  final String? sizeFilter;
  final String? usSize;
  final String? euSize;
  final List<String> colorsAvailable;
  final num? originalPrice;
  final num? regularPrice;

  /// Per-product shipping tier in NOK. Null (or 0) means the seller never
  /// picked one — the UI treats that as the 99 kr standard tier.
  final num? shippingPriceNok;

  /// The product's shared sellable stock — what the auction can still sell.
  /// Display only: it does not include draft (not yet submitted) units, and
  /// the app never computes it. Null when the server didn't send it.
  final int? stockCount;

  /// Product-level catalog SKU (`products.sku`). Shared across sellers and
  /// admin; null when nobody has entered one yet.
  final String? sku;

  ProductRequestProduct({
    required this.id,
    required this.name,
    this.brand,
    this.shortDescription,
    this.image,
    this.thumbnailUrl,
    this.images = const [],
    this.colour,
    this.colourNorsk,
    this.sizesAvailable = const [],
    this.sizeFilter,
    this.usSize,
    this.euSize,
    this.colorsAvailable = const [],
    this.originalPrice,
    this.regularPrice,
    this.shippingPriceNok,
    this.stockCount,
    this.sku,
  });

  static String? _text(dynamic v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

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
      colourNorsk: _text(json['colourNorsk']),
      sizesAvailable: (json['sizesAvailable'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sizeFilter: _text(json['sizeFilter']),
      usSize: _text(json['usSize']),
      euSize: _text(json['euSize']),
      colorsAvailable: (json['colorsAvailable'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      originalPrice: (json['veilPris'] ?? json['originalPrice']) as num?,
      regularPrice: json['regularPrice'] as num?,
      shippingPriceNok: json['shippingPriceNok'] is num
          ? json['shippingPriceNok'] as num
          : num.tryParse('${json['shippingPriceNok'] ?? ''}'),
      stockCount: json['stockCount'] is num
          ? (json['stockCount'] as num).toInt()
          : int.tryParse('${json['stockCount'] ?? ''}'),
      sku: _text(json['sku']),
    );
  }

  ProductRequestProduct copyWith({num? shippingPriceNok, String? sku}) {
    return ProductRequestProduct(
      id: id,
      name: name,
      brand: brand,
      shortDescription: shortDescription,
      image: image,
      thumbnailUrl: thumbnailUrl,
      images: images,
      colour: colour,
      colourNorsk: colourNorsk,
      sizesAvailable: sizesAvailable,
      sizeFilter: sizeFilter,
      usSize: usSize,
      euSize: euSize,
      colorsAvailable: colorsAvailable,
      originalPrice: originalPrice,
      regularPrice: regularPrice,
      shippingPriceNok: shippingPriceNok ?? this.shippingPriceNok,
      stockCount: stockCount,
      sku: sku ?? this.sku,
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

int? _intOrNull(dynamic v) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

class ProductRequestItem {
  final String id;
  final String productId;

  /// The line's running total — it keeps growing across submits and sales,
  /// so it is never "what is left". Show [newScanQuantity] /
  /// [streamRemainingQuantity] instead.
  final int quantityRequested;
  final int reservedQuantity;
  final int pendingQuantity;

  /// Units scanned in this draft and not confirmed yet ("1 new scan"). Null
  /// when the server didn't send it (older backend).
  final int? newScanQuantity;

  /// Units of this line already confirmed into the shared stock. Null when
  /// the server didn't send it.
  final int? confirmedQuantity;

  /// Units still sellable on this stream right now (same number the stream
  /// queue shows). Null for unknown-UPC lines and non stock-managed products.
  final int? streamRemainingQuantity;

  /// Draft defect units on this line.
  final int defectQuantity;
  final String lineStatus;
  final bool isUnknownUpc;
  final String? requestedUpc;
  final String? requestedName;
  final List<String> requestedImageUrls;
  final int sortOrder;
  final ProductRequestProduct? product;

  /// TW-193: the seller has an unresolved issue report on this line. Cleared
  /// when the admin resolves it. False when the server didn't send it.
  final bool hasOpenIssue;

  /// TW-193: why this line stays in draft on submit — `UNKNOWN_PRODUCT` or
  /// `OPEN_ISSUE`. Null when the line goes to the auction (or is already
  /// RESERVED / CANCELLED), and on older servers that don't send it.
  final String? holdReason;

  /// True when the server sent `holdReason` (even as null) — i.e. it is a
  /// TW-193 server and [holdReason] is authoritative.
  final bool holdReasonKnown;

  ProductRequestItem({
    required this.id,
    required this.productId,
    required this.quantityRequested,
    required this.reservedQuantity,
    required this.pendingQuantity,
    this.newScanQuantity,
    this.confirmedQuantity,
    this.streamRemainingQuantity,
    this.defectQuantity = 0,
    required this.lineStatus,
    required this.isUnknownUpc,
    this.requestedUpc,
    this.requestedName,
    this.requestedImageUrls = const [],
    required this.sortOrder,
    this.product,
    this.hasOpenIssue = false,
    this.holdReason,
    this.holdReasonKnown = false,
  });

  factory ProductRequestItem.fromJson(Map<String, dynamic> json) {
    return ProductRequestItem(
      id: json['id'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      quantityRequested: _intOrNull(json['quantityRequested']) ?? 0,
      reservedQuantity: _intOrNull(json['reservedQuantity']) ?? 0,
      pendingQuantity: _intOrNull(json['pendingQuantity']) ?? 0,
      newScanQuantity: _intOrNull(json['newScanQuantity']),
      confirmedQuantity: _intOrNull(json['confirmedQuantity']),
      streamRemainingQuantity: _intOrNull(json['streamRemainingQuantity']),
      defectQuantity: _intOrNull(json['defectQuantity']) ?? 0,
      lineStatus: (json['lineStatus'] as String? ?? '').toUpperCase(),
      isUnknownUpc: json['isUnknownUpc'] as bool? ?? false,
      requestedUpc: json['requestedUpc'] as String?,
      requestedName: json['requestedName'] as String?,
      requestedImageUrls: (json['requestedImageUrls'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sortOrder: _intOrNull(json['sortOrder']) ?? 0,
      product: json['product'] is Map<String, dynamic>
          ? ProductRequestProduct.fromJson(
              json['product'] as Map<String, dynamic>)
          : null,
      hasOpenIssue: json['hasOpenIssue'] as bool? ?? false,
      holdReason: _holdReason(json['holdReason']),
      holdReasonKnown: json.containsKey('holdReason'),
    );
  }

  static String? _holdReason(dynamic v) {
    final s = v?.toString().trim().toUpperCase();
    return s == null || s.isEmpty ? null : s;
  }

  static const holdUnknownProduct = 'UNKNOWN_PRODUCT';
  static const holdOpenIssue = 'OPEN_ISSUE';

  /// Why submit keeps this line in draft. Uses the server's [holdReason]
  /// when it sends one; on an older server (no `holdReason` key) an unknown-UPC line is still held
  /// for the admin, and an [hasOpenIssue] line is held for its issue.
  String? get effectiveHoldReason {
    if (holdReasonKnown) return holdReason;
    if (lineStatus == 'RESERVED' || lineStatus == 'CANCELLED') return null;
    if (isUnknownUpc) return holdUnknownProduct;
    if (hasOpenIssue) return holdOpenIssue;
    return null;
  }

  /// True when the line is waiting for the admin rather than going to the
  /// auction on submit.
  bool get isHeld => effectiveHoldReason != null;

  /// Case-insensitive name / UPC match, the same rule the server's `q` uses
  /// (product name, else requested name; requested UPC). Client-side
  /// fallback for servers that ignore `q`.
  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final name = (product?.name ?? requestedName ?? '').toLowerCase();
    final upc = (requestedUpc ?? '').toLowerCase();
    return name.contains(q) || upc.contains(q);
  }

  ProductRequestItem copyWith({
    ProductRequestProduct? product,
    int? quantityRequested,
    bool? hasOpenIssue,
    String? holdReason,
  }) {
    return ProductRequestItem(
      id: id,
      productId: productId,
      quantityRequested: quantityRequested ?? this.quantityRequested,
      reservedQuantity: reservedQuantity,
      pendingQuantity: pendingQuantity,
      newScanQuantity: newScanQuantity,
      confirmedQuantity: confirmedQuantity,
      streamRemainingQuantity: streamRemainingQuantity,
      defectQuantity: defectQuantity,
      lineStatus: lineStatus,
      isUnknownUpc: isUnknownUpc,
      requestedUpc: requestedUpc,
      requestedName: requestedName,
      requestedImageUrls: requestedImageUrls,
      sortOrder: sortOrder,
      product: product ?? this.product,
      hasOpenIssue: hasOpenIssue ?? this.hasOpenIssue,
      holdReason: holdReason ?? this.holdReason,
      holdReasonKnown: holdReasonKnown,
    );
  }

  /// Units of this line not yet sent to live (submitted) — the server's
  /// [newScanQuantity] when it sends one.
  ///
  /// Fallback for an older backend: submit credits a known line's units and
  /// records them in [reservedQuantity], so re-scanning afterwards leaves the
  /// new units in `quantityRequested − reservedQuantity`. An unknown-UPC line
  /// never gets stock, so it counts as unsent only while it is a `DRAFT`.
  int get unsentQuantity {
    if (lineStatus == 'CANCELLED') return 0;
    final fresh = newScanQuantity;
    if (fresh != null) return fresh > 0 ? fresh : 0;
    if (isUnknownUpc) return lineStatus == 'DRAFT' ? quantityRequested : 0;
    final unsent = quantityRequested - reservedQuantity;
    return unsent > 0 ? unsent : 0;
  }

  /// Units already confirmed into shared stock ([reservedQuantity] on an
  /// older backend).
  int get confirmedUnits => confirmedQuantity ?? reservedQuantity;

  /// Highest quantity `PATCH …/items/:itemId` accepts.
  static const int maxQuantity = 999;

  /// Lowest `quantityRequested` the server accepts: never below 1, the
  /// confirmed units, or the line's defects.
  int get minQuantity =>
      [1, confirmedUnits, defectQuantity].reduce((a, b) => a > b ? a : b);

  /// The "−" control: the line can be lowered without touching confirmed
  /// units (`quantityRequested > max(1, confirmedQuantity)`) or its defects.
  bool get canDecreaseQuantity => quantityRequested > minQuantity;

  bool get canIncreaseQuantity => quantityRequested < maxQuantity;

  /// Best-effort image to display in the list/quick view.
  String get displayImageUrl =>
      product?.thumbnailUrl ??
      product?.image ??
      (requestedImageUrls.isNotEmpty ? requestedImageUrls.first : '');

  /// Best-effort name to display.
  String get displayName =>
      product?.name ?? requestedName ?? requestedUpc ?? TKeys.reqUnknownProduct.tr;
}
