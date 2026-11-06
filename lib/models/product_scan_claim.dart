/// `error.claim` from a `409 PRODUCT_ALREADY_SCANNED` on
/// `POST …/product-requests/scan`: the scanned catalog product is already on
/// another seller's open product request, so nothing was added.
class ProductScanClaim {
  const ProductScanClaim({
    this.productId,
    this.productName,
    this.sellerId,
    this.sellerName,
    this.streamId,
    this.streamName,
  });

  final String? productId;
  final String? productName;
  final String? sellerId;
  final String? sellerName;
  final String? streamId;
  final String? streamName;

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  factory ProductScanClaim.fromJson(Map<String, dynamic> j) => ProductScanClaim(
        productId: _str(j['productId']),
        productName: _str(j['productName']),
        sellerId: _str(j['sellerId']),
        sellerName: _str(j['sellerName']),
        streamId: _str(j['streamId']),
        streamName: _str(j['streamName']),
      );
}
