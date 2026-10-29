/// `GET /api/v1/seller/streams/{streamId}/product-requests/{requestId}` —
/// one product request with its line items.
class SellerProductRequestDetail {
  const SellerProductRequestDetail({
    required this.id,
    required this.status,
    this.submittedAt,
    this.createdAt,
    this.adminNotes,
    required this.items,
  });

  final String id;
  final String status;
  final DateTime? submittedAt;
  final DateTime? createdAt;
  final String? adminNotes;
  final List<RequestLineItem> items;

  static DateTime? _date(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory SellerProductRequestDetail.fromJson(Map<String, dynamic> json) {
    // `items` and `composeItems` carry the same rows today; prefer `items`.
    final raw = (json['items'] as List?)?.isNotEmpty == true
        ? json['items'] as List
        : (json['composeItems'] as List? ?? const []);
    final items = raw
        .whereType<Map<String, dynamic>>()
        .map(RequestLineItem.fromJson)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final notes = (json['adminNotes'] as String?)?.trim();
    return SellerProductRequestDetail(
      id: json['id'] as String? ?? '',
      status: (json['status'] as String? ?? '').toUpperCase(),
      submittedAt: _date(json['submittedAt']),
      createdAt: _date(json['createdAt']),
      adminNotes: notes == null || notes.isEmpty ? null : notes,
      items: items,
    );
  }
}

/// One product line on a request.
class RequestLineItem {
  const RequestLineItem({
    required this.id,
    required this.quantityRequested,
    required this.reservedQuantity,
    required this.pendingQuantity,
    required this.defectQuantity,
    required this.lineStatus,
    required this.isUnknownUpc,
    this.requestedUpc,
    this.requestedName,
    this.productName,
    this.brand,
    this.imageUrl,
    this.veilPris,
    required this.sortOrder,
  });

  final String id;
  final int quantityRequested;
  final int reservedQuantity;
  final int pendingQuantity;
  final int defectQuantity;

  /// e.g. PENDING_STOCK, FULFILLED.
  final String lineStatus;
  final bool isUnknownUpc;
  final String? requestedUpc;
  final String? requestedName;
  final String? productName;
  final String? brand;
  final String? imageUrl;
  final num? veilPris;
  final int sortOrder;

  /// Catalog name, else what the seller typed for an unknown UPC.
  String? get displayName {
    for (final n in [productName, requestedName]) {
      if (n != null && n.trim().isNotEmpty) return n.trim();
    }
    return null;
  }

  static int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

  static String? _text(dynamic v) {
    final s = (v as String?)?.trim();
    return s == null || s.isEmpty ? null : s;
  }

  factory RequestLineItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'] is Map<String, dynamic>
        ? json['product'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final requestedImages = (json['requestedImageUrls'] as List? ?? const [])
        .whereType<String>()
        .toList();
    final productImages =
        (product['images'] as List? ?? const []).whereType<String>().toList();
    return RequestLineItem(
      id: json['id'] as String? ?? '',
      quantityRequested: _int(json['quantityRequested']),
      reservedQuantity: _int(json['reservedQuantity']),
      pendingQuantity: _int(json['pendingQuantity']),
      defectQuantity: _int(json['defectQuantity']),
      lineStatus: (json['lineStatus'] as String? ?? '').toUpperCase(),
      isUnknownUpc: json['isUnknownUpc'] == true,
      requestedUpc: _text(json['requestedUpc']),
      requestedName: _text(json['requestedName']),
      productName: _text(product['name']),
      brand: _text(product['brand']),
      imageUrl: _text(product['thumbnailUrl']) ??
          _text(product['image']) ??
          (productImages.isNotEmpty ? productImages.first : null) ??
          (requestedImages.isNotEmpty ? requestedImages.first : null),
      veilPris: product['veilPris'] as num?,
      sortOrder: _int(json['sortOrder']),
    );
  }
}
