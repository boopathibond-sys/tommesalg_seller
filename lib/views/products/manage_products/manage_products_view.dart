import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../controllers/stream_controller.dart';
import '../../../core/config/get_or_put.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/product_request_model.dart';
import '../../../models/stream_model.dart';
import '../../scanner/barcode_scanner_view.dart';

class ManageProductView extends StatefulWidget {
  const ManageProductView({super.key});

  @override
  State<ManageProductView> createState() => _ManageProductViewState();
}

class _ManageProductViewState extends State<ManageProductView> {
  final TextEditingController _nameController = TextEditingController();
  final List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _addingUnknown = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(images);
      });
    }
  }

  void _removeImageAt(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  String formatDate(DateTime? date) {
    if (date == null) return "No schedule";

    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year} • "
        "${date.hour.toString().padLeft(2, '0')}:"
        "${date.minute.toString().padLeft(2, '0')}";
  }

  final ctrl = getOrPut(() => StreamListController());

  /// Pull-to-refresh: force-reloads the scheduled streams, then (if a stream is
  /// still selected) its product requests / pending products.
  Future<void> _onRefresh() async {
    await ctrl.fetchStreamsByStatus(status: 'SCHEDULED', refresh: true);
    final stream = ctrl.selectedStream.value;
    if (stream != null) {
      await ctrl.fetchProductRequests(stream.id);
    }
  }

  Future<void> _openScanner() async {
    final result = await Navigator.of(context).push<Barcode>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerView()),
    );
    if (result != null) {
      ctrl.addScannedProductByStream(upc: result.rawValue.toString());
    }
  }

  Future<void> _openManualUpcSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManualUpcSheet(ctrl: ctrl),
    );
  }


  Future<void> _addUnknownProduct() async {
    if (_addingUnknown) return;

    if (_nameController.text.trim().isEmpty) {
      Get.snackbar("Error", "Please enter product name");
      return;
    }

    setState(() => _addingUnknown = true);

    final ok = await ctrl.addUnknownProduct(
      name: _nameController.text.trim(),
      imagePaths: _selectedImages.map((e) => e.path).toList(),
    );

    if (!mounted) return;
    setState(() => _addingUnknown = false);

    if (ok) {
      _nameController.clear();
      setState(() => _selectedImages.clear());
      Get.snackbar("Success", "Product added");
    } else {
      Get.snackbar("Error", ctrl.errorMessage ?? "Could not add product");
    }
  }

  void _dismissUnknownForm() {
    _nameController.clear();
    setState(() => _selectedImages.clear());
    ctrl.clearProductNotFound();
  }

  void _openQuickView(ProductRequestItem item) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => _ProductDiscrepancyDialog(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Products"),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AppColors.brandNavy,
        child: Obx(() {
        if (ctrl.isLoading == true) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        if (ctrl.scheduledStreams.isEmpty) {
          final hasError = ctrl.errorMessage != null;
          return _EmptyStreamsState(
            isError: hasError,
            message: hasError
                ? ctrl.errorMessage!
                : "You don't have any scheduled streams yet. "
                    "Create or schedule a stream to start adding products to it.",
            onRefresh: () =>
                ctrl.fetchStreamsByStatus(status: 'SCHEDULED', refresh: true),
          );
        }

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.grey),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CustomText(
                      "Select Stream",
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.grey,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                      child: DropdownButton<StreamModel>(
                        value: ctrl.selectedStream.value,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(14),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                        selectedItemBuilder: (context) {
                          return ctrl.scheduledStreams.map((stream) {
                            return Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: stream.isLive
                                        ? Colors.red
                                        : stream.isScheduled
                                            ? AppColors.brandYellow
                                            : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stream.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        formatDate(
                                          stream.scheduledStartTime,
                                        ),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList();
                        },
                        hint: const Row(
                          children: [
                            Icon(
                              Icons.live_tv_rounded,
                              color: AppColors.brandNavy,
                            ),
                            SizedBox(width: 12),
                            Text(
                              "Select Stream",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        items: ctrl.scheduledStreams.map((stream) {
                          return DropdownMenuItem<StreamModel>(
                            value: stream,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  margin: const EdgeInsets.only(top: 8),
                                  decoration: BoxDecoration(
                                    color: stream.isLive
                                        ? Colors.red
                                        : stream.isScheduled
                                            ? AppColors.brandYellow
                                            : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stream.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        formatDate(
                                          stream.scheduledStartTime,
                                        ),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          ctrl.selectStream(value);
                        },
                      ),
                    ),
                  ),
                  if (ctrl.selectedStream.value != null) ...[
                    const SizedBox(height: 18),
                    _ScanCard(onTap: _openScanner),
                    const SizedBox(height: 12),
                    _AddUpcManuallyButton(onTap: _openManualUpcSheet),
                  ],
                  if (ctrl.isProductNotFoundByScan) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.inputBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CustomText(
                                      "Product Not Found",
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.brandNavy,
                                    ),
                                    SizedBox(height: 4),
                                    CustomText(
                                      "Please enter details to add this product.",
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed:
                                    _addingUnknown ? null : _dismissUnknownForm,
                                icon: const Icon(Icons.close_rounded),
                                color: AppColors.textSecondary,
                                splashRadius: 20,
                                tooltip: "Scan again",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: "Product Name",
                              hintText: "Enter name",
                              filled: true,
                              fillColor: AppColors.inputFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 110,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _selectedImages.length + 1,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                if (index == _selectedImages.length) {
                                  return GestureDetector(
                                    onTap: _pickImage,
                                    child: Container(
                                      width: 110,
                                      decoration: BoxDecoration(
                                        color: AppColors.inputFill,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.inputBorder,
                                        ),
                                      ),
                                      child: const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_a_photo_outlined,
                                              color: AppColors.textMuted),
                                          SizedBox(height: 8),
                                          CustomText(
                                            "Add Image",
                                            fontSize: 12,
                                            color: AppColors.textMuted,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                final image = _selectedImages[index];
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        File(image.path),
                                        width: 110,
                                        height: 110,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () => _removeImageAt(index),
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed:
                                  _addingUnknown ? null : _addUnknownProduct,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandNavy,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _addingUnknown
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const CustomText(
                                      "Add Unknown Product",
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                ),
              ),
              const SizedBox(height: 20,),
              //start here
              if (ctrl.selectedStream.value != null) ...[
                if (ctrl.isLoadingProductRequests)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (ctrl.productRequestItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CustomText(
                        "No products added yet",
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                else
                  ...ctrl.productRequestItems.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ScannedProductCard(
                        id: item.id,
                        upc: item.requestedUpc??'',
                        name: item.displayName,
                        quantity: item.quantityRequested,
                        imageUrl: item.displayImageUrl,
                        onDelete: () {},
                        onQuickView: () => _openQuickView(item),
                      ),
                    );
                  }),
              ],
            ],
          ),
        );
      }),
      ),
    );
  }
}

/// Friendly placeholder shown when there are no scheduled streams to pick
/// from — either because none exist yet or because the load failed. Offers a
/// Refresh action so the seller can retry without leaving the screen.
class _EmptyStreamsState extends StatelessWidget {
  const _EmptyStreamsState({
    required this.isError,
    required this.message,
    required this.onRefresh,
  });

  final bool isError;
  final String message;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: (isError ? Colors.red : AppColors.brandNavy)
                    .withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isError
                    ? Icons.wifi_off_rounded
                    : Icons.live_tv_outlined,
                size: 42,
                color: isError ? Colors.red : AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 20),
            CustomText(
              isError ? "Couldn't load streams" : "No streams yet",
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 8),
            CustomText(
              message,
              fontSize: 13.5,
              height: 1.45,
              textAlign: TextAlign.center,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRefresh,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandNavy,
                side: const BorderSide(color: AppColors.brandNavy),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const CustomText(
                'Refresh',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannedProductCard extends StatelessWidget {
  const _ScannedProductCard({
    required this.id,
    required this.upc,
    required this.name,
    required this.quantity,
    required this.imageUrl,
    required this.onDelete,
    required this.onQuickView,
  });

  final String id;
  final String name;
  final String upc;
  final int quantity;
  final String imageUrl;
  final VoidCallback onDelete;
  final VoidCallback onQuickView;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 70,
                height: 70,
                color: AppColors.grey,
                child: const Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  name,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                CustomText(
                  'UPC: $upc',
                  fontSize: 11,
                  color: Colors.grey,
                  maxLines: 1,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandYellow.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: CustomText(
                    'Qty: $quantity',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              GestureDetector(
                onTap: onQuickView,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6,vertical: 5),
                  width: 108,
                  decoration: BoxDecoration(
                    color: AppColors.brandNavy.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                       Icon(
                        Icons.remove_red_eye_outlined,
                        size: 18,
                        color: AppColors.brandNavy,
                      ),
                      SizedBox(width: 4,),
                      CustomText("Quick View",fontSize: 12,fontWeight: FontWeight.w600,),

                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6,vertical: 5),
                  width: 108,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      SizedBox(width: 4,),
                      CustomText("Delete",fontSize: 12,fontWeight: FontWeight.w600,),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _DiscrepancyTag { size, color, picture, other }

class _ProductDiscrepancyDialog extends StatefulWidget {
  const _ProductDiscrepancyDialog({required this.item});

  final ProductRequestItem item;

  @override
  State<_ProductDiscrepancyDialog> createState() =>
      _ProductDiscrepancyDialogState();
}

class _ProductDiscrepancyDialogState extends State<_ProductDiscrepancyDialog> {
  static const int _maxImages = 10;

  final TextEditingController _reportCtrl = TextEditingController();
  final List<XFile> _reportImages = <XFile>[];
  final List<String> _existingImageUrls = <String>[];
  final ImagePicker _picker = ImagePicker();

  final _ctrl = getOrPut(() => StreamListController());
  bool _loadingIssue = true;
  bool _submitting = false;

  ProductRequestItem get _item => widget.item;
  ProductRequestProduct? get _product => widget.item.product;

  String get _brand => _product?.brand ?? '';
  String get _imageUrl => _item.displayImageUrl;
  String get _productName => _item.displayName;
  String get _suggestedPrice =>
      _product?.originalPrice != null ? '${_product!.originalPrice} \$' : '-';
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

  int get _totalImages => _existingImageUrls.length + _reportImages.length;

  @override
  void initState() {
    super.initState();
    _loadIssue();
  }

  Future<void> _loadIssue() async {
    final issue = await _ctrl.fetchProductRequestItemIssue(_item.id);
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

  @override
  void dispose() {
    _reportCtrl.dispose();
    super.dispose();
  }

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
  /// the caret at the end. Chips are not "selected" — they just insert text.
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

  Future<void> _submitReport() async {
    if (_submitting) return;

    final message = _reportCtrl.text.trim();
    if (message.isEmpty) {
      Get.snackbar('Error', 'Please describe the discrepancy');
      return;
    }

    setState(() => _submitting = true);

    final ok = await _ctrl.submitProductRequestItemIssue(
      itemId: _item.id,
      message: message,
      imagePaths: _reportImages.map((e) => e.path).toList(),
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
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
        _ctrl.errorMessage ?? 'Could not update report',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    }
  }

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
                    _buildSpecLine('Color:', _color),
                    const SizedBox(height: 6),
                    _buildSpecLine('Sizes:', _sizes),
                    const SizedBox(height: 12),
                    CustomText(
                      _description,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted,
                    ),
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
                    const SizedBox(height: 12),
                    _buildSeeFullProductButton(),
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
            child: Image.network(
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
        CustomText(
          _brand.toUpperCase(),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 4),
        CustomText(
          _productName,
          fontSize: 18,
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
        Expanded(child: _priceColumn('Suggested price', _suggestedPrice)),
        Expanded(child: _priceColumn('MRP', _regularPrice)),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

  Widget _buildSeeFullProductButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).pop();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandYellow,
          foregroundColor: AppColors.brandNavy,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const CustomText(
          'See full product',
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppColors.brandNavy,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Add UPC manually" — outlined button shown under the scan card. Opens the
// manual-entry bottom sheet so the seller can type a UPC the scanner can't read.
// ─────────────────────────────────────────────────────────────────────────────
class _AddUpcManuallyButton extends StatelessWidget {
  const _AddUpcManuallyButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brandNavy,
          side: const BorderSide(color: AppColors.brandNavy),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.keyboard_alt_outlined, size: 20),
        label: const CustomText(
          'Add UPC manually',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.brandNavy,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Manual UPC entry sheet — a numeric UPC field plus the same name + image
// inputs as the "unknown product" form. Submits through the same
// addUnknownProduct API, passing the typed UPC explicitly.
// ─────────────────────────────────────────────────────────────────────────────
class _ManualUpcSheet extends StatefulWidget {
  const _ManualUpcSheet({required this.ctrl});
  final StreamListController ctrl;

  @override
  State<_ManualUpcSheet> createState() => _ManualUpcSheetState();
}

class _ManualUpcSheetState extends State<_ManualUpcSheet> {
  final TextEditingController _upcController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _submitting = false;

  @override
  void dispose() {
    _upcController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() => _selectedImages.addAll(images));
    }
  }

  void _removeImageAt(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final upc = _upcController.text.trim();
    if (upc.isEmpty) {
      Get.snackbar("Error", "Please enter a UPC");
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      Get.snackbar("Error", "Please enter product name");
      return;
    }

    setState(() => _submitting = true);

    final ok = await widget.ctrl.addUnknownProduct(
      name: _nameController.text.trim(),
      imagePaths: _selectedImages.map((e) => e.path).toList(),
      upc: upc,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      Navigator.of(context).pop();
      Get.snackbar("Success", "Product added");
    } else {
      Get.snackbar(
        "Error",
        widget.ctrl.errorMessage ?? "Could not add product",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.inputBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CustomText(
                          "Add UPC manually",
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandNavy,
                        ),
                        SizedBox(height: 4),
                        CustomText(
                          "Enter the UPC and product details to add it.",
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                    splashRadius: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _upcController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "UPC",
                  hintText: "Enter UPC number",
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: "Product Name",
                  hintText: "Enter name",
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    if (index == _selectedImages.length) {
                      return GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: 110,
                          decoration: BoxDecoration(
                            color: AppColors.inputFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.inputBorder),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_outlined,
                                  color: AppColors.textMuted),
                              SizedBox(height: 8),
                              CustomText(
                                "Add Image",
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final image = _selectedImages[index];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(image.path),
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImageAt(index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandNavy,
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
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const CustomText(
                          "Add Unknown Product",
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryYellow, AppColors.primaryOrange],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: AppColors.buttonShadow,
              blurRadius: 22,
              offset: Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.brandNavy,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    'Scan & add product',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  SizedBox(height: 4),
                  CustomText(
                    'Use the camera to scan the barcode.',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.brandNavy,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

