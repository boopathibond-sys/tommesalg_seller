/// One entry of `GET /api/v1/seller/products/{id}/edit-logs` — a single field
/// change, with the reason the editor gave for it.
///
/// The API logs one row per changed field, so a save that touched three fields
/// shows up as three entries sharing a reason and timestamp.
class ProductEditLog {
  final String id;
  final String productId;
  final String? editedBy;
  final String? editorDisplayName;
  final String field;
  final String? oldValue;
  final String? newValue;
  final String? reason;
  final DateTime? createdAt;

  ProductEditLog({
    required this.id,
    required this.productId,
    required this.field,
    this.editedBy,
    this.editorDisplayName,
    this.oldValue,
    this.newValue,
    this.reason,
    this.createdAt,
  });

  factory ProductEditLog.fromJson(Map<String, dynamic> json) {
    return ProductEditLog(
      id: json['id']?.toString() ?? '',
      productId: json['productId']?.toString() ?? '',
      editedBy: json['editedBy']?.toString(),
      editorDisplayName: json['editorDisplayName']?.toString(),
      field: json['field']?.toString() ?? '',
      oldValue: _value(json['oldValue']),
      newValue: _value(json['newValue']),
      reason: json['reason']?.toString(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString())?.toLocal(),
    );
  }

  /// Values arrive as whatever the column held — strings, numbers, arrays —
  /// so everything is flattened to display text here.
  static String? _value(dynamic value) {
    if (value == null) return null;
    if (value is List) return value.map((e) => e.toString()).join(', ');
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
