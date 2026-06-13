import 'inventory_location.dart';

/// Result of the warehouse search endpoints:
/// `GET /api/v1/seller/inventory/search/by-upc?upc=...` and
/// `GET /api/v1/seller/inventory/search/by-tag?tagSlug=...&includeProducts=true`.
///
/// Both return `data: { kind, query, items[] }`, where each item is one of:
/// `product` (a product + its placements), `placement` (a single placement +
/// its product), or `location` (a SKU/bin). [InventorySearchItem] normalizes
/// all three shapes.
class InventorySearchResult {
  const InventorySearchResult({
    required this.kind,
    required this.query,
    required this.items,
  });

  /// `"upc"` or `"tag"`.
  final String kind;
  final String query;
  final List<InventorySearchItem> items;

  factory InventorySearchResult.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return InventorySearchResult(
      kind: json['kind'] as String? ?? '',
      query: json['query'] as String? ?? '',
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(InventorySearchItem.fromJson)
          .toList(),
    );
  }
}

/// A single search hit. [type] is `product`, `placement`, or `location`.
class InventorySearchItem {
  const InventorySearchItem({
    required this.type,
    this.product,
    this.placements = const [],
    this.primaryPlacement,
    this.placement,
    this.location,
  });

  final String type;

  /// Set for `product` and `placement` items.
  final SearchProduct? product;

  /// The placements carried by a `product` item.
  final List<SearchPlacement> placements;
  final SearchPlacement? primaryPlacement;

  /// The single placement carried by a `placement` item.
  final SearchPlacement? placement;

  /// Set for `location` items.
  final InventoryLocation? location;

  bool get isProduct => type == 'product';
  bool get isPlacement => type == 'placement';
  bool get isLocation => type == 'location';

  factory InventorySearchItem.fromJson(Map<String, dynamic> json) {
    final product = (json['product'] as Map?)?.cast<String, dynamic>();
    final location = (json['location'] as Map?)?.cast<String, dynamic>();
    final primary = (json['primaryPlacement'] as Map?)?.cast<String, dynamic>();
    final single = (json['placement'] as Map?)?.cast<String, dynamic>();
    final rawPlacements = (json['placements'] as List?) ?? const [];

    return InventorySearchItem(
      type: json['type'] as String? ?? '',
      product: product != null ? SearchProduct.fromJson(product) : null,
      placements: rawPlacements
          .whereType<Map<String, dynamic>>()
          .map(SearchPlacement.fromJson)
          .toList(),
      primaryPlacement:
          primary != null ? SearchPlacement.fromJson(primary) : null,
      placement: single != null ? SearchPlacement.fromJson(single) : null,
      location: location != null ? InventoryLocation.fromJson(location) : null,
    );
  }
}

/// Minimal product info returned by search (`{ id, name, upc }`).
class SearchProduct {
  const SearchProduct({required this.id, required this.name, this.upc});

  final String id;
  final String name;
  final String? upc;

  factory SearchProduct.fromJson(Map<String, dynamic> json) {
    return SearchProduct(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      upc: json['upc'] as String?,
    );
  }
}

/// A product placement at a SKU/bin, as returned by search.
class SearchPlacement {
  const SearchPlacement({
    required this.id,
    required this.productId,
    required this.locationId,
    required this.locationCode,
    required this.locationName,
    required this.quantity,
    required this.isPrimary,
    required this.locationIsActive,
  });

  final String id;
  final String productId;
  final String locationId;
  final String locationCode;
  final String locationName;
  final int quantity;
  final bool isPrimary;
  final bool locationIsActive;

  factory SearchPlacement.fromJson(Map<String, dynamic> json) {
    return SearchPlacement(
      id: json['id'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      locationId: json['locationId'] as String? ?? '',
      locationCode: json['locationCode'] as String? ?? '',
      locationName: json['locationName'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      isPrimary: json['isPrimary'] as bool? ?? false,
      locationIsActive: json['locationIsActive'] as bool? ?? false,
    );
  }
}
