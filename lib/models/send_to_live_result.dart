import '../features/live_auction/data/models/catalog_product.dart';
import 'product_request_model.dart';

/// Outcome of "Send to live" — submitting the stream's product request
/// (`PATCH …/product-requests/{requestId}` `{action: "submit"}`).
///
/// Submit credits every known line's new units to the product's stock and
/// queues those products in the stream's auction queue (one queue entry per
/// product; each lot sold takes one unit of stock). Unknown-UPC lines wait for
/// an admin instead.
class SendToLiveResult {
  const SendToLiveResult({
    required this.ok,
    this.units = 0,
    this.products = 0,
    this.unknown = 0,
    this.notQueued = 0,
    this.error,
  });

  const SendToLiveResult.failed(String message)
      : ok = false,
        units = 0,
        products = 0,
        unknown = 0,
        notQueued = 0,
        error = message;

  final bool ok;

  /// Units of known products sent (added to stock).
  final int units;

  /// Distinct known products sent.
  final int products;

  /// Unknown-UPC lines sent for admin approval (no stock, not queued yet).
  final int unknown;

  /// Known products the queue catalog doesn't show as queued after the
  /// submit (the server's enqueue is best effort). 0 when it couldn't be
  /// checked.
  final int notQueued;

  /// Server-supplied failure message, when [ok] is false.
  final String? error;

  /// Counts what [sent] (the unsent lines at the moment of submit) amounted
  /// to, and — given the queue [catalog] read afterwards — which known
  /// products didn't make it into the queue. A sold-out product isn't counted
  /// as missing: the server keeps those out of the queue on purpose.
  static SendToLiveResult summarize(
    List<ProductRequestItem> sent, {
    List<CatalogProduct>? catalog,
  }) {
    var units = 0;
    var unknown = 0;
    final productIds = <String>{};
    for (final item in sent) {
      final qty = item.unsentQuantity;
      if (qty <= 0) continue;
      if (item.isUnknownUpc || item.productId.isEmpty) {
        unknown++;
      } else {
        units += qty;
        productIds.add(item.productId);
      }
    }

    var notQueued = 0;
    if (catalog != null) {
      final byId = {for (final p in catalog) p.productId: p};
      for (final id in productIds) {
        final p = byId[id];
        if (p == null || (!p.inQueue && !p.soldOut)) notQueued++;
      }
    }

    return SendToLiveResult(
      ok: true,
      units: units,
      products: productIds.length,
      unknown: unknown,
      notQueued: notQueued,
    );
  }
}
