/// A warehouse SKU tag from
/// `GET /api/v1/seller/inventory/location-tags` (guide §5.5).
///
/// Maps one entry of the response `data.items[]`:
/// `{ id, slug, label }`. Created via `POST /location-tags` with
/// `{ slug, label }`.
class InventoryTag {
  const InventoryTag({
    required this.id,
    required this.slug,
    required this.label,
  });

  final String id;
  final String slug;
  final String label;

  factory InventoryTag.fromJson(Map<String, dynamic> json) {
    return InventoryTag(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      label: (json['label'] as String?)?.isNotEmpty == true
          ? json['label'] as String
          : (json['slug'] as String? ?? ''),
    );
  }
}
