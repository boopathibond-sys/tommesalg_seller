import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../controllers/seller_products_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/seller_product.dart';
import '../../../models/seller_product_detail.dart';
import '../../../models/seller_product_preview.dart';
import 'edit_product_view.dart';
import 'product_common.dart';
import '../../../core/localization/translation_keys.dart';

/// Full-page product details, opened from the My Products grid's View button.
///
/// Carries the same sections, labels and values as the web console — Main
/// information, Pricing and auction, Shipping settings, Warehouse and
/// logistics, Extended description, System data — including the italic
/// "Not stated" placeholder for fields the catalog hasn't filled in.
///
/// The layout adapts to the space it is given rather than to a device class:
///
/// * **Phone** — the gallery is a collapsing header the sheet of sections
///   scrolls under, and Edit lives in a pinned bottom bar where a thumb can
///   reach it.
/// * **Large phone / small tablet** — the field grid goes from one column to
///   two.
/// * **Tablet & landscape (≥ 900pt)** — a two-pane split: the gallery and the
///   headline tiles stay put on the left while the sections scroll on the
///   right, three fields to a row.
///
/// Everything comes from `GET /api/v1/seller/products/{id}`. The `/preview`
/// payload is loaded alongside it for the size chart, which the detail
/// endpoint doesn't carry, and to prefill the edit form.
class ProductDetailView extends StatefulWidget {
  const ProductDetailView({
    super.key,
    required this.product,
    required this.ctrl,
    this.initialImages = const [],
  });

  final SellerProduct product;
  final SellerProductsController ctrl;

  /// Images the card already had — shown until the detail payload lands.
  final List<String> initialImages;

  @override
  State<ProductDetailView> createState() => _ProductDetailViewState();
}

class _ProductDetailViewState extends State<ProductDetailView> {
  final PageController _pageCtrl = PageController();
  int _page = 0;

  /// The live row for this product, falling back to the one we were pushed
  /// with. The row carries the price / status / visibility this page renders
  /// before the detail call lands, and an edit replaces it in the controller's
  /// list — reading it back by id (inside the `Obx` below) is what makes those
  /// fields refresh after a save instead of showing the values captured when
  /// the page was opened.
  SellerProduct get _product {
    for (final p in widget.ctrl.products) {
      if (p.id == widget.product.id) return p;
    }
    return widget.product;
  }

  @override
  void initState() {
    super.initState();
    widget.ctrl.loadDetail(_product.id);
    // Only the preview carries the size chart, and it's usually already cached
    // by the grid (it resolves card images through the same call).
    widget.ctrl.loadPreview(_product.id);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait([
      widget.ctrl.loadDetail(_product.id, force: true),
      widget.ctrl.loadPreview(_product.id, force: true),
    ]);
  }

  /// Opens the edit form prefilled with what we've already loaded. The
  /// controller refreshes the detail + preview + list itself after a
  /// successful PATCH, so the `Obx` below picks the new values up on return.
  Future<void> _onEdit() async {
    final preview = widget.ctrl.previewFor(_product.id) ??
        widget.ctrl.detailFor(_product.id)?.toPreview();

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProductView(
          product: _product,
          ctrl: widget.ctrl,
          preview: preview,
        ),
      ),
    );
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.brandNavy,
          duration: const Duration(seconds: 2),
          content: CustomText(
            TKeys.copiedSuffix.trParams({'label': label}),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _copy(TKeys.linkLabel.tr, url);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _Metrics.of(constraints.maxWidth);

        return Scaffold(
          backgroundColor: _canvas,
          // The split layout keeps a conventional bar; the phone layout uses a
          // collapsing one that belongs to the scroll view instead.
          appBar: metrics.split
              ? AppBar(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  elevation: 0,
                  title: Text(TKeys.productDetails.tr),
                  actions: [
                    _EditAction(onTap: _onEdit),
                    const SizedBox(width: 16),
                  ],
                )
              : null,
          bottomNavigationBar:
              metrics.split ? null : _EditBar(onTap: _onEdit),
          body: Obx(() {
            final detail = widget.ctrl.detailFor(_product.id);
            final preview = widget.ctrl.previewFor(_product.id);
            final loading = widget.ctrl.isLoadingDetail(_product.id);

            final images = detail?.imageUrls.isNotEmpty == true
                ? detail!.imageUrls
                : (preview?.imageUrls.isNotEmpty == true
                    ? preview!.imageUrls
                    : widget.initialImages);

            if (detail == null && loading) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2.4),
              );
            }

            final gallery = _Gallery(
              images: images,
              controller: _pageCtrl,
              // An edit can shrink the gallery, leaving the remembered page
              // past the end until the seller swipes — clamp so the counter
              // and dots can't read "4/2".
              page: images.isEmpty ? 0 : _page.clamp(0, images.length - 1),
              onPageChanged: (i) => setState(() => _page = i),
              status: detail?.status.isNotEmpty == true
                  ? detail!.status
                  : _product.status,
              isVisible: detail?.isVisible ?? _product.isVisible,
              rounded: metrics.split,
            );

            final sections = _sections(
              detail: detail,
              preview: preview,
              loading: loading,
              metrics: metrics,
            );

            return RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.brandNavy,
              child: metrics.split
                  ? _SplitLayout(
                      metrics: metrics,
                      gallery: gallery,
                      summary: _summaryPane(detail, metrics),
                      sections: sections,
                    )
                  : _StackedLayout(
                      metrics: metrics,
                      gallery: gallery,
                      title: (detail?.name.isNotEmpty ?? false)
                          ? detail!.name
                          : _product.name,
                      onEdit: _onEdit,
                      children: [
                        _TitleBlock(detail: detail, product: _product),
                        const SizedBox(height: 16),
                        _HeadlineTiles(
                          detail: detail,
                          product: _product,
                          metrics: metrics,
                        ),
                        const SizedBox(height: 26),
                        ...sections,
                      ],
                    ),
            );
          }),
        );
      },
    );
  }

  /// Left pane of the split layout: the title block and the headline tiles,
  /// which stay in view while the sections scroll.
  Widget _summaryPane(SellerProductDetail? detail, _Metrics metrics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleBlock(detail: detail, product: _product),
        const SizedBox(height: 18),
        _HeadlineTiles(detail: detail, product: _product, metrics: metrics),
      ],
    );
  }

  /// Every section below the header, in the web console's order.
  List<Widget> _sections({
    required SellerProductDetail? detail,
    required SellerProductPreview? preview,
    required bool loading,
    required _Metrics metrics,
  }) {
    final columns = metrics.columns;

    return [
      _SectionTitle(TKeys.mainInformation.tr, icon: Icons.badge_outlined),
      const SizedBox(height: 14),
      _InfoGrid(
        columns: columns,
        items: [
          _Info(
            TKeys.productId.tr,
            _product.id,
            span: true,
            onTap: () => _copy(TKeys.productId.tr, _product.id),
          ),
          _Info(TKeys.sexLabel.tr, detail?.gender),
          _Info(TKeys.mainCategory.tr, detail?.category),
          _Info(TKeys.subcategory.tr, detail?.subCategory),
          _Info(TKeys.fieldBrand.tr, detail?.brand),
          _Info(TKeys.tagsKeywords.tr, _list(detail?.tags)),
        ],
      ),
      const SizedBox(height: 26),

      _SectionTitle(TKeys.pricingAndAuction.tr, icon: Icons.sell_outlined),
      const SizedBox(height: 14),
      _InfoGrid(
        columns: columns,
        items: [
          _Info(TKeys.catalogPrice.tr, _money(detail?.regularPrice), accent: true),
          _Info(TKeys.fieldOriginalPrice.tr, _money(detail?.originalPrice)),
          _Info(TKeys.buyNowPrice.tr, _money(detail?.buyNowPrice), accent: true),
          _Info(TKeys.startingPriceAuction.tr, _money(detail?.startingPrice)),
          _Info(TKeys.bidStep.tr, _money(detail?.bidIncrement)),
          _Info(TKeys.fieldBottomPrice.tr, _money(detail?.bottomPrice)),
        ],
      ),
      const SizedBox(height: 26),

      _ShippingCard(detail: detail, onUpdate: _onEdit, metrics: metrics),
      const SizedBox(height: 26),

      _SectionTitle(
        TKeys.warehouseAndLogistics.tr,
        icon: Icons.warehouse_outlined,
      ),
      const SizedBox(height: 14),
      _InfoGrid(
        columns: columns,
        items: [
          _Info(TKeys.inStock.tr, detail?.stockCount?.toString(), accent: true),
          _Info(TKeys.referenceSku.tr, detail?.sku),
          _Info(TKeys.barcodeUpc.tr, detail?.upc),
          _Info(TKeys.searchBarcode.tr, detail?.barcodeLookup),
          _Info(TKeys.fieldWeight.tr, _weight(detail?.weight)),
          _Info(TKeys.fieldMaterial.tr, detail?.material),
          _Info(TKeys.mainColor.tr, detail?.colour),
          _Info(TKeys.availableSizes.tr, _list(detail?.sizesAvailable)),
          _Info(TKeys.colorSelection.tr, _list(detail?.colorsAvailable)),
          _Info(TKeys.vendorStyle.tr, detail?.vendorStyle),
        ],
      ),
      const SizedBox(height: 26),

      _SectionTitle(
        TKeys.extendedDescription.tr,
        icon: Icons.notes_rounded,
      ),
      const SizedBox(height: 14),
      _DescriptionBlock(
        title: TKeys.briefSummary.tr,
        body: detail?.shortDescription,
      ),
      const SizedBox(height: 12),
      _DescriptionBlock(
        title: TKeys.fullDescription.tr,
        body: detail?.description,
      ),
      if ((detail?.features ?? '').isNotEmpty) ...[
        const SizedBox(height: 12),
        _DescriptionBlock(title: TKeys.fieldFeatures.tr, body: detail!.features),
      ],
      if ((detail?.materialsAndCare ?? '').isNotEmpty) ...[
        const SizedBox(height: 12),
        _DescriptionBlock(
          title: TKeys.materialsAndCare.tr,
          body: detail!.materialsAndCare,
        ),
      ],
      if ((detail?.sellerNote ?? '').isNotEmpty) ...[
        const SizedBox(height: 12),
        _DescriptionBlock(title: TKeys.sellerNote.tr, body: detail!.sellerNote),
      ],
      if ((detail?.shippingAndReturns ?? '').isNotEmpty) ...[
        const SizedBox(height: 12),
        _DescriptionBlock(
          title: TKeys.shippingAndReturns.tr,
          body: detail!.shippingAndReturns,
        ),
      ],
      if (detail?.productReferralLink != null) ...[
        const SizedBox(height: 12),
        _LinkCard(
          url: detail!.productReferralLink!,
          onOpen: () => _openLink(detail.productReferralLink!),
          onCopy: () => _copy(TKeys.linkLabel.tr, detail.productReferralLink!),
        ),
      ],
      if (preview?.sizeChart?.found == true) ...[
        const SizedBox(height: 26),
        _SectionTitle(TKeys.sizeChart.tr, icon: Icons.straighten_rounded),
        const SizedBox(height: 14),
        _SizeChartCard(chart: preview!.sizeChart!),
      ],
      const SizedBox(height: 26),

      _SectionTitle(TKeys.systemData.tr, icon: Icons.dns_outlined),
      const SizedBox(height: 14),
      _InfoGrid(
        columns: columns,
        items: [
          _Info(TKeys.importFlag.tr, detail?.importTag),
          _Info(TKeys.distributedTo.tr, _sellers(detail?.assignedSellerCount)),
          _Info(
            TKeys.createdInCatalog.tr,
            _dateTime(detail?.createdAt ?? _product.createdAt),
          ),
          _Info(TKeys.lastSynced.tr, _dateTime(detail?.updatedAt)),
        ],
      ),
      if (detail == null && !loading) ...[
        const SizedBox(height: 20),
        _ErrorCard(onRetry: _refresh),
      ],
    ];
  }
}

/// Page background — a hair cooler than the cards, so every panel lifts off it.
const Color _canvas = Color(0xFFF5F6F8);

// ── Adaptive metrics ────────────────────────────────────────────────────────

/// What the available width buys us: how many fields fit side by side, how
/// much air to leave at the edges, and whether there's room for two panes.
class _Metrics {
  const _Metrics({
    required this.width,
    required this.columns,
    required this.pagePadding,
    required this.galleryHeight,
    required this.split,
  });

  final double width;

  /// Fields per row in an [_InfoGrid].
  final int columns;

  final double pagePadding;
  final double galleryHeight;

  /// True once there is room to keep the gallery beside the sections.
  final bool split;

  factory _Metrics.of(double width) {
    if (width >= 900) {
      return _Metrics(
        width: width,
        columns: 3,
        pagePadding: 28,
        galleryHeight: 420,
        split: true,
      );
    }
    if (width >= 620) {
      return _Metrics(
        width: width,
        columns: 3,
        pagePadding: 22,
        galleryHeight: 360,
        split: false,
      );
    }
    if (width >= 380) {
      return _Metrics(
        width: width,
        columns: 2,
        pagePadding: 16,
        galleryHeight: 330,
        split: false,
      );
    }
    return _Metrics(
      width: width,
      columns: 1,
      pagePadding: 14,
      galleryHeight: 300,
      split: false,
    );
  }
}

// ── Layouts ─────────────────────────────────────────────────────────────────

/// Phone layout: the gallery is a collapsing header, and the sections ride up
/// over it on a rounded sheet.
class _StackedLayout extends StatelessWidget {
  const _StackedLayout({
    required this.metrics,
    required this.gallery,
    required this.title,
    required this.onEdit,
    required this.children,
  });

  final _Metrics metrics;
  final Widget gallery;
  final String title;
  final VoidCallback onEdit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: metrics.galleryHeight,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          foregroundColor: AppColors.brandNavy,
          titleSpacing: 0,
          // Only the collapsed bar carries the name; expanded, the photo has
          // the stage to itself.
          title: _CollapsedTitle(title: title),
          flexibleSpace: FlexibleSpaceBar(background: gallery),
        ),
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: const Offset(0, -22),
            child: Container(
              decoration: const BoxDecoration(
                color: _canvas,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              padding: EdgeInsets.fromLTRB(
                metrics.pagePadding,
                20,
                metrics.pagePadding,
                26,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: AppColors.borderGrey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The product name, faded in as the header collapses so it never fights with
/// the photo underneath.
class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final deltaExtent = (settings?.maxExtent ?? 0) - (settings?.minExtent ?? 0);
    final t = deltaExtent <= 0
        ? 1.0
        : (1 - ((settings!.currentExtent - settings.minExtent) / deltaExtent))
            .clamp(0.0, 1.0);
    // Hold the name back until the header is nearly closed, then bring it in.
    final opacity = ((t - 0.65) / 0.35).clamp(0.0, 1.0);

    return Opacity(
      opacity: opacity,
      child: CustomText(
        title,
        fontSize: 15.5,
        fontWeight: FontWeight.w800,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        color: AppColors.textPrimary,
      ),
    );
  }
}

/// Tablet / landscape layout: gallery and headline tiles pinned on the left,
/// sections scrolling on the right.
class _SplitLayout extends StatelessWidget {
  const _SplitLayout({
    required this.metrics,
    required this.gallery,
    required this.summary,
    required this.sections,
  });

  final _Metrics metrics;
  final Widget gallery;
  final Widget summary;
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    final paneWidth = (metrics.width * 0.38).clamp(320.0, 460.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: paneWidth,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              metrics.pagePadding,
              metrics.pagePadding,
              metrics.pagePadding / 2,
              metrics.pagePadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: metrics.galleryHeight, child: gallery),
                const SizedBox(height: 20),
                summary,
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              metrics.pagePadding / 2,
              metrics.pagePadding,
              metrics.pagePadding,
              metrics.pagePadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sections,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Value formatting ────────────────────────────────────────────────────────

/// `1500` → `1,500.00 kr`, the same grouping the web page uses. Null stays
/// null so the field renders as "Not stated".
String? _money(num? value) {
  if (value == null) return null;

  final fixed = value.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final whole = fixed.substring(0, dot);
  final decimals = fixed.substring(dot);

  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '$grouped$decimals kr';
}

/// `800` → `NOK 800` for the headline tile — whole NOK, as the web shows it.
String _pricePoint(num? value) {
  if (value == null) return '—';
  return 'NOK ${value % 1 == 0 ? value.toInt() : value}';
}

/// Weight carries the catalog's own unit, matching the web page.
String? _weight(num? value) {
  if (value == null) return null;
  return '${value % 1 == 0 ? value.toInt() : value} kg';
}

String? _list(List<String>? values) =>
    (values == null || values.isEmpty) ? null : values.join(', ');

String? _sellers(int? count) {
  if (count == null) return null;
  return (count == 1 ? TKeys.sellerCount : TKeys.sellersCount)
      .trParams({'count': '$count'});
}

/// `2026-07-18T08:41:36Z` → `July 18, 2026, 10:41 AM` in the seller's own
/// timezone — the format the web page prints.
String? _dateTime(DateTime? value) {
  if (value == null) return null;
  final months = [
    TKeys.monthJanuary.tr, TKeys.monthFebruary.tr, TKeys.monthMarch.tr,
    TKeys.monthApril.tr, TKeys.monthMay.tr, TKeys.monthJune.tr,
    TKeys.monthJuly.tr, TKeys.monthAugust.tr, TKeys.monthSeptember.tr,
    TKeys.monthOctober.tr, TKeys.monthNovember.tr, TKeys.monthDecember.tr,
  ];

  final local = value.toLocal();
  final hour24 = local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  // Norwegian reads a 24-hour clock; English keeps AM/PM. The catalogue says
  // which, so a new language picks its own convention without touching this.
  final time = TKeys.dateClock24.tr == 'true'
      ? '${hour24.toString().padLeft(2, '0')}:$minute'
      : '${hour24 % 12 == 0 ? 12 : hour24 % 12}:$minute '
          '${hour24 < 12 ? 'AM' : 'PM'}';

  return TKeys.dateTimeFormat.trParams({
    'month': months[local.month - 1],
    'day': '${local.day}',
    'year': '${local.year}',
    'time': time,
  });
}

// ── Layout primitives ───────────────────────────────────────────────────────

/// Section heading: a brand-yellow marker, the title, and a hairline running
/// out to the edge.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.brandYellow,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandYellow.withOpacity(0.5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 16, color: AppColors.brandNavy),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: CustomText(
            title,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Container(height: 1, color: AppColors.borderGrey),
        ),
      ],
    );
  }
}

/// One label / value pair inside a section.
class _Info {
  const _Info(
    this.label,
    this.value, {
    this.span = false,
    this.accent = false,
    this.onTap,
  });

  final String label;

  /// Null or blank renders as the italic "Not stated" placeholder.
  final String? value;

  /// Takes the full row instead of one column — for long values like the id.
  final bool span;

  /// Headline figures (prices the seller trades on, stock) get the yellow
  /// edge so the eye lands on them first.
  final bool accent;

  final VoidCallback? onTap;
}

/// Field grid that reflows to [columns], with spanning entries on their own
/// row. Every cell is its own tile, so a one-column phone still reads as a
/// list of cards rather than a wall of text.
class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items, required this.columns});

  final List<_Info> items;
  final int columns;

  @override
  Widget build(BuildContext context) {
    const gap = 10.0;
    final rows = <Widget>[];
    var i = 0;

    while (i < items.length) {
      if (items[i].span || columns == 1) {
        rows.add(_InfoCell(items[i]));
        i += 1;
        continue;
      }

      final group = <_Info>[];
      while (group.length < columns && i < items.length && !items[i].span) {
        group.add(items[i]);
        i += 1;
      }

      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) const SizedBox(width: gap),
              Expanded(
                child: c < group.length
                    ? _InfoCell(group[c])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: gap),
          IntrinsicHeight(child: rows[r]),
        ],
      ],
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell(this.item);

  final _Info item;

  @override
  Widget build(BuildContext context) {
    final value = item.value?.trim();
    final stated = value != null && value.isNotEmpty;
    final accent = item.accent && stated;

    final tile = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent
              ? AppColors.brandYellow.withOpacity(0.9)
              : AppColors.borderGrey,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: accent ? AppColors.brandYellow : AppColors.borderGrey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: CustomText(
                  item.label.toUpperCase(),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: CustomText(
                  stated ? value : TKeys.notStated.tr,
                  fontSize: 13.5,
                  height: 1.35,
                  fontWeight: stated ? FontWeight.w700 : FontWeight.w500,
                  fontStyle: stated ? FontStyle.normal : FontStyle.italic,
                  color: stated
                      ? AppColors.textPrimary
                      : AppColors.textMuted.withOpacity(0.75),
                ),
              ),
              if (item.onTap != null && stated)
                const Padding(
                  padding: EdgeInsets.only(left: 8, top: 2),
                  child: Icon(Icons.copy_rounded,
                      size: 13, color: AppColors.textMuted),
                ),
            ],
          ),
        ],
      ),
    );

    if (item.onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: item.onTap,
        child: tile,
      ),
    );
  }
}

/// White rounded panel used by the shipping, description and chart blocks.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGrey),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── Sections ────────────────────────────────────────────────────────────────

/// Product name with the status / visibility chips.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.detail, required this.product});

  final SellerProductDetail? detail;
  final SellerProduct product;

  @override
  Widget build(BuildContext context) {
    final name =
        (detail?.name.isNotEmpty ?? false) ? detail!.name : product.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((detail?.brand ?? '').isNotEmpty) ...[
          CustomText(
            detail!.brand!.toUpperCase(),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 6),
        ],
        CustomText(
          name,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1.18,
          color: AppColors.textPrimary,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusChip(
              status: detail?.status.isNotEmpty == true
                  ? detail!.status
                  : product.status,
              large: true,
            ),
            VisibilityBadge(
              isVisible: detail?.isVisible ?? product.isVisible,
              chip: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// `INVENTORY 14` and `PRICE POINT NOK 800` — the web page's headline tiles,
/// stacked when there isn't width for both.
class _HeadlineTiles extends StatelessWidget {
  const _HeadlineTiles({
    required this.detail,
    required this.product,
    required this.metrics,
  });

  final SellerProductDetail? detail;
  final SellerProduct product;
  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final inventory = _Tile(
      label: TKeys.inventoryCaps.tr,
      value: detail?.stockCount?.toString() ?? '—',
      icon: Icons.inventory_2_outlined,
    );
    final price = _Tile(
      label: TKeys.pricePointCaps.tr,
      value: _pricePoint(detail?.effectivePrice ?? product.effectivePrice),
      icon: Icons.local_offer_outlined,
      highlighted: true,
    );

    // A very narrow phone gets them stacked rather than squeezed.
    if (metrics.width < 340) {
      return Column(
        children: [inventory, const SizedBox(height: 12), price],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: inventory),
          const SizedBox(width: 12),
          Expanded(child: price),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.icon,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final IconData icon;

  /// The price tile wears the brand gradient; inventory stays white.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: highlighted ? null : Colors.white,
        gradient: highlighted
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandYellow, Color(0xFFFFC93D)],
              )
            : null,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted ? Colors.transparent : AppColors.borderGrey,
        ),
        boxShadow: [
          BoxShadow(
            color: highlighted
                ? AppColors.brandYellow.withOpacity(0.45)
                : AppColors.brandNavy.withOpacity(0.04),
            blurRadius: highlighted ? 18 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: highlighted
                    ? AppColors.brandNavy
                    : AppColors.textMuted,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: CustomText(
                  label,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  color: highlighted
                      ? AppColors.brandNavy.withOpacity(0.75)
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CustomText(
              value,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.05,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The web page's LOGISTICS panel: which shipping price applies, the daily
/// free-shipping limit, and a way through to change it.
class _ShippingCard extends StatelessWidget {
  const _ShippingCard({
    required this.detail,
    required this.onUpdate,
    required this.metrics,
  });

  final SellerProductDetail? detail;
  final VoidCallback onUpdate;
  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final platform = detail?.platformShipping;
    final usesPlatform = !(detail?.shippingOverrideEnabled ?? false);
    final platformPrice = platform?.defaultShippingPriceNok;
    final ownPrice = detail?.shippingPriceNok;
    final cap = platform?.dailyFreeShippingCapNok;
    final canOverride = platform?.allowSellerOverride ?? true;

    final button = _UpdateShippingButton(onTap: onUpdate, enabled: canOverride);
    final note = CustomText(
      cap == null
          ? TKeys.shippingPerOrder.tr
          : TKeys.freeShippingAt.trParams({'cap': _nok(cap)}),
      fontSize: 12.5,
      height: 1.45,
      color: AppColors.textMuted,
    );

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.brandNavy,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_shipping_outlined,
                    size: 16, color: AppColors.brandYellow),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      TKeys.logisticsCaps.tr,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 2),
                    CustomText(
                      TKeys.shippingSettings.tr,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: _canvas,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CheckMark(checked: usesPlatform),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomText(
                    usesPlatform
                        ? TKeys.useStandardShipping.trParams(
                            {'price': _nok(platformPrice ?? ownPrice)})
                        : TKeys.customShipping.trParams(
                            {'price': _nok(ownPrice ?? platformPrice)}),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (platform != null &&
              platform.allowedShippingAmountsNok.isNotEmpty) ...[
            const SizedBox(height: 14),
            CustomText(
              TKeys.allowedAmountsCaps.tr,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final amount in platform.allowedShippingAmountsNok)
                  _Pill(
                    _nok(amount),
                    selected: amount == (ownPrice ?? platformPrice),
                  ),
              ],
            ),
          ],
          if (platform?.maxShippingPerProductNok != null) ...[
            const SizedBox(height: 12),
            CustomText(
              '${TKeys.maximumPerProduct.tr} '
              '${_nok(platform!.maxShippingPerProductNok)}.',
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ],
          const SizedBox(height: 16),
          // Side by side where there's room; stacked on a narrow phone so the
          // button keeps its full width and the note stays readable.
          if (metrics.width < 380)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: double.infinity, child: button),
                const SizedBox(height: 12),
                note,
              ],
            )
          else
            Row(
              children: [
                button,
                const SizedBox(width: 14),
                Expanded(child: note),
              ],
            ),
        ],
      ),
    );
  }

  /// `99` → `99 NOK`, decimals kept only when they exist.
  static String _nok(num? value) {
    if (value == null) return '—';
    return '${value % 1 == 0 ? value.toInt() : value} NOK';
  }
}

/// Rounded amount chip; the one in force is filled in brand yellow.
class _Pill extends StatelessWidget {
  const _Pill(this.label, {this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? AppColors.brandYellow : _canvas,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.brandNavy.withOpacity(0.2)
              : AppColors.borderGrey,
        ),
      ),
      child: CustomText(
        label,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: selected ? AppColors.brandNavy : AppColors.textSecondary,
      ),
    );
  }
}

/// The filled checkbox the web panel shows beside the shipping choice.
class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: checked ? AppColors.primaryBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked ? AppColors.primaryBlue : AppColors.textMuted,
          width: 1.6,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
          : null,
    );
  }
}

/// Navy button with yellow type, as on the web panel. Opens the edit form,
/// where the shipping section lives.
class _UpdateShippingButton extends StatelessWidget {
  const _UpdateShippingButton({required this.onTap, this.enabled = true});

  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: AppColors.brandNavy,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.tune_rounded, size: 15,
                    color: AppColors.brandYellow),
                const SizedBox(width: 8),
                Flexible(
                  child: CustomText(
                    TKeys.updateShippingOptions.tr,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: AppColors.brandYellow,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One block of long-form copy — "Brief summary", "Full description", …
class _DescriptionBlock extends StatelessWidget {
  const _DescriptionBlock({required this.title, required this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final text = body?.trim();
    final stated = text != null && text.isNotEmpty;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.brandYellow,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: CustomText(
                  title,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CustomText(
            stated ? text : TKeys.notStated.tr,
            fontSize: 13.5,
            height: 1.55,
            fontWeight: FontWeight.w500,
            fontStyle: stated ? FontStyle.normal : FontStyle.italic,
            color: stated
                ? AppColors.textSecondary
                : AppColors.textMuted.withOpacity(0.75),
          ),
        ],
      ),
    );
  }
}

/// The product's referral link, with open + copy actions.
class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.url,
    required this.onOpen,
    required this.onCopy,
  });

  final String url;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            TKeys.referralLink.tr,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 10),
          CustomText(
            url,
            fontSize: 12.5,
            height: 1.4,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MiniButton(
                icon: Icons.open_in_new_rounded,
                label: TKeys.openAction.tr,
                onTap: onOpen,
              ),
              _MiniButton(
                icon: Icons.copy_rounded,
                label: TKeys.copyAction.tr,
                onTap: onCopy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _canvas,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.brandNavy),
              const SizedBox(width: 6),
              CustomText(
                label,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Size chart carried by the `/preview` payload.
class _SizeChartCard extends StatelessWidget {
  const _SizeChartCard({required this.chart});

  final SellerSizeChart chart;

  @override
  Widget build(BuildContext context) {
    final images = chart.images;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            chart.title ?? TKeys.sizeChart.tr,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 12),
          if (images.isEmpty)
            CustomText(
              TKeys.notStated.tr,
              fontSize: 13.5,
              fontStyle: FontStyle.italic,
              color: AppColors.textMuted,
            )
          else
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    images[i],
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 120,
                      height: 120,
                      color: _canvas,
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown when the detail call failed — the page still renders what the list
/// row knows, with a retry for the rest.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: CustomText(
              TKeys.couldNotLoadDetails.tr,
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: CustomText(
              TKeys.retryAction.tr,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned bottom action on the phone layout — a thumb-height Edit button that
/// doesn't make the seller scroll back to the top of a long page.
class _EditBar extends StatelessWidget {
  const _EditBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderGrey)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Material(
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [AppColors.primaryYellow, Color(0xFFFFC93D)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandYellow.withOpacity(0.5),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: SizedBox(
                  height: 50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.edit_rounded,
                          size: 17, color: AppColors.brandNavy),
                      const SizedBox(width: 8),
                      CustomText(
                        TKeys.editProductAction.tr,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandNavy,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact "Edit" pill for the split layout's app bar.
class _EditAction extends StatelessWidget {
  const _EditAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [AppColors.primaryYellow, AppColors.primaryOrange],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryOrange.withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.edit_rounded, size: 15, color: AppColors.brandNavy),
                  const SizedBox(width: 7),
                  CustomText(
                    TKeys.edit.tr,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Swipeable image strip with page dots, an index counter and the status /
/// visibility chips laid over it.
class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.images,
    required this.controller,
    required this.page,
    required this.onPageChanged,
    required this.status,
    required this.isVisible,
    this.rounded = true,
  });

  final List<String> images;
  final PageController controller;
  final int page;
  final ValueChanged<int> onPageChanged;
  final String status;
  final bool isVisible;

  /// Square corners when the gallery is the collapsing header; rounded when
  /// it sits as a card in the split layout.
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(rounded ? 18 : 0);

    if (images.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: rounded ? Border.all(color: AppColors.borderGrey) : null,
        ),
        child: const Icon(
          Icons.image_not_supported_outlined,
          color: AppColors.textMuted,
          size: 34,
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        color: Colors.white,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: controller,
              itemCount: images.length,
              onPageChanged: onPageChanged,
              itemBuilder: (_, i) => Image.network(
                images[i],
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppColors.brandNavy,
                          ),
                        ),
                      ),
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: AppColors.textMuted,
                    size: 34,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 56,
              left: 14,
              child: Row(
                children: [
                  StatusChip(status: status),
                  const SizedBox(width: 6),
                  if (!isVisible)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility_off_outlined,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          CustomText(
                            TKeys.hiddenLabel.tr,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (images.length > 1) ...[
              Positioned(
                top: 12,
                right: 14,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: CustomText(
                    '${page + 1}/${images.length}',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: i == page ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == page
                            ? AppColors.brandNavy
                            : AppColors.brandNavy.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
