import 'package:flutter/material.dart';

import '../../controllers/stream_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/branded_loading_view.dart';
import '../../core/widgets/branded_refresh_indicator.dart';
import '../../core/widgets/custom_text.dart';
import '../../models/stream_analytics.dart';
import '../../models/stream_model.dart';
import '../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

/// Post-mortem for a finished (or admin-rejected) stream: status, real
/// broadcast duration, viewer peaks, every auctioned product, the money
/// summary and a per-buyer breakdown.
///
/// One read, by stream id:
///   • `GET /api/v1/seller/streams/:id/analytics`
///
/// All numbers come straight from that payload — nothing is recomputed on the
/// client. Closed streams don't change on their own, hence the "retrieved at"
/// footer and pull-to-refresh instead of any polling.
class StreamAnalyticsView extends StatefulWidget {
  const StreamAnalyticsView({super.key, required this.streamId, this.initial});

  final String streamId;

  /// The card's copy of the stream, shown while the analytics GET is in flight.
  final StreamModel? initial;

  @override
  State<StreamAnalyticsView> createState() => _StreamAnalyticsViewState();
}

class _StreamAnalyticsViewState extends State<StreamAnalyticsView> {
  final StreamListController _ctrl = getOrPut(() => StreamListController());

  StreamAnalytics? _analytics;
  bool _loading = true;
  bool _failed = false;
  DateTime? _retrievedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final fresh = await _ctrl.fetchStreamAnalytics(widget.streamId);
    if (!mounted) return;
    setState(() {
      if (fresh != null) _analytics = fresh;
      _failed = fresh == null;
      _loading = false;
      _retrievedAt = DateTime.now();
    });
  }

  // ── Derived ────────────────────────────────────────────────────────────────

  String get _title =>
      _analytics?.streamTitle ?? widget.initial?.title ?? TKeys.saStream.tr;

  String? get _status => _analytics?.streamStatus ?? widget.initial?.status;

  DateTime? get _startTime =>
      _analytics?.startTime ??
      widget.initial?.actualStartTime ??
      widget.initial?.scheduledStartTime;

  DateTime? get _endTime => _analytics?.endTime ?? widget.initial?.endTime;

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final a = _analytics;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.brandNavy),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: CustomText(
          TKeys.saStreamAnalysis.tr,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        centerTitle: false,
      ),
      body: _loading && a == null
          ? const BrandedLoadingView()
          : BrandedRefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 24),
                children: [
                  if (a == null && _failed) ...[
                    _errorCard(),
                    const SizedBox(height: 14),
                  ],
                  _overviewCard(a),
                  const SizedBox(height: 14),
                  _productsCard(a),
                  const SizedBox(height: 14),
                  _salesCard(a),
                  const SizedBox(height: 14),
                  _auctionsCard(a),
                  const SizedBox(height: 14),
                  _buyersCard(a),
                  const SizedBox(height: 14),
                  _footer(a),
                ],
              ),
            ),
    );
  }

  Widget _errorCard() {
    return _Card(
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB26A00)),
          const SizedBox(width: 10),
          Expanded(
            child: CustomText(
              TKeys.saCouldNotLoad.tr,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          TextButton(
            onPressed: _load,
            child: CustomText(TKeys.retryAction.tr,
                fontSize: 13, fontWeight: FontWeight.w800,
                color: AppColors.brandNavy),
          ),
        ],
      ),
    );
  }

  Widget _overviewCard(StreamAnalytics? a) {
    // Prefer the spelled-out duration ("30 minutes, 5 seconds"); fall back to
    // the server's hh:mm:ss string when only that came back.
    final duration = _spellDuration(a?.streamDuration) ??
        a?.streamDurationFormatted ??
        '—';
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            _title,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 16),
          _SectionCaption(TKeys.saStatusCaps.tr),
          const SizedBox(height: 4),
          Row(
            children: [
              CustomText(
                _statusLabel(_status),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              if (widget.initial?.approvalStatus != null) ...[
                const SizedBox(width: 8),
                _ApprovalPill(status: widget.initial!.approvalStatus!),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // IntrinsicHeight gives the row a real height, so the tiles in a pair
          // can stretch to match the taller one (their labels wrap differently).
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatTile(
                    label: TKeys.saMaxViewers.tr,
                    value: _count(a?.peakViewerCount),
                    hint: TKeys.saStoredValue.tr,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    label: TKeys.saAvgViewers.tr,
                    value: _count(a?.averageViewerCount),
                    hint: TKeys.saStoredValue.tr,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatTile(
                    label: TKeys.saStreamDuration.tr,
                    value: duration,
                    hint: a?.streamDurationFormatted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    label: TKeys.saAuctionTime.tr,
                    value: _spellDuration(a?.auctionDuration) ??
                        a?.totalAuctionDurationFormatted ??
                        '—',
                    hint: a?.totalAuctionDurationFormatted,
                  ),
                ),
              ],
            ),
          ),
          if ((a?.currentViewerCount ?? 0) > 0) ...[
            const SizedBox(height: 10),
            _StatTile(
              label: TKeys.saViewersNow.tr,
              value: _count(a!.currentViewerCount),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TimeBlock(label: TKeys.saStarted.tr, time: _startTime),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeBlock(label: TKeys.saCompleted.tr, time: _endTime),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _productsCard(StreamAnalytics? a) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            TKeys.productsLabel.tr,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: TKeys.saAuctioned.tr,
                  value: '${a?.productsAuctioned ?? 0}',
                  color: AppColors.textPrimary,
                  background: const Color(0xFFF3F4F6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  label: TKeys.soldLabel.tr,
                  value: '${a?.productsSold ?? 0}',
                  color: const Color(0xFF2E7D32),
                  background: const Color(0xFFEFF7EF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  label: TKeys.saNotSold.tr,
                  value: '${a?.productsNotSold ?? 0}',
                  color: const Color(0xFFB26A00),
                  background: const Color(0xFFFDF6E6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _salesCard(StreamAnalytics? a) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            TKeys.saSalesSummary.tr,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: TKeys.saTotalTurnover.tr,
                  value: _kr(a?.totalSales ?? 0),
                  color: const Color(0xFF2E7D32),
                  background: const Color(0xFFEFF7EF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  label: TKeys.saPaid.tr,
                  value: _kr(a?.totalPaid ?? 0),
                  color: const Color(0xFF1565C0),
                  background: const Color(0xFFEEF3FC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: TKeys.saUnpaid.tr,
                  value: _kr(a?.totalPending ?? 0),
                  color: const Color(0xFFB26A00),
                  background: const Color(0xFFFDF6E6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  label: TKeys.saNumberOfBuyers.tr,
                  value: '${a?.totalBuyers ?? 0}',
                  color: AppColors.textPrimary,
                  background: const Color(0xFFF3F4F6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _auctionsCard(StreamAnalytics? a) {
    final items = a?.productAuctionDetails ?? const <AuctionedProduct>[];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CustomText(
                  TKeys.saAuctionsInStream.tr,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (items.isNotEmpty) _CountPill(count: items.length),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            CustomText(
              TKeys.saNoAuctionsYet.tr,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: AppColors.textMuted,
            )
          else
            ...List.generate(items.length, (i) {
              return Padding(
                padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 10),
                child: _AuctionRow(item: items[i]),
              );
            }),
        ],
      ),
    );
  }

  Widget _buyersCard(StreamAnalytics? a) {
    final buyers = a?.buyerDetails ?? const <AnalyticsBuyer>[];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CustomText(
                  TKeys.saBuyers.tr,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (buyers.isNotEmpty) _CountPill(count: buyers.length),
            ],
          ),
          const SizedBox(height: 12),
          if (buyers.isEmpty)
            CustomText(
              TKeys.saNoOrders.tr,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: AppColors.textMuted,
            )
          else
            ...List.generate(buyers.length, (i) {
              return Padding(
                padding:
                    EdgeInsets.only(bottom: i == buyers.length - 1 ? 0 : 10),
                child: _BuyerBlock(buyer: buyers[i]),
              );
            }),
        ],
      ),
    );
  }

  Widget _footer(StreamAnalytics? a) {
    final t = _retrievedAt;
    final stamp = t == null
        ? '—'
        : '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
    final generated = a?.generatedAt;
    return Column(
      children: [
        CustomText(
          TKeys.saRetrieved.trParams({'stamp': stamp}),
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          textAlign: TextAlign.center,
          color: AppColors.textMuted,
        ),
        if (generated != null) ...[
          const SizedBox(height: 3),
          CustomText(
            TKeys.saGeneratedByServer
                .trParams({'stamp': _formatStamp(generated)}),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            textAlign: TextAlign.center,
            color: AppColors.textMuted,
          ),
        ],
      ],
    );
  }

  // ── Formatting ─────────────────────────────────────────────────────────────

  String _statusLabel(String? status) {
    switch (status?.toUpperCase()) {
      case 'ENDED':
        return TKeys.saCompleted.tr;
      case 'CANCELLED':
        return TKeys.statusCancelled.tr;
      case 'LIVE':
        return TKeys.statusLive.tr;
      case 'SCHEDULED':
        return TKeys.statusScheduled.tr;
      case 'DRAFT':
        return TKeys.statusDraft.tr;
      default:
        return status ?? '—';
    }
  }

  /// "1 minute, 15 seconds" — matches the web analytics wording. Null when the
  /// server sent no duration at all.
  String? _spellDuration(Duration? d) {
    if (d == null) return null;
    final parts = <String>[];
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      parts.add('$h ${h == 1 ? TKeys.durHourOne.tr : TKeys.durHourMany.tr}');
    }
    if (m > 0) {
      parts.add('$m ${m == 1 ? TKeys.durMinuteOne.tr : TKeys.durMinuteMany.tr}');
    }
    if (s > 0 || parts.isEmpty) {
      parts.add('$s ${s == 1 ? TKeys.durSecondOne.tr : TKeys.durSecondMany.tr}');
    }
    return parts.join(', ');
  }

  /// Viewer counts arrive as ints (peak) or decimals (average) — keep the
  /// decimal only when there is one.
  String _count(num? v) {
    if (v == null) return '0';
    if (v == v.roundToDouble()) return '${v.round()}';
    return v.toStringAsFixed(2);
  }

  String _kr(num v) => '${v.toStringAsFixed(2)} kr';
}

String _two(int v) => v.toString().padLeft(2, '0');

String _kr(num v) => '${v.toStringAsFixed(2)} kr';

String _formatStamp(DateTime dt) {
  final months = [
    '', TKeys.monthJanuary.tr, TKeys.monthFebruary.tr, TKeys.monthMarch.tr,
    TKeys.monthApril.tr, TKeys.monthMay.tr, TKeys.monthJune.tr,
    TKeys.monthJuly.tr, TKeys.monthAugust.tr, TKeys.monthSeptember.tr,
    TKeys.monthOctober.tr, TKeys.monthNovember.tr, TKeys.monthDecember.tr,
  ];
  final local = dt.toLocal();
  final h24 = local.hour;
  // Norwegian reads a 24-hour clock; English keeps AM/PM.
  final time = TKeys.dateClock24.tr == 'true'
      ? '${_two(h24)}:${_two(local.minute)}:${_two(local.second)}'
      : '${h24 % 12 == 0 ? 12 : h24 % 12}:${_two(local.minute)}:'
          '${_two(local.second)} ${h24 < 12 ? 'AM' : 'PM'}';
  return TKeys.dateStampFormat.trParams({
    'month': months[local.month],
    'day': '${local.day}',
    'year': '${local.year}',
    'time': time,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.grey.withOpacity(0.15), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionCaption extends StatelessWidget {
  const _SectionCaption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return CustomText(
      text,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      color: AppColors.textMuted,
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.brandYellow.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: CustomText(
        '$count',
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppColors.brandNavy,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.hint});
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(label, fontSize: 13, fontWeight: FontWeight.w600,
              color: AppColors.textSecondary),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CustomText(value, fontSize: 20, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            CustomText(hint!, fontSize: 11.5, fontWeight: FontWeight.w500,
                color: AppColors.textMuted),
          ],
        ],
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({required this.label, required this.time});
  final String label;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(label, fontSize: 13, fontWeight: FontWeight.w800,
            color: AppColors.textSecondary),
        const SizedBox(height: 4),
        CustomText(
          time == null ? '—' : _formatStamp(time!),
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          height: 1.35,
          color: AppColors.textPrimary,
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });
  final String label;
  final String value;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(label, fontSize: 12.5, fontWeight: FontWeight.w600,
              color: AppColors.textSecondary, maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CustomText(value, fontSize: 19,
                fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

class _ApprovalPill extends StatelessWidget {
  const _ApprovalPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status.toUpperCase()) {
      case 'APPROVED':
        color = const Color(0xFF2E7D32);
        label = TKeys.adminApproved.tr;
        break;
      case 'PENDING':
        color = const Color(0xFFB26A00);
        label = TKeys.awaitingAdmin.tr;
        break;
      case 'REJECTED':
        color = AppColors.vipps;
        label = TKeys.adminRejected.tr;
        break;
      default:
        color = AppColors.textMuted;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: CustomText(label, fontSize: 11,
          fontWeight: FontWeight.w800, color: color),
    );
  }
}

/// One row of `productAuctionDetails`.
class _AuctionRow extends StatelessWidget {
  const _AuctionRow({required this.item});
  final AuctionedProduct item;

  @override
  Widget build(BuildContext context) {
    final sold = item.sold ?? (item.finalPrice != null && item.finalPrice! > 0);
    final color = sold ? const Color(0xFF2E7D32) : const Color(0xFFB26A00);
    final meta = <String>[
      if (item.auctionType != null) item.auctionType!.toUpperCase(),
      if (item.durationFormatted != null) item.durationFormatted!,
      if (item.bidCount != null)
        TKeys.saBidsCount.trParams({'count': '${item.bidCount}'}),
      if (item.buyerName != null) item.buyerName!,
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 44, height: 44, color: AppColors.inputFill,
              child: item.productImage != null
                  ? Image.network(item.productImage!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_outlined, color: AppColors.textMuted))
                  : const Icon(Icons.gavel_rounded,
                      color: AppColors.textMuted, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  item.productName ?? TKeys.saProduct.tr,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  CustomText(
                    meta.join(' · '),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (item.startingPrice != null) ...[
                  const SizedBox(height: 2),
                  CustomText(
                    TKeys.saStartPrice.trParams({'price': _kr(item.startingPrice!)}),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CustomText(
                item.finalPrice == null ? '—' : _kr(item.finalPrice!),
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: CustomText(
                  item.paymentStatus?.toUpperCase() ??
                      (sold ? TKeys.saSoldCaps.tr : TKeys.saNotSoldCaps.tr),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row of `buyerDetails` — the buyer plus every product they took home.
class _BuyerBlock extends StatelessWidget {
  const _BuyerBlock({required this.buyer});
  final AnalyticsBuyer buyer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandYellow.withOpacity(0.35),
                  shape: BoxShape.circle,
                ),
                child: CustomText(
                  _initials(buyer.buyerName ?? buyer.buyerEmail ?? '?'),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      buyer.buyerName ?? TKeys.saBuyer.tr,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (buyer.buyerEmail != null) ...[
                      const SizedBox(height: 2),
                      CustomText(
                        buyer.buyerEmail!,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CustomText(
                _kr(buyer.totalSpent),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStat(
                label: TKeys.saPaid.tr,
                value: _kr(buyer.paid),
                color: const Color(0xFF1565C0),
              ),
              const SizedBox(width: 8),
              _MiniStat(
                label: TKeys.saPending.tr,
                value: _kr(buyer.pending),
                color: const Color(0xFFB26A00),
              ),
            ],
          ),
          if (buyer.productsPurchased.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...buyer.productsPurchased.map(
              (p) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _PurchaseRow(purchase: p),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _initials(String source) {
    final parts = source.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1 || parts[1].isEmpty) {
      return parts.first[0].toUpperCase();
    }
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomText('$label ', fontSize: 11,
              fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          CustomText(value, fontSize: 11.5,
              fontWeight: FontWeight.w800, color: color),
        ],
      ),
    );
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({required this.purchase});
  final BuyerPurchase purchase;

  @override
  Widget build(BuildContext context) {
    final color =
        purchase.isPaid ? const Color(0xFF2E7D32) : const Color(0xFFB26A00);
    final meta = <String>[
      if (purchase.orderId != null) '#${purchase.orderId}',
      if (purchase.auctionType != null) purchase.auctionType!.toUpperCase(),
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  purchase.productName ?? TKeys.saProduct.tr,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  CustomText(
                    meta.join(' · '),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CustomText(
                purchase.finalPrice == null ? '—' : _kr(purchase.finalPrice!),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: CustomText(
                  (purchase.paymentStatus ?? TKeys.saUnpaidCaps.tr).toUpperCase(),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
