import 'package:get/get.dart';

import '../views/stock/shared/stock_segment.dart';

/// Cross-tab intent bus for the Warehouse / Stock tab.
///
/// Lets other tabs (e.g. the Home quick actions) ask the Stock tab to switch to
/// a segment and optionally run an action once it's shown — currently used to
/// jump to the SKUs segment and open the New SKU sheet. `StockView` watches
/// [requestedSegment] and calls [consume] once it has handled the request.
class StockNavController extends GetxController {
  /// Segment the Stock tab should switch to, or null when nothing is pending.
  /// Set by callers, consumed (reset to null) by `StockView`.
  final Rxn<StockSegment> requestedSegment = Rxn<StockSegment>();

  /// When true, `StockView` opens the New SKU dialog after switching segment.
  final RxBool openCreateSku = false.obs;

  /// Requests the Stock tab to show the SKUs segment, optionally opening the
  /// New SKU dialog (when [create] is true).
  void goToSkus({bool create = false}) {
    openCreateSku.value = create;
    requestedSegment.value = StockSegment.skus;
  }

  /// Clears the pending request after `StockView` has handled it.
  void consume() {
    requestedSegment.value = null;
    openCreateSku.value = false;
  }
}
