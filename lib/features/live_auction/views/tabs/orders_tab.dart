import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../../../models/seller_order.dart';
import '../../../../views/orders/order_detail_view.dart';
import '../../controllers/auction_room_controller.dart';
import '../../data/models/stream_order.dart';
import '../../../../core/localization/translation_keys.dart';

/// The Orders tab: who won each lot in this stream and for how much.
/// Backed by `GET /api/v1/seller/streams/:id/orders` (loaded on open, with a
/// pull-to-refresh + manual refresh).
class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key, required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: CustomText(TKeys.otWinningOrders.tr, fontSize: 15,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              Obx(() => ctrl.loadingOrders.value
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation(AppColors.brandNavy)),
                    )
                  : IconButton(
                      onPressed: ctrl.loadOrders,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.refresh_rounded,
                          size: 20, color: AppColors.textSecondary),
                    )),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
            final orders = ctrl.orders;
            if (orders.isEmpty) {
              return RefreshIndicator(
                color: AppColors.brandNavy,
                onRefresh: ctrl.loadOrders,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                    Obx(() => ctrl.loadingOrders.value
                        ? const SizedBox.shrink()
                        : const _EmptyOrders()),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              color: AppColors.brandNavy,
              onRefresh: ctrl.loadOrders,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _OrderRow(order: orders[i]),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});
  final StreamOrder order;

  /// The stream `/orders` payload is loosely specified, so an order can come
  /// back without an id — nothing to fetch the detail with, so that row stays
  /// flat rather than opening a screen that can only fail.
  String? get _orderId {
    final id = order.id;
    return (id == null || id.isEmpty) ? null : id;
  }

  /// The row we already have, mapped onto the shape [OrderDetailView] takes so
  /// its header is right from the first frame while the full read is in flight.
  /// Fields this list doesn't carry (the product/shipping split, freight state)
  /// are left unset — the detail response fills them in.
  SellerOrder _asSellerOrder(String id) => SellerOrder(
        id: id,
        orderNumber: order.orderNumber ?? id,
        buyerName: order.buyerName ?? '—',
        buyerEmail: order.buyerEmail ?? '',
        productName: order.productTitle ?? '—',
        amount: order.amount,
        shippingAmount: null,
        productAmount: null,
        paymentStatus: order.status?.toUpperCase() ?? 'UNKNOWN',
        shippingStatus: 'UNKNOWN',
        createdAt: order.createdAt == null
            ? null
            : DateTime.tryParse(order.createdAt!),
      );

  void _open(BuildContext context) {
    final id = _orderId;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailView(orderId: id, initial: _asSellerOrder(id)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = order.image;
    final showImage = image != null && image.startsWith('http');
    final tappable = _orderId != null;
    final row = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 48, height: 48, color: AppColors.inputFill,
              child: showImage
                  ? Image.network(image, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_outlined, color: AppColors.textMuted))
                  : const Icon(Icons.shopping_bag_outlined,
                      color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (order.orderNumber != null)
                  CustomText(
                  TKeys.otOrderNumber
                      .trParams({'number': '${order.orderNumber}'}),
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.textMuted),
                CustomText(order.productTitle ?? TKeys.otLot.tr,
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded,
                        size: 13, color: Color(0xFFB8860B)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: CustomText(order.buyerName ?? TKeys.otWinner.tr,
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                if (order.buyerEmail != null && order.buyerEmail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  CustomText(order.buyerEmail!,
                      fontSize: 11, fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                if (order.status != null) ...[
                  const SizedBox(height: 5),
                  _StatusTag(status: order.status!),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          CustomText(_kr(order.amount), fontSize: 15,
              fontWeight: FontWeight.w800, color: AppColors.brandNavy),
          if (tappable) ...[
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textMuted),
          ],
        ],
      ),
    );
    if (!tappable) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: row,
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final s = status.toUpperCase();
    final paid = s.contains('PAID') || s.contains('COMPLETE') || s.contains('FULFIL');
    final pending = s.contains('PENDING') || s.contains('AWAIT');
    final c = paid
        ? const Color(0xFF2E7D32)
        : pending
            ? const Color(0xFFB8860B)
            : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomText(s, fontSize: 9.5,
          fontWeight: FontWeight.w800, color: c),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 12),
            CustomText(TKeys.otNoOrdersYet.tr, fontSize: 16,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            const SizedBox(height: 4),
            CustomText(TKeys.otOrdersAppearHere.tr,
                fontSize: 13, fontWeight: FontWeight.w500,
                textAlign: TextAlign.center, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

String _kr(num? v) => v == null ? '—' : 'kr ${v % 1 == 0 ? v.toInt() : v}';
