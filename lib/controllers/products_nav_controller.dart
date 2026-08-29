import 'package:get/get.dart';

/// Cross-tab intent bus for the Products tab, mirroring `StockNavController`.
///
/// Lets other tabs (e.g. the Home "See products" quick action) ask
/// `ManageProductView` to switch to one of its segments — 0 "Assign to Live",
/// 1 "My Products". `ManageProductView` watches [requestedTab] and calls
/// [consume] once it has moved.
class ProductsNavController extends GetxController {
  /// Segment index the Products tab should show, or null when nothing is
  /// pending. Set by callers, consumed by `ManageProductView`.
  final RxnInt requestedTab = RxnInt();

  /// Index of the "My Products" segment inside `ManageProductView`.
  static const int myProductsTab = 1;

  /// Asks the Products tab to show the "My Products" segment.
  void goToMyProducts() => requestedTab.value = myProductsTab;

  /// Clears the pending request after `ManageProductView` has handled it.
  void consume() => requestedTab.value = null;
}
