// import 'dart:async';

import 'package:flutter/material.dart';

import '../../../controllers/inventory_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
// import '../../../models/location_suggestion.dart';
// import '../sku_detail_view.dart';
import '../shared/stock_segment.dart';
import '../shared/stock_widgets.dart';
import '../widgets/new_sku_dialog.dart';

/// Overview — stat cards on top, then quick actions to jump into the other
/// warehouse sections (or create a new SKU).
class OverviewSection extends StatefulWidget {
  const OverviewSection({super.key, required this.ctrl, this.onOpenSegment});
  final InventoryController ctrl;

  /// Lets a quick action switch the Warehouse tab to another segment.
  final ValueChanged<StockSegment>? onOpenSegment;

  @override
  State<OverviewSection> createState() => _OverviewSectionState();
}

class _OverviewSectionState extends State<OverviewSection> {
  // final _searchCtrl = TextEditingController();
  // Timer? _debounce;

  InventoryController get ctrl => widget.ctrl;

  @override
  void dispose() {
    // _debounce?.cancel();
    // _searchCtrl.dispose();
    super.dispose();
  }

  // ── SKU search (disabled — replaced by quick actions) ───────────────────
  // @override
  // void initState() {
  //   super.initState();
  //   // A fresh search each time Overview is opened.
  //   ctrl.clearSuggestions();
  // }
  //
  // /// Debounced live search as the user types.
  // void _onQueryChanged(String value) {
  //   _debounce?.cancel();
  //   final q = value.trim();
  //   if (q.isEmpty) {
  //     ctrl.clearSuggestions();
  //     return;
  //   }
  //   _debounce = Timer(const Duration(milliseconds: 350), () {
  //     ctrl.suggestLocations(q);
  //   });
  // }
  //
  // void _search() {
  //   _debounce?.cancel();
  //   FocusScope.of(context).unfocus();
  //   ctrl.suggestLocations(_searchCtrl.text);
  // }
  //
  // Future<void> _openDetail(LocationSuggestion s) async {
  //   FocusScope.of(context).unfocus();
  //   await Navigator.of(context).push(
  //     MaterialPageRoute(
  //       builder: (_) => SkuDetailView(
  //         locationId: s.id,
  //         initialCode: s.code,
  //       ),
  //     ),
  //   );
  //   if (!mounted) return;
  //   // Refresh stats in case products were assigned on the detail page.
  //   ctrl.fetchStats();
  // }

  void _go(StockSegment s) => widget.onOpenSegment?.call(s);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stat cards — live from GET /api/v1/seller/inventory/stats
        StockStatsCards(ctrl: ctrl, compact: true),

        const SizedBox(height: 20),

        const CustomText(
          'Quick actions',
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.inventory_2_rounded,
                title: 'Manage SKUs',
                subtitle: 'Search & open SKUs',
                onTap: () => _go(StockSegment.skus),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.add_box_rounded,
                title: 'Assign to SKU',
                subtitle: 'Scan products in',
                onTap: () => _go(StockSegment.assign),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.search_rounded,
                title: 'Search',
                subtitle: 'By UPC or tag',
                onTap: () => _go(StockSegment.search),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.add_rounded,
                title: 'New SKU',
                subtitle: 'Create a bin',
                highlighted: true,
                onTap: () => NewSkuDialog.show(context, ctrl),
              ),
            ),
          ],
        ),

        // ── SKU search UI (disabled — replaced by quick actions above) ──────
        /*
        const CustomText(
          'Find a SKU',
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        const SizedBox(height: 2),
        const CustomText(
          'Search a SKU code or name, then open it to view and assign products.',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.35,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 10),

        // SKU search → suggest (auto-runs as you type)
        StockSearchField(
          controller: _searchCtrl,
          hint: 'Search SKU…',
          icon: Icons.search_rounded,
          onChanged: _onQueryChanged,
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 12),

        // Results: loading · error · list · empty
        Obx(() {
          if (ctrl.isSuggesting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
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

          final error = ctrl.suggestError;
          if (error != null) {
            return StockStatsError(message: error, onRetry: _search);
          }

          if (!ctrl.hasSuggested) return const SizedBox.shrink();

          final items = ctrl.suggestions;
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CustomText(
                  'No SKUs match your search.',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
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
                  _SuggestionRow(
                    suggestion: items[i],
                    onTap: () => _openDetail(items[i]),
                  ),
                ],
              ],
            ),
          );
        }),
        */
      ],
    );
  }
}

/// A square-ish quick action card — icon, title, subtitle.
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? AppColors.brandNavy : AppColors.white;
    final fg = highlighted ? AppColors.white : AppColors.textPrimary;
    final sub = highlighted
        ? AppColors.white.withOpacity(0.7)
        : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted ? AppColors.brandNavy : AppColors.inputBorder,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: highlighted
                    ? AppColors.white.withOpacity(0.14)
                    : AppColors.brandYellow.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: highlighted ? AppColors.white : AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 12),
            CustomText(
              title,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
            const SizedBox(height: 2),
            CustomText(
              subtitle,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: sub,
            ),
          ],
        ),
      ),
    );
  }
}

// ── SKU suggestion row (disabled — used by the commented search list) ───────
/*
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion, required this.onTap});
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
*/
