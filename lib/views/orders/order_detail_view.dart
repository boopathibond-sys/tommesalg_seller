import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/seller_orders_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/branded_loading_view.dart';
import '../../core/widgets/branded_refresh_indicator.dart';
import '../../core/widgets/custom_text.dart';
import '../../models/seller_order.dart';
import '../../models/seller_order_detail.dart';
import 'order_common.dart';
import '../../core/localization/translation_keys.dart';

/// One order in full — `GET /api/v1/seller/orders/{orderId}`.
///
/// Sections mirror the web order page: summary, buyer information (contact +
/// shipping address), seller details, payment timeline, and the in-store pickup
/// banner when the order is collected rather than shipped.
///
/// [initial] is the row the list already has, so the summary paints straight
/// away while the full read is in flight.
class OrderDetailView extends StatefulWidget {
  const OrderDetailView({super.key, required this.orderId, this.initial});

  final String orderId;
  final SellerOrder? initial;

  @override
  State<OrderDetailView> createState() => _OrderDetailViewState();
}

class _OrderDetailViewState extends State<OrderDetailView> {
  final SellerOrdersController _ctrl = getOrPut(() => SellerOrdersController());

  SellerOrderDetail? _detail;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_loading) setState(() => _loading = true);
    final detail = await _ctrl.fetchOrderDetail(widget.orderId);
    if (!mounted) return;
    setState(() {
      _detail = detail ?? _detail;
      _failed = detail == null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.white,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: AppColors.brandNavy,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: CustomText(
          TKeys.ordOrderNumberHash.trParams({
            'number': _detail?.orderNumber ?? initial?.orderNumber ?? '',
          }),
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      body: Builder(
        builder: (context) {
          final detail = _detail;

          if (detail == null && _loading) return const BrandedLoadingView();

          if (detail == null) {
            return _DetailError(onRetry: _load);
          }

          return BrandedRefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, 14, 16, bottom + 24),
              children: [
                if (_failed) ...[
                  const _StaleBanner(),
                  const SizedBox(height: 12),
                ],
                _SummaryCard(detail: detail),
                const SizedBox(height: 14),
                _BuyerCard(detail: detail),
                if (detail.seller != null) ...[
                  const SizedBox(height: 14),
                  _SellerCard(seller: detail.seller!),
                ],
                const SizedBox(height: 14),
                _PaymentTimelineCard(detail: detail),
                if (detail.isLocalPickup && detail.pickupAddress != null) ...[
                  const SizedBox(height: 14),
                  _PickupCard(pickup: detail.pickupAddress!),
                ],
                if ((detail.trackingUrl ?? '').isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _TrackButton(url: detail.trackingUrl!),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cards

/// Card shell: icon + title header, optional trailing widget, then content.
class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orderBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.brandNavy),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomText(
                    title,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: orderBorder),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Order number / product / created date / total, then the product + shipping
/// split behind that total.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.detail});
  final SellerOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.shopping_bag_outlined,
      title: TKeys.ordOrderSummary.tr,
      trailing: Flexible(
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          alignment: WrapAlignment.end,
          children: [
            PaymentBadge(status: detail.paymentStatus),
            FreightBadge(status: detail.shippingStatus),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Field(
                  label: TKeys.ordOrderNumberCaps.tr,
                  value: detail.orderNumber,
                ),
              ),
              Expanded(
                child: _Field(
                  label: TKeys.ordCreatedDateCaps.tr,
                  value: formatOrderDay(detail.createdAt),
                  icon: Icons.calendar_today_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Field(label: TKeys.ordProductCaps.tr, value: detail.productName),
          const SizedBox(height: 14),
          _Field(
            label: TKeys.ordTotalAmountCaps.tr,
            value: formatAmount(detail.amount),
            large: true,
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 1, color: orderBorder),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InlineAmount(
                  label: TKeys.ordProductsColon.tr,
                  value: formatAmount(detail.productAmount),
                ),
              ),
              Expanded(
                child: _InlineAmount(
                  label: TKeys.ordShippingColon.tr,
                  value: formatAmount(detail.shippingAmount),
                ),
              ),
            ],
          ),
          if (detail.wasRefunded) ...[
            const SizedBox(height: 10),
            _InlineAmount(
              label: TKeys.ordRefundedColon
                  .trParams({'status': statusLabel(detail.refundStatus)}),
              value: formatAmount(detail.refundedAmount),
              highlight: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// Buyer contact rows plus the shipping address block.
class _BuyerCard extends StatelessWidget {
  const _BuyerCard({required this.detail});
  final SellerOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final buyer = detail.buyer;
    final address = detail.shippingAddress;

    return _Card(
      icon: Icons.person_outline_rounded,
      title: TKeys.ordBuyerInformation.tr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrderSectionLabel(TKeys.ordContactDetailsCaps.tr),
          const SizedBox(height: 10),
          _ContactRow(
            icon: Icons.person_outline_rounded,
            value: buyer?.displayName ?? detail.buyerName,
            label: TKeys.ordFullName.tr,
          ),
          _ContactRow(
            icon: Icons.mail_outline_rounded,
            value: buyer?.email ?? '—',
            label: TKeys.ordEmailAddress.tr,
          ),
          _ContactRow(
            icon: Icons.badge_outlined,
            value: buyer?.id ?? '—',
            label: TKeys.ordCustomerId.tr,
          ),
          _ContactRow(
            icon: Icons.phone_outlined,
            value: buyer?.phone ?? '—',
            label: TKeys.ordPhoneNumber.tr,
          ),
          if (address != null) ...[
            const SizedBox(height: 8),
            OrderSectionLabel(TKeys.ordShippingAddressCaps.tr),
            const SizedBox(height: 10),
            _AddressBlock(address: address),
          ],
        ],
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.seller});
  final OrderParty seller;

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.storefront_outlined,
      title: TKeys.ordSellerDetails.tr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ContactRow(
            icon: Icons.person_outline_rounded,
            value: seller.displayName ?? '—',
            label: TKeys.ordDisplayName.tr,
          ),
          _ContactRow(
            icon: Icons.mail_outline_rounded,
            value: seller.email ?? '—',
            label: TKeys.ordEmailAddress.tr,
          ),
          if ((seller.phone ?? '').isNotEmpty)
            _ContactRow(
              icon: Icons.phone_outlined,
              value: seller.phone!,
              label: TKeys.ordPhoneNumber.tr,
            ),
        ],
      ),
    );
  }
}

/// Payment attempts (usually empty), then the confirmed / delivered stamps.
class _PaymentTimelineCard extends StatelessWidget {
  const _PaymentTimelineCard({required this.detail});
  final SellerOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final attempts = detail.paymentAttempts;

    return _Card(
      icon: Icons.history_rounded,
      title: TKeys.ordPaymentTimeline.tr,
      trailing: PaymentBadge(status: detail.paymentStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (attempts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: CustomText(
                  TKeys.ordNoPaymentAttempts.tr,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
            )
          else
            for (final attempt in attempts) _AttemptRow(attempt: attempt),
          const Divider(height: 20, thickness: 1, color: orderBorder),
          _StampRow(
            label: TKeys.ordFinalPaymentAt.tr,
            value: formatOrderDateTime(detail.paidAt),
          ),
          if (detail.deliveredAt != null) ...[
            const SizedBox(height: 8),
            _StampRow(
              label: TKeys.ordDeliveredAt.tr,
              value: formatOrderDateTime(detail.deliveredAt),
            ),
          ],
        ],
      ),
    );
  }
}

/// Green "ready for pickup" banner naming the shop the buyer collects from.
class _PickupCard extends StatelessWidget {
  const _PickupCard({required this.pickup});
  final PickupLocation pickup;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF2E7D32);
    return _Card(
      icon: Icons.store_mall_directory_outlined,
      title: TKeys.osLocalPickup.tr,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: green.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: green.withOpacity(0.25), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomText(
              TKeys.ordReadyPickupNote.tr,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              height: 1.35,
              color: green,
            ),
            const SizedBox(height: 6),
            CustomText(
              pickup.summary.isEmpty ? (pickup.name ?? '—') : pickup.summary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: green,
            ),
            if ((pickup.phone ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 13, color: green),
                  const SizedBox(width: 5),
                  CustomText(
                    pickup.phone!,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: green,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces

/// `LABEL` over its value — the summary card's grid cells.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.icon,
    this.large = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrderSectionLabel(label),
        const SizedBox(height: 5),
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: CustomText(
                value,
                fontSize: large ? 20 : 15,
                fontWeight: FontWeight.w800,
                letterSpacing: large ? -0.4 : 0,
                color: AppColors.textPrimary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// `Products: 510.00 NOK` — the split under the summary divider.
class _InlineAmount extends StatelessWidget {
  const _InlineAmount({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CustomText(
          label,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: CustomText(
            value,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: highlight ? AppColors.vipps : AppColors.textPrimary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Icon tile + value over its caption, as in the web contact list.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  value,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 1),
                CustomText(
                  label,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Boxed delivery address — pin, recipient, street lines, country and phone.
class _AddressBlock extends StatelessWidget {
  const _AddressBlock({required this.address});
  final OrderAddress address;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 17, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      address.name ?? '—',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(height: 3),
                    for (final line in address.lines)
                      CustomText(
                        line,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    if ((address.country ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      CustomText(
                        address.country!.toUpperCase(),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if ((address.phone ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 1, color: orderBorder),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.phone_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                CustomText(
                  address.phone!,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.attempt});
  final PaymentAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final status = attempt.status ?? 'UNKNOWN';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          PaymentBadge(status: status.toUpperCase()),
          const SizedBox(width: 8),
          Expanded(
            child: CustomText(
              [
                if (attempt.provider != null) attempt.provider!,
                if (attempt.amount != null) formatAmount(attempt.amount),
              ].join(' · '),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          CustomText(
            formatOrderDateTime(attempt.at),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _StampRow extends StatelessWidget {
  const _StampRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CustomText(
            label,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        CustomText(
          value,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ],
    );
  }
}

class _TrackButton extends StatelessWidget {
  const _TrackButton({required this.url});
  final String url;

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      Get.snackbar(TKeys.ordInvalidLink.tr, TKeys.ordInvalidLinkBody.tr);
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      Get.snackbar(
        TKeys.ordCouldNotOpen.tr,
        TKeys.ordNoAppForLink.tr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _open,
      child: Container(
        width: double.infinity,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brandNavy,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_shipping_outlined,
                size: 18, color: AppColors.brandYellow),
            const SizedBox(width: 8),
            CustomText(
              TKeys.ordTrackShipment.tr,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.white,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when a refresh failed but an earlier read is still on screen — the
/// data below is real, just not current.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.vipps.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.vipps),
          const SizedBox(width: 8),
          Expanded(
            child: CustomText(
              TKeys.ordCouldNotRefresh.tr,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.vipps,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.onRetry});
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
              TKeys.ordCouldNotLoadOrder.tr,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 6),
            CustomText(
              TKeys.ordCheckConnection.tr,
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
