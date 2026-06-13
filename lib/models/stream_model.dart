class StreamModel {
  final String id;
  final String title;
  final String status;
  final DateTime? scheduledStartTime;
  final DateTime createdAt;
  final bool openForProductRequests;
  final String? thumbnailUrl;

  StreamModel({
    required this.id,
    required this.title,
    required this.status,
    this.scheduledStartTime,
    required this.createdAt,
    required this.openForProductRequests,
    this.thumbnailUrl,
  });

  factory StreamModel.fromJson(Map<String, dynamic> json) {
    return StreamModel(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? '',
      scheduledStartTime: json['scheduledStartTime'] != null
          ? DateTime.tryParse(json['scheduledStartTime'] as String)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      openForProductRequests: json['openForProductRequests'] as bool? ?? false,
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }

  bool get isScheduled => status == 'SCHEDULED';
  bool get isLive => status == 'LIVE';
  bool get isEnded => status == 'ENDED';
}
