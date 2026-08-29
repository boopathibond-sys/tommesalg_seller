import '../../../../core/localization/translation_keys.dart';
import 'package:get/get.dart';
/// Models for Seller Media Push — restreaming a live auction out to TikTok,
/// Facebook, Instagram, YouTube or a custom RTMP target.
///
/// Backed by `/api/v1/seller/streams/{streamId}/media-push` (see
/// `lib/raw/FLUTTER_SELLER_MEDIA_PUSH_GUIDE.md`). Destinations are what the
/// seller configures; converters are the Agora instances actually pushing.

/// One RTMP target saved on the stream.
class MediaPushDestination {
  const MediaPushDestination({
    required this.platform,
    required this.rtmpUrl,
    this.streamKey,
  });

  /// `tiktok` | `facebook` | `instagram` | `youtube` | `custom`.
  final String platform;
  final String rtmpUrl;
  final String? streamKey;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'rtmp_url': rtmpUrl,
        if (streamKey != null && streamKey!.trim().isNotEmpty)
          'stream_key': streamKey!.trim(),
      };

  factory MediaPushDestination.fromJson(Map<String, dynamic> json) {
    return MediaPushDestination(
      platform: (json['platform'] as String?) ?? 'custom',
      rtmpUrl: (json['rtmp_url'] as String?) ?? '',
      streamKey: json['stream_key'] as String?,
    );
  }

  MediaPushDestination copyWith({
    String? platform,
    String? rtmpUrl,
    String? streamKey,
  }) =>
      MediaPushDestination(
        platform: platform ?? this.platform,
        rtmpUrl: rtmpUrl ?? this.rtmpUrl,
        streamKey: streamKey ?? this.streamKey,
      );

  /// Base URL + key — what the server actually pushes to, and what has to be
  /// unique across destinations.
  String get fullUrl {
    final key = streamKey?.trim() ?? '';
    if (key.isEmpty) return rtmpUrl.trim();
    final base = rtmpUrl.trim();
    return base.endsWith('/') ? '$base$key' : '$base/$key';
  }

  /// `abcd-efgh-…` → `abcd…efgh`, so a shoulder-surfer can't lift the key but
  /// the seller can still tell two of them apart.
  String? get maskedKey {
    final key = streamKey?.trim();
    if (key == null || key.isEmpty) return null;
    if (key.length <= 8) return '•' * key.length;
    return '${key.substring(0, 4)}${'•' * 6}${key.substring(key.length - 4)}';
  }
}

/// One Agora Media Push converter — a destination that is actually running.
class MediaPushConverter {
  const MediaPushConverter({
    required this.id,
    required this.converterId,
    required this.platform,
    required this.rtmpUrl,
    required this.state,
    this.displayState,
    this.displayNote,
    this.usingRawMode,
    this.hasVideoLayout,
    this.statusError,
  });

  final String id;

  /// Agora's own id — for support/debug only, never for navigation.
  final String converterId;
  final String platform;
  final String rtmpUrl;

  /// `connecting` | `running` | `failed`.
  final String state;

  final String? displayState;
  final String? displayNote;
  final bool? usingRawMode;
  final bool? hasVideoLayout;
  final String? statusError;

  /// `display_state` wins when the server sent one — it accounts for Agora's
  /// status lag.
  String get effectiveState =>
      (displayState != null && displayState!.isNotEmpty) ? displayState! : state;

  bool get isRunning => effectiveState == 'running';
  bool get isFailed => effectiveState == 'failed';

  /// Transcoding without a video layout means the destination may only get
  /// audio — worth warning about.
  bool get audioOnlyRisk => hasVideoLayout == false && usingRawMode != true;

  factory MediaPushConverter.fromJson(Map<String, dynamic> json) {
    return MediaPushConverter(
      id: (json['id'] as String?) ?? '',
      converterId: (json['converter_id'] as String?) ?? '',
      platform: (json['platform'] as String?) ?? 'custom',
      rtmpUrl: (json['rtmp_url'] as String?) ?? '',
      state: (json['state'] as String?) ?? 'connecting',
      displayState: json['display_state'] as String?,
      displayNote: json['display_note'] as String?,
      usingRawMode: json['using_raw_mode'] as bool?,
      hasVideoLayout: json['has_video_layout'] as bool?,
      statusError: json['status_error'] as String?,
    );
  }
}

/// The whole `GET …/media-push` payload.
class MediaPushConfig {
  const MediaPushConfig({
    this.autoStart = false,
    this.isActive = false,
    this.sellerPublisherDetected = false,
    this.destinations = const [],
    this.converters = const [],
  });

  /// Arms the server to start converters when the stream goes LIVE. It never
  /// starts anything by itself.
  final bool autoStart;

  /// True while at least one live converter exists for this stream.
  final bool isActive;

  /// The server found the seller's Agora publisher UID in the channel.
  final bool sellerPublisherDetected;

  final List<MediaPushDestination> destinations;
  final List<MediaPushConverter> converters;

  factory MediaPushConfig.fromJson(Map<String, dynamic> json) {
    return MediaPushConfig(
      autoStart: json['autoStart'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? false,
      sellerPublisherDetected:
          json['sellerPublisherDetected'] as bool? ?? false,
      destinations: ((json['destinations'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => MediaPushDestination.fromJson(e.cast<String, dynamic>()))
          .toList(),
      converters: ((json['converters'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => MediaPushConverter.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  /// More than one converter for the same RTMP URL — the guide's cue to offer
  /// a stop-then-start cleanup.
  bool get hasDuplicateConverters {
    final seen = <String>{};
    for (final c in converters) {
      if (!seen.add(c.rtmpUrl)) return true;
    }
    return false;
  }
}

/// Outcome of `POST …/media-push`. A run counts as a success when at least one
/// converter came up, so [errors] can be non-empty on success.
class MediaPushStartResult {
  const MediaPushStartResult({this.converters = const [], this.errors = const []});

  /// `[{ converterId, platform, state, mode }]` as returned.
  final List<Map<String, dynamic>> converters;

  /// `[{ platform, error }]` for the destinations that could not start.
  final List<Map<String, dynamic>> errors;

  factory MediaPushStartResult.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(dynamic value) =>
        ((value as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();

    return MediaPushStartResult(
      converters: rows(json['converters']),
      errors: rows(json['errors']),
    );
  }

  /// "instagram: requires a detected seller publisher UID…" per failed row.
  String get errorSummary => errors
      .map((e) => '${e['platform'] ?? 'destination'}: ${e['error'] ?? 'failed'}')
      .join('\n');
}

/// The platforms the API accepts, with the copy and RTMP defaults the seller
/// forms use.
class MediaPushPlatform {
  const MediaPushPlatform({
    required this.id,
    required this.label,
    this.defaultRtmpUrl,
    this.requiresKey = false,
    this.needsPublisher = false,
    this.keyHint,
  });

  final String id;
  final String label;

  /// Prefilled ingest URL where the platform publishes a fixed one.
  final String? defaultRtmpUrl;

  /// The API rejects a start without a key (YouTube).
  final bool requiresKey;

  /// The server refuses to create the converter until the seller's publisher
  /// UID is visible in the channel.
  final bool needsPublisher;

  final String? keyHint;

  // Getter, not a stored field: `.tr` must re-resolve when the seller
  // switches language, and a field initialiser only ever runs once.
  static List<MediaPushPlatform> get all => [
    const MediaPushPlatform(
      id: 'youtube',
      label: 'YouTube',
      defaultRtmpUrl: 'rtmp://a.rtmp.youtube.com/live2',
      requiresKey: true,
      keyHint: 'From YouTube Studio → Go live → Stream key',
    ),
    const MediaPushPlatform(
      id: 'tiktok',
      label: 'TikTok',
      keyHint: 'From TikTok LIVE Studio → Stream key',
    ),
    const MediaPushPlatform(
      id: 'facebook',
      label: 'Facebook',
      defaultRtmpUrl: 'rtmps://live-api-s.facebook.com:443/rtmp/',
      needsPublisher: true,
      keyHint: 'From Facebook Live producer → Stream key',
    ),
    const MediaPushPlatform(
      id: 'instagram',
      label: 'Instagram',
      needsPublisher: true,
      keyHint: 'From the Instagram live producer tool',
    ),
    MediaPushPlatform(id: 'custom', label: TKeys.mpCustomRtmp.tr),
  ];

  static MediaPushPlatform of(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return MediaPushPlatform(id: 'custom', label: TKeys.mpCustomRtmp.tr);
  }

  static String labelOf(String id) => of(id).label;
}

/// Client-side validation, mirroring the web form so the seller sees the
/// problem before the round trip. Returns null when the destination is fine.
String? validateMediaPushDestination({
  required String platform,
  required String rtmpUrl,
  String? streamKey,
}) {
  const platforms = {'tiktok', 'facebook', 'instagram', 'youtube', 'custom'};
  final rtmpPattern = RegExp(r'^rtmps?://', caseSensitive: false);

  if (!platforms.contains(platform)) {
    return 'Platform must be TikTok, Facebook, Instagram, YouTube or custom.';
  }
  if (rtmpUrl.trim().isEmpty) return 'RTMP URL is required.';
  if (!rtmpPattern.hasMatch(rtmpUrl.trim())) {
    return 'RTMP URL must start with rtmp:// or rtmps://';
  }
  if (platform == 'youtube' && (streamKey == null || streamKey.trim().isEmpty)) {
    return 'YouTube requires a stream key.';
  }
  return null;
}
