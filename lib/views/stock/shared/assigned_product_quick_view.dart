import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../controllers/sku_detail_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/inventory_placement.dart';
import '../../../models/product_request_model.dart';

/// Quick-insert discrepancy presets for the report field.
enum _DiscrepancyTag { size, color, picture, other }

/// Read-only "quick view" for a product assigned to a SKU.
///
/// Mirrors the product-info section of the Manage Products quick view (hero
/// image, brand, title, suggested / MRP price, colour, sizes, description)
/// **without** the report-a-discrepancy section — placements have no
/// product-request item id to report against.
///
/// Placements only carry `id/name/upc/image`, so on open this fetches the
/// product via [SkuDetailController.fetchQuickViewProduct] (which logs the raw
/// response). Any richer fields it returns are rendered; everything else falls
/// back to the placement's own data, with unavailable specs shown as `-`.
class AssignedProductQuickView extends StatefulWidget {
  const AssignedProductQuickView({
    super.key,
    required this.ctrl,
    required this.placement,
  });

  final SkuDetailController ctrl;
  final InventoryPlacement placement;

  static Future<void> show(
    BuildContext context,
    SkuDetailController ctrl,
    InventoryPlacement placement,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) =>
          AssignedProductQuickView(ctrl: ctrl, placement: placement),
    );
  }

  @override
  State<AssignedProductQuickView> createState() =>
      _AssignedProductQuickViewState();
}

class _AssignedProductQuickViewState extends State<AssignedProductQuickView> {
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

  InventoryPlacement get _p => widget.placement;

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
    final product = await widget.ctrl.fetchQuickViewProduct(_p.productId);
    if (!mounted) return;
    setState(() {
      _product = product;
      _loading = false;
    });
  }

  /// Loads any existing reported discrepancy for this product+bin so the form
  /// prefills its message and previously-uploaded images.
  Future<void> _loadIssue() async {
    final issue = await widget.ctrl.fetchProductIssue(
      productId: _p.productId,
      locationId: widget.ctrl.locationId,
    );
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
              title: const CustomText('Camera',
                  fontSize: 15, fontWeight: FontWeight.w700),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.brandNavy),
              title: const CustomText('Gallery',
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
        'Unsupported file',
        'Only JPEG, PNG, or WebP images are allowed.',
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
        return 'Size';
      case _DiscrepancyTag.color:
        return 'Color';
      case _DiscrepancyTag.picture:
        return 'Picture';
      case _DiscrepancyTag.other:
        return 'Other';
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
  /// product issue with the message + keys + this bin's location id.
  Future<void> _submitReport() async {
    if (_submitting) return;

    final message = _reportCtrl.text.trim();
    if (message.isEmpty) {
      Get.snackbar('Error', 'Please describe the discrepancy');
      return;
    }

    setState(() => _submitting = true);

    // Upload each newly-picked image to collect its s3 key.
    final imageKeys = <String>[];
    for (final img in _reportImages) {
      final key = await widget.ctrl.uploadIssueImage(img.path);
      if (key == null) {
        if (!mounted) return;
        setState(() => _submitting = false);
        Get.snackbar(
          'Error',
          'Could not upload ${img.name}',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade600,
          colorText: Colors.white,
        );
        return;
      }
      imageKeys.add(key);
    }

    final error = await widget.ctrl.submitProductIssue(
      productId: _p.productId,
      message: message,
      imageKeys: imageKeys,
      locationId: widget.ctrl.locationId,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (error == null) {
      Navigator.of(context).pop();
      Get.snackbar(
        'Success',
        'Report updated',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade600,
        colorText: Colors.white,
      );
    } else {
      Get.snackbar(
        'Error',
        error,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
      );
    }
  }

  // ---------- Field resolution (fetched product → placement fallback) ----------

  String get _imageUrl {
    final fromProduct = _product?.thumbnailUrl ?? _product?.image;
    if (fromProduct != null && fromProduct.isNotEmpty) return fromProduct;
    final img = _p.image;
    return (img != null && img.startsWith('http')) ? img : '';
  }

  String get _productName {
    final n = _product?.name;
    if (n != null && n.isNotEmpty) return n;
    return _p.productName.isNotEmpty ? _p.productName : 'Product';
  }

  String get _brand => _product?.brand ?? '';
  String get _upc => (_p.upc?.isNotEmpty ?? false) ? _p.upc! : '—';
  String get _suggestedPrice =>
      _product?.originalPrice != null ? '${_product!.originalPrice} NOK' : '-';
  String get _regularPrice =>
      _product?.regularPrice != null ? '${_product!.regularPrice} \$' : '-';
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
          : 'No description';

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
                    _buildSpecLine('UPC:', _upc),
                    const SizedBox(height: 6),
                    _buildSpecLine('Quantity:', '${_p.quantity}'),
                    const SizedBox(height: 6),
                    _buildSpecLine('Color:', _color),
                    const SizedBox(height: 6),
                    _buildSpecLine('Sizes:', _sizes),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            CustomText(
                              'Loading details…',
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

                    // ── Report a discrepancy ──────────────────────────────
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: AppColors.inputBorder),
                    const SizedBox(height: 18),
                    _buildSectionLabel('REPORT A DISCREPANCY'),
                    const SizedBox(height: 8),
                    const CustomText(
                      'Does the catalog data not match the physical product? '
                      'Describe the discrepancy and upload images if the product '
                      'image is incorrect — admin sees this upon request.',
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
                    _buildSectionLabel('WRONG PRODUCT IMAGE?'),
                    const SizedBox(height: 6),
                    const CustomText(
                      'Upload one or more images of the physical product '
                      '(max $_maxImages).',
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
        hintText: 'Describe the discrepancy',
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
            label: const CustomText(
              'UPLOAD IMAGE(S)',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        CustomText(
          '$_totalImages / $_maxImages image(s)',
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
            : const CustomText(
                'Update report',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
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
                ? const Center(
                    child: Icon(
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
        Expanded(child: _priceColumn('Suggested retail price', _suggestedPrice)),
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
}
