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

/// Non-blank string, else null.
String? _text(dynamic v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

List<String> _strings(dynamic v) => v is List
    ? v.map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).toList()
    : const [];

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

  /// [clearActiveAuction] drops the running lot — `activeAuction: null`
  /// alone means "keep it", like every other field here.
  AuctionRoomSnapshot copyWith({
    StreamSnapshot? stream,
    ActiveAuction? activeAuction,
    bool clearActiveAuction = false,
  }) =>
      AuctionRoomSnapshot(
        stream: stream ?? this.stream,
        activeAuction: clearActiveAuction
            ? null
            : (activeAuction ?? this.activeAuction),
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
    final parsedActive =
        active is Map<String, dynamic> ? ActiveAuction.fromJson(active) : null;
    return AuctionRoomSnapshot(
      stream: StreamSnapshot.fromJson(
        json['stream'] is Map<String, dynamic>
            ? json['stream'] as Map<String, dynamic>
            : const {},
      ),
      // A lot the server has already closed (it can still ride the snapshot
      // as `ENDED` while settlement runs) is not a running lot: showing it
      // left the seller staring at a 0 s clock and a live End button.
      activeAuction:
          parsedActive != null && parsedActive.isFinished ? null : parsedActive,
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
    this.description,
    this.thumbnailUrl,
    this.bidsPaused = false,
    this.chatDisabled = false,
    this.streamEndsAt,
    this.startedAt,
    this.scheduledStartTime,
    this.streamDurationMinutes,
    this.sellerAnnouncement,
    this.effectiveAnnouncement,
    this.viewerCount,
  });

  final String id;
  final String? sellerId;
  final String status; // LIVE | SCHEDULED | ENDED | CANCELLED
  final String? title;

  /// The seller's own text about the stream — what buyers open as "Show Notes".
  final String? description;

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

  /// Buyers watching right now, when the frame carries a count. Null means
  /// "not reported on this frame" — not zero — so the room keeps its last
  /// known figure instead of flashing to 0 on a lightweight frame.
  final int? viewerCount;

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
        description: description,
        thumbnailUrl: thumbnailUrl,
        bidsPaused: bidsPaused ?? this.bidsPaused,
        chatDisabled: chatDisabled ?? this.chatDisabled,
        streamEndsAt: streamEndsAt,
        scheduledStartTime: scheduledStartTime,
        startedAt: startedAt,
        streamDurationMinutes: streamDurationMinutes,
        sellerAnnouncement: sellerAnnouncement,
        effectiveAnnouncement: effectiveAnnouncement,
        viewerCount: viewerCount,
      );

  factory StreamSnapshot.fromJson(Map<String, dynamic> json) => StreamSnapshot(
        id: (json['id'] ?? '') as String,
        sellerId: json['sellerId'] as String?,
        status: (json['status'] ?? '') as String,
        title: json['title'] as String?,
        description: json['description'] as String?,
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
        viewerCount: readViewerCount(json),
      );

  /// A viewer count under any of the spellings the API uses for it (the
  /// buyer app reads the same set), or null when the map has none.
  static int? readViewerCount(Map<String, dynamic> json) {
    for (final key in const [
      'viewerCount',
      'currentViewerCount',
      'currentViewers',
      'viewers',
      'viewer_count',
    ]) {
      final raw = json[key];
      if (raw is num) return raw.toInt();
      if (raw is String) {
        final parsed = int.tryParse(raw);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

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
    this.images = const [],
    this.isRandom = false,
    this.stockCount,
    this.brand,
    this.category,
    this.subCategory,
    this.mainCategory,
    this.parentCategory,
    this.subItem,
    this.sizesAvailable = const [],
    this.description,
    this.bottomPrice,
    this.remainingDefectQuantity = 0,
    this.defectDescription,
    this.upc,
  });

  final String productId;
  final String title;
  final num? price;
  final num? startingPrice;

  /// Dutch auction opening price ("Dutch pris").
  final num? dutchPrice;

  /// Recommended retail price ("Veil. pris", `veilPris` on the wire).
  final num? originalPrice;

  final String auctionType; // NORMAL | DUTCH
  final num? bidIncrement;
  final num? shippingPriceNok;
  final String? image;

  /// Every image of the product (absolute URLs), for the quick view gallery.
  final List<String> images;

  final bool isRandom;

  /// Shared sellable stock (managed products), or the random lot's stock.
  final int? stockCount;

  final String? brand;
  final String? category;
  final String? subCategory;

  /// From `taxonomyPathSnapshot` — e.g. "Menn" › "Yttertøy" › "Briefs".
  final String? parentCategory;
  final String? mainCategory;
  final String? subItem;

  final List<String> sizesAvailable;
  final String? description;
  final num? bottomPrice;

  /// Units of this product sold as defective, with the seller's note.
  final int remainingDefectQuantity;
  final String? defectDescription;

  /// Barcode. The snapshot doesn't always carry it; the queue catalog does.
  final String? upc;

  bool get isDutch => auctionType == 'DUTCH';

  /// [images] when present, otherwise the single [image].
  List<String> get gallery {
    final all = images.where((e) => e.startsWith('http')).toSet().toList();
    if (all.isEmpty && image != null && image!.startsWith('http')) {
      return [image!];
    }
    return all;
  }

  factory AuctionProduct.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    final productMap =
        product is Map<String, dynamic> ? product : const <String, dynamic>{};
    // The queue item shape is loosely specified and the price for a field may
    // live under a few different keys (or nested under `product`), so probe a
    // small set of candidates defensively.
    final rawTaxonomy =
        json['taxonomyPathSnapshot'] ?? json['taxonomy_path_snapshot'];
    final taxonomy = rawTaxonomy is Map ? rawTaxonomy : const {};
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
        'veilPris',
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
      images: _strings(json['images'] ?? productMap['images']),
      isRandom: json['isRandom'] == true,
      stockCount: _int(json['isRandom'] == true
          ? (json['randomStock'] ?? json['stockCount'])
          : json['stockCount']),
      brand: _text(json['brand'] ?? productMap['brand']),
      category: _text(json['category']),
      subCategory: _text(json['subCategory'] ?? json['sub_category']),
      parentCategory: _text(taxonomy['parent_category']),
      mainCategory: _text(taxonomy['main_category']),
      subItem: _text(taxonomy['sub_item']),
      sizesAvailable: _strings(json['sizesAvailable']),
      description: _text(json['description'] ?? productMap['description']),
      bottomPrice: _num(json['bottomPrice']),
      remainingDefectQuantity: _int(json['remainingDefectQuantity']) ?? 0,
      defectDescription: _text(json['defectDescription']),
      upc: _text(json['upc'] ?? json['gtin'] ?? productMap['upc']),
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
    this.status,
    this.startedAt,
    this.endsAt,
    this.startingPrice,
    this.currentPrice,
    this.highestBid,
    this.bidCount = 0,
    this.shippingPriceNok,
    this.winnerName,
    required this.raw,
  });

  final String? id;
  final String? productId;
  final String? title;
  final String? image;
  final String auctionType;

  /// Server lifecycle status, upper-cased (`ACTIVE`, `ENDED`, …). Null when
  /// the payload doesn't say, which reads as running.
  final String? status;
  final String? startedAt;
  final String? endsAt;
  final num? startingPrice;
  final num? currentPrice;
  final num? highestBid;
  final int bidCount;

  /// What the buyer pays on top of the winning bid, as the seller set it when
  /// the lot was started. Raw: zero (and anything negative) means "not
  /// configured" on this backend rather than "free" — [shippingPrice] is the
  /// one to read.
  final num? shippingPriceNok;

  final String? winnerName;
  final Map<String, dynamic> raw;

  bool get isDutch => auctionType == 'DUTCH';

  static const _finishedStatuses = {
    'ENDED',
    'SOLD',
    'UNSOLD',
    'SETTLED',
    'SETTLING',
    'COMPLETED',
    'CLOSED',
    'CANCELLED',
    'CANCELED',
    'EXPIRED',
    'PASSED',
  };

  /// True once the server has closed this lot.
  bool get isFinished => status != null && _finishedStatuses.contains(status);

  /// Every id the payload names this lot by. The room snapshot has shipped it
  /// as `auctionId`, `id` and `productAuctionId`, while WS events always say
  /// `auctionId` — matching on one key alone dropped every bid whenever the
  /// two disagreed.
  ///
  /// The product id is never one of them: the same (random) product can run
  /// again as the next lot, and must not be mistaken for the one that ended.
  Set<String> get knownIds => {
        if (id != null) id!,
        for (final k in const ['auctionId', 'id', 'productAuctionId'])
          if (raw[k] is String && (raw[k] as String).isNotEmpty)
            raw[k] as String,
      }..remove(productId);

  /// Whether an event naming [otherId] is about this lot. An event (or a lot)
  /// that names no id at all is taken as being about the running one.
  bool isSameLot(String? otherId) {
    if (otherId == null) return true;
    final ids = knownIds;
    return ids.isEmpty || ids.contains(otherId);
  }

  /// The shipping figure worth showing, or null when there is none.
  num? get shippingPrice {
    final raw = shippingPriceNok;
    return raw != null && raw > 0 ? raw : null;
  }

  /// Best-effort "current price to beat / offer" for the header.
  ///
  /// A non-positive figure counts as absent, not as a price. A lot that has
  /// just started comes back with `highestBid: 0` (and, on this backend, often
  /// `currentPrice: 0` with it) because nobody has bid yet — taking that at
  /// face value rendered a brand-new lot as "kr 0" until the first bid landed.
  /// Falling through to [startingPrice] shows the figure the seller actually
  /// set. Dutch lots are unaffected: their descending `currentPrice` is always
  /// positive.
  num? get displayPrice {
    final highest = highestBid;
    if (highest != null && highest > 0) return highest;
    final current = currentPrice;
    if (current != null && current > 0) return current;
    return startingPrice;
  }

  /// Fills only the given fields, keeping everything else. Used to enrich a
  /// sparse start-mutation echo (which often omits the product name / price)
  /// from the queue head, so the running-auction card shows details instantly
  /// — and to post a bid read straight off a WS event, without waiting for the
  /// next full snapshot to carry it.
  ActiveAuction copyWith({
    String? title,
    String? image,
    num? startingPrice,
    num? currentPrice,
    num? highestBid,
    int? bidCount,
    num? shippingPriceNok,
    String? winnerName,
    String? endsAt,
  }) =>
      ActiveAuction(
        id: id,
        productId: productId,
        title: title ?? this.title,
        image: image ?? this.image,
        auctionType: auctionType,
        status: status,
        startedAt: startedAt,
        endsAt: endsAt ?? this.endsAt,
        startingPrice: startingPrice ?? this.startingPrice,
        currentPrice: currentPrice ?? this.currentPrice,
        highestBid: highestBid ?? this.highestBid,
        bidCount: bidCount ?? this.bidCount,
        shippingPriceNok: shippingPriceNok ?? this.shippingPriceNok,
        winnerName: winnerName ?? this.winnerName,
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
      // `auctionId` first: it is the key every WS event (`BID_PLACED`,
      // `AUCTION_ENDED`) names the lot by, so it is what bids are matched on.
      id: (json['auctionId'] ?? json['id']) as String?,
      productId: (json['productId'] ?? productMap['id']) as String?,
      title: (json['title'] ?? productMap['title'] ?? productMap['name'])
          as String?,
      image: (json['image'] ?? productMap['image'] ?? productMap['thumbnailUrl'])
          as String?,
      auctionType: (json['auctionType'] ?? 'NORMAL') as String,
      status: (json['status'] as String?)?.toUpperCase(),
      startedAt: json['startedAt'] as String?,
      endsAt: (json['endsAt'] ?? json['endTime']) as String?,
      startingPrice: _num(json['startingPrice']),
      currentPrice: _num(json['currentPrice'] ?? json['dutchCurrentPrice']),
      highestBid:
          _num(json['highestBid'] is num ? json['highestBid'] : highestMap['amount']),
      bidCount: _int(json['bidCount']) ?? 0,
      shippingPriceNok: _num(json['shippingPriceNok'] ??
          json['shippingPrice'] ??
          json['shipping']),
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

    final start = startedAtUtc;
    final end = endsAtUtc;
    final ms = start == null || end == null
        ? 0
        : end.difference(start).inMilliseconds;
    final scheduled = ms <= 0 ? null : (ms / 1000).round();

    // A late bid extends `endsAt` (anti-snipe), so the declared duration can
    // be shorter than the lot now runs. Capping the countdown at it would hide
    // the extension.
    if (declared != null && declared > 0) {
      return scheduled != null && scheduled > declared ? scheduled : declared;
    }
    return scheduled;
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
