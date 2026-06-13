import 'inventory_tag.dart';

/// Full warehouse SKU record from
/// `GET /api/v1/seller/inventory/locations/{id}` (guide §5.2).
///
/// Maps the response `data` payload:
/// `{ location: {...}, tags: [...], placementCount }`.
class InventoryLocationDetail {
  const InventoryLocationDetail({
    required this.id,
    required this.code,
    required this.name,
    this.zone,
    this.aisle,
    this.shelf,
    required this.isActive,
    this.sortOrder = 0,
    this.notes,
    this.tagSlugs = const [],
    this.tags = const [],
    this.placementCount = 0,
  });

  final String id;
  final String code;
  final String name;
  final String? zone;
  final String? aisle;
  final String? shelf;
  final bool isActive;
  final int sortOrder;
  final String? notes;
  final List<String> tagSlugs;
  final List<InventoryTag> tags;
  final int placementCount;

  /// Labeled path, e.g. "Zone 01 · Aisle A · Shelf B3" (skips blank parts).
  String get locationPath => [
        if (zone != null && zone!.isNotEmpty) 'Zone $zone',
        if (aisle != null && aisle!.isNotEmpty) 'Aisle $aisle',
        if (shelf != null && shelf!.isNotEmpty) 'Shelf $shelf',
      ].join(' · ');

  factory InventoryLocationDetail.fromJson(Map<String, dynamic> json) {
    final loc = (json['location'] as Map?)?.cast<String, dynamic>() ?? json;
    final rawTags = (json['tags'] as List?) ?? const [];
    final rawSlugs = loc['tagSlugs'];

    return InventoryLocationDetail(
      id: loc['id'] as String? ?? '',
      code: loc['code'] as String? ?? '',
      name: loc['name'] as String? ?? '',
      zone: loc['zone'] as String?,
      aisle: loc['aisle'] as String?,
      shelf: loc['shelf'] as String?,
      isActive: loc['isActive'] as bool? ?? false,
      sortOrder: (loc['sortOrder'] as num?)?.toInt() ?? 0,
      notes: loc['notes'] as String?,
      tagSlugs: rawSlugs is List
          ? rawSlugs.map((e) => e.toString()).toList()
          : const [],
      tags: rawTags
          .whereType<Map<String, dynamic>>()
          .map(InventoryTag.fromJson)
          .toList(),
      placementCount: (json['placementCount'] as num?)?.toInt() ?? 0,
    );
  }
}
