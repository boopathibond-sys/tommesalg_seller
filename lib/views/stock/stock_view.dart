import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/inventory_controller.dart';
import '../../controllers/stock_nav_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/branded_refresh_indicator.dart';
import '../../core/widgets/custom_text.dart';
import 'assign/assign_section.dart';
import 'overview/overview_section.dart';
import 'search/search_section.dart';
import 'shared/stock_segment.dart';
import 'skus/skus_section.dart';
import 'widgets/new_sku_dialog.dart';
import '../../core/localization/translation_keys.dart';

/// Warehouse / Stock tab.
///
/// Mobile-adaptive port of the web "Warehouse" page: a header, a horizontally
/// scrollable segment bar (Overview · SKUs · Assign to SKU · Search · Activity),
/// and a switched body. Each segment lives in its own sub-directory under
/// `lib/views/stock/`; shared chrome (search field, pill button, stat cards,
/// error card) lives in `shared/`.
class StockView extends StatefulWidget {
  const StockView({super.key});

  @override
  State<StockView> createState() => _StockViewState();
}

class _StockViewState extends State<StockView> {
  StockSegment _segment = StockSegment.overview;

  final _inventoryCtrl = getOrPut(() => InventoryController());
  final _nav = getOrPut(() => StockNavController());
  Worker? _navWorker;

  // Keys onto the Assign / Search sections so pull-to-refresh can ask the
  // currently-visible section to re-run its own page's APIs.
  final _assignKey = GlobalKey<AssignSectionState>();
  final _searchKey = GlobalKey<SearchSectionState>();

  @override
  void initState() {
    super.initState();
    // React to cross-tab requests (e.g. Home quick actions) asking us to jump
    // to a segment and optionally open the New SKU dialog.
    _navWorker = ever<StockSegment?>(_nav.requestedSegment, _handleNavRequest);
    // Handle a request that may have been queued before this worker attached.
    if (_nav.requestedSegment.value != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleNavRequest(_nav.requestedSegment.value),
      );
    }
  }

  @override
  void dispose() {
    _navWorker?.dispose();
    super.dispose();
  }

  /// Switches to the requested segment and, when asked, opens the New SKU
  /// dialog once the tab is on screen. Marks the request handled via
  /// [StockNavController.consume].
  void _handleNavRequest(StockSegment? seg) {
    if (seg == null || !mounted) return;
    final openCreate = _nav.openCreateSku.value;
    _nav.consume();
    setState(() => _segment = seg);
    if (openCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) NewSkuDialog.show(context, _inventoryCtrl);
      });
    }
  }

  void _go(StockSegment s) => setState(() => _segment = s);

  /// Pull-to-refresh: re-runs the API(s) backing whichever segment is on
  /// screen — Overview/SKUs reload the warehouse stats, while Assign and Search
  /// delegate to their sections (selected SKU's products + pending, or the last
  /// search respectively).
  Future<void> _onRefresh() async {
    switch (_segment) {
      case StockSegment.overview:
      case StockSegment.skus:
        await _inventoryCtrl.fetchStats();
        break;
      case StockSegment.assign:
        await _assignKey.currentState?.refresh();
        break;
      case StockSegment.search:
        await _searchKey.currentState?.refresh();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandedRefreshIndicator(
      onRefresh: _onRefresh,
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  TKeys.stWarehouse.tr,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 6),
                CustomText(
                  TKeys.stWarehouseSub.tr,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Segment bar (horizontally scrollable pills) ──────────────────
          _SegmentBar(selected: _segment, onSelect: _go),

          const SizedBox(height: 16),

          // ── Body ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _body(),
          ),

          const SizedBox(height: 32),
        ],
      ),
      ),
    );
  }

  Widget _body() {
    switch (_segment) {
      case StockSegment.overview:
        return OverviewSection(ctrl: _inventoryCtrl, onOpenSegment: _go);
      case StockSegment.skus:
        return SkusSection(ctrl: _inventoryCtrl, onOpenSegment: _go);
      case StockSegment.assign:
        return AssignSection(key: _assignKey, ctrl: _inventoryCtrl);
      case StockSegment.search:
        return SearchSection(key: _searchKey, ctrl: _inventoryCtrl);
      // case StockSegment.activity:
      //   return const ActivitySection();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Segment bar
// ─────────────────────────────────────────────────────────────────────────────
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.selected, required this.onSelect});
  final StockSegment selected;
  final ValueChanged<StockSegment> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: StockSegment.values.map((s) {
          final active = s == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: active ? AppColors.brandNavy : AppColors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: active
                        ? AppColors.brandNavy
                        : AppColors.inputBorder,
                    width: 1,
                  ),
                ),
                child: CustomText(
                  s.label.toUpperCase(),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: active ? AppColors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
