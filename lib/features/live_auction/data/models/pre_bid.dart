/// A pre-bid placed on a queued product before its auction starts
/// (`GET /pre-bids?productId=`). Shape is loosely specified, so parse
/// defensively and keep [raw].
class PreBid {
  const PreBid({
    this.userId,
    this.displayName,
    this.amount,
    this.createdAt,
    required this.raw,
  });

  final String? userId;
  final String? displayName;
  final num? amount;
  final String? createdAt;
  final Map<String, dynamic> raw;

  factory PreBid.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final userMap = user is Map<String, dynamic> ? user : const <String, dynamic>{};
    num? amount;
    final a = json['amount'] ?? json['price'] ?? json['bidAmount'];
    if (a is num) amount = a;
    if (a is String) amount = num.tryParse(a);
    return PreBid(
      userId: (json['userId'] ?? userMap['id']) as String?,
      displayName:
          (json['displayName'] ?? userMap['displayName'] ?? userMap['name'])
              as String?,
      amount: amount,
      createdAt: (json['createdAt'] ?? json['ts']) as String?,
      raw: json,
    );
  }

  static List<PreBid> listFrom(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().map(PreBid.fromJson).toList();
    }
    if (data is Map) {
      final items = data['preBids'] ?? data['items'] ?? data['bids'];
      if (items is List) {
        return items.whereType<Map<String, dynamic>>().map(PreBid.fromJson).toList();
      }
    }
    return const [];
  }
}
