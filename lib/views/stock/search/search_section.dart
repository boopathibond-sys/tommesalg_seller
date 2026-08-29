import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../controllers/inventory_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/inventory_location.dart';
import '../../../models/inventory_search.dart';
import '../../../models/inventory_tag.dart';
import '../../../models/location_suggestion.dart';
import '../../scanner/barcode_scanner_view.dart';
import '../shared/product_quick_view.dart';
import '../shared/stock_widgets.dart';
import '../sku_detail_view.dart';
import '../../../core/localization/translation_keys.dart';

/// The three warehouse-search modes the section can switch between.
enum _SearchMode { upc, tag, sku }

/// Opens the read-only quick view for a product hit (UPC / Tag results).
typedef _OpenProduct = void Function(
  SearchProduct product,
  List<SearchPlacement> placements,
);

/// Warehouse search — a single adaptive search box driven by a mode selector:
///
///  • **UPC** — numeric input + barcode scan → `/search/by-upc`
///  • **Tag** — tag slug → `/search/by-tag`
///  • **SKU** — live SKU code/name suggest → `/locations/suggest` (tap a hit to
///    open its detail page)
///
/// UPC and Tag share the product/location result renderer; SKU shows its own
/// tappable suggestion list.
class SearchSection extends StatefulWidget {
  const SearchSection({super.key, required this.ctrl});
  final InventoryController ctrl;

  @override
  SearchSectionState createState() => SearchSectionState();
}

class SearchSectionState extends State<SearchSection> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  _SearchMode _mode = _SearchMode.upc;

  /// Slug of the last tag picked from suggestions — used to re-run / retry the
  /// tag search.
  String? _selectedTagSlug;

  InventoryController get ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    // Fresh search each time the Search tab is opened.
    ctrl.clearSearch();
    ctrl.clearSuggestions();
    ctrl.clearTagSuggestions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectMode(_SearchMode mode) {
    if (_mode == mode) return;
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    _searchCtrl.clear();
    _selectedTagSlug = null;
    ctrl.clearSearch();
    ctrl.clearSuggestions();
    ctrl.clearTagSuggestions();
    setState(() => _mode = mode);
  }

  /// Runs the search for the active mode using the current field text. UPC
  /// searches outright; Tag/SKU only ever surface suggestions here (the actual
  /// search runs when the user taps a suggestion).
  void _runSearch() {
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    final q = _searchCtrl.text;
    switch (_mode) {
      case _SearchMode.upc:
        ctrl.searchByUpc(q);
        break;
      case _SearchMode.tag:
        ctrl.suggestTags(q);
        break;
      case _SearchMode.sku:
        ctrl.suggestLocations(q);
        break;
    }
  }

  /// Live, debounced suggestions while typing for Tag (tag suggest) and SKU
  /// (location suggest). UPC waits for the Search button / enter.
  void _onChanged(String value) {
    if (_mode == _SearchMode.upc) return;
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      if (_mode == _SearchMode.tag) {
        ctrl.clearTagSuggestions();
      } else {
        ctrl.clearSuggestions();
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (_mode == _SearchMode.tag) {
        ctrl.suggestTags(q);
      } else {
        ctrl.suggestLocations(q);
      }
    });
  }

  /// Picks a tag from the suggestions and runs the existing tag search with the
  /// selected tag's full slug. Clears the suggestion list so the results show.
  void _selectTag(InventoryTag tag) {
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    _searchCtrl.text = tag.label;
    _selectedTagSlug = tag.slug;
    ctrl.clearTagSuggestions();
    ctrl.searchByTag(tag.slug);
  }

  /// Re-runs the last tag search (results-area retry button).
  void _retryTagSearch() {
    final slug = _selectedTagSlug;
    if (slug != null) ctrl.searchByTag(slug);
  }

  /// Pull-to-refresh hook for the Search tab — re-runs the current search for
  /// the active mode using the last query / selected tag. No-ops when nothing
  /// has been searched yet.
  Future<void> refresh() async {
    switch (_mode) {
      case _SearchMode.upc:
        final q = _searchCtrl.text.trim();
        if (q.isNotEmpty) await ctrl.searchByUpc(q);
        break;
      case _SearchMode.tag:
        final slug = _selectedTagSlug;
        if (slug != null) await ctrl.searchByTag(slug);
        break;
      case _SearchMode.sku:
        final q = _searchCtrl.text.trim();
        if (q.isNotEmpty) await ctrl.suggestLocations(q);
        break;
    }
  }

  /// Opens the camera scanner, drops the scanned code into the field, and
  /// immediately runs the UPC search.
  Future<void> _scanUpc() async {
    final result = await Navigator.of(context).push<Barcode>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerView()),
    );
    if (result == null || !mounted) return;
    final raw = result.rawValue;
    if (raw == null || raw.isEmpty) return;
    _searchCtrl.text = raw;
    ctrl.searchByUpc(raw);
  }

  /// Opens the SKU detail page for a location id / code.
  Future<void> _openSkuDetail(String id, String code) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SkuDetailView(locationId: id, initialCode: code),
      ),
    );
  }

  Future<void> _openSku(LocationSuggestion s) => _openSkuDetail(s.id, s.code);

  /// Opens the read-only product quick view for a UPC / Tag product hit.
  void _openProductQuickView(
    SearchProduct product,
    List<SearchPlacement> placements,
  ) {
    FocusScope.of(context).unfocus();
    ProductQuickView.show(context, ctrl, product, placements);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _configFor(_mode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeSelector(mode: _mode, onChanged: _selectMode),
        const SizedBox(height: 14),
        CustomText(
          cfg.subtitle,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 12),
        _buildSearchCard(cfg),
        const SizedBox(height: 20),
        if (_mode == _SearchMode.sku)
          _SkuSuggestResults(ctrl: ctrl, onOpen: _openSku, onRetry: _runSearch)
        else if (_mode == _SearchMode.tag)
          _TagSearchResults(
            ctrl: ctrl,
            onRetry: _retryTagSearch,
            onOpenSku: (l) => _openSkuDetail(l.id, l.code),
            onOpenProduct: _openProductQuickView,
          )
        else
          _UpcTagResults(
            ctrl: ctrl,
            onRetry: _runSearch,
            onOpenSku: (l) => _openSkuDetail(l.id, l.code),
            onOpenProduct: _openProductQuickView,
          ),
      ],
    );
  }

  /// Adaptive search box: the input, a Scan button (UPC only), and Search.
  Widget _buildSearchCard(_ModeConfig cfg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      child: Column(
        children: [
          StockSearchField(
            controller: _searchCtrl,
            hint: cfg.hint,
            icon: cfg.icon,
            keyboardType: cfg.keyboard,
            onChanged: _onChanged,
            onSubmitted: (_) => _runSearch(),
          ),
          // Tag + SKU search are live while typing, so they need no action
          // buttons — only UPC keeps the Scan + Search row.
          if (_mode == _SearchMode.upc) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _ScanButton(onTap: _scanUpc)),
                const SizedBox(width: 10),
                Expanded(
                  child: StockPillButton(
                    icon: Icons.search_rounded,
                    label: TKeys.stSearch.tr,
                    onTap: _runSearch,
                    expanded: true,
                  ),
                ),
              ],
            ),
          ],
          // Tag suggestions live inline, inside the same search container.
          if (_mode == _SearchMode.tag) _buildInlineTagSuggestions(),
        ],
      ),
    );
  }

  /// The live tag-suggestion dropdown rendered inside the search card (under
  /// the field, separated by a divider). Hidden until a suggest query runs.
  Widget _buildInlineTagSuggestions() {
    return Obx(() {
      if (ctrl.isSuggestingTags) {
        return const Padding(
          padding: EdgeInsets.only(top: 14),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
            ),
          ),
        );
      }
      if (!ctrl.hasSuggestedTags) return const SizedBox.shrink();

      final tags = ctrl.tagSuggestions;
      if (tags.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: CustomText(
              TKeys.stNoMatchingTags.tr,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
        );
      }

      return Column(
        children: [
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.inputBorder),
          for (final t in tags)
            _TagSuggestRow(tag: t, onTap: () => _selectTag(t)),
        ],
      );
    });
  }
}

/// Per-mode field configuration (icon, hint, keyboard, subtitle copy).
class _ModeConfig {
  const _ModeConfig(this.icon, this.hint, this.keyboard, this.subtitle);
  final IconData icon;
  final String hint;
  final TextInputType keyboard;
  final String subtitle;
}

_ModeConfig _configFor(_SearchMode mode) {
  switch (mode) {
    case _SearchMode.upc:
      return _ModeConfig(
        Icons.qr_code_2_rounded,
        TKeys.stEnterOrScanUpc.tr,
        TextInputType.number,
        TKeys.stTypeUpcHint.tr,
      );
    case _SearchMode.tag:
      return _ModeConfig(
        Icons.sell_outlined,
        TKeys.stSearchTagsHint.tr,
        TextInputType.text,
        TKeys.stSearchTagBody.tr,
      );
    case _SearchMode.sku:
      return _ModeConfig(
        Icons.inventory_2_outlined,
        TKeys.stSearchSkuHint.tr,
        TextInputType.text,
        TKeys.stFindSkuByCode.tr,
      );
  }
}

/// Segmented control that switches between the UPC / Tag / SKU modes.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});
  final _SearchMode mode;
  final ValueChanged<_SearchMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _seg(_SearchMode.upc, Icons.qr_code_2_rounded, 'UPC'),
          _seg(_SearchMode.tag, Icons.sell_outlined, TKeys.stTag.tr),
          _seg(_SearchMode.sku, Icons.inventory_2_outlined, 'SKU'),
        ],
      ),
    );
  }

  Widget _seg(_SearchMode m, IconData icon, String label) {
    final selected = mode == m;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(m),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandNavy : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? AppColors.white : AppColors.textMuted),
              const SizedBox(width: 6),
              CustomText(
                label,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.white : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outlined "Scan" button shown only in UPC mode.
class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.brandNavy, width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner_rounded,
                size: 17, color: AppColors.brandNavy),
            const SizedBox(width: 7),
            CustomText(
              TKeys.stScan.tr,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ],
        ),
      ),
    );
  }
}

/// Result area for UPC / Tag searches — drives off [InventoryController]'s
/// shared `searchResult` state.
class _UpcTagResults extends StatelessWidget {
  const _UpcTagResults({
    required this.ctrl,
    required this.onRetry,
    required this.onOpenSku,
    required this.onOpenProduct,
  });
  final InventoryController ctrl;
  final VoidCallback onRetry;
  final ValueChanged<InventoryLocation> onOpenSku;
  final _OpenProduct onOpenProduct;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isSearching) return const _SearchLoading();

      final error = ctrl.searchError;
      if (error != null) {
        return StockStatsError(message: error, onRetry: onRetry);
      }

      if (!ctrl.hasSearched) {
        return _SearchPlaceholder(
          icon: Icons.search_rounded,
          message: TKeys.stEnterUpcOrTag.tr,
        );
      }

      final result = ctrl.searchResult;
      final items = result?.items ?? const <InventorySearchItem>[];
      if (items.isEmpty) {
        return _SearchPlaceholder(
          icon: Icons.search_off_rounded,
          message: TKeys.stNoMatchesFound.tr,
        );
      }

      return _SearchResults(
        result: result!,
        onOpenSku: onOpenSku,
        onOpenProduct: onOpenProduct,
      );
    });
  }
}

/// Result area for SKU search — the live `suggestions` list, rendered as
/// tappable rows that open the SKU detail page.
class _SkuSuggestResults extends StatelessWidget {
  const _SkuSuggestResults({
    required this.ctrl,
    required this.onOpen,
    required this.onRetry,
  });
  final InventoryController ctrl;
  final ValueChanged<LocationSuggestion> onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isSuggesting) return const _SearchLoading();

      final error = ctrl.suggestError;
      if (error != null) {
        return StockStatsError(message: error, onRetry: onRetry);
      }

      if (!ctrl.hasSuggested) {
        return _SearchPlaceholder(
          icon: Icons.search_rounded,
          message: TKeys.stSearchSkuToSee.tr,
        );
      }

      final items = ctrl.suggestions;
      if (items.isEmpty) {
        return _SearchPlaceholder(
          icon: Icons.search_off_rounded,
          message: TKeys.stNoSkusMatch.tr,
        );
      }

      return _ResultGroup(
        title: TKeys.stSkus.tr,
        count: items.length,
        rows: [
          for (final s in items)
            _SkuSuggestRow(suggestion: s, onTap: () => onOpen(s)),
        ],
      );
    });
  }
}

/// One tappable SKU suggestion row — code badge, name, chevron.
class _SkuSuggestRow extends StatelessWidget {
  const _SkuSuggestRow({required this.suggestion, required this.onTap});
  final LocationSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.brandNavy,
                borderRadius: BorderRadius.circular(7),
              ),
              child: CustomText(
                suggestion.code,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CustomText(
                suggestion.name.isNotEmpty ? suggestion.name : suggestion.code,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Result area for Tag search — the products/locations under the picked tag.
/// The live tag suggestions render inline inside the search card (see
/// [_SearchSectionState._buildInlineTagSuggestions]); this area stays empty
/// while the user is still choosing a tag.
class _TagSearchResults extends StatelessWidget {
  const _TagSearchResults({
    required this.ctrl,
    required this.onRetry,
    required this.onOpenSku,
    required this.onOpenProduct,
  });
  final InventoryController ctrl;
  final VoidCallback onRetry;
  final ValueChanged<InventoryLocation> onOpenSku;
  final _OpenProduct onOpenProduct;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Suggestions are showing in the card — keep the results area clear.
      if (ctrl.isSuggestingTags || ctrl.hasSuggestedTags) {
        return const SizedBox.shrink();
      }

      if (!ctrl.hasSearched) {
        return _SearchPlaceholder(
          icon: Icons.sell_outlined,
          message: TKeys.stSearchTagToList.tr,
        );
      }

      return _UpcTagResults(
        ctrl: ctrl,
        onRetry: onRetry,
        onOpenSku: onOpenSku,
        onOpenProduct: onOpenProduct,
      );
    });
  }
}

/// One tappable tag suggestion row — label badge and a chevron.
class _TagSuggestRow extends StatelessWidget {
  const _TagSuggestRow({required this.tag, required this.onTap});
  final InventoryTag tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.sell_outlined, size: 18, color: AppColors.brandNavy),
            const SizedBox(width: 10),
            Expanded(
              child: CustomText(
                tag.label,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Centered spinner shared by both result areas.
class _SearchLoading extends StatelessWidget {
  const _SearchLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
          ),
        ),
      ),
    );
  }
}

/// Renders the search result set grouped into separate sections — SKUs first,
/// then Products. Rows are light and compact (no per-item bordered cards);
/// each section is one soft container with thin dividers between rows.
/// Duplicate `placement` items (already covered by a `product` item) are
/// dropped to avoid showing the same product twice.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.result,
    required this.onOpenSku,
    required this.onOpenProduct,
  });
  final InventorySearchResult result;
  final ValueChanged<InventoryLocation> onOpenSku;
  final _OpenProduct onOpenProduct;

  @override
  Widget build(BuildContext context) {
    // SKUs / locations.
    final locations = result.items
        .where((i) => i.isLocation && i.location != null)
        .map((i) => i.location!)
        .toList();

    // Products (with their placements). A lone `placement` item is folded in
    // only when no matching `product` item already represents it.
    final productIds = <String>{};
    final products = <_ProductHit>[];
    for (final item in result.items) {
      if (item.isProduct && item.product != null) {
        productIds.add(item.product!.id);
        products.add(_ProductHit(item.product!, item.placements));
      }
    }
    for (final item in result.items) {
      if (item.isPlacement && item.product != null) {
        if (productIds.add(item.product!.id)) {
          products.add(_ProductHit(
            item.product!,
            item.placement != null ? [item.placement!] : const [],
          ));
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (locations.isNotEmpty) ...[
          _ResultGroup(
            title: TKeys.stSkus.tr,
            count: locations.length,
            rows: [
              for (final l in locations)
                _SkuRow(location: l, onTap: () => onOpenSku(l)),
            ],
          ),
          if (products.isNotEmpty) const SizedBox(height: 18),
        ],
        if (products.isNotEmpty)
          _ResultGroup(
            title: TKeys.productsLabel.tr,
            count: products.length,
            rows: [
              for (final p in products)
                _ProductRow(
                  hit: p,
                  onTap: () => onOpenProduct(p.product, p.placements),
                ),
            ],
          ),
      ],
    );
  }
}

/// A product + its placements, the shape rendered in the Products section.
class _ProductHit {
  const _ProductHit(this.product, this.placements);
  final SearchProduct product;
  final List<SearchPlacement> placements;
}

/// A titled section: a small header with a count, then one soft container
/// holding the rows separated by hairline dividers.
class _ResultGroup extends StatelessWidget {
  const _ResultGroup({
    required this.title,
    required this.count,
    required this.rows,
  });
  final String title;
  final int count;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CustomText(
              title.toUpperCase(),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(20),
              ),
              child: CustomText(
                '$count',
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.inputFill.withOpacity(0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  const Divider(
                      height: 1, indent: 14, endIndent: 14,
                      color: AppColors.inputBorder),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact SKU row — code badge, name, status dot, and tag slugs. Tapping
/// opens the SKU detail page for this location.
class _SkuRow extends StatelessWidget {
  const _SkuRow({required this.location, required this.onTap});
  final InventoryLocation location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final path = location.locationPath;
    final tags = location.tagSlugs;
    final meta = <String>[
      if (path.isNotEmpty) path,
      if (tags.isNotEmpty) tags.map((t) => '#$t').join(' '),
    ].join('  ·  ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.brandNavy,
                borderRadius: BorderRadius.circular(7),
              ),
              child: CustomText(
                location.code,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    location.name,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    CustomText(
                      meta,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: location.isActive
                    ? AppColors.mascotShadow
                    : AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Compact product row — name + UPC and a "Quick view" button, with small bin
/// chips for placements. The button opens the product quick view (info +
/// report-a-discrepancy).
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.hit, required this.onTap});
  final _ProductHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final product = hit.product;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checkroom_rounded,
                  size: 18, color: AppColors.brandNavy),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      product.name,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    CustomText(
                      'UPC ${product.upc ?? '—'}',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _QuickViewButton(onTap: onTap),
            ],
          ),
          if (hit.placements.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in hit.placements) _BinChip(placement: p),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Small navy "Quick view" text button shown on each product row.
class _QuickViewButton extends StatelessWidget {
  const _QuickViewButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.brandNavy,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_outlined, size: 14, color: AppColors.white),
            const SizedBox(width: 5),
            CustomText(
              TKeys.stQuickViewLower.tr,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.white,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny chip showing a bin code and quantity for a product placement.
class _BinChip extends StatelessWidget {
  const _BinChip({required this.placement});
  final SearchPlacement placement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.brandYellow.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomText(
            placement.locationCode,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.brandNavy,
          ),
          const SizedBox(width: 5),
          CustomText(
            '×${placement.quantity}',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
          if (placement.isPrimary) ...[
            const SizedBox(width: 4),
            const Icon(Icons.star_rounded, size: 12, color: AppColors.brandNavy),
          ],
        ],
      ),
    );
  }
}

/// Centered placeholder for the empty / not-yet-searched states.
class _SearchPlaceholder extends StatelessWidget {
  const _SearchPlaceholder({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppColors.textMuted.withOpacity(0.5)),
            const SizedBox(height: 10),
            CustomText(
              message,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              textAlign: TextAlign.center,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
