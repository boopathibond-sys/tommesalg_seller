import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

// Status pills, borders and formatting shared by the orders list and the order
// details screen.

/// Border/divider colour for every card, field and pill outline on the orders
/// screens. Neutral grey on purpose — [AppColors.inputBorder] is a muted amber,
/// which reads as a yellow outline once a screen is mostly cards.
const Color orderBorder = Color(0xFFE6E8EC);

/// Wording for the statuses the API uses. Anything not listed falls back to the
/// generic `SNAKE_CASE` → `Snake case` conversion in [statusLabel], so a status
/// this build has never seen still reads properly.
// A getter, not a `const` map: the values are translated, so they have to
// re-resolve when the seller switches language. Keys stay the API's verbatim
// status codes.
Map<String, String> get _statusLabels => <String, String>{
      'PAID': TKeys.osPaid.tr,
      'PENDING_PAYMENT': TKeys.osAwaitingPayment.tr,
      'FAILED': TKeys.osFailed.tr,
      'REFUNDED': TKeys.osRefunded.tr,
      'NOT_CREATED': TKeys.osNotCreated.tr,
      'CREATED': TKeys.osCreated.tr,
      'IN_TRANSIT': TKeys.osInTransit.tr,
      'DELIVERED': TKeys.osDelivered.tr,
      'CANCELLED': TKeys.osCancelled.tr,
      'READY_FOR_PICKUP': TKeys.osReadyForPickup.tr,
      'PICKED_UP': TKeys.osPickedUp.tr,
      'LOCAL_PICKUP': TKeys.osLocalPickup.tr,
    };

/// `PENDING_PAYMENT` → `Awaiting payment`; `SOME_NEW_STATE` → `Some new state`.
String statusLabel(String status) {
  if (status.isEmpty) return '—';
  final known = _statusLabels[status];
  if (known != null) return known;
  final words = status.split('_').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return status;
  final first = words.first;
  return [
    first[0].toUpperCase() + first.substring(1).toLowerCase(),
    ...words.skip(1).map((w) => w.toLowerCase()),
  ].join(' ');
}

/// Pill colour per payment state — green once paid, amber while the buyer
/// still owes, red when the payment failed or was cancelled.
Color paymentStatusColor(String status) {
  switch (status) {
    case 'PAID':
      return const Color(0xFF2E9E5B);
    case 'PENDING_PAYMENT':
    case 'PENDING':
      return const Color(0xFFD08700);
    case 'FAILED':
    case 'CANCELLED':
      return AppColors.vipps;
    case 'REFUNDED':
      return AppColors.primaryBlue;
    default:
      return AppColors.textMuted;
  }
}

/// `1045` → `1,045.00 NOK`; null → `—`.
String formatAmount(num? value) {
  if (value == null) return '—';
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts.first.replaceFirst('-', '');
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  final sign = value < 0 ? '-' : '';
  return '$sign$grouped.${parts.last} NOK';
}

List<String> get _months => [
      '', TKeys.monthJanShort.tr, TKeys.monthFebShort.tr, TKeys.monthMarShort.tr,
      TKeys.monthAprShort.tr, TKeys.monthMayShort.tr, TKeys.monthJunShort.tr,
      TKeys.monthJulShort.tr, TKeys.monthAugShort.tr, TKeys.monthSepShort.tr,
      TKeys.monthOctShort.tr, TKeys.monthNovShort.tr, TKeys.monthDecShort.tr,
    ];

/// `2026-08-05T10:22:30Z` → `Aug 5, 2026` (device local time).
String formatOrderDay(DateTime? date) {
  if (date == null) return '—';
  final d = date.toLocal();
  return TKeys.ordDayFormat.trParams({
    'month': _months[d.month],
    'day': '${d.day}',
    'year': '${d.year}',
  });
}

/// `2026-08-05T13:52:00Z` → `Aug 5, 2026, 3:52 PM` (device local time).
String formatOrderDateTime(DateTime? date) {
  if (date == null) return '—';
  final d = date.toLocal();
  final minute = d.minute.toString().padLeft(2, '0');
  // Norwegian reads a 24-hour clock; English keeps AM/PM.
  final time = TKeys.dateClock24.tr == 'true'
      ? '${d.hour.toString().padLeft(2, '0')}:$minute'
      : '${d.hour % 12 == 0 ? 12 : d.hour % 12}:$minute '
          '${d.hour < 12 ? 'AM' : 'PM'}';
  return '${formatOrderDay(d)}, $time';
}

/// Green PAID / amber AWAITING PAYMENT pill.
class PaymentBadge extends StatelessWidget {
  const PaymentBadge({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => _StatusPill(
        label: statusLabel(status),
        color: paymentStatusColor(status),
        tinted: true,
      );
}

/// Freight state pill — muted until a label exists, brand navy once it does.
class FreightBadge extends StatelessWidget {
  const FreightBadge({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final pending = status == 'NOT_CREATED' || status == 'UNKNOWN';
    return _StatusPill(
      label: statusLabel(status),
      color: pending ? AppColors.textMuted : AppColors.brandNavy,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    this.tinted = false,
  });

  final String label;
  final Color color;

  /// Payment pills carry their colour into the background; freight pills sit on
  /// the neutral fill so the two never compete.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tinted ? color.withOpacity(0.1) : AppColors.inputFill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Flexible(
            child: CustomText(
              label.toUpperCase(),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: color,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small all-caps section heading used inside the details cards.
class OrderSectionLabel extends StatelessWidget {
  const OrderSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => CustomText(
        label,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: AppColors.textMuted,
      );
}
