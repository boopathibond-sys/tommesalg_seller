/// A warehouse SKU / bin row from
/// `GET /api/v1/seller/inventory/locations` (guide §5.2).
///
/// Maps one entry of the response `data.items[]`:
/// `{ id, code, name, zone, aisle, shelf, isActive, sortOrder, tagSlugs[] }`.
class InventoryLocation {
  const InventoryLocation({
    required this.id,
    required this.code,
    required this.name,
    this.zone,
    this.aisle,
    this.shelf,
    required this.isActive,
    this.sortOrder = 0,
    this.tagSlugs = const [],
  });

  final String id;
  final String code;
  final String name;
  final String? zone;
  final String? aisle;
  final String? shelf;
  final bool isActive;
  final int sortOrder;
  final List<String> tagSlugs;

  /// Human-readable "Zone · Aisle · Shelf", skipping any blank parts.
  String get locationPath =>
      [zone, aisle, shelf].where((p) => p != null && p.isNotEmpty).join(' · ');

  factory InventoryLocation.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tagSlugs'];
    return InventoryLocation(
      id: json['id'] as String? ?? '',
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      zone: json['zone'] as String?,
      aisle: json['aisle'] as String?,
      shelf: json['shelf'] as String?,
      isActive: json['isActive'] as bool? ?? false,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      tagSlugs: rawTags is List
          ? rawTags.map((e) => e.toString()).toList()
          : const [],
    );
  }
}
