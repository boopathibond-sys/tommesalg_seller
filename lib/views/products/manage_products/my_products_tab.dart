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

/// "My Products" tab — the seller's own catalog (`GET /api/v1/seller/products`)
/// as a compact two-column grid, with a search field and an All / Available /
/// Reserved / Sold status filter.
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
                  countFor: _ctrl.countFor,
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
                      (_ctrl.products.isEmpty
                          ? TKeys.noProductsYet.tr
                          : TKeys.noProductsMatch.tr),
                  isError: _ctrl.error != null,
                  onAction: _ctrl.error != null
                      ? () => _ctrl.fetchProducts(refresh: true)
                      : (_ctrl.products.isEmpty
                          ? null
                          : () {
                              _searchCtrl.clear();
                              _ctrl.clearFilters();
                            }),
                  actionLabel: _ctrl.error != null ? TKeys.retryAction.tr : TKeys.clearFilters.tr,
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.60,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _ProductCard(
                      product: products[index],
                      ctrl: _ctrl,
                    ),
                    childCount: products.length,
                  ),
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
    required this.countFor,
  });

  final TextEditingController searchCtrl;
  final String status;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onStatusChanged;
  final int Function(String) countFor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
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
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: TKeys.filterByStatus.tr,
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: onStatusChanged,
          itemBuilder: (_) => SellerProductsController.statusOptions
              .map(
                (option) => PopupMenuItem<String>(
                  value: option,
                  height: 40,
                  child: Row(
                    children: [
                      Icon(
                        option == status
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 17,
                        color: option == status
                            ? AppColors.brandNavy
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      CustomText(
                        statusLabel(option),
                        fontSize: 13,
                        fontWeight: option == status
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      const Spacer(),
                      CustomText(
                        '${countFor(option)}',
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: status == 'ALL'
                  ? AppColors.inputFill
                  : AppColors.brandYellow.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: status == 'ALL'
                    ? Colors.transparent
                    : AppColors.brandNavy.withOpacity(0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune_rounded,
                    size: 17, color: AppColors.brandNavy),
                const SizedBox(width: 6),
                CustomText(
                  statusLabel(status),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
                const Icon(Icons.arrow_drop_down_rounded,
                    size: 18, color: AppColors.brandNavy),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid card — swipeable images on top, compact details underneath
// ─────────────────────────────────────────────────────────────────────────────
class _ProductCard extends StatefulWidget {
  const _ProductCard({required this.product, required this.ctrl});

  final SellerProduct product;
  final SellerProductsController ctrl;

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

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final images = widget.ctrl.imagesFor(_product);
      final resolving = widget.ctrl.isResolvingImages(_product.id);

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.grey.withOpacity(0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The details block takes the height it needs; the image gets
            // whatever is left, so a two-line name can never overflow the tile.
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: AppColors.inputFill,
                      child: images.isEmpty
                          ? Center(
                              child: resolving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(
                                      Icons.image_not_supported_outlined,
                                      color: AppColors.textMuted,
                                      size: 26,
                                    ),
                            )
                          : PageView.builder(
                              controller: _pageCtrl,
                              itemCount: images.length,
                              onPageChanged: (i) => setState(() => _page = i),
                              itemBuilder: (_, i) => Image.network(
                                images[i],
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                    color: AppColors.textMuted,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: StatusChip(status: _product.status),
                  ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 6,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          images.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            width: i == _page ? 12 : 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    // Two lines' worth of room so cards in a row stay aligned
                    // whether the name wraps or not.
                    height: 30,
                    width: double.infinity,
                    child: CustomText(
                      _product.name,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  VisibilityBadge(isVisible: _product.isVisible),
                  const SizedBox(height: 6),
                  CustomText(
                    TKeys.buyNowPrice.tr,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: CustomText(
                          formatPrice(_product.effectivePrice),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (_product.hasDiscount) ...[
                        const SizedBox(width: 5),
                        Flexible(
                          child: CustomText(
                            formatPrice(_product.originalPrice),
                            fontSize: 10,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: AppColors.textMuted,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  CustomText(
                    formatDate(_product.createdAt),
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 26,
                    child: TextButton.icon(
                      onPressed: () => _openDetails(images),
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.brandNavy.withOpacity(0.08),
                        foregroundColor: AppColors.brandNavy,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
                      label: CustomText(
                        TKeys.viewAction.tr,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
