import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../controllers/seller_products_controller.dart';
import '../../../../core/config/get_or_put.dart';
import '../../../../core/localization/translation_keys.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../../../models/seller_product.dart';
import '../../../../views/products/manage_products/product_detail_view.dart';
import '../../data/models/auction_room_snapshot.dart';

/// Shipping tier the server means by `shippingPriceNok` 0 / null.
const num _standardShipping = 99;

/// Width from which the quick view is a centred two-pane dialog (gallery left,
/// details right) instead of a bottom sheet.
const double _splitBreakpoint = 700;

/// Quick view of a product in the stream's auction queue, opened by tapping
/// its image or name. Everything shown comes from the queue item in the
/// auction-room snapshot, so it opens instantly; "View details" leads to the
/// full product page.
///
/// Adapts to the space available: a draggable bottom sheet on phones, a
/// two-pane dialog on tablets and in landscape.
Future<void> showQueueProductQuickView(
  BuildContext context,
  AuctionProduct product, {
  String? upc,
}) {
  upc ??= product.upc;
  final width = MediaQuery.sizeOf(context).width;
  if (width >= _splitBreakpoint) {
    return showDialog<void>(
      context: context,
      builder: (_) => _QuickViewDialog(product: product, upc: upc),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuickViewSheet(product: product, upc: upc),
  );
}

/// Closes the quick view and opens the full product page.
void _openDetails(BuildContext context, AuctionProduct p) {
  final navigator = Navigator.of(context);
  navigator.pop();
  navigator.push(
    MaterialPageRoute(
      builder: (_) => ProductDetailView(
        // The page reloads everything by id; this row only fills the header
        // until `GET /seller/products/{id}` lands.
        product: SellerProduct(
          id: p.productId,
          name: p.title,
          status: '',
          isVisible: true,
          originalPrice: p.originalPrice,
          images: p.gallery,
        ),
        ctrl: getOrPut(() => SellerProductsController()),
        initialImages: p.gallery,
      ),
    ),
  );
}

// ── Phone: bottom sheet ──────────────────────────────────────────────────────

class _QuickViewSheet extends StatelessWidget {
  const _QuickViewSheet({required this.product, this.upc});
  final AuctionProduct product;
  final String? upc;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 1,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            // Grabber centred, close button on the right.
            Stack(
              alignment: Alignment.topCenter,
              children: [
                const _Grabber(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 6),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  _Gallery(product: product, maxHeight: 360),
                  const SizedBox(height: 16),
                  _Details(product: product, upc: upc),
                ],
              ),
            ),
            _Footer(product: product),
          ],
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.borderGrey,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ── Tablet / landscape: two-pane dialog ──────────────────────────────────────

class _QuickViewDialog extends StatelessWidget {
  const _QuickViewDialog({required this.product, this.upc});
  final AuctionProduct product;
  final String? upc;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: AppColors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 960,
          maxHeight: size.height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textSecondary),
              ),
            ),
            Flexible(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 10, 20),
                      child: _Gallery(
                        product: product,
                        maxHeight: size.height * 0.6,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(10, 0, 24, 20),
                      child: _Details(product: product, upc: upc),
                    ),
                  ),
                ],
              ),
            ),
            _Footer(product: product),
          ],
        ),
      ),
    );
  }
}

// ── Gallery ──────────────────────────────────────────────────────────────────

/// Swipeable main image with a page counter and a thumbnail strip below.
/// Tapping the image opens it full screen with pinch-to-zoom.
class _Gallery extends StatefulWidget {
  const _Gallery({required this.product, required this.maxHeight});
  final AuctionProduct product;
  final double maxHeight;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    _pages.animateToPage(i,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.product.gallery;
    return LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth.clamp(0.0, widget.maxHeight);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: side,
                height: side,
                color: AppColors.inputFill,
                child: images.isEmpty
                    ? const Icon(Icons.shopping_bag_outlined,
                        size: 48, color: AppColors.textMuted)
                    : Stack(
                        children: [
                          PageView.builder(
                            controller: _pages,
                            itemCount: images.length,
                            onPageChanged: (i) => setState(() => _index = i),
                            itemBuilder: (_, i) => GestureDetector(
                              onTap: () => _openFullScreen(context, images, i),
                              child: _NetImage(images[i], fit: BoxFit.contain),
                            ),
                          ),
                          if (images.length > 1)
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.brandNavy.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: CustomText(
                                  '${_index + 1}/${images.length}',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          if (images.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final selected = i == _index;
                  return GestureDetector(
                    onTap: () => _goTo(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 56,
                      decoration: BoxDecoration(
                        color: AppColors.inputFill,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppColors.brandNavy
                              : AppColors.borderGrey,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _NetImage(images[i], fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      );
    });
  }

  void _openFullScreen(BuildContext context, List<String> images, int start) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenGallery(images: images, initial: start),
      ),
    );
  }
}

class _FullScreenGallery extends StatefulWidget {
  const _FullScreenGallery({required this.images, required this.initial});
  final List<String> images;
  final int initial;

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: widget.images.length > 1
            ? CustomText('${_index + 1}/${widget.images.length}',
                fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)
            : null,
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 4,
          child:
              Center(child: _NetImage(widget.images[i], fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

class _NetImage extends StatelessWidget {
  const _NetImage(this.url, {required this.fit});
  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.image_outlined, color: AppColors.textMuted),
      ),
    );
  }
}

// ── Details ──────────────────────────────────────────────────────────────────

class _Details extends StatelessWidget {
  const _Details({required this.product, this.upc});
  final AuctionProduct product;
  final String? upc;

  String _shipping(num? v) {
    if (v == null || v == 0) {
      return TKeys.shippingStandardSuffix
          .trParams({'price': formatNok(_standardShipping)});
    }
    return formatNok(v);
  }

  @override
  Widget build(BuildContext context) {
    final p = product;
    final stock = p.stockCount;
    // Taxonomy path, most general first, without repeats.
    final path = <String>[];
    for (final part in [
      p.parentCategory,
      p.category,
      p.mainCategory,
      p.subCategory,
      p.subItem,
    ]) {
      if (part != null && !path.contains(part)) path.add(part);
    }

    final tiles = <(String, String)>[
      if (p.startingPrice != null)
        (TKeys.fieldStartingPrice.tr, formatNok(p.startingPrice!)),
      if (p.bottomPrice != null)
        (TKeys.fieldBottomPrice.tr, formatNok(p.bottomPrice!)),
      if (p.bidIncrement != null)
        (TKeys.qvBidIncrement.tr, formatNok(p.bidIncrement!)),
      (TKeys.fieldShippingPrice.tr, _shipping(p.shippingPriceNok)),
      if (stock != null) (TKeys.qtStock.tr, '$stock'),
      if (upc != null && upc!.isNotEmpty) ('UPC', upc!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.brand != null)
          CustomText(p.brand!.toUpperCase(),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.textMuted),
        const SizedBox(height: 2),
        CustomText(p.title,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            height: 1.25,
            color: AppColors.textPrimary),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Pill(
              label: p.isDutch
                  ? TKeys.auctionTypeDutchCaps.tr
                  : TKeys.auctionTypeNormalCaps.tr,
              color: p.isDutch ? const Color(0xFF6A1B9A) : AppColors.brandNavy,
            ),
            if (stock != null)
              stock > 0
                  ? _Pill(
                      label: TKeys.qtUnitsLeft.trParams({'count': '$stock'}),
                      color: AppColors.brandNavy)
                  : _Pill(label: TKeys.qtSoldOut.tr, color: AppColors.vipps),
          ],
        ),
        if (p.originalPrice != null) ...[
          const SizedBox(height: 14),
          CustomText(
              TKeys.qtVeilPrisKr
                  .trParams({'price': formatNok(p.originalPrice!)}),
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          // Two tiles per row on a phone, three when there is room.
          final columns = c.maxWidth >= 420 ? 3 : 2;
          const gap = 8.0;
          final w = (c.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final t in tiles)
                SizedBox(width: w, child: _InfoTile(label: t.$1, value: t.$2)),
            ],
          );
        }),
        if (p.remainingDefectQuantity > 0) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.vipps.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.vipps.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.report_gmailerrorred_rounded,
                    size: 18, color: AppColors.vipps),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomText(
                    [
                      TKeys.qvDefectUnits
                          .trParams({'count': '${p.remainingDefectQuantity}'}),
                      if (p.defectDescription != null) p.defectDescription!,
                    ].join('\n'),
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (path.isNotEmpty) ...[
          _SectionLabel(TKeys.qvCategory.tr),
          CustomText(path.join('  ›  '),
              fontSize: 13, height: 1.4, color: AppColors.textSecondary),
        ],
        if (p.sizesAvailable.isNotEmpty) ...[
          _SectionLabel(TKeys.fieldSizesAvailable.tr),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in p.sizesAvailable)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.inputFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderGrey),
                  ),
                  child: CustomText(s,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
            ],
          ),
        ],
        if (p.description != null) ...[
          _SectionLabel(TKeys.fieldDescription.tr),
          CustomText(p.description!,
              fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: CustomText(text,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(label,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              color: AppColors.textMuted),
          const SizedBox(height: 3),
          CustomText(value,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              color: AppColors.textPrimary),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomText(label,
          fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
    );
  }
}

// ── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({required this.product});
  final AuctionProduct product;

  @override
  Widget build(BuildContext context) {
    // Random lots are stream-only and have no product page.
    if (product.isRandom || product.productId.isEmpty) {
      return const SizedBox(height: 8);
    }
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderGrey)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            // Full width on a phone; a normal-sized button in the dialog.
            constraints: const BoxConstraints(maxWidth: 420),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _openDetails(context, product),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandNavy,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.open_in_new_rounded,
                    size: 18, color: AppColors.brandYellow),
                label: CustomText(TKeys.qvViewDetails.tr,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
