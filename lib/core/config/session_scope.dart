import 'package:get/get.dart';

import '../../controllers/dashboard_controller.dart';
import '../../controllers/inventory_controller.dart';
import '../../controllers/notification_controller.dart';
import '../../controllers/products_nav_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../controllers/seller_application_controller.dart';
import '../../controllers/seller_orders_controller.dart';
import '../../controllers/seller_products_controller.dart';
import '../../controllers/stock_nav_controller.dart';
import '../../controllers/stream_controller.dart';

/// Drops every controller whose contents belong to one signed-in seller.
///
/// The home shell builds these through `getOrPut`, which hands back whatever
/// is already in GetX's registry. Nothing ever un-registers them, so without
/// this a second seller signing in on the same handset gets the *previous*
/// account's instances — their name, dashboard totals, streams, stock and
/// orders — and keeps seeing them until each screen happens to be
/// pull-to-refreshed. Clearing the registry instead means the next `getOrPut`
/// constructs fresh controllers, whose `onInit` fetches for the account that
/// is actually signed in, and whose screens show a loading state meanwhile
/// rather than stale rows.
///
/// Deliberately not touched:
/// * [AuthController] — owns the session this runs inside of, and holds no
///   per-account payload beyond the two fields `logout()` already clears.
/// * `LanguageViewModel` — a device preference, not account data.
/// * `SkuDetailController` — created per SKU with a tag and deleted by the
///   view that created it.
void resetSessionControllers() {
  // `force` because NotificationController is registered as permanent: the
  // bell badge has to outlive tab switches, but not the session.
  Get.delete<NotificationController>(force: true);

  Get.delete<ProfileController>(force: true);
  Get.delete<DashboardController>(force: true);
  Get.delete<StreamListController>(force: true);
  Get.delete<InventoryController>(force: true);
  Get.delete<SellerOrdersController>(force: true);
  Get.delete<SellerProductsController>(force: true);
  Get.delete<SellerApplicationController>(force: true);

  // Tab/segment selections — not account data, but leaving the next seller on
  // the previous one's deep-linked segment is just as confusing.
  Get.delete<ProductsNavController>(force: true);
  Get.delete<StockNavController>(force: true);
}
