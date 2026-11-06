import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/stream_controller.dart';
import '../../../core/localization/translation_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/product_request_model.dart';

/// Which slice of the scanned lines the panel shows.
enum ScannedLinesFilter { all, ready, held }

/// The Requests tab's scanned-products list, built for streams with hundreds
/// of lines (500+ scans is normal):
///
/// * **Search** by product name or UPC — server-side `?q=` (TW-194), debounced
///   300 ms, with a client-side fallback for older servers.
/// * **Filter chips** — All / Ready / Waiting for admin (TW-193 held lines),
///   each with its count, so the seller can go straight to what needs them.
/// * **Pages** of [pageSize] instead of one endless scroll. The pager shows
///   "21–30 of 500"; tapping it opens a page grid to jump anywhere in one tap.
/// * **Jump to the scan** — after a scan the parent calls [revealItem]; the
///   panel flips to the page holding that line and briefly highlights it.
class ScannedLinesPanel extends StatefulWidget {
  const ScannedLinesPanel({
    super.key,
    required this.ctrl,
    required this.itemBuilder,
    this.pageSize = 10,
  });

  final StreamListController ctrl;

  /// Builds one row. [highlighted] is true for a just-scanned line.
  final Widget Function(ProductRequestItem item, bool highlighted) itemBuilder;

  final int pageSize;

  @override
  State<ScannedLinesPanel> createState() => ScannedLinesPanelState();
}

class ScannedLinesPanelState extends State<ScannedLinesPanel> {
  final TextEditingController _searchCtrl = TextEditingController();
  final GlobalKey _topKey = GlobalKey();

  ScannedLinesFilter _filter = ScannedLinesFilter.all;
  int _page = 0;
  String? _highlightId;
  Timer? _highlightTimer;

  StreamListController get ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    // Keep the box in sync if the controller's search was cleared elsewhere
    // (e.g. switching streams).
    _searchCtrl.text = ctrl.requestSearchQuery;
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ProductRequestItem> _applyFilter(List<ProductRequestItem> items) {
    return switch (_filter) {
      ScannedLinesFilter.all => items,
      ScannedLinesFilter.ready => items.where((i) => !i.isHeld).toList(),
      ScannedLinesFilter.held => items.where((i) => i.isHeld).toList(),
    };
  }

  /// Shows the page that holds [itemId] and highlights the row for a moment.
  /// Clears search / filter first if they would hide it. Doesn't scroll by
  /// default: the scan button sits above the list, and rapid scanning
  /// shouldn't keep yanking the page away from it.
  void revealItem(String itemId, {bool scroll = false}) {
    if (!mounted) return;
    var items = _applyFilter(ctrl.filteredRequestItems);
    var index = items.indexWhere((i) => i.id == itemId);
    if (index < 0) {
      // Hidden by the search or a chip — drop both so the scan is visible.
      _searchCtrl.clear();
      ctrl.clearRequestSearch();
      _filter = ScannedLinesFilter.all;
      items = ctrl.visibleRequestItems;
      index = items.indexWhere((i) => i.id == itemId);
      if (index < 0) return;
    }
    _highlightTimer?.cancel();
    setState(() {
      _page = index ~/ widget.pageSize;
      _highlightId = itemId;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _highlightId = null);
    });
    if (scroll) _scrollToTop();
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _topKey.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _onSearchChanged(String text) {
    setState(() => _page = 0);
    ctrl.onRequestSearchChanged(text);
  }

  void _clearSearch() {
    _searchCtrl.clear();
    ctrl.clearRequestSearch();
    setState(() => _page = 0);
  }

  void _setFilter(ScannedLinesFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _page = 0;
    });
  }

  Future<void> _openPageJump(int pageCount, int total) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PageJumpSheet(
        pageCount: pageCount,
        current: _page,
        pageSize: widget.pageSize,
        total: total,
      ),
    );
    if (picked != null && mounted) _goToPage(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final searched = ctrl.filteredRequestItems;
      final readyCount = searched.where((i) => !i.isHeld).length;
      final heldCount = searched.length - readyCount;
      // A chip that has emptied (e.g. admin resolved everything) falls back
      // to All instead of leaving the seller on an empty view.
      final filter = _filter == ScannedLinesFilter.held && heldCount == 0
          ? ScannedLinesFilter.all
          : _filter;
      final items = filter == _filter ? _applyFilter(searched) : searched;

      final total = items.length;
      final pageCount = total == 0 ? 1 : (total / widget.pageSize).ceil();
      final page = _page.clamp(0, pageCount - 1);
      final start = page * widget.pageSize;
      final end = (start + widget.pageSize).clamp(0, total);
      final pageItems = total == 0 ? const <ProductRequestItem>[] : items.sublist(start, end);

      return Column(
        key: _topKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SearchField(
            controller: _searchCtrl,
            searching: ctrl.isSearchingRequest,
            onChanged: _onSearchChanged,
            onClear: _clearSearch,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: TKeys.reqFilterAll
                      .trParams({'count': '${searched.length}'}),
                  selected: filter == ScannedLinesFilter.all,
                  onTap: () => _setFilter(ScannedLinesFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: TKeys.reqFilterReady
                      .trParams({'count': '$readyCount'}),
                  selected: filter == ScannedLinesFilter.ready,
                  onTap: () => _setFilter(ScannedLinesFilter.ready),
                ),
                if (heldCount > 0) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: TKeys.reqFilterHeld
                        .trParams({'count': '$heldCount'}),
                    selected: filter == ScannedLinesFilter.held,
                    accent: Colors.orange.shade800,
                    onTap: () => _setFilter(ScannedLinesFilter.held),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (pageCount > 1) ...[
            _Pager(
              page: page,
              pageCount: pageCount,
              from: start + 1,
              to: end,
              total: total,
              onPage: _goToPage,
              onJump: () => _openPageJump(pageCount, total),
            ),
            const SizedBox(height: 10),
          ],
          if (pageItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  const Icon(Icons.search_off_rounded,
                      size: 32, color: AppColors.textMuted),
                  const SizedBox(height: 8),
                  CustomText(
                    ctrl.hasRequestSearch
                        ? TKeys.reqNoSearchMatch
                            .trParams({'query': ctrl.requestSearchQuery})
                        : TKeys.reqNoFilterMatch.tr,
                    textAlign: TextAlign.center,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            )
          else
            ...pageItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: widget.itemBuilder(item, item.id == _highlightId),
                )),
          if (pageCount > 1)
            _Pager(
              page: page,
              pageCount: pageCount,
              from: start + 1,
              to: end,
              total: total,
              onPage: _goToPage,
              onJump: () => _openPageJump(pageCount, total),
            ),
        ],
      );
    });
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.searching,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool searching;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            hintText: TKeys.reqSearchHint.tr,
            hintStyle:
                const TextStyle(fontSize: 13, color: AppColors.textMuted),
            prefixIcon: const Icon(Icons.search_rounded,
                size: 20, color: AppColors.textSecondary),
            suffixIcon: searching
                ? const Padding(
                    padding: EdgeInsets.all(13),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : value.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: AppColors.textSecondary,
                        onPressed: onClear,
                      ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderGrey),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderGrey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.brandNavy),
            ),
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = AppColors.brandNavy,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? accent : AppColors.borderGrey),
        ),
        child: CustomText(
          label,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : accent,
        ),
      ),
    );
  }
}

/// ‹  21–30 of 500 ▾  ›  — the middle opens the page grid.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pageCount,
    required this.from,
    required this.to,
    required this.total,
    required this.onPage,
    required this.onJump,
  });

  final int page;
  final int pageCount;
  final int from;
  final int to;
  final int total;
  final ValueChanged<int> onPage;
  final VoidCallback onJump;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, int? target) => IconButton(
          onPressed: target == null ? null : () => onPage(target),
          icon: Icon(icon),
          color: AppColors.brandNavy,
          disabledColor: AppColors.borderGrey,
          visualDensity: VisualDensity.compact,
        );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Row(
        children: [
          arrow(Icons.first_page_rounded, page > 0 ? 0 : null),
          arrow(Icons.chevron_left_rounded, page > 0 ? page - 1 : null),
          Expanded(
            child: InkWell(
              onTap: onJump,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CustomText(
                          TKeys.reqPageRange.trParams({
                            'from': '$from',
                            'to': '$to',
                            'total': '$total',
                          }),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandNavy,
                        ),
                        const Icon(Icons.arrow_drop_down_rounded,
                            size: 20, color: AppColors.brandNavy),
                      ],
                    ),
                    CustomText(
                      TKeys.reqPageOf.trParams({
                        'page': '${page + 1}',
                        'pages': '$pageCount',
                      }),
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          arrow(Icons.chevron_right_rounded,
              page < pageCount - 1 ? page + 1 : null),
          arrow(Icons.last_page_rounded,
              page < pageCount - 1 ? pageCount - 1 : null),
        ],
      ),
    );
  }
}

/// Grid of every page with its item range — one tap to anywhere in a long
/// list instead of paging through it.
class _PageJumpSheet extends StatelessWidget {
  const _PageJumpSheet({
    required this.pageCount,
    required this.current,
    required this.pageSize,
    required this.total,
  });

  final int pageCount;
  final int current;
  final int pageSize;
  final int total;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.6;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderGrey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            CustomText(
              TKeys.reqJumpToPage.tr,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                itemCount: pageCount,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.35,
                ),
                itemBuilder: (context, index) {
                  final selected = index == current;
                  final from = index * pageSize + 1;
                  final to = ((index + 1) * pageSize).clamp(0, total);
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(index),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected ? AppColors.brandNavy : AppColors.inputFill,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CustomText(
                            '${index + 1}',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: selected ? Colors.white : AppColors.brandNavy,
                          ),
                          CustomText(
                            '$from–$to',
                            fontSize: 10,
                            color: selected ? Colors.white70 : AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
