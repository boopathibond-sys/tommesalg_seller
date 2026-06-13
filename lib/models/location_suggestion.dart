/// A lightweight SKU suggestion from
/// `GET /api/v1/seller/inventory/locations/suggest?q=...` — `{ id, code, name }`.
class LocationSuggestion {
  const LocationSuggestion({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;

  factory LocationSuggestion.fromJson(Map<String, dynamic> json) {
    return LocationSuggestion(
      id: json['id'] as String? ?? '',
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}
