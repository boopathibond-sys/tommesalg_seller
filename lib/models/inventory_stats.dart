/// Aggregate warehouse counts returned by
/// `GET /api/v1/seller/inventory/stats`.
///
/// See `lib/raw/MOBILE_SELLER_INVENTORY_API_GUIDE.md` §5.1 — the `data`
/// payload is typically `{ totalSkus, activeSkus, productsAssigned }`. The
/// parser is tolerant of camelCase / snake_case and string-or-num values so a
/// minor server shape change doesn't blank the dashboard.
class InventoryStats {
  const InventoryStats({
    required this.totalSkus,
    required this.activeSkus,
    required this.productsAssigned,
  });

  /// Total inventory locations (bins) for this seller.
  final int totalSkus;

  /// Bins with `isActive == true`.
  final int activeSkus;

  /// Total placement rows (products assigned across all bins).
  final int productsAssigned;

  factory InventoryStats.fromJson(Map<String, dynamic> json) {
    int read(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is num) return v.toInt();
        if (v is String) {
          final parsed = int.tryParse(v);
          if (parsed != null) return parsed;
        }
      }
      return 0;
    }

    return InventoryStats(
      totalSkus: read(['totalSkus', 'total_skus', 'totalLocations']),
      activeSkus: read(['activeSkus', 'active_skus', 'activeLocations']),
      productsAssigned: read([
        'assignedProducts',
        'productsAssigned',
        'products_assigned',
        'assigned_products',
        'placements',
        'totalPlacements',
      ]),
    );
  }
}
