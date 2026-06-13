import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/inventory_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/location_suggestion.dart';
import '../sku_detail_view.dart';
import '../widgets/new_sku_dialog.dart';
import '../shared/stock_segment.dart';
import '../shared/stock_widgets.dart';

/// SKUs — a single live SKU search (`GET /locations/suggest?q=`) plus New SKU.
/// Typing queries the suggest endpoint; tapping a result opens the SKU detail
/// page.
class SkusSection extends StatefulWidget {
  const SkusSection({super.key, required this.ctrl, required this.onOpenSegment});
  final InventoryController ctrl;

  /// Kept for the Warehouse tab contract; assigning now happens on the detail
  /// page, so this is currently unused.
  final ValueChanged<StockSegment> onOpenSegment;

  @override
  State<SkusSection> createState() => _SkusSectionState();
}

class _SkusSectionState extends State<SkusSection> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  InventoryController get ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    // Fresh search each time this section is shown.
    ctrl.clearSuggestions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Debounced live search as the user types.
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

  Future<void> _openDetail(LocationSuggestion s) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SkuDetailView(
          locationId: s.id,
          initialCode: s.code,
        ),
      ),
    );
    if (!mounted) return;
    ctrl.fetchStats();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header — subtitle + New SKU
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: CustomText(
                'Search a SKU to view and assign products, or create a new one.',
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            StockPillButton(
              icon: Icons.add_rounded,
              label: 'New SKU',
              dense: true,
              onTap: () => NewSkuDialog.show(context, ctrl),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Single SKU search → suggest (auto-runs as you type)
        StockSearchField(
          controller: _searchCtrl,
          hint: 'Search SKU code or name…',
          icon: Icons.search_rounded,
          onChanged: _onQueryChanged,
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 16),

        // Results: loading · error · list · empty · idle
        Obx(() {
          if (ctrl.isSuggesting) {
            return const _ListLoading();
          }
          if (ctrl.suggestError != null) {
            return StockStatsError(
              message: ctrl.suggestError!,
              onRetry: _search,
            );
          }
          if (!ctrl.hasSuggested) {
            return const _SkuHint(
              icon: Icons.inventory_2_outlined,
              message: 'Start typing to find a SKU.',
            );
          }
          final items = ctrl.suggestions;
          if (items.isEmpty) {
            return const _SkuHint(
              icon: Icons.search_off_rounded,
              message: 'No SKUs match your search.',
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
                    onTap: () => _openDetail(items[i]),
                  ),
                ],
              ],
            ),
          );
        }),
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

/// Search results skeleton while the suggest request is in flight.
class _ListLoading extends StatelessWidget {
  const _ListLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (i) {
        return Container(
          height: 56,
          margin: EdgeInsets.only(bottom: i == 2 ? 0 : 10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.inputBorder, width: 1),
          ),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Centered hint for the idle / no-results states.
class _SkuHint extends StatelessWidget {
  const _SkuHint({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 38, color: AppColors.textMuted.withOpacity(0.6)),
            const SizedBox(height: 12),
            CustomText(
              message,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              textAlign: TextAlign.center,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
