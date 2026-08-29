import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../controllers/inventory_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/auto_quick_view_toggle.dart';
import '../../../core/widgets/custom_text.dart';
import '../../scanner/barcode_scanner_view.dart';
import '../../../core/localization/translation_keys.dart';

/// Reusable "assign products to a SKU" panel: a scan card, a UPC field with a
/// Thrown button, and the list of products added in this session. Used both in
/// the Assign tab (after a SKU is picked) and on the SKU detail page (where the
/// SKU is the one being viewed).
///
/// Scanning and the Thrown button run the same lookup → add flow; an unknown
/// UPC from either falls through to the manual sheet (UPC pre-filled),
/// which uploads images to `/product-request-issue-images` and POSTs the
/// product to `/locations/{locationId}/unknown-product`. [onAdded] fires after
/// a successful add so the host can refresh (e.g. the assigned-products list).
class AssignProductsPanel extends StatefulWidget {
  const AssignProductsPanel({
    super.key,
    required this.ctrl,
    required this.locationId,
    this.onAdded,
    this.onKnownProductAdded,
  });

  final InventoryController ctrl;
  final String locationId;
  final VoidCallback? onAdded;

  /// Fires after a *known* (catalog) product is added to the SKU via scan /
  /// manual UPC entry, with that product's id. The host uses it to open the
  /// product quick view once the new placement is loaded.
  final void Function(String productId)? onKnownProductAdded;

  @override
  State<AssignProductsPanel> createState() => _AssignProductsPanelState();
}

class _AssignProductsPanelState extends State<AssignProductsPanel> {
  /// Products added in this session (local display only).
  final List<_AssignScanItem> _items = [];

  /// Inline "enter UPC" field shown under the scan card.
  final TextEditingController _upcFieldCtrl = TextEditingController();

  /// True while a UPC is being looked up / added to the SKU.
  bool _looking = false;

  @override
  void dispose() {
    _upcFieldCtrl.dispose();
    super.dispose();
  }

  Future<void> _openScanner() async {
    final result = await Navigator.of(context).push<Barcode>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerView()),
    );
    if (!mounted || result == null) return;
    final raw = result.rawValue;
    if (raw == null || raw.isEmpty) return;
    // Strip leading zero(s) from the scanned UPC (e.g. 05673080 → 5673080).
    // Falls back to the raw value if it was all zeros.
    var upc = raw.trim().replaceFirst(RegExp(r'^0+'), '');
    if (upc.isEmpty) upc = raw.trim();
    // Run the scanned UPC through the catalog lookup → add flow.
    _processUpc(upc);
  }

  /// Looks a UPC up in the catalog. If it resolves to a known product, the
  /// product is added to this SKU via the batch placement endpoint. If the UPC
  /// isn't in the catalog, the manual add sheet opens with the UPC pre-filled.
  Future<void> _processUpc(String upc) async {
    if (_looking) return;
    final trimmed = upc.trim();
    if (trimmed.isEmpty) {
      Get.snackbar(TKeys.errorTitle.tr, TKeys.enterUpc.tr);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _looking = true);

    final result = await widget.ctrl.lookupUpcForAssign(trimmed);
    if (!mounted) return;

    switch (result.status) {
      case UpcLookupStatus.found:
        final error = await widget.ctrl.addProductPlacement(
          locationId: widget.locationId,
          productId: result.productId!,
        );
        if (!mounted) return;
        setState(() => _looking = false);
        if (error == null) {
          setState(() {
            _items.add(_AssignScanItem(
              upc: trimmed,
              name: result.productName ?? '',
            ));
            _upcFieldCtrl.clear();
          });
          widget.onAdded?.call();
          // Known product → let the host open its quick view (with the report
          // functions) now that it's been assigned to the SKU — but only if the
          // user left the auto quick-view toggle on.
          if (AutoQuickViewPref.enabled) {
            widget.onKnownProductAdded?.call(result.productId!);
          }
          Get.snackbar(TKeys.successTitle.tr, TKeys.stProductAddedToSku.tr);
        } else {
          Get.snackbar(TKeys.errorTitle.tr, error);
        }
        break;
      case UpcLookupStatus.notFound:
        setState(() => _looking = false);
        // Not in the catalog → let the user add it manually.
        _openManualUpcSheet(initialUpc: trimmed);
        break;
      case UpcLookupStatus.error:
        setState(() => _looking = false);
        Get.snackbar(TKeys.errorTitle.tr, result.message ?? TKeys.stSomethingWentWrong.tr);
        break;
    }
  }

  Future<void> _openManualUpcSheet({String? initialUpc}) async {
    final item = await showModalBottomSheet<_AssignScanItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignManualUpcSheet(
        ctrl: widget.ctrl,
        locationId: widget.locationId,
        initialUpc: initialUpc,
      ),
    );
    if (!mounted || item == null) return;
    setState(() {
      _items.add(item);
      _upcFieldCtrl.clear();
    });
    widget.onAdded?.call();
  }

  // void _removeItemAt(int index) {
  //   setState(() => _items.removeAt(index));
  // }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: AutoQuickViewToggle(
            value: AutoQuickViewPref.enabled,
            onChanged: (v) => setState(() => AutoQuickViewPref.enabled = v),
          ),
        ),
        const SizedBox(height: 10),
        _AssignScanCard(onTap: _looking ? null : _openScanner),
        const SizedBox(height: 12),
        _UpcEntryRow(
          controller: _upcFieldCtrl,
          busy: _looking,
          onAdd: () => _processUpc(_upcFieldCtrl.text),
        ),
        // if (_items.isNotEmpty) ...[
        //   const SizedBox(height: 16),
        //   const CustomText(
        //     'ADDED THIS SESSION',
        //     fontSize: 11,
        //     fontWeight: FontWeight.w700,
        //     letterSpacing: 0.6,
        //     color: AppColors.textMuted,
        //   ),
        //   const SizedBox(height: 10),
        //   for (var i = 0; i < _items.length; i++) ...[
        //     if (i > 0) const SizedBox(height: 12),
        //     _AssignItemCard(
        //       item: _items[i],
        //       onDelete: () => _removeItemAt(i),
        //     ),
        //   ],
        // ],
      ],
    );
  }
}

/// A product added in the Assign flow. `name` / images are optional.
class _AssignScanItem {
  _AssignScanItem({required this.upc, this.name = '', this.imagePaths = const []});
  final String upc;
  final String name;
  final List<String> imagePaths;
}

/// A collected product row, with a delete affordance.
// class _AssignItemCard extends StatelessWidget {
//   const _AssignItemCard({required this.item, required this.onDelete});
//   final _AssignScanItem item;
//   final VoidCallback onDelete;
//
//   @override
//   Widget build(BuildContext context) {
//     final hasImage = item.imagePaths.isNotEmpty;
//     return Container(
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(
//         color: AppColors.white,
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: AppColors.inputBorder),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           ClipRRect(
//             borderRadius: BorderRadius.circular(12),
//             child: hasImage
//                 ? Image.file(
//                     File(item.imagePaths.first),
//                     width: 64,
//                     height: 64,
//                     fit: BoxFit.cover,
//                   )
//                 : Container(
//                     width: 64,
//                     height: 64,
//                     color: AppColors.inputFill,
//                     child: const Icon(
//                       Icons.inventory_2_outlined,
//                       color: AppColors.textMuted,
//                     ),
//                   ),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 CustomText(
//                   item.name.isNotEmpty ? item.name : 'Scanned product',
//                   fontSize: 14,
//                   fontWeight: FontWeight.w700,
//                   color: AppColors.textPrimary,
//                   maxLines: 2,
//                 ),
//                 const SizedBox(height: 4),
//                 CustomText(
//                   'UPC: ${item.upc}',
//                   fontSize: 11.5,
//                   color: AppColors.textMuted,
//                   maxLines: 1,
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(width: 8),
//           GestureDetector(
//             onTap: onDelete,
//             child: Container(
//               padding: const EdgeInsets.all(7),
//               decoration: BoxDecoration(
//                 color: AppColors.vipps.withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: const Icon(Icons.delete_outline,
//                   size: 18, color: AppColors.vipps),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

/// Tappable scan card — mirrors the Manage Products "Scan & add product" card.
class _AssignScanCard extends StatelessWidget {
  const _AssignScanCard({required this.onTap});
  final VoidCallback? onTap;

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
                color: AppColors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    TKeys.scanAndAddProduct.tr,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(height: 4),
                  CustomText(
                    TKeys.useCameraToScan.tr,
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

/// Inline "enter UPC" row — a number field plus an Add button. Submitting or
/// tapping Add runs the UPC through the catalog lookup → batch-add flow.
class _UpcEntryRow extends StatelessWidget {
  const _UpcEntryRow({
    required this.controller,
    required this.busy,
    required this.onAdd,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: busy ? null : (_) => onAdd(),
            decoration: InputDecoration(
              hintText: TKeys.enterUpcLabel.tr,
              prefixIcon: const Icon(Icons.qr_code_2_rounded,
                  size: 20, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: busy ? null : onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandNavy,
              disabledBackgroundColor: AppColors.brandNavy.withOpacity(0.4),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(AppColors.white),
                    ),
                  )
                : CustomText(
                    TKeys.thrownLabel.tr,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
          ),
        ),
      ],
    );
  }
}

/// One row in the camera / gallery image-source chooser sheet.
class _ImageSourceTile extends StatelessWidget {
  const _ImageSourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.inputBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.brandNavy),
            const SizedBox(width: 14),
            CustomText(
              label,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ],
        ),
      ),
    );
  }
}

/// An image picked in the manual sheet — the local file (for the thumbnail)
/// paired with the `s3Key` returned by the upload endpoint.
class _UploadedImage {
  const _UploadedImage(this.file, this.s3Key);
  final XFile file;
  final String s3Key;
}

/// Manual UPC entry sheet. Each picked image is uploaded to
/// `/product-request-issue-images` as it's chosen (collecting `s3Key`s); on
/// "Add Product" it POSTs to the SKU's `/unknown-product` endpoint with the
/// collected keys. Pops the created [_AssignScanItem] on success.
class _AssignManualUpcSheet extends StatefulWidget {
  const _AssignManualUpcSheet({
    required this.ctrl,
    required this.locationId,
    this.initialUpc,
  });
  final InventoryController ctrl;
  final String locationId;

  /// Pre-fills the UPC field (e.g. from a barcode scan).
  final String? initialUpc;

  @override
  State<_AssignManualUpcSheet> createState() => _AssignManualUpcSheetState();
}

class _AssignManualUpcSheetState extends State<_AssignManualUpcSheet> {
  final TextEditingController _upcController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _qtyController =
      TextEditingController(text: '1');
  final List<_UploadedImage> _images = [];
  final ImagePicker _picker = ImagePicker();

  /// Number of images currently being uploaded (shows spinner placeholders).
  int _uploading = 0;
  bool _submitting = false;

  bool get _busy => _submitting || _uploading > 0;

  @override
  void initState() {
    super.initState();
    _upcController.text = widget.initialUpc ?? '';
  }

  @override
  void dispose() {
    _upcController.dispose();
    _nameController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  /// Asks the user where to get the image from (camera or gallery), then picks
  /// and uploads. Camera captures a single photo; gallery allows multiple.
  Future<void> _pickImage() async {
    final source = await _showImageSourceSheet();
    if (source == null || !mounted) return;

    final List<XFile> picked;
    if (source == ImageSource.camera) {
      final shot = await _picker.pickImage(source: ImageSource.camera);
      picked = shot == null ? const [] : [shot];
    } else {
      picked = await _picker.pickMultiImage();
    }
    if (picked.isEmpty || !mounted) return;

    setState(() => _uploading += picked.length);
    for (final img in picked) {
      final s3Key = await widget.ctrl.uploadProductRequestImage(img.path);
      if (!mounted) return;
      setState(() {
        _uploading -= 1;
        if (s3Key != null) {
          _images.add(_UploadedImage(img, s3Key));
        }
      });
      if (s3Key == null) {
        Get.snackbar(TKeys.csUploadFailed.tr, TKeys.stCouldNotUploadNamed.trParams({'name': img.name}));
      }
    }
  }

  /// Bottom sheet offering Camera / Gallery as image sources.
  Future<ImageSource?> _showImageSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SafeArea(
          top: false,
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
              CustomText(
                TKeys.stAddImage.tr,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
              const SizedBox(height: 16),
              _ImageSourceTile(
                icon: Icons.photo_camera_outlined,
                label: TKeys.stTakeAPhoto.tr,
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              const SizedBox(height: 12),
              _ImageSourceTile(
                icon: Icons.photo_library_outlined,
                label: TKeys.stChooseFromGallery.tr,
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _removeImageAt(int index) {
    setState(() => _images.removeAt(index));
  }

  Future<void> _submit() async {
    if (_busy) return;

    final upc = _upcController.text.trim();
    if (upc.isEmpty) {
      Get.snackbar(TKeys.errorTitle.tr, TKeys.enterUpc.tr);
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      Get.snackbar(TKeys.errorTitle.tr, TKeys.enterProductName.tr);
      return;
    }
    final quantity = int.tryParse(_qtyController.text.trim());
    if (quantity == null || quantity < 1) {
      Get.snackbar(TKeys.errorTitle.tr, TKeys.stEnterQuantityOne.tr);
      return;
    }

    setState(() => _submitting = true);

    final error = await widget.ctrl.addUnknownProductToLocation(
      locationId: widget.locationId,
      upc: upc,
      name: name,
      quantityRequested: quantity,
      imageS3Keys: _images.map((e) => e.s3Key).toList(),
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (error == null) {
      Navigator.of(context).pop(
        _AssignScanItem(
          upc: upc,
          name: name,
          imagePaths: _images.map((e) => e.file.path).toList(),
        ),
      );
      Get.snackbar(TKeys.successTitle.tr, TKeys.stProductAddedToSku.tr);
    } else {
      Get.snackbar(TKeys.errorTitle.tr, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CustomText(
                          TKeys.addUpcManually.tr,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandNavy,
                        ),
                        const SizedBox(height: 4),
                        CustomText(
                          TKeys.addUpcManuallyBody.tr,
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
                  labelText: 'UPC',
                  hintText: TKeys.enterUpcNumber.tr,
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
                  labelText: TKeys.productNameLabel.tr,
                  hintText: TKeys.enterNameHint.tr,
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
                controller: _qtyController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: TKeys.stQuantity.tr,
                  hintText: TKeys.stEnterQuantity.tr,
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
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // Uploaded image thumbnails
                    for (var i = 0; i < _images.length; i++) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_images[i].file.path),
                              width: 110,
                              height: 110,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap:
                                  _submitting ? null : () => _removeImageAt(i),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                    ],
                    // In-flight upload spinners
                    for (var i = 0; i < _uploading; i++) ...[
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: AppColors.inputFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.inputBorder),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor:
                                  AlwaysStoppedAnimation(AppColors.brandNavy),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    // Add-image tile
                    GestureDetector(
                      onTap: _submitting ? null : _pickImage,
                      child: Container(
                        width: 110,
                        decoration: BoxDecoration(
                          color: AppColors.inputFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.inputBorder),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo_outlined,
                                color: AppColors.textMuted),
                            const SizedBox(height: 8),
                            CustomText(
                              TKeys.addImage.tr,
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandNavy,
                    disabledBackgroundColor:
                        AppColors.brandNavy.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.white),
                          ),
                        )
                      : CustomText(
                          _uploading > 0 ? TKeys.stUploadingImages.tr : TKeys.stAddProduct.tr,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.white,
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
