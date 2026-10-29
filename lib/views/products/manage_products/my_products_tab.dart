import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/seller_products_controller.dart';
import '../../../core/config/get_or_put.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/branded_loading_view.dart';
import '../../../core/widgets/branded_refresh_indicator.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/seller_product.dart';
import 'product_common.dart';
import 'product_detail_view.dart';
import '../../../core/localization/translation_keys.dart';

/// "My Products" tab — the mobile twin of the web "Mine produkter" page:
/// every product the seller scanned into their stream requests
/// (`GET /api/v1/seller/products`) as a compact grid, with a search field and
/// status / size filters that are all applied on the server.
class MyProductsTab extends StatefulWidget {
  const MyProductsTab({super.key});

  @override
  State<MyProductsTab> createState() => _MyProductsTabState();
}

class _MyProductsTabState extends State<MyProductsTab> {
  final _ctrl = getOrPut(() => SellerProductsController());
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = _ctrl.query;
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Pulls the next page as the grid nears its end.
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final position = _scrollCtrl.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _ctrl.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandedRefreshIndicator(
      onRefresh: () => _ctrl.fetchProducts(refresh: true),
      child: Obx(() {
        final products = _ctrl.filteredProducts;
        final loading = _ctrl.isLoading;

        return CustomScrollView(
          controller: _scrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: _FilterBar(
                  searchCtrl: _searchCtrl,
                  status: _ctrl.statusFilter,
                  onQueryChanged: _ctrl.setQuery,
                  onStatusChanged: _ctrl.setStatusFilter,
                  size: _ctrl.sizeFilter,
                  sizes: _ctrl.availableSizes,
                  onSizeChanged: _ctrl.setSizeFilter,
                ),
              ),
            ),
            if (loading && _ctrl.products.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: BrandedLoadingView(),
              )
            else if (products.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyProducts(
                  message: _ctrl.error ??
                      (_ctrl.hasFilters
                          ? TKeys.noProductsMatch.tr
                          : TKeys.noProductsYet.tr),
                  isError: _ctrl.error != null,
                  onAction: _ctrl.error != null
                      ? () => _ctrl.fetchProducts(refresh: true)
                      : (_ctrl.hasFilters
                          ? () {
                              _searchCtrl.clear();
                              _ctrl.clearFilters();
                            }
                          : null),
                  actionLabel: _ctrl.error != null ? TKeys.retryAction.tr : TKeys.clearFilters.tr,
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                // Column count follows the available width so the grid reads
                // well from a small phone up to a tablet in landscape; the
                // tile height follows the column width (square image) plus a
                // details block that grows with the system text scale.
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 12.0;
                    final width = constraints.crossAxisExtent;
                    final columns = (width / 190).floor().clamp(2, 6);
                    final tileWidth =
                        (width - spacing * (columns - 1)) / columns;
                    final textScale = MediaQuery.textScalerOf(context)
                        .scale(1)
                        .clamp(1.0, 1.4);
                    final detailsHeight = 136 * textScale;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        mainAxisExtent: tileWidth + detailsHeight,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _ProductCard(
                          product: products[index],
                          ctrl: _ctrl,
                          detailsHeight: detailsHeight,
                        ),
                        childCount: products.length,
                      ),
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                  child: Center(
                    child: _ctrl.isLoadingMore
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : CustomText(
                            _ctrl.hasMore
                                ? TKeys.scrollForMore.tr
                                : (products.length == 1
                                        ? TKeys.productCountOne
                                        : TKeys.productCountMany)
                                    .trParams({'count': '${products.length}'}),
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                  ),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search field + status filter menu
// ─────────────────────────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchCtrl,
    required this.status,
    required this.onQueryChanged,
    required this.onStatusChanged,
    required this.size,
    required this.sizes,
    required this.onSizeChanged,
  });

  final TextEditingController searchCtrl;
  final String status;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onStatusChanged;

  /// Selected size bucket; empty = all sizes.
  final String size;

  /// The server's `availableSizes`; empty hides the size menu.
  final List<String> sizes;
  final ValueChanged<String> onSizeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 42,
          child: TextField(
            controller: searchCtrl,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: TKeys.searchProducts.tr,
              hintStyle: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
              prefixIcon: const Icon(Icons.search_rounded,
                  size: 19, color: AppColors.textMuted),
              suffixIcon: searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 17),
                      color: AppColors.textMuted,
                      splashRadius: 16,
                      onPressed: () {
                        searchCtrl.clear();
                        onQueryChanged('');
                      },
                    ),
              filled: true,
              fillColor: AppColors.inputFill,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _FilterMenu(
                tooltip: TKeys.filterByStatus.tr,
                icon: Icons.tune_rounded,
                value: status,
                options: SellerProductsController.statusOptions,
                isAll: (v) => v == 'ALL',
                labelOf: statusLabel,
                onSelected: onStatusChanged,
              ),
            ),
            if (sizes.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _FilterMenu(
                  tooltip: TKeys.sizeLabel.tr,
                  icon: Icons.straighten_rounded,
                  value: size,
                  options: ['', ...sizes],
                  isAll: (v) => v.isEmpty,
                  labelOf: (v) => v.isEmpty ? TKeys.allSizes.tr : v,
                  onSelected: onSizeChanged,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// One filter dropdown (status or size) — a pill that turns yellow while a
/// non-"all" value is picked.
class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.tooltip,
    required this.icon,
    required this.value,
    required this.options,
    required this.isAll,
    required this.labelOf,
    required this.onSelected,
  });

  final String tooltip;
  final IconData icon;
  final String value;
  final List<String> options;
  final bool Function(String) isAll;
  final String Function(String) labelOf;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final all = isAll(value);
    return PopupMenuButton<String>(
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: onSelected,
      itemBuilder: (_) => options
          .map(
            (option) => PopupMenuItem<String>(
              value: option,
              height: 40,
              child: Row(
                children: [
                  Icon(
                    option == value
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 17,
                    color: option == value
                        ? AppColors.brandNavy
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  CustomText(
                    labelOf(option),
                    fontSize: 13,
                    fontWeight:
                        option == value ? FontWeight.w700 : FontWeight.w500,
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: all
              ? AppColors.inputFill
              : AppColors.brandYellow.withOpacity(0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: all
                ? Colors.transparent
                : AppColors.brandNavy.withOpacity(0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppColors.brandNavy),
            const SizedBox(width: 6),
            Expanded(
              child: CustomText(
                labelOf(value),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                color: AppColors.brandNavy,
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded,
                size: 18, color: AppColors.brandNavy),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid card — swipeable images on top, compact details underneath. The whole
// card is the tap target for the detail view.
// ─────────────────────────────────────────────────────────────────────────────
class _ProductCard extends StatefulWidget {
  const _ProductCard({
    required this.product,
    required this.ctrl,
    required this.detailsHeight,
  });

  final SellerProduct product;
  final SellerProductsController ctrl;

  /// Fixed by the grid so every card in a row lines up, whatever the name
  /// length.
  final double detailsHeight;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  final PageController _pageCtrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  SellerProduct get _product => widget.product;

  void _openDetails(List<String> images) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailView(
          product: _product,
          ctrl: widget.ctrl,
          initialImages: images,
        ),
      ),
    );
  }

  Widget _placeholder({bool loading = false}) => Center(
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.image_outlined,
                color: AppColors.textMuted.withOpacity(0.7),
                size: 30,
              ),
      );

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final images = widget.ctrl.imagesFor(_product);
      final resolving = widget.ctrl.isResolvingImages(_product.id);

      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderGrey),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandNavy.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openDetails(images),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image fills whatever the details block leaves over; the
                // grid sizes the tile so that's roughly a square.
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: AppColors.inputFill,
                          child: images.isEmpty
                              ? _placeholder(loading: resolving)
                              : PageView.builder(
                                  controller: _pageCtrl,
                                  itemCount: images.length,
                                  onPageChanged: (i) =>
                                      setState(() => _page = i),
                                  itemBuilder: (_, i) => Image.network(
                                    images[i],
                                    fit: BoxFit.cover,
                                    loadingBuilder: (_, child, progress) =>
                                        progress == null
                                            ? child
                                            : _placeholder(loading: true),
                                    errorBuilder: (_, __, ___) =>
                                        _placeholder(),
                                  ),
                                ),
                        ),
                      ),
                      // Soft scrim so the dots stay legible on light photos.
                      if (images.length > 1)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 36,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.28),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: StatusChip(status: _product.status),
                      ),
                      if (images.length > 1)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.photo_library_outlined,
                                    size: 11, color: Colors.white),
                                const SizedBox(width: 3),
                                CustomText(
                                  '${_page + 1}/${images.length}',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (images.length > 1)
                        Positioned(
                          bottom: 8,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                images.length.clamp(0, 6),
                                (i) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 2),
                                  width: i == _page.clamp(0, 5) ? 14 : 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: i == _page.clamp(0, 5)
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.55),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  height: widget.detailsHeight,
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomText(
                        _product.name,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        color: AppColors.textPrimary,
                      ),
                      const Spacer(),
                      CustomText(
                        TKeys.veilPris.tr.toUpperCase(),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Expanded(
                            child: CustomText(
                              formatPrice(_product.originalPrice),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              color: AppColors.brandNavy,
                            ),
                          ),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.brandYellow,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.arrow_forward_rounded,
                                size: 14, color: AppColors.brandNavy),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      CustomText(
                        '${TKeys.rrpLabel.tr} ${formatPrice(_product.msrp)}',
                        fontSize: 10.5,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          VisibilityBadge(isVisible: _product.isVisible),
                          const SizedBox(width: 6),
                          Expanded(
                            child: CustomText(
                              formatDate(_product.createdAt),
                              fontSize: 10,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts({
    required this.message,
    required this.isError,
    required this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool isError;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: (isError ? Colors.red : AppColors.brandNavy)
                    .withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isError ? Icons.wifi_off_rounded : Icons.inventory_2_outlined,
                size: 34,
                color: isError ? Colors.red : AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 16),
            CustomText(
              message,
              fontSize: 13.5,
              height: 1.45,
              textAlign: TextAlign.center,
              color: AppColors.textSecondary,
            ),
            if (onAction != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandNavy,
                  side: const BorderSide(color: AppColors.brandNavy),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: CustomText(
                  actionLabel,
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
