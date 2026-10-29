import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/my_requests_controller.dart';
import '../../../core/localization/translation_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/branded_loading_view.dart';
import '../../../core/widgets/branded_refresh_indicator.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/seller_product_request_summary.dart';
import 'request_detail_view.dart';

/// "My requests" — every product request the seller has sent, across all
/// streams, newest first. Filterable All / Active / Invalid, paged on scroll.
///
/// Mirrors the web "Historical requests" panel. Tapping an active request
/// pops back with it (see `ManageProductView._openMyRequests`); a
/// discontinued one opens its read-only history.
class MyRequestsView extends StatefulWidget {
  const MyRequestsView({super.key});

  @override
  State<MyRequestsView> createState() => _MyRequestsViewState();
}

class _MyRequestsViewState extends State<MyRequestsView> {
  // Screen-owned (not in the Get registry), so it dies with the screen.
  final _ctrl = MyRequestsController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _ctrl.refreshRequests();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) _ctrl.loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppColors.textPrimary),
        ),
        title: CustomText(
          TKeys.myRequests.tr,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      body: SafeArea(
        top: false,
        child: BrandedRefreshIndicator(
          onRefresh: _ctrl.refreshRequests,
          child: Obx(() {
            final rows = _ctrl.items;
            final filter = _ctrl.filter;
            return CustomScrollView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    filter: filter,
                    countFor: _ctrl.countFor,
                    onFilter: _ctrl.setFilter,
                  ),
                ),
                if (!_ctrl.loaded || (_ctrl.isLoading && _ctrl.allItems.isEmpty))
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: BrandedLoadingView(),
                  )
                else if (_ctrl.error != null && _ctrl.allItems.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      icon: Icons.wifi_off_rounded,
                      message: TKeys.reqLoadFailed.tr,
                      actionLabel: TKeys.retryAction.tr,
                      onAction: _ctrl.refreshRequests,
                    ),
                  )
                else if (rows.isEmpty && !_ctrl.hasMore)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      icon: Icons.inbox_outlined,
                      message: _ctrl.allItems.isEmpty
                          ? TKeys.reqEmpty.tr
                          : TKeys.reqEmptyFiltered.tr,
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    sliver: _AdaptiveGrid(rows: rows),
                  ),
                  SliverToBoxAdapter(
                    child: _Footer(
                      loadingMore: _ctrl.isLoadingMore,
                      hasMore: _ctrl.hasMore,
                      onLoadMore: _ctrl.loadMore,
                    ),
                  ),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header: title, subtitle, filter pills
// ─────────────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({
    required this.filter,
    required this.countFor,
    required this.onFilter,
  });

  final RequestFilter filter;
  final int Function(RequestFilter) countFor;
  final ValueChanged<RequestFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomText(
          TKeys.historicalRequests.tr,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        const SizedBox(height: 3),
        CustomText(
          TKeys.historicalRequestsSub.tr,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          height: 1.35,
          color: AppColors.textSecondary,
        ),
      ],
    );
    final pills = _FilterPills(
      value: filter,
      countFor: countFor,
      onChanged: onFilter,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 640
            // Wide: title left, pills right — like the web panel.
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: titles),
                  const SizedBox(width: 16),
                  SizedBox(width: 340, child: pills),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [titles, const SizedBox(height: 14), pills],
              ),
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  const _FilterPills({
    required this.value,
    required this.countFor,
    required this.onChanged,
  });

  final RequestFilter value;
  final int Function(RequestFilter) countFor;
  final ValueChanged<RequestFilter> onChanged;

  String _label(RequestFilter f) => switch (f) {
        RequestFilter.all => TKeys.filterAll.tr,
        RequestFilter.active => TKeys.reqFilterActive.tr,
        RequestFilter.invalid => TKeys.reqFilterInvalid.tr,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF0F3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final f in RequestFilter.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: f == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: f == value
                        ? [
                            BoxShadow(
                              color: AppColors.brandNavy.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : const [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: CustomText(
                          _label(f).toUpperCase(),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          color: f == value
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 5),
                      CustomText(
                        '${countFor(f)}',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: f == value
                            ? AppColors.textSecondary
                            : AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Adaptive grid: 2 columns on phones, more as the width allows (~170 px per
// card). Rows are built by hand (not SliverGrid) so a card keeps its natural
// height and every card in a row still lines up.
// ─────────────────────────────────────────────────────────────────────────────
class _AdaptiveGrid extends StatelessWidget {
  const _AdaptiveGrid({required this.rows});

  final List<SellerProductRequestSummary> rows;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = (width / 170).floor().clamp(2, 5);
        final lineCount = (rows.length / columns).ceil();
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, line) {
              final start = line * columns;
              final cells = <Widget>[];
              for (var c = 0; c < columns; c++) {
                if (c > 0) cells.add(const SizedBox(width: _gap));
                final i = start + c;
                cells.add(Expanded(
                  child: i < rows.length
                      ? _RequestCard(request: rows[i])
                      : const SizedBox.shrink(),
                ));
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: _gap),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: cells,
                  ),
                ),
              );
            },
            childCount: lineCount,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card — narrow enough for two per phone row, so everything stacks. A tinted
// header band carries the request's status colour; the body holds the stream,
// and a soft footer panel shows status + sent time.
// ─────────────────────────────────────────────────────────────────────────────
class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final SellerProductRequestSummary request;

  /// Active: back to the Requests tab with this stream selected, where
  /// products can still be added. Discontinued: read-only history.
  void _open(BuildContext context) {
    if (request.isActive) {
      Navigator.of(context).pop(request);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RequestDetailView(request: request),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = request;
    final active = r.isActive;
    final status = requestStatusColor(r.status);
    final count =
        (r.itemCount == 1 ? TKeys.productCountOne : TKeys.productCountMany)
            .trParams({'count': '${r.itemCount}'});

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGrey),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header band — the only coloured part of the card.
              // Discontinued cards skip it and start straight at the title.
              if (active)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  decoration: BoxDecoration(
                    color: AppColors.brandYellow.withOpacity(0.28),
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.brandYellow.withOpacity(0.45),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.brandNavy,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          r.isStreamLive
                              ? Icons.sensors_rounded
                              : Icons.live_tv_rounded,
                          size: 16,
                          color: AppColors.brandYellow,
                        ),
                      ),
                      const Spacer(),
                      const _StateChip(active: true),
                      const SizedBox(width: 6),
                      // Chevron so the whole card reads as tappable.
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppColors.brandNavy.withOpacity(0.55),
                      ),
                    ],
                  ),
                ),
              // Stream title + live / scheduled line
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: CustomText(
                            r.streamTitle.isEmpty ? '—' : r.streamTitle,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            letterSpacing: -0.2,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            color: active
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                        // No header on discontinued cards, so the tap hint
                        // sits beside the title instead.
                        if (!active) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ],
                    ),
                    if (r.isStreamLive) ...[
                      const SizedBox(height: 6),
                      _MetaLine(
                        leading: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        text: TKeys.reqLiveNow.tr,
                        textColor: Colors.red,
                      ),
                    ] else if (r.streamScheduledStartTime != null) ...[
                      const SizedBox(height: 6),
                      _MetaLine(
                        leading: const Icon(Icons.event_rounded,
                            size: 13, color: AppColors.textMuted),
                        text: formatRequestDate(r.streamScheduledStartTime),
                      ),
                    ],
                    if (!active) ...[
                      const SizedBox(height: 6),
                      _MetaLine(
                        leading: const Icon(Icons.history_rounded,
                            size: 13, color: AppColors.textMuted),
                        text: TKeys.reqDiscontinued.tr,
                        textColor: AppColors.textMuted,
                      ),
                    ],
                  ],
                ),
              ),
              const _CardDivider(),
              // Product count
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: CustomText(
                        count,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const _CardDivider(),
              // Status + sent time
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FooterRow(
                      label: TKeys.reqStatusLabel.tr,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: status,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: CustomText(
                              requestStatusLabel(r.status).toUpperCase(),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              color: status,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 7),
                    _FooterRow(
                      label: TKeys.reqSentLabel.tr,
                      child: CustomText(
                        formatRequestDate(r.sentAt),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Localised request status (DRAFT / SUBMITTED / FULFILLED / CANCELLED).
String requestStatusLabel(String s) => switch (s) {
      'DRAFT' => TKeys.reqStatusDraft.tr,
      'SUBMITTED' => TKeys.reqStatusSubmitted.tr,
      'FULFILLED' => TKeys.reqStatusFulfilled.tr,
      'CANCELLED' => TKeys.reqStatusCancelled.tr,
      _ => s,
    };

/// Accent colour for a request status.
Color requestStatusColor(String s) => switch (s) {
      'DRAFT' => AppColors.brandNavy,
      'SUBMITTED' => const Color(0xFFC98A00),
      'FULFILLED' => const Color(0xFF1E9E63),
      'CANCELLED' => const Color(0xFFE5484D),
      _ => AppColors.textSecondary,
    };

class _StateChip extends StatelessWidget {
  const _StateChip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1E9E63);
    final fg = active ? green : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? green.withOpacity(0.30) : AppColors.borderGrey,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle_rounded : Icons.history_rounded,
            size: 11,
            color: fg,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: CustomText(
              (active ? TKeys.reqFilterActive.tr : TKeys.reqDiscontinued.tr)
                  .toUpperCase(),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.leading,
    required this.text,
    this.textColor = AppColors.textSecondary,
  });

  final Widget leading;
  final String text;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading,
        const SizedBox(width: 6),
        Flexible(
          child: CustomText(
            text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

/// Small caps label over a value, used in the card's footer panel.
class _FooterRow extends StatelessWidget {
  const _FooterRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomText(
          label.toUpperCase(),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 3),
        child,
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
  });

  final bool loadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Center(
        child: loadingMore
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
                ),
              )
            : hasMore
                // Fallback when the list is too short to scroll.
                ? TextButton(
                    onPressed: onLoadMore,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandNavy,
                    ),
                    child: CustomText(
                      TKeys.loadMore.tr,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandNavy,
                    ),
                  )
                : const SizedBox.shrink(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.brandNavy.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: AppColors.brandNavy),
            ),
            const SizedBox(height: 14),
            CustomText(
              message,
              fontSize: 13.5,
              height: 1.45,
              textAlign: TextAlign.center,
              color: AppColors.textSecondary,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandNavy,
                  side: const BorderSide(color: AppColors.brandNavy),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: CustomText(
                  actionLabel!,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "16.10.2026 · 05:16" in the device's local time.
String formatRequestDate(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} · '
      '${two(d.hour)}:${two(d.minute)}';
}

/// Hairline separating the sections inside a request card.
class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFFEEF0F3),
    );
  }
}
