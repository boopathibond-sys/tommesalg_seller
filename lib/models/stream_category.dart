/// A selectable taxonomy node used when creating a stream. The stream-create
/// payload sends the picked nodes' [id]s as `taxonomyNodeIds`.
class StreamCategory {
  final String id;
  final String name;

  const StreamCategory({required this.id, required this.name});

  factory StreamCategory.fromJson(Map<String, dynamic> json) {
    return StreamCategory(
      id: (json['id'] ?? json['nodeId'] ?? json['taxonomyNodeId'] ?? '')
          .toString(),
      name: (json['name'] ??
              json['label'] ??
              json['title'] ??
              json['displayName'] ??
              '')
          .toString(),
    );
  }

  /// Pulls a list of categories out of the various envelope shapes the API
  /// might use: `data` as a raw list, or `data.items` / `data.categories` /
  /// `data.nodes` as the list.
  static List<StreamCategory> listFromResponse(Map<String, dynamic> body) {
    final data = body['data'];
    List<dynamic>? raw;
    if (data is List) {
      raw = data;
    } else if (data is Map<String, dynamic>) {
      raw = (data['items'] ??
          data['categories'] ??
          data['nodes'] ??
          data['taxonomyNodes']) as List<dynamic>?;
    } else if (body['categories'] is List) {
      raw = body['categories'] as List<dynamic>;
    }
    if (raw == null) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(StreamCategory.fromJson)
        .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
        .toList();
  }
}
