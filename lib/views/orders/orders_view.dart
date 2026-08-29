import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/seller_orders_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/branded_loading_view.dart';
import '../../core/widgets/branded_refresh_indicator.dart';
import '../../core/widgets/custom_text.dart';
import '../../models/seller_order.dart';
import 'order_common.dart';
import 'order_detail_view.dart';
import '../../core/localization/translation_keys.dart';

/// All of the seller's orders — `GET /api/v1/seller/orders?limit=20` — with a
/// search box, payment / freight status filters and cursor pagination.
///
/// Reached from the Home tab's quick actions and from the bottom of a product's
/// details page.
class OrdersView extends StatefulWidget {
  const OrdersView({super.key});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  final SellerOrdersController ctrl = getOrPut(() => SellerOrdersController());
  late final TextEditingController _searchCtrl =
      TextEditingController(text: ctrl.query);

  @override
  void initState() {
    super.initState();
    // onInit only fires the first time the controller is created; a second
    // visit re-reads so the list isn't stale.
    if (ctrl.orders.isNotEmpty) ctrl.fetchOrders(refresh: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.white,
        toolbarHeight: 68,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: AppColors.brandNavy,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        // The icon + title + subtitle block sits next to the back arrow, so the
        // screen isn't titled "Orders" twice.
        title: const _Header(),
      ),
      body: Column(
        children: [
          _FilterBar(ctrl: ctrl, searchCtrl: _searchCtrl),
          Expanded(
            child: Obx(() {
              if (ctrl.isLoading && ctrl.orders.isEmpty) {
                return const BrandedLoadingView();
              }

              if (ctrl.error != null && ctrl.orders.isEmpty) {
                return _ErrorState(
                  message: ctrl.error ?? '',
                  onRetry: () => ctrl.fetchOrders(refresh: true),
                );
              }

              // Already filtered server-side by the active status filters and
              // order-number search.
              final orders = ctrl.orders;

              if (orders.isEmpty) {
                return BrandedRefreshIndicator(
                  onRefresh: () => ctrl.fetchOrders(refresh: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                      _EmptyState(
                        filtered: ctrl.hasActiveFilters,
                        onClear: () {
                          _searchCtrl.clear();
                          ctrl.clearFilters();
                        },
                      ),
                    ],
                  ),
                );
              }

              return BrandedRefreshIndicator(
                onRefresh: () => ctrl.fetchOrders(refresh: true),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 24),
                  itemCount: orders.length + (ctrl.hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    if (i >= orders.length) return _LoadMoreButton(ctrl: ctrl);
                    return _OrderCard(order: orders[i]);
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// The screen's identity — icon tile, title and one-line summary. Rendered as
/// the [AppBar] title, right after the back arrow.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.brandYellow.withOpacity(0.3),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 19,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  TKeys.ordersLabel.tr,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 1),
                CustomText(
                  TKeys.ordAllOrdersSub.tr,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Search box + the two status dropdowns, in a card like the web table's
/// toolbar.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.ctrl, required this.searchCtrl});

  final SellerOrdersController ctrl;
  final TextEditingController searchCtrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orderBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: searchCtrl,
            onChanged: ctrl.setQuery,
            textInputAction: TextInputAction.search,
            // The API matches on `orderNumber`, so anything but digits would
            // only ever come back empty.
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: TKeys.ordSearchHint.tr,
              hintStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 20,
                color: AppColors.textMuted,
              ),
              suffixIcon: Obx(
                () => ctrl.query.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () {
                          searchCtrl.clear();
                          ctrl.setQuery('');
                          FocusScope.of(context).unfocus();
                        },
                      ),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide:
                    const BorderSide(color: orderBorder, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide:
                    const BorderSide(color: orderBorder, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide:
                    const BorderSide(color: AppColors.brandNavy, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 6),
              CustomText(
                TKeys.ordFilterBy.tr,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Obx(
                  () => _StatusDropdown(
                    value: ctrl.paymentFilter,
                    allLabel: TKeys.ordAllPaymentStatuses.tr,
                    options: SellerOrdersController.paymentOptions,
                    onChanged: ctrl.setPaymentFilter,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Obx(
                  () => _StatusDropdown(
                    value: ctrl.shippingFilter,
                    allLabel: TKeys.ordAllShippingStatuses.tr,
                    options: SellerOrdersController.shippingOptions,
                    onChanged: ctrl.setShippingFilter,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One of the two filter menus. Picking an entry sends its value straight to
/// the API as `paymentStatus` / `shippingStatus`; the "all" entry drops the
/// param instead.
///
/// No counts next to the entries: the server only returns the selected
/// status's rows, so the others' totals aren't known.
class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({
    required this.value,
    required this.allLabel,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final String allLabel;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == SellerOrdersController.anyStatus;
    return PopupMenuButton<String>(
      onSelected: onChanged,
      color: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => options
          .map(
            (option) => PopupMenuItem<String>(
              value: option,
              child: Row(
                children: [
                  Expanded(
                    child: CustomText(
                      option == SellerOrdersController.anyStatus
                          ? allLabel
                          : statusLabel(option),
                      fontSize: 13.5,
                      fontWeight: option == value
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (option == value) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.check_rounded,
                        size: 16, color: AppColors.brandNavy),
                  ],
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.white : AppColors.brandYellow.withOpacity(0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: orderBorder, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: CustomText(
                selected ? allLabel : statusLabel(value),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// One order row: number + total on top, buyer and product under it, then the
/// payment / freight pills and the "Show details" action.
class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final SellerOrder order;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderDetailView(orderId: order.id, initial: order),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: orderBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandNavy.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  '#${order.orderNumber}',
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryBlue,
                ),
                const Spacer(),
                CustomText(
                  formatAmount(order.amount),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 5),
                Expanded(
                  child: CustomText(
                    order.buyerName,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.shopping_bag_outlined,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 5),
                Expanded(
                  child: CustomText(
                    order.productName,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(child: PaymentBadge(status: order.paymentStatus)),
                const SizedBox(width: 6),
                Flexible(child: FreightBadge(status: order.shippingStatus)),
                const Spacer(),
                const Icon(Icons.visibility_outlined,
                    size: 16, color: AppColors.brandNavy),
                const SizedBox(width: 5),
                CustomText(
                  TKeys.ordShowDetails.tr,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.ctrl});
  final SellerOrdersController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: ctrl.isLoadingMore
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
                  ),
                )
              : GestureDetector(
                  onTap: ctrl.loadMore,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: orderBorder, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.expand_more_rounded,
                            size: 18, color: AppColors.brandNavy),
                        const SizedBox(width: 6),
                        CustomText(
                          TKeys.loadMore.tr,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, required this.onClear});
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.brandYellow.withOpacity(0.3),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  size: 32, color: AppColors.brandNavy),
            ),
            const SizedBox(height: 16),
            CustomText(
              filtered ? TKeys.ordNoMatchingOrders.tr : TKeys.ordNoOrdersYet.tr,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 6),
            CustomText(
              filtered
                  ? TKeys.ordNothingMatches.tr
                  : TKeys.ordWillShowHere.tr,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
              textAlign: TextAlign.center,
              color: AppColors.textSecondary,
            ),
            if (filtered) ...[
              const SizedBox(height: 18),
              GestureDetector(
                onTap: onClear,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.brandNavy,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CustomText(
                    TKeys.clearFilters.tr,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.vipps.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  size: 28, color: AppColors.vipps),
            ),
            const SizedBox(height: 16),
            CustomText(
              TKeys.ordCouldNotLoad.tr,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 6),
            CustomText(
              message,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              textAlign: TextAlign.center,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.brandNavy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CustomText(
                  TKeys.tryAgain.tr,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
