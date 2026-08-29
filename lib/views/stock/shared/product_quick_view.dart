import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../controllers/inventory_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/inventory_search.dart';
import '../../../models/product_request_model.dart';
import '../../../core/localization/translation_keys.dart';

/// Quick-insert discrepancy presets for the report field.
enum _DiscrepancyTag { size, color, picture, other }

/// "Quick view" for a product surfaced by a warehouse search (UPC / Tag
/// results in [SearchSection]).
///
/// Search hits only carry `{ id, name, upc }`, so on open this fetches the
/// richer catalog fields via [InventoryController.fetchQuickViewProduct]
/// (hero image, brand, prices, colour, sizes, description). Anything the
/// preview endpoint doesn't return falls back to the search hit's own data,
/// with unavailable specs shown as `-`.
///
/// Mirrors the SKU-detail [AssignedProductQuickView]: product info **plus** a
/// report-a-discrepancy section (message + preset tags + image upload). The
/// search hit can span several bins, so the report is filed at the product
/// level (no `locationId`).
class ProductQuickView extends StatefulWidget {
  const ProductQuickView({
    super.key,
    required this.ctrl,
    required this.product,
    this.placements = const [],
  });

  final InventoryController ctrl;
  final SearchProduct product;
  final List<SearchPlacement> placements;

  static Future<void> show(
    BuildContext context,
    InventoryController ctrl,
    SearchProduct product,
    List<SearchPlacement> placements,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => ProductQuickView(
        ctrl: ctrl,
        product: product,
        placements: placements,
      ),
    );
  }

  @override
  State<ProductQuickView> createState() => _ProductQuickViewState();
}

class _ProductQuickViewState extends State<ProductQuickView> {
  static const int _maxImages = 10;

  bool _loading = true;
  ProductRequestProduct? _product;

  // ---------- Report-a-discrepancy state ----------
  final TextEditingController _reportCtrl = TextEditingController();
  final List<XFile> _reportImages = <XFile>[];
  final List<String> _existingImageUrls = <String>[];
  final ImagePicker _picker = ImagePicker();
  bool _submitting = false;
  bool _loadingIssue = true;

  int get _totalImages => _existingImageUrls.length + _reportImages.length;

  SearchProduct get _hit => widget.product;

  @override
  void initState() {
    super.initState();
    _load();
    _loadIssue();
  }

  @override
  void dispose() {
    _reportCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final product = await widget.ctrl.fetchQuickViewProduct(_hit.id);
    if (!mounted) return;
    setState(() {
      _product = product;
      _loading = false;
    });
  }

  /// Loads any existing reported discrepancy for this product so the form
  /// prefills its message and previously-uploaded images.
  Future<void> _loadIssue() async {
    final issue = await widget.ctrl.fetchProductIssue(productId: _hit.id);
    if (!mounted) return;
    setState(() {
      if (issue != null) {
        _reportCtrl.text = issue.message;
        _existingImageUrls
          ..clear()
          ..addAll(issue.imageUrls);
      }
      _loadingIssue = false;
    });
  }

  // ---------- Report image handling ----------

  static const Set<String> _allowedImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  bool _isAllowedImage(XFile file) {
    final name = file.name.toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _allowedImageExtensions.contains(name.substring(dot + 1));
  }

  /// Asks the user to pick an image source, then captures / picks from it.
  Future<void> _addReportImages() async {
    if (_totalImages >= _maxImages) return;

    final source = await _chooseImageSource();
    if (source == null || !mounted) return;

    if (source == ImageSource.camera) {
      final shot = await _picker.pickImage(source: ImageSource.camera);
      _ingestPicked(shot == null ? const [] : [shot]);
    } else {
      final picked = await _picker.pickMultiImage();
      _ingestPicked(picked);
    }
  }

  /// Bottom sheet offering Camera or Gallery.
  Future<ImageSource?> _chooseImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.inputBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.brandNavy),
              title: CustomText(TKeys.cameraSource.tr,
                  fontSize: 15, fontWeight: FontWeight.w700),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.brandNavy),
              title: CustomText(TKeys.gallerySource.tr,
                  fontSize: 15, fontWeight: FontWeight.w700),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Validates + appends picked images, respecting the max + allowed types.
  void _ingestPicked(List<XFile> picked) {
    if (picked.isEmpty || !mounted) return;
    final remaining = _maxImages - _totalImages;
    if (remaining <= 0) return;

    final allowed = picked.where(_isAllowedImage).toList();
    final rejected = picked.length - allowed.length;

    if (rejected > 0) {
      Get.snackbar(
        TKeys.unsupportedFile.tr,
        TKeys.onlyImageTypes.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    }

    if (allowed.isEmpty) return;
    setState(() {
      _reportImages.addAll(allowed.take(remaining));
    });
  }

  void _removeReportImage(int index) {
    setState(() => _reportImages.removeAt(index));
  }

  void _removeExistingImage(int index) {
    setState(() => _existingImageUrls.removeAt(index));
  }

  /// Short word appended to the report field when a chip is tapped.
  String _presetFor(_DiscrepancyTag tag) {
    switch (tag) {
      case _DiscrepancyTag.size:
        return TKeys.sizeLabel.tr;
      case _DiscrepancyTag.color:
        return TKeys.colorLabel.tr;
      case _DiscrepancyTag.picture:
        return TKeys.pictureLabel.tr;
      case _DiscrepancyTag.other:
        return TKeys.otherLabel.tr;
    }
  }

  /// Appends [snippet] to the report field (with a separating space) and keeps
  /// the caret at the end.
  void _appendReportText(String snippet) {
    final current = _reportCtrl.text;
    final needsSpace = current.isNotEmpty &&
        !current.endsWith(' ') &&
        !current.endsWith('\n');
    final next = '$current${needsSpace ? ' ' : ''}$snippet ';
    _reportCtrl
      ..text = next
      ..selection = TextSelection.collapsed(offset: next.length);
  }

  /// Uploads any newly-picked images for their `s3Key`s, then PATCHes the
  /// product issue with the message + keys (filed at product level).
  Future<void> _submitReport() async {
    if (_submitting) return;

    final message = _reportCtrl.text.trim();
    if (message.isEmpty) {
      Get.snackbar(TKeys.errorTitle.tr, TKeys.describeDiscrepancyError.tr);
      return;
    }

    setState(() => _submitting = true);

    final imageKeys = <String>[];
    for (final img in _reportImages) {
      final key = await widget.ctrl.uploadProductRequestImage(img.path);
      if (key == null) {
        if (!mounted) return;
        setState(() => _submitting = false);
        Get.snackbar(
          TKeys.errorTitle.tr,
          TKeys.stCouldNotUploadNamed.trParams({'name': img.name}),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade600,
          colorText: Colors.white,
        );
        return;
      }
      imageKeys.add(key);
    }

    final error = await widget.ctrl.submitProductIssue(
      productId: _hit.id,
      message: message,
      imageKeys: imageKeys,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (error == null) {
      Navigator.of(context).pop();
      Get.snackbar(
        TKeys.successTitle.tr,
        TKeys.reportUpdated.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade600,
        colorText: Colors.white,
      );
    } else {
      Get.snackbar(
        TKeys.errorTitle.tr,
        error,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
      );
    }
  }

  // ---------- Field resolution (fetched product → search-hit fallback) ----------

  String get _imageUrl {
    final fromProduct = _product?.thumbnailUrl ?? _product?.image;
    return (fromProduct != null && fromProduct.isNotEmpty) ? fromProduct : '';
  }

  String get _productName {
    final n = _product?.name;
    if (n != null && n.isNotEmpty) return n;
    return _hit.name.isNotEmpty ? _hit.name : TKeys.saProduct.tr;
  }

  String get _brand => _product?.brand ?? '';
  String get _upc => (_hit.upc?.isNotEmpty ?? false) ? _hit.upc! : '—';
  String get _suggestedPrice =>
      _product?.originalPrice != null ? '${_product!.originalPrice} NOK' : '-';
  String get _regularPrice =>
      _product?.regularPrice != null ? '${_product!.regularPrice} NOK' : '-';
  String get _color =>
      _product?.colour ??
      ((_product?.colorsAvailable.isNotEmpty ?? false)
          ? _product!.colorsAvailable.join(', ')
          : '-');
  String get _sizes => (_product?.sizesAvailable.isNotEmpty ?? false)
      ? _product!.sizesAvailable.join(', ')
      : '-';
  String get _description =>
      (_product?.shortDescription?.trim().isNotEmpty ?? false)
          ? _product!.shortDescription!
          : TKeys.noDescription.tr;

  int get _totalQty =>
      widget.placements.fold(0, (sum, p) => sum + p.quantity);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxHeight = size.height * 0.86;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCloseRow(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroImage(),
                    const SizedBox(height: 18),
                    _buildBrandAndTitle(),
                    const SizedBox(height: 14),
                    _buildPriceRow(),
                    const SizedBox(height: 14),
                    _buildSpecLine(TKeys.stUpcColon.tr, _upc),
                    const SizedBox(height: 6),
                    _buildSpecLine(TKeys.colorColon.tr, _color),
                    const SizedBox(height: 6),
                    _buildSpecLine(TKeys.sizesColon.tr, _sizes),
                    const SizedBox(height: 12),
                    if (_loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            CustomText(
                              TKeys.stLoadingDetails.tr,
                              fontSize: 12.5,
                              color: AppColors.textMuted,
                            ),
                          ],
                        ),
                      )
                    else
                      CustomText(
                        _description,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textMuted,
                      ),
                    if (widget.placements.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildPlacements(),
                    ],

                    // ── Report a discrepancy ──────────────────────────────
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: AppColors.inputBorder),
                    const SizedBox(height: 18),
                    _buildSectionLabel(TKeys.reportDiscrepancyCaps.tr),
                    const SizedBox(height: 8),
                    CustomText(
                      TKeys.reportDiscrepancyBody.tr,
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    if (_loadingIssue)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else ...[
                      _buildReportField(),
                      const SizedBox(height: 14),
                      _buildTagChips(),
                    ],
                    const SizedBox(height: 22),
                    _buildSectionLabel(TKeys.wrongProductImageCaps.tr),
                    const SizedBox(height: 6),
                    CustomText(
                      TKeys.uploadPhysicalImages
                          .trParams({'max': '$_maxImages'}),
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    if (_totalImages > 0) ...[
                      _buildImageStrip(),
                      const SizedBox(height: 12),
                    ],
                    _buildUploadRow(),
                    const SizedBox(height: 22),
                    _buildUpdateButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloseRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.textSecondary,
            splashRadius: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            color: AppColors.inputFill,
            child: _imageUrl.isEmpty
                ? Center(
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.image_not_supported_outlined,
                            size: 40,
                            color: AppColors.textMuted,
                          ),
                  )
                : Image.network(
                    _imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        size: 40,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandAndTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_brand.isNotEmpty) ...[
          CustomText(
            _brand.toUpperCase(),
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 4),
        ],
        CustomText(
          _productName,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          height: 1.25,
          color: AppColors.textPrimary,
        ),
      ],
    );
  }

  Widget _buildPriceRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _priceColumn(TKeys.stSuggestedRetail.tr, _suggestedPrice)),
        Expanded(child: _priceColumn('MSRP', _regularPrice)),
      ],
    );
  }

  Widget _priceColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(
          label,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 4),
        CustomText(
          value,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ],
    );
  }

  Widget _buildSpecLine(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textPrimary,
          height: 1.35,
        ),
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  Widget _buildPlacements() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CustomText(
              TKeys.stInStockCaps.tr,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: 6),
            CustomText(
              TKeys.stPcs.trParams({'count': '$_totalQty'}),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in widget.placements) _BinChip(placement: p),
          ],
        ),
      ],
    );
  }

  // ---------- Report section widgets ----------

  Widget _buildSectionLabel(String label) {
    return CustomText(
      label,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.3,
      color: AppColors.textPrimary,
    );
  }

  Widget _buildReportField() {
    return TextField(
      controller: _reportCtrl,
      maxLines: 3,
      minLines: 3,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: TKeys.describeDiscrepancy.tr,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandNavy, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildTagChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _DiscrepancyTag.values.map((tag) {
        return GestureDetector(
          onTap: () => _appendReportText(_presetFor(tag)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded,
                    size: 14, color: AppColors.brandNavy),
                const SizedBox(width: 5),
                CustomText(
                  tag.name.toUpperCase(),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textPrimary,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildImageStrip() {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _totalImages,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final isExisting = index < _existingImageUrls.length;
          final Widget thumb = isExisting
              ? Image.network(
                  _existingImageUrls[index],
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 76,
                    height: 76,
                    color: AppColors.inputFill,
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.textMuted,
                    ),
                  ),
                )
              : Image.file(
                  File(_reportImages[index - _existingImageUrls.length].path),
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                );
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: thumb,
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => isExisting
                      ? _removeExistingImage(index)
                      : _removeReportImage(index - _existingImageUrls.length),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUploadRow() {
    final atLimit = _totalImages >= _maxImages;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: atLimit ? null : _addReportImages,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.inputBorder),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.upload_rounded, size: 18),
            label: CustomText(
              TKeys.uploadImagesCaps.tr,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        CustomText(
          TKeys.imageCount.trParams(
              {'current': '$_totalImages', 'max': '$_maxImages'}),
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ],
    );
  }

  Widget _buildUpdateButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submitReport,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : CustomText(
                TKeys.stSubmitReport.tr,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
      ),
    );
  }
}

/// Tiny chip showing a bin code + quantity for one product placement.
class _BinChip extends StatelessWidget {
  const _BinChip({required this.placement});
  final SearchPlacement placement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brandYellow.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomText(
            placement.locationCode,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: AppColors.brandNavy,
          ),
          const SizedBox(width: 5),
          CustomText(
            '×${placement.quantity}',
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
          if (placement.isPrimary) ...[
            const SizedBox(width: 4),
            const Icon(Icons.star_rounded, size: 13, color: AppColors.brandNavy),
          ],
        ],
      ),
    );
  }
}
