/// Structured models mirroring the Seller Auction Room V1 snapshot
/// (`GET /api/v1/seller/streams/:id/auction-room` and every WS `SNAPSHOT`).
///
/// Parsing is deliberately defensive: fields the guide leaves loosely typed
/// (numeric prices as int/string, optional nested objects) are coerced with
/// helpers so a slightly different server shape never crashes the room. The
/// authoritative ordering/versioning field is [snapshotVersion].
library;

num? _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

int? _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Pulls the product-queue list out of a snapshot, tolerating the different
/// keys / nestings the backend has shipped it under. The seller room reads the
/// queue purely from the snapshot, so if the server renames this field the
/// mobile queue silently empties (while `queue/catalog` still flags items as
/// `inQueue`) — probing a handful of candidates keeps the two in sync.
///
/// Returns `null` when the payload carries **no** recognisable queue key at
/// all — a partial frame that simply doesn't talk about the queue. That is a
/// different thing from `productQueue: []` ("the queue is empty"), and the two
/// must not be conflated: only the latter may clear the queue we already hold.
List<AuctionProduct>? _parseQueue(Map<String, dynamic> json) {
  const topKeys = [
    'productQueue',
    'queue',
    'products',
    'queuedProducts',
    'queueItems',
    'queuedItems',
    'lineup',
  ];
  List<dynamic>? list;
  for (final k in topKeys) {
    final v = json[k];
    if (v is List) {
      list = v;
      break;
    }
    // Or a wrapper object, e.g. { queue: { items: [...] } }.
    if (v is Map) {
      for (final nk in const ['items', 'products', 'queue']) {
        if (v[nk] is List) {
          list = v[nk] as List;
          break;
        }
      }
      if (list != null) break;
    }
  }
  if (list == null) return null;
  return list
      .whereType<Map>()
      .map((e) => AuctionProduct.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

class AuctionRoomSnapshot {
  const AuctionRoomSnapshot({
    required this.stream,
    this.activeAuction,
    this.productQueue = const [],
    this.hasProductQueue = true,
    this.mutedUserIds = const [],
    this.lastAuctionResult,
    this.snapshotVersion = 0,
    this.generatedAt,
    this.auctionId,
    this.serverTimestamp,
    this.realtime,
    required this.raw,
  });

  final StreamSnapshot stream;
  final ActiveAuction? activeAuction;
  final List<AuctionProduct> productQueue;

  /// Whether this payload actually carried a product queue. `false` means the
  /// frame was silent about the queue (partial mutation echo / lightweight WS
  /// frame) and [productQueue] is a placeholder, not "the queue is empty".
  final bool hasProductQueue;

  final List<String> mutedUserIds;
  final LastAuctionResult? lastAuctionResult;
  final int snapshotVersion;
  final String? generatedAt;
  final String? auctionId;
  final String? serverTimestamp;
  final RealtimeHints? realtime;

  /// The untouched decoded map, kept so newly-added server fields remain
  /// reachable without a model change.
  final Map<String, dynamic> raw;

  AuctionRoomSnapshot copyWith({
    StreamSnapshot? stream,
    ActiveAuction? activeAuction,
  }) =>
      AuctionRoomSnapshot(
        stream: stream ?? this.stream,
        activeAuction: activeAuction ?? this.activeAuction,
        productQueue: productQueue,
        hasProductQueue: hasProductQueue,
        mutedUserIds: mutedUserIds,
        lastAuctionResult: lastAuctionResult,
        snapshotVersion: snapshotVersion,
        generatedAt: generatedAt,
        auctionId: auctionId,
        serverTimestamp: serverTimestamp,
        realtime: realtime,
        raw: raw,
      );

  factory AuctionRoomSnapshot.fromJson(Map<String, dynamic> json) {
    final active = json['activeAuction'];
    final result = json['lastAuctionResult'];
    final queue = _parseQueue(json);
    return AuctionRoomSnapshot(
      stream: StreamSnapshot.fromJson(
        json['stream'] is Map<String, dynamic>
            ? json['stream'] as Map<String, dynamic>
            : const {},
      ),
      activeAuction: active is Map<String, dynamic>
          ? ActiveAuction.fromJson(active)
          : null,
      productQueue: queue ?? const [],
      hasProductQueue: queue != null,
      mutedUserIds:
          (json['mutedUserIds'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      lastAuctionResult: result is Map<String, dynamic>
          ? LastAuctionResult.fromJson(result)
          : null,
      snapshotVersion: _int(json['snapshotVersion']) ?? 0,
      generatedAt: json['generatedAt'] as String?,
      auctionId: json['auctionId'] as String?,
      serverTimestamp: json['serverTimestamp'] as String?,
      realtime: json['realtime'] is Map<String, dynamic>
          ? RealtimeHints.fromJson(json['realtime'] as Map<String, dynamic>)
          : null,
      raw: json,
    );
  }
}

class StreamSnapshot {
  const StreamSnapshot({
    required this.id,
    this.sellerId,
    required this.status,
    this.title,
    this.thumbnailUrl,
    this.bidsPaused = false,
    this.chatDisabled = false,
    this.streamEndsAt,
    this.startedAt,
    this.scheduledStartTime,
    this.streamDurationMinutes,
    this.sellerAnnouncement,
    this.effectiveAnnouncement,
  });

  final String id;
  final String? sellerId;
  final String status; // LIVE | SCHEDULED | ENDED | CANCELLED
  final String? title;
  final String? thumbnailUrl;
  final bool bidsPaused;
  final bool chatDisabled;
  final String? streamEndsAt;

  /// The banner the seller set (what the announcement editor manages).
  final String? sellerAnnouncement;

  /// What buyers actually see — an admin announcement outranks the seller's,
  /// so this can differ from [sellerAnnouncement].
  final String? effectiveAnnouncement;

  /// When the stream actually went live (only the "real start" keys — never the
  /// scheduled time, which would make [endsAt] fire early for a late start).
  final String? startedAt;

  /// When a SCHEDULED stream is planned to start. Kept apart from [startedAt]
  /// for that reason — this one is a plan, not a fact.
  final String? scheduledStartTime;

  /// [scheduledStartTime] parsed, or null when the stream isn't scheduled.
  DateTime? get scheduledStartAt {
    final iso = scheduledStartTime;
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }

  final int? streamDurationMinutes;

  bool get isLive => status == 'LIVE';
  bool get isScheduled => status == 'SCHEDULED';
  bool get isTerminal => status == 'ENDED' || status == 'CANCELLED';

  /// The moment the stream auto-ends. Prefers the server's `streamEndsAt`, and
  /// falls back to went-live + duration for payloads that only carry those, so
  /// the room's countdown / "extend" warning still works.
  DateTime? get endsAt {
    final iso = streamEndsAt;
    if (iso != null && iso.isNotEmpty) {
      final parsed = DateTime.tryParse(iso);
      if (parsed != null) return parsed;
    }
    final start = startedAt;
    final mins = streamDurationMinutes;
    if (start == null || start.isEmpty || mins == null || mins <= 0) return null;
    return DateTime.tryParse(start)?.add(Duration(minutes: mins));
  }

  StreamSnapshot copyWith({String? status, bool? bidsPaused, bool? chatDisabled}) =>
      StreamSnapshot(
        id: id,
        sellerId: sellerId,
        status: status ?? this.status,
        title: title,
        thumbnailUrl: thumbnailUrl,
        bidsPaused: bidsPaused ?? this.bidsPaused,
        chatDisabled: chatDisabled ?? this.chatDisabled,
        streamEndsAt: streamEndsAt,
        scheduledStartTime: scheduledStartTime,
        startedAt: startedAt,
        streamDurationMinutes: streamDurationMinutes,
        sellerAnnouncement: sellerAnnouncement,
        effectiveAnnouncement: effectiveAnnouncement,
      );

  factory StreamSnapshot.fromJson(Map<String, dynamic> json) => StreamSnapshot(
        id: (json['id'] ?? '') as String,
        sellerId: json['sellerId'] as String?,
        status: (json['status'] ?? '') as String,
        title: json['title'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        bidsPaused: json['bidsPaused'] as bool? ?? false,
        chatDisabled: json['chatDisabled'] as bool? ?? false,
        streamEndsAt: json['streamEndsAt'] as String?,
        scheduledStartTime: (json['scheduledStartTime'] ??
            json['scheduledStartAt'] ??
            json['scheduledAt']) as String?,
        startedAt: (json['startedAt'] ??
            json['actualStartTime'] ??
            json['liveStartedAt'] ??
            json['wentLiveAt']) as String?,
        streamDurationMinutes: _int(json['streamDurationMinutes']),
        sellerAnnouncement: _announcementText(json['sellerAnnouncement']),
        effectiveAnnouncement: _announcementText(json['effectiveAnnouncement']),
      );

  /// An announcement arrives either as a plain string or as an object like
  /// `{ "source": "admin", "message": "…" }` — normalise both to the text, and
  /// treat a blank one as "no announcement".
  static String? _announcementText(dynamic value) {
    final text = value is String
        ? value
        : (value is Map ? value['message'] ?? value['content'] : null);
    if (text is! String || text.trim().isEmpty) return null;
    return text;
  }
}

class AuctionProduct {
  const AuctionProduct({
    required this.productId,
    required this.title,
    this.price,
    this.startingPrice,
    this.dutchPrice,
    this.originalPrice,
    this.auctionType = 'NORMAL',
    this.bidIncrement,
    this.shippingPriceNok,
    this.image,
  });

  final String productId;
  final String title;
  final num? price;
  final num? startingPrice;

  /// Dutch auction opening price ("Dutch pris").
  final num? dutchPrice;

  /// Product's original / retail price ("Originalpris").
  final num? originalPrice;

  final String auctionType; // NORMAL | DUTCH
  final num? bidIncrement;
  final num? shippingPriceNok;
  final String? image;

  bool get isDutch => auctionType == 'DUTCH';

  factory AuctionProduct.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    final productMap =
        product is Map<String, dynamic> ? product : const <String, dynamic>{};
    // The queue item shape is loosely specified and the price for a field may
    // live under a few different keys (or nested under `product`), so probe a
    // small set of candidates defensively.
    num? pick(List<String> keys) {
      for (final k in keys) {
        final v = _num(json[k]) ?? _num(productMap[k]);
        if (v != null) return v;
      }
      return null;
    }

    return AuctionProduct(
      productId: (json['productId'] ?? productMap['id'] ?? '') as String,
      title: (json['title'] ?? json['name'] ?? productMap['title'] ??
              productMap['name'] ?? '') as String,
      price: _num(json['price']),
      startingPrice: pick(['startingPrice', 'startPrice', 'startingPriceNok']),
      dutchPrice: pick(
          ['dutchPrice', 'dutchStartingPrice', 'dutchStartPrice', 'dutch_price']),
      originalPrice: pick([
        'originalPrice',
        'original_price',
        'retailPrice',
        'compareAtPrice',
        'msrp',
      ]),
      auctionType: (json['auctionType'] ?? 'NORMAL') as String,
      bidIncrement: _num(json['bidIncrement']),
      shippingPriceNok: _num(json['shippingPriceNok']),
      image: (json['image'] ?? productMap['thumbnailUrl'] ?? productMap['image'])
          as String?,
    );
  }
}

/// The running lot. The guide leaves the exact shape open, so we pull the
/// commonly-present fields and keep [raw] for anything else.
class ActiveAuction {
  const ActiveAuction({
    this.id,
    this.productId,
    this.title,
    this.image,
    this.auctionType = 'NORMAL',
    this.startedAt,
    this.endsAt,
    this.startingPrice,
    this.currentPrice,
    this.highestBid,
    this.bidCount = 0,
    this.winnerName,
    required this.raw,
  });

  final String? id;
  final String? productId;
  final String? title;
  final String? image;
  final String auctionType;
  final String? startedAt;
  final String? endsAt;
  final num? startingPrice;
  final num? currentPrice;
  final num? highestBid;
  final int bidCount;
  final String? winnerName;
  final Map<String, dynamic> raw;

  bool get isDutch => auctionType == 'DUTCH';

  /// Best-effort "current price to beat / offer" for the header.
  num? get displayPrice => highestBid ?? currentPrice ?? startingPrice;

  /// Fills only the given fields, keeping everything else. Used to enrich a
  /// sparse start-mutation echo (which often omits the product name / price)
  /// from the queue head, so the running-auction card shows details instantly.
  ActiveAuction copyWith({
    String? title,
    String? image,
    num? startingPrice,
    num? currentPrice,
  }) =>
      ActiveAuction(
        id: id,
        productId: productId,
        title: title ?? this.title,
        image: image ?? this.image,
        auctionType: auctionType,
        startedAt: startedAt,
        endsAt: endsAt,
        startingPrice: startingPrice ?? this.startingPrice,
        currentPrice: currentPrice ?? this.currentPrice,
        highestBid: highestBid,
        bidCount: bidCount,
        winnerName: winnerName,
        raw: raw,
      );

  factory ActiveAuction.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    final productMap =
        product is Map<String, dynamic> ? product : const <String, dynamic>{};
    final highest = json['highestBid'];
    final highestMap =
        highest is Map<String, dynamic> ? highest : const <String, dynamic>{};
    final winner = json['winner'];
    final winnerMap =
        winner is Map<String, dynamic> ? winner : const <String, dynamic>{};

    return ActiveAuction(
      id: (json['id'] ?? json['auctionId']) as String?,
      productId: (json['productId'] ?? productMap['id']) as String?,
      title: (json['title'] ?? productMap['title'] ?? productMap['name'])
          as String?,
      image: (json['image'] ?? productMap['image'] ?? productMap['thumbnailUrl'])
          as String?,
      auctionType: (json['auctionType'] ?? 'NORMAL') as String,
      startedAt: json['startedAt'] as String?,
      endsAt: (json['endsAt'] ?? json['endTime']) as String?,
      startingPrice: _num(json['startingPrice']),
      currentPrice: _num(json['currentPrice'] ?? json['dutchCurrentPrice']),
      highestBid:
          _num(json['highestBid'] is num ? json['highestBid'] : highestMap['amount']),
      bidCount: _int(json['bidCount']) ?? 0,
      winnerName:
          (json['winnerName'] ?? winnerMap['displayName'] ?? winnerMap['name'])
              as String?,
      raw: json,
    );
  }

  DateTime? get endsAtUtc =>
      endsAt == null ? null : DateTime.tryParse(endsAt!)?.toUtc();

  DateTime? get startedAtUtc =>
      startedAt == null ? null : DateTime.tryParse(startedAt!)?.toUtc();

  /// The lot's full length as the server scheduled it — the declared
  /// `durationSec` when the payload carries one, otherwise `endsAt - startedAt`.
  /// Both are server-side values, so this is free of device clock skew and can
  /// be used to cap the countdown (a 30 s auction must never read 31 s).
  /// Null when the payload gives us neither.
  int? get totalDurationSec {
    final declared = _int(raw['durationSec'] ?? raw['durationSeconds']);
    if (declared != null && declared > 0) return declared;

    final start = startedAtUtc;
    final end = endsAtUtc;
    if (start == null || end == null) return null;
    final ms = end.difference(start).inMilliseconds;
    return ms <= 0 ? null : (ms / 1000).round();
  }
}

class LastAuctionResult {
  const LastAuctionResult({
    this.productTitle,
    this.winnerName,
    this.finalPrice,
    this.hadWinner = false,
    required this.raw,
  });

  final String? productTitle;
  final String? winnerName;
  final num? finalPrice;
  final bool hadWinner;
  final Map<String, dynamic> raw;

  factory LastAuctionResult.fromJson(Map<String, dynamic> json) {
    final winner = json['winner'];
    final winnerMap =
        winner is Map<String, dynamic> ? winner : const <String, dynamic>{};
    final product = json['product'];
    final productMap =
        product is Map<String, dynamic> ? product : const <String, dynamic>{};
    final winnerName =
        (json['winnerName'] ?? winnerMap['displayName'] ?? winnerMap['name'])
            as String?;
    return LastAuctionResult(
      productTitle:
          (json['productTitle'] ?? json['title'] ?? productMap['title']) as String?,
      winnerName: winnerName,
      finalPrice: _num(json['finalPrice'] ?? json['soldPrice'] ?? json['price']),
      hadWinner: json['hadWinner'] as bool? ?? (winnerName != null),
      raw: json,
    );
  }
}

class RealtimeHints {
  const RealtimeHints({
    this.wsPath,
    this.wsStreamId,
    this.accessTokenQueryParam = 'access_token',
    this.rtcChannelName,
    this.rtmChannelName,
  });

  final String? wsPath;
  final String? wsStreamId;
  final String accessTokenQueryParam;
  final String? rtcChannelName;
  final String? rtmChannelName;

  factory RealtimeHints.fromJson(Map<String, dynamic> json) {
    final ws = json['websocket'];
    final wsMap = ws is Map<String, dynamic> ? ws : const <String, dynamic>{};
    final agora = json['agora'];
    final agoraMap =
        agora is Map<String, dynamic> ? agora : const <String, dynamic>{};
    return RealtimeHints(
      wsPath: wsMap['path'] as String?,
      wsStreamId: wsMap['streamId'] as String?,
      accessTokenQueryParam:
          (wsMap['accessTokenQueryParam'] ?? 'access_token') as String,
      rtcChannelName: agoraMap['rtcChannelName'] as String?,
      rtmChannelName: agoraMap['rtmChannelName'] as String?,
    );
  }
}
