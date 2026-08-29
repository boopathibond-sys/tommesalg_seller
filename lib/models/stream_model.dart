class StreamModel {
  final String id;
  final String title;
  final String? description;
  final String status;
  final DateTime? scheduledStartTime;
  final DateTime createdAt;
  final bool openForProductRequests;
  final String? thumbnailUrl;
  final String? approvalStatus;

  /// Size tags the stream was created with — prefilled back into the edit form.
  final List<String> sizes;

  /// Planned duration in minutes, as sent on create/update.
  final int? streamDurationMinutes;

  /// When the broadcast actually started / ended. Only the single-stream GET
  /// returns these; they drive the real duration on the analytics page.
  final DateTime? actualStartTime;
  final DateTime? endTime;

  StreamModel({
    required this.id,
    required this.title,
    this.description,
    required this.status,
    this.scheduledStartTime,
    required this.createdAt,
    required this.openForProductRequests,
    this.thumbnailUrl,
    this.approvalStatus,
    this.sizes = const [],
    this.streamDurationMinutes,
    this.actualStartTime,
    this.endTime,
  });

  factory StreamModel.fromJson(Map<String, dynamic> json) {
    return StreamModel(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      status: json['status'] as String? ?? '',
      scheduledStartTime: json['scheduledStartTime'] != null
          ? DateTime.tryParse(json['scheduledStartTime'] as String)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      openForProductRequests: json['openForProductRequests'] as bool? ?? false,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      approvalStatus: json['approvalStatus'] as String?,
      sizes: (json['sizes'] as List?)
              ?.map((e) => '$e')
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      streamDurationMinutes: json['streamDurationMinutes'] is num
          ? (json['streamDurationMinutes'] as num).toInt()
          : null,
      actualStartTime: json['actualStartTime'] is String
          ? DateTime.tryParse(json['actualStartTime'] as String)
          : null,
      endTime: json['endTime'] is String
          ? DateTime.tryParse(json['endTime'] as String)
          : null,
    );
  }

  StreamModel copyWith({
    String? title,
    String? description,
    String? status,
    DateTime? scheduledStartTime,
    bool? openForProductRequests,
    String? thumbnailUrl,
    String? approvalStatus,
    List<String>? sizes,
    int? streamDurationMinutes,
    DateTime? actualStartTime,
    DateTime? endTime,
  }) {
    return StreamModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      scheduledStartTime: scheduledStartTime ?? this.scheduledStartTime,
      createdAt: createdAt,
      openForProductRequests:
          openForProductRequests ?? this.openForProductRequests,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      sizes: sizes ?? this.sizes,
      streamDurationMinutes:
          streamDurationMinutes ?? this.streamDurationMinutes,
      actualStartTime: actualStartTime ?? this.actualStartTime,
      endTime: endTime ?? this.endTime,
    );
  }

  bool get isDraft => status == 'DRAFT';
  bool get isScheduled => status == 'SCHEDULED';
  bool get isLive => status == 'LIVE';
  bool get isCancelled => status == 'CANCELLED';

  /// A stream the seller can no longer broadcast in. `CANCELLED` counts as
  /// ended too — the auction room treats both as terminal, so the list must
  /// not keep offering "Enter room" for either.
  bool get isEnded => status == 'ENDED' || status == 'CANCELLED';
}
