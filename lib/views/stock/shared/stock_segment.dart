import '../../../core/localization/translation_keys.dart';
import 'package:get/get.dart';
/// The Warehouse / Stock tab's top-level segments, shared between the segment
/// bar and the sections that need to switch between them (e.g. SKUs → Assign).
enum StockSegment { overview, skus, assign, search,
  // activity
}

extension StockSegmentLabel on StockSegment {
  String get label {
    switch (this) {
      case StockSegment.overview: return TKeys.stOverview.tr;
      case StockSegment.skus:     return TKeys.stSkus.tr;
      case StockSegment.assign:   return TKeys.stAssignToSku.tr;
      case StockSegment.search:   return TKeys.stSearch.tr;
      // case StockSegment.activity: return 'Activity';
    }
  }
}
