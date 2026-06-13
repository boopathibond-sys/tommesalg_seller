import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/inventory_controller.dart';
import '../../../controllers/sku_detail_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/inventory_placement.dart';
import '../../../models/location_suggestion.dart';
import '../shared/assigned_product_quick_view.dart';
import '../shared/sku_products_section.dart';
import '../shared/stock_widgets.dart';
import 'assign_products_panel.dart';

/// Assign to SKU — search for a SKU (`GET /locations/suggest?q=`), pick one,
/// then scan products or add a UPC manually. The scan / manual-entry flow lives
/// in the shared [AssignProductsPanel] (also used on the SKU detail page), and
/// the assigned + pending lists (with edit / delete) live in the shared
/// [SkuProductsSection].
class AssignSection extends StatefulWidget {
  const AssignSection({super.key, required this.ctrl});
  final InventoryController ctrl;

  @override
  AssignSectionState createState() => AssignSectionState();
}

class AssignSectionState extends State<AssignSection> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  InventoryController get ctrl => widget.ctrl;

  LocationSuggestion? _selectedSku;

  /// Drives the assigned + pending lists for the selected SKU. Created on
  /// [_select], torn down on [_changeSku]/dispose.
  SkuDetailController? _detailCtrl;

  @override
  void initState() {
    super.initState();
    ctrl.clearSuggestions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _disposeDetailCtrl();
    super.dispose();
  }

  void _disposeDetailCtrl() {
    final tag = _selectedSku?.id;
    if (tag != null && Get.isRegistered<SkuDetailController>(tag: tag)) {
      Get.delete<SkuDetailController>(tag: tag);
    }
    _detailCtrl = null;
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      ctrl.clearSuggestions();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ctrl.suggestLocations(q);
    });
  }

  void _search() {
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    ctrl.suggestLocations(_searchCtrl.text);
  }

  void _select(LocationSuggestion s) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedSku = s;
      // Spin up a detail controller for the picked SKU — loads its placements
      // (`GET /locations/{id}/placements`) for the assigned-products list.
      _detailCtrl = Get.put(SkuDetailController(s.id), tag: s.id);
    });
    ctrl.clearSuggestions();
  }

  /// Pull-to-refresh hook for the Assign tab. When a SKU is selected, re-loads
  /// its detail record, assigned products (placements) and pending products;
  /// otherwise re-runs the current SKU suggestion search if there is a query.
  Future<void> refresh() async {
    final detailCtrl = _detailCtrl;
    if (detailCtrl != null) {
      await Future.wait([
        detailCtrl.fetchDetail(),
        detailCtrl.fetchPlacements(),
        detailCtrl.fetchPendingUnknown(),
      ]);
      return;
    }
    final q = _searchCtrl.text.trim();
    if (q.isNotEmpty) await ctrl.suggestLocations(q);
  }

  /// After a known product is scanned / typed and assigned to the SKU, reload
  /// the placements so the new row exists, then open its quick view (read-only
  /// product info + the report-a-discrepancy functions, with a close button).
  Future<void> _onKnownProductAdded(String productId) async {
    final detailCtrl = _detailCtrl;
    if (detailCtrl == null) return;

    await detailCtrl.fetchPlacements();
    if (!mounted) return;

    InventoryPlacement? placement;
    for (final p in detailCtrl.placements) {
      if (p.productId == productId) {
        placement = p;
        break;
      }
    }
    if (placement == null) return;

    await AssignedProductQuickView.show(context, detailCtrl, placement);
  }

  void _changeSku() {
    _searchCtrl.clear();
    ctrl.clearSuggestions();
    _disposeDetailCtrl();
    setState(() {
      _selectedSku = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CustomText(
          'Pick a SKU → scan products → save all',
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: _selectedSku == null
              ? _buildSkuSearch()
              : _buildSelectedSku(),
        ),
      ],
    );
  }

  Widget _buildSkuSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CustomText(
          'Select SKU',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        const SizedBox(height: 10),
        StockSearchField(
          controller: _searchCtrl,
          hint: 'Search SKU code or name…',
          icon: Icons.search_rounded,
          onChanged: _onQueryChanged,
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 12),

        // Results: loading · error · list · empty · idle
        Obx(() {
          if (ctrl.isSuggesting) {
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
          if (ctrl.suggestError != null) {
            return StockStatsError(
              message: ctrl.suggestError!,
              onRetry: _search,
            );
          }
          if (!ctrl.hasSuggested) {
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
          final items = ctrl.suggestions;
          if (items.isEmpty) {
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
          return Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.inputBorder, width: 1),
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: AppColors.inputBorder),
                  _SkuRow(
                    suggestion: items[i],
                    onTap: () => _select(items[i]),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSelectedSku() {
    final sku = _selectedSku!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.brandYellow.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomText(
                sku.code,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CustomText(
                sku.name.isNotEmpty ? sku.name : sku.code,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _changeSku,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.inputBorder, width: 1),
                ),
                child: const CustomText(
                  'Change',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        AssignProductsPanel(
          key: ValueKey(sku.id),
          ctrl: ctrl,
          locationId: sku.id,
          // Adding / incrementing a product re-fetches both lists: a known UPC
          // lands in placements, while an unknown one becomes a pending
          // product — so refresh both so whichever tab shows it updates.
          onAdded: () {
            _detailCtrl?.fetchPlacements();
            _detailCtrl?.fetchPendingUnknown();
          },
          // Known product → open its quick view right after it's assigned.
          onKnownProductAdded: _onKnownProductAdded,
        ),
        const SizedBox(height: 24),
        // Assigned + pending lists with edit / delete (shared with SKU detail).
        if (_detailCtrl != null)
          SkuProductsSection(
            detailCtrl: _detailCtrl!,
            inventoryCtrl: ctrl,
          ),
      ],
    );
  }
}

/// One SKU suggestion row — code badge, name, and a chevron.
class _SkuRow extends StatelessWidget {
  const _SkuRow({required this.suggestion, required this.onTap});
  final LocationSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.brandYellow.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomText(
                suggestion.code,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomText(
                suggestion.name.isNotEmpty ? suggestion.name : suggestion.code,
                fontSize: 14,
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
