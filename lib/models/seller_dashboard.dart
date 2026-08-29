/// Payload of `GET /api/v1/seller/dashboard[?month=YYYY-MM]`.
///
/// Mirrors the seller web dashboard: a per-calendar-month snapshot of the
/// store (products, streams, orders, revenue) plus the commission rates the
/// admin has set. [availableMonths] is the list the month picker offers —
/// newest first, each entry a `YYYY-MM` key that can be sent straight back as
/// the `month` query param.
///
/// Months are calendar months; the API bounds them in UTC and the web app
/// displays them in Europe/Oslo, so the label is derived from the key itself
/// rather than from a local `DateTime`.
class SellerDashboard {
  const SellerDashboard({
    required this.yearMonth,
    required this.availableMonths,
    required this.sellerAccountType,
    required this.stats,
    required this.commission,
  });

  /// The month this payload covers, `YYYY-MM`.
  final String yearMonth;

  /// Selectable months, newest first — each a `YYYY-MM` key.
  final List<String> availableMonths;

  /// e.g. `managed` / `independent`.
  final String sellerAccountType;

  final DashboardStats stats;
  final DashboardCommission? commission;

  factory SellerDashboard.fromJson(Map<String, dynamic> json) {
    final months = (json['availableMonths'] as List?) ?? const [];
    return SellerDashboard(
      yearMonth: (json['yearMonth'] ?? '').toString(),
      availableMonths:
          months.map((m) => m.toString()).where((m) => m.isNotEmpty).toList(),
      sellerAccountType: (json['sellerAccountType'] ?? '').toString(),
      stats: DashboardStats.fromJson(
        (json['stats'] as Map<String, dynamic>?) ?? const {},
      ),
      commission: json['commission'] is Map
          ? DashboardCommission.fromJson(
              json['commission'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

/// The `stats` block — every counter the dashboard cards render.
class DashboardStats {
  const DashboardStats({
    required this.yearMonth,
    required this.totalProducts,
    required this.availableProducts,
    required this.soldProducts,
    required this.totalStreams,
    required this.liveStreams,
    required this.scheduledStreams,
    required this.totalOrders,
    required this.paidOrders,
    required this.revenue,
    required this.followers,
    required this.averageStreamDuration,
    required this.averageViewers,
  });

  final String yearMonth;
  final int totalProducts;
  final int availableProducts;
  final int soldProducts;
  final int totalStreams;
  final int liveStreams;
  final int scheduledStreams;
  final int totalOrders;
  final int paidOrders;

  /// Paid sales volume for the month, in NOK.
  final double revenue;
  final int followers;

  /// Mean stream length in minutes.
  final double averageStreamDuration;

  /// Mean concurrent viewers per stream.
  final double averageViewers;

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    // Tolerant readers: the API sends numbers, but a string wouldn't blank the
    // whole dashboard.
    num? num_(String key) {
      final v = json[key];
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }

    int int_(String key) => num_(key)?.toInt() ?? 0;
    double dbl_(String key) => num_(key)?.toDouble() ?? 0;

    return DashboardStats(
      yearMonth: (json['yearMonth'] ?? '').toString(),
      totalProducts: int_('totalProducts'),
      availableProducts: int_('availableProducts'),
      soldProducts: int_('soldProducts'),
      totalStreams: int_('totalStreams'),
      liveStreams: int_('liveStreams'),
      scheduledStreams: int_('scheduledStreams'),
      totalOrders: int_('totalOrders'),
      paidOrders: int_('paidOrders'),
      revenue: dbl_('revenue'),
      followers: int_('followers'),
      averageStreamDuration: dbl_('averageStreamDuration'),
      averageViewers: dbl_('averageViewers'),
    );
  }
}

/// Admin-set commission rates. [mode] is `dual` when both an auction and an
/// offer rate apply; other modes may leave one side null.
class DashboardCommission {
  const DashboardCommission({
    required this.mode,
    this.auctionCommissionPercentage,
    this.offerCommissionPercentage,
    this.auctionLabel,
    this.offerLabel,
  });

  final String mode;
  final num? auctionCommissionPercentage;
  final num? offerCommissionPercentage;
  final String? auctionLabel;
  final String? offerLabel;

  factory DashboardCommission.fromJson(Map<String, dynamic> json) {
    num? pct(String key) {
      final v = json[key];
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }

    String? label(String key) {
      final v = json[key];
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return DashboardCommission(
      mode: (json['mode'] ?? '').toString(),
      auctionCommissionPercentage: pct('auctionCommissionPercentage'),
      offerCommissionPercentage: pct('offerCommissionPercentage'),
      auctionLabel: label('auctionLabel'),
      offerLabel: label('offerLabel'),
    );
  }

  /// `2` → `2%`. Prefers the API's own label, falling back to the number.
  String? get auctionDisplay => _display(auctionLabel, auctionCommissionPercentage);
  String? get offerDisplay => _display(offerLabel, offerCommissionPercentage);

  static String? _display(String? label, num? value) {
    final raw = label ?? (value == null ? null : _trimZeros(value));
    if (raw == null) return null;
    return raw.endsWith('%') ? raw : '$raw%';
  }

  static String _trimZeros(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// `2026-08` → `Aug 2026`. Returns the key unchanged if it isn't a month key,
/// so an unexpected value still renders as something.
String formatYearMonth(String yearMonth) {
  final parts = yearMonth.split('-');
  if (parts.length < 2) return yearMonth;
  final year = parts[0];
  final month = int.tryParse(parts[1]);
  if (month == null || month < 1 || month > 12) return yearMonth;
  return '${_shortMonths[month - 1]} $year';
}

/// `2026-08` → `August 2026`, for the "in <month>" card subtitles.
String formatYearMonthLong(String yearMonth) {
  final parts = yearMonth.split('-');
  if (parts.length < 2) return yearMonth;
  final year = parts[0];
  final month = int.tryParse(parts[1]);
  if (month == null || month < 1 || month > 12) return yearMonth;
  return '${_longMonths[month - 1]} $year';
}

const _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _longMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
