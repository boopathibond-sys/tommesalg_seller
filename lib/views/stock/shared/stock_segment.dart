/// The Warehouse / Stock tab's top-level segments, shared between the segment
/// bar and the sections that need to switch between them (e.g. SKUs → Assign).
enum StockSegment { overview, skus, assign, search,
  // activity
}

extension StockSegmentLabel on StockSegment {
  String get label {
    switch (this) {
      case StockSegment.overview: return 'Overview';
      case StockSegment.skus:     return 'SKUs';
      case StockSegment.assign:   return 'Assign to SKU';
      case StockSegment.search:   return 'Search';
      // case StockSegment.activity: return 'Activity';
    }
  }
}
