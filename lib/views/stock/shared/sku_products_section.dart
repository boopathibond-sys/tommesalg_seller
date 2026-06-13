import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../controllers/inventory_controller.dart';
import '../../../controllers/sku_detail_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/inventory_placement.dart';
import '../../../models/location_suggestion.dart';
import '../../../models/pending_product.dart';
import 'assigned_product_quick_view.dart';
import 'stock_widgets.dart';

/// Assigned + pending products for a SKU, with an "Assigned / Pending" tab
/// switcher and full edit + delete actions on both lists.
///
/// Shared by the Assign screen (after a SKU is picked) and the SKU detail page
/// so both expose exactly the same functionality. Pass the [SkuDetailController]
/// that owns the placements + pending lists, and the [InventoryController] used
/// for image uploads in the pending-edit sheet.
class SkuProductsSection extends StatefulWidget {
  const SkuProductsSection({
    super.key,
    required this.detailCtrl,
    required this.inventoryCtrl,
  });

  final SkuDetailController detailCtrl;
  final InventoryController inventoryCtrl;

  @override
  State<SkuProductsSection> createState() => _SkuProductsSectionState();
}

class _SkuProductsSectionState extends State<SkuProductsSection> {
  /// 0 = assigned products, 1 = pending products.
  int _bottomTab = 0;

  void _selectBottomTab(int index) {
    if (_bottomTab == index) return;
    setState(() => _bottomTab = index);
    // Pending tab: fetch the pending / unknown products for this SKU.
    if (index == 1) widget.detailCtrl.fetchPendingUnknown();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBottomTabs(),
        const SizedBox(height: 12),
        _bottomTab == 0
            ? _AssignedProducts(ctrl: widget.detailCtrl)
            : _PendingProducts(
                ctrl: widget.detailCtrl,
                inventoryCtrl: widget.inventoryCtrl,
              ),
      ],
    );
  }

  /// Tab switcher — "Assigned" vs "Pending".
  Widget _buildBottomTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _bottomTabButton('Assigned', 0),
          _bottomTabButton('Pending', 1),
        ],
      ),
    );
  }

  Widget _bottomTabButton(String label, int index) {
    final selected = _bottomTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectBottomTab(index),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: selected
                ? Border.all(color: AppColors.inputBorder, width: 1)
                : null,
          ),
          alignment: Alignment.center,
          child: CustomText(
            label,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? AppColors.brandNavy : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Assigned-products list for the SKU — image, name, UPC, quantity, a red
/// delete affordance, and an Edit button that opens the [EditPlacementDialog].
class _AssignedProducts extends StatelessWidget {
  const _AssignedProducts({required this.ctrl});
  final SkuDetailController ctrl;

  Future<void> _confirmDelete(
    BuildContext context,
    InventoryPlacement placement,
  ) async {
    final placementId = placement.placementId;
    if (placementId == null || placementId.isEmpty) {
      Get.snackbar('Error', 'This product cannot be removed right now.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const CustomText(
          'Remove product?',
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        content: CustomText(
          'Remove "${placement.productName}" from this SKU?',
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const CustomText(
              'Cancel',
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const CustomText(
              'Remove',
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.vipps,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final error = await ctrl.deletePlacement(placementId);
    if (error == null) {
      Get.snackbar('Removed', 'Product removed from SKU');
    } else {
      Get.snackbar('Error', error);
    }
  }

  void _move(BuildContext context, InventoryPlacement placement) {
    final placementId = placement.placementId;
    if (placementId == null || placementId.isEmpty) {
      Get.snackbar('Error', 'This product cannot be moved right now.');
      return;
    }
    MovePlacementDialog.show(context, ctrl, placement);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoadingPlacements && ctrl.placements.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
              ),
            ),
          ),
        );
      }

      if (ctrl.placementsError != null && ctrl.placements.isEmpty) {
        return StockStatsError(
          message: ctrl.placementsError!,
          onRetry: ctrl.fetchPlacements,
        );
      }

      if (ctrl.placements.isEmpty) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.inputBorder, width: 1),
          ),
          child: const Column(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 34, color: AppColors.textMuted),
              SizedBox(height: 10),
              CustomText(
                'No products assigned yet',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ],
          ),
        );
      }

      final items = ctrl.placements;
      return Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.inputBorder, width: 1),
        ),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.inputBorder),
              _AssignedProductRow(
                placement: items[i],
                onQuickView: () =>
                    AssignedProductQuickView.show(context, ctrl, items[i]),
                onEdit: () => EditPlacementDialog.show(context, ctrl, items[i]),
                onDelete: () => _confirmDelete(context, items[i]),
                onMove: () => _move(context, items[i]),
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// Pending / unknown products for the SKU — from
/// `GET /locations/{id}/pending-unknown`. Each row offers Edit (name, UPC,
/// quantity, images) and Delete.
class _PendingProducts extends StatelessWidget {
  const _PendingProducts({required this.ctrl, required this.inventoryCtrl});
  final SkuDetailController ctrl;
  final InventoryController inventoryCtrl;

  Future<void> _confirmDelete(
    BuildContext context,
    PendingProduct product,
  ) async {
    if (product.itemId.isEmpty) {
      Get.snackbar('Error', 'This product cannot be removed right now.');
      return;
    }

    final name = product.name.isNotEmpty ? product.name : 'this product';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const CustomText(
          'Delete product?',
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        content: CustomText(
          'Are you sure you want to delete "$name"?',
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const CustomText(
              'Cancel',
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const CustomText(
              'Delete',
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.vipps,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final error = await ctrl.deletePendingUnknown(product.itemId);
    if (error == null) {
      Get.snackbar('Deleted', 'Pending product removed');
    } else {
      Get.snackbar('Error', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoadingPending && ctrl.pending.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
              ),
            ),
          ),
        );
      }

      if (ctrl.pendingError != null && ctrl.pending.isEmpty) {
        return StockStatsError(
          message: ctrl.pendingError!,
          onRetry: ctrl.fetchPendingUnknown,
        );
      }

      if (ctrl.pending.isEmpty) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.inputBorder, width: 1),
          ),
          child: const Column(
            children: [
              Icon(Icons.pending_actions_outlined,
                  size: 34, color: AppColors.textMuted),
              SizedBox(height: 10),
              CustomText(
                'No pending products',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ],
          ),
        );
      }

      final items = ctrl.pending;
      return Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.inputBorder, width: 1),
        ),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.inputBorder),
              _PendingProductRow(
                product: items[i],
                onEdit: () => _EditPendingDialog.show(
                  context,
                  product: items[i],
                  detailCtrl: ctrl,
                  inventoryCtrl: inventoryCtrl,
                ),
                onDelete: () => _confirmDelete(context, items[i]),
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// One pending-product row — image, name + UPC + qty, edit + red delete.
class _PendingProductRow extends StatelessWidget {
  const _PendingProductRow({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });
  final PendingProduct product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final image = product.displayImage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: image != null
                ? Image.network(
                    image,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imagePlaceholder(),
                  )
                : _imagePlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  product.name.isNotEmpty ? product.name : 'Product',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                CustomText(
                  'UPC: ${product.upc ?? '—'}',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 4),
                CustomText(
                  'Qty ${product.quantity}',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.brandNavy),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.vipps.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_outline,
                  size: 18, color: AppColors.vipps),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: AppColors.inputFill,
      child: const Icon(Icons.inventory_2_outlined,
          size: 22, color: AppColors.textMuted),
    );
  }
}

/// One assigned-product row — image, name + UPC + qty, red delete, edit.
class _AssignedProductRow extends StatelessWidget {
  const _AssignedProductRow({
    required this.placement,
    required this.onQuickView,
    required this.onEdit,
    required this.onDelete,
    required this.onMove,
  });
  final InventoryPlacement placement;
  final VoidCallback onQuickView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMove;

  bool get _hasImage {
    final img = placement.image;
    return img != null && img.startsWith('http');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _hasImage
                ? Image.network(
                    placement.image!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imagePlaceholder(),
                  )
                : _imagePlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  placement.productName.isNotEmpty
                      ? placement.productName
                      : 'Product',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                CustomText(
                  'UPC: ${placement.upc ?? '—'}',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    CustomText(
                      'Qty ${placement.quantity}',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                    if (placement.isPrimary) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brandYellow.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const CustomText(
                          'PRIMARY',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: AppColors.brandNavy,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Actions: Quick View on its own line, with Edit + Delete in a row
          // below it — keeps the trailing area narrow on small-width screens.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: onQuickView,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.brandNavy.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.remove_red_eye_outlined,
                          size: 16, color: AppColors.brandNavy),
                      SizedBox(width: 5),
                      CustomText(
                        'Quick View',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: onMove,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.brandYellow.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.drive_file_move_outline,
                          size: 18, color: AppColors.brandNavy),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onEdit,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.inputFill,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.brandNavy),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.vipps.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.delete_outline,
                          size: 18, color: AppColors.vipps),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: AppColors.inputFill,
      child: const Icon(Icons.inventory_2_outlined,
          size: 22, color: AppColors.textMuted),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit placement dialog — increment quantity + primary
// ─────────────────────────────────────────────────────────────────────────────

/// Edit sheet for an assigned product. The placements API only supports
/// incrementing stock (no decrement), so the user enters how many units to add
/// on top of the current quantity, plus the primary-location flag.
class EditPlacementDialog extends StatefulWidget {
  const EditPlacementDialog({
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditPlacementDialog(ctrl: ctrl, placement: placement),
    );
  }

  @override
  State<EditPlacementDialog> createState() => _EditPlacementDialogState();
}

class _EditPlacementDialogState extends State<EditPlacementDialog> {
  // Units to add on top of the current quantity (increment-only API).
  late final _addCtrl = TextEditingController(text: '1');
  late bool _isPrimary = widget.placement.isPrimary;

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final add = int.tryParse(_addCtrl.text.trim());
    if (add == null || add <= 0) {
      Get.snackbar('Invalid quantity', 'Enter a quantity of 1 or more to add.');
      return;
    }
    final error = await widget.ctrl.incrementPlacement(
      productId: widget.placement.productId,
      addQuantity: add,
      isPrimary: _isPrimary,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      Get.snackbar('Saved', 'Added $add to product quantity.');
    } else {
      Get.snackbar('Error', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: CustomText(
                    widget.placement.productName,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.inputBorder, width: 1),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: CustomText(
                      'Current quantity',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  CustomText(
                    '${widget.placement.quantity}',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'ADD QUANTITY',
              controller: _addCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() => _isPrimary = !_isPrimary),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.inputBorder, width: 1),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: CustomText(
                        'Primary location',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Switch(
                      value: _isPrimary,
                      activeColor: AppColors.brandNavy,
                      onChanged: (v) => setState(() => _isPrimary = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Obx(() => _SaveButton(
                  label: 'Save',
                  loading: widget.ctrl.isSaving,
                  onTap: _save,
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Move placement dialog — pick a target SKU, then move
// ─────────────────────────────────────────────────────────────────────────────

/// Move sheet for an assigned product: search for a target SKU
/// (`GET /locations/suggest?q=`), pick one, then move the placement there via
/// `POST /placements/{placementId}/move` with `{ targetLocationId }`.
class MovePlacementDialog extends StatefulWidget {
  const MovePlacementDialog({
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MovePlacementDialog(ctrl: ctrl, placement: placement),
    );
  }

  @override
  State<MovePlacementDialog> createState() => _MovePlacementDialogState();
}

class _MovePlacementDialogState extends State<MovePlacementDialog> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _searching = false;
  bool _searched = false;
  List<LocationSuggestion> _results = const [];
  LocationSuggestion? _target;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() => _target = null);
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searching = true);
    final hits = await widget.ctrl.searchLocations(q);
    if (!mounted) return;
    setState(() {
      // Hide the SKU the product already lives in.
      _results =
          hits.where((s) => s.id != widget.ctrl.locationId).toList();
      _searching = false;
      _searched = true;
    });
  }

  Future<void> _move() async {
    final target = _target;
    final placementId = widget.placement.placementId;
    if (target == null) {
      Get.snackbar('Pick a SKU', 'Choose a target SKU to move into.');
      return;
    }
    if (placementId == null || placementId.isEmpty) {
      Get.snackbar('Error', 'This product cannot be moved right now.');
      return;
    }

    final error = await widget.ctrl.movePlacement(
      placementId: placementId,
      targetLocationId: target.id,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      Get.snackbar('Moved', 'Product moved to ${target.code}.');
    } else {
      Get.snackbar('Error', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: CustomText(
                    'Move "${widget.placement.productName}"',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const CustomText(
              'Search a SKU to move this product into.',
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 14),
            StockSearchField(
              controller: _searchCtrl,
              hint: 'Search SKU code or name…',
              icon: Icons.search_rounded,
              onChanged: _onChanged,
              onSubmitted: (v) => _runSearch(v),
            ),
            const SizedBox(height: 12),
            _buildResults(),
            const SizedBox(height: 18),
            Obx(() => _SaveButton(
                  label: _target == null
                      ? 'Move'
                      : 'Move to ${_target!.code}',
                  loading: widget.ctrl.isSaving,
                  onTap: _move,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
            ),
          ),
        ),
      );
    }
    if (!_searched) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: CustomText(
          'Start typing to find a SKU.',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        ),
      );
    }
    if (_results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: CustomText(
          'No SKUs match your search.',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.inputBorder, width: 1),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _results.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: AppColors.inputBorder),
          itemBuilder: (_, i) {
            final s = _results[i];
            final selected = _target?.id == s.id;
            return InkWell(
              onTap: () => setState(() => _target = s),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.brandYellow.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CustomText(
                        s.code,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomText(
                        s.name.isNotEmpty ? s.name : s.code,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: selected
                          ? AppColors.brandNavy
                          : AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit pending product sheet — name, UPC, quantity, images
// ─────────────────────────────────────────────────────────────────────────────

/// A new image picked in the edit sheet — the local file (for the thumbnail)
/// paired with the `s3Key` returned by the upload endpoint.
class _PendingUploadedImage {
  const _PendingUploadedImage(this.file, this.s3Key);
  final XFile file;
  final String s3Key;
}

/// Edit sheet for a pending product — name, UPC, quantity, and images. Saving
/// uploads any newly-picked images (collecting their `s3Key`s) and PATCHes
/// `/locations/{id}/pending-unknown/{itemId}` with `imageUrls` = the kept
/// existing images plus the new keys.
class _EditPendingDialog extends StatefulWidget {
  const _EditPendingDialog({
    required this.product,
    required this.detailCtrl,
    required this.inventoryCtrl,
  });
  final PendingProduct product;
  final SkuDetailController detailCtrl;
  final InventoryController inventoryCtrl;

  static Future<void> show(
    BuildContext context, {
    required PendingProduct product,
    required SkuDetailController detailCtrl,
    required InventoryController inventoryCtrl,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditPendingDialog(
        product: product,
        detailCtrl: detailCtrl,
        inventoryCtrl: inventoryCtrl,
      ),
    );
  }

  @override
  State<_EditPendingDialog> createState() => _EditPendingDialogState();
}

class _EditPendingDialogState extends State<_EditPendingDialog> {
  late final _nameCtrl = TextEditingController(text: widget.product.name);
  late final _upcCtrl = TextEditingController(text: widget.product.upc ?? '');
  late final _qtyCtrl =
      TextEditingController(text: '${widget.product.quantity}');

  final _picker = ImagePicker();

  /// Existing images (storage keys / URLs) kept on save — removable.
  late final List<String> _existingImages =
      List<String>.from(widget.product.imageUrls);

  /// New images picked in this sheet, each uploaded for its `s3Key`.
  final List<_PendingUploadedImage> _newImages = [];

  /// Number of images currently uploading (shows spinner placeholders).
  int _uploading = 0;
  bool _saving = false;

  bool get _busy => _saving || _uploading > 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _upcCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  /// Picks images and uploads each immediately, collecting its `s3Key`
  /// (same flow as the "Add UPC manually" sheet).
  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty || !mounted) return;

    setState(() => _uploading += picked.length);
    for (final img in picked) {
      final s3Key = await widget.inventoryCtrl.uploadProductRequestImage(
        img.path,
      );
      if (!mounted) return;
      setState(() {
        _uploading -= 1;
        if (s3Key != null) {
          _newImages.add(_PendingUploadedImage(img, s3Key));
        }
      });
      if (s3Key == null) {
        Get.snackbar('Upload failed', 'Could not upload ${img.name}');
      }
    }
  }

  Future<void> _save() async {
    if (_busy) return;

    final name = _nameCtrl.text.trim();
    final qty = int.tryParse(_qtyCtrl.text.trim());
    if (name.isEmpty) {
      Get.snackbar('Missing name', 'Enter a product name.');
      return;
    }
    if (qty == null || qty < 0) {
      Get.snackbar('Invalid quantity', 'Enter a quantity of 0 or more.');
      return;
    }

    // Kept existing images + newly-uploaded keys. If no new images were
    // picked, this is just the original list (old URLs sent back as-is).
    final imageUrls = <String>[
      ..._existingImages,
      ..._newImages.map((e) => e.s3Key),
    ];

    setState(() => _saving = true);

    final error = await widget.detailCtrl.updatePendingUnknown(
      itemId: widget.product.itemId,
      name: name,
      upc: _upcCtrl.text.trim(),
      quantity: qty,
      imageUrls: imageUrls,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (error == null) {
      Navigator.of(context).pop();
      Get.snackbar('Saved', 'Pending product updated');
    } else {
      Get.snackbar('Error', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + viewInsets),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: CustomText(
                      'Edit pending product',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _PendingField(label: 'NAME', controller: _nameCtrl),
              const SizedBox(height: 14),
              _PendingField(
                label: 'UPC',
                controller: _upcCtrl,
                readOnly: true,
              ),
              const SizedBox(height: 14),
              _PendingField(
                label: 'QUANTITY',
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 18),
              const CustomText(
                'IMAGES',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _existingImages.length; i++)
                      _ImageThumb(
                        onRemove: _busy
                            ? null
                            : () =>
                                setState(() => _existingImages.removeAt(i)),
                        child: _existingImages[i].startsWith('http')
                            ? Image.network(_existingImages[i],
                                width: 72, height: 72, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _thumbFallback())
                            : _thumbFallback(),
                      ),
                    for (var i = 0; i < _newImages.length; i++)
                      _ImageThumb(
                        onRemove: _busy
                            ? null
                            : () => setState(() => _newImages.removeAt(i)),
                        child: Image.file(
                          File(_newImages[i].file.path),
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                    for (var i = 0; i < _uploading; i++)
                      _ImageThumb(
                        child: Container(
                          width: 72,
                          height: 72,
                          color: AppColors.inputFill,
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor:
                                    AlwaysStoppedAnimation(AppColors.brandNavy),
                              ),
                            ),
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: _busy ? null : _pickImages,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.inputFill,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: AppColors.inputBorder, width: 1),
                        ),
                        child: const Icon(Icons.add_a_photo_outlined,
                            size: 22, color: AppColors.brandNavy),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _busy ? null : _save,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: _busy
                        ? AppColors.brandNavy.withOpacity(0.4)
                        : AppColors.brandNavy,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.white),
                          ),
                        )
                      : CustomText(
                          _uploading > 0 ? 'Uploading images…' : 'Save',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
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

  Widget _thumbFallback() {
    return Container(
      width: 72,
      height: 72,
      color: AppColors.inputFill,
      child: const Icon(Icons.inventory_2_outlined,
          size: 22, color: AppColors.textMuted),
    );
  }
}

/// A 72×72 image thumbnail with an optional remove badge (for picked files).
class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.child, this.onRemove});
  final Widget child;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      size: 14, color: AppColors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Labeled text field used inside the pending-edit sheet.
class _PendingField extends StatelessWidget {
  const _PendingField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.inputFormatters,
    this.readOnly = false,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// Display-only field (e.g. UPC) — shown but not editable.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(
          label,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: readOnly ? AppColors.inputBorder.withOpacity(0.25)
                : AppColors.inputFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.inputBorder, width: 1),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            readOnly: readOnly,
            enableInteractiveSelection: !readOnly,
            style: TextStyle(
              color: readOnly ? AppColors.textMuted : AppColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 11),
            ),
          ),
        ),
      ],
    );
  }
}

/// Labeled text field used inside the edit-placement sheet.
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.inputFormatters,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(
          label,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.inputBorder, width: 1),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 11),
            ),
          ),
        ),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.label,
    required this.onTap,
    this.loading = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.brandNavy,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(AppColors.white),
                ),
              ),
              const SizedBox(width: 10),
            ],
            CustomText(
              label,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: AppColors.white,
            ),
          ],
        ),
      ),
    );
  }
}
