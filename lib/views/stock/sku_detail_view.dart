import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/inventory_controller.dart';
import '../../controllers/sku_detail_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/branded_refresh_indicator.dart';
import '../../core/widgets/custom_text.dart';
import '../../models/inventory_location_detail.dart';
import '../../models/inventory_placement.dart';
import 'assign/assign_products_panel.dart';
import 'shared/assigned_product_quick_view.dart';
import 'shared/sku_products_section.dart';
import 'widgets/new_sku_dialog.dart';
import '../../core/localization/translation_keys.dart';

/// Result a [SkuDetailView] can pop with, so the caller can react — e.g.
/// switch the Warehouse tab to "Assign to SKU".
enum SkuDetailResult { assign }

/// Full-page SKU detail — mobile port of the web SKU detail screen.
///
/// Loads `GET /locations/{id}` (record + tags) and
/// `GET /locations/{id}/placements` (assigned products), and offers Edit /
/// Deactivate (`PATCH /locations/{id}`) plus per-product quantity edits.
class SkuDetailView extends StatefulWidget {
  const SkuDetailView({
    super.key,
    required this.locationId,
    this.initialCode,
  });

  final String locationId;

  /// Shown in the title bar before the detail request resolves.
  final String? initialCode;

  @override
  State<SkuDetailView> createState() => _SkuDetailViewState();
}

class _SkuDetailViewState extends State<SkuDetailView> {
  late final SkuDetailController ctrl = Get.put(
    SkuDetailController(widget.locationId),
    tag: widget.locationId,
  );

  @override
  void dispose() {
    Get.delete<SkuDetailController>(tag: widget.locationId);
    super.dispose();
  }

  /// After a known product is scanned / typed and assigned to this SKU, reload
  /// the placements so the new row exists, then open its quick view (read-only
  /// product info + the report-a-discrepancy functions, with a close button) —
  /// mirroring the Assign-to-SKU flow.
  Future<void> _onKnownProductAdded(String productId) async {
    await ctrl.fetchPlacements();
    if (!mounted) return;

    InventoryPlacement? placement;
    for (final p in ctrl.placements) {
      if (p.productId == productId) {
        placement = p;
        break;
      }
    }
    if (placement == null) return;

    await AssignedProductQuickView.show(context, ctrl, placement);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        surfaceTintColor: AppColors.white,
        foregroundColor: AppColors.textPrimary,
        title: Obx(() => CustomText(
              ctrl.detail?.code ?? widget.initialCode ?? 'SKU',
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            )),
        actions: [
          Obx(() {
            final d = ctrl.detail;
            return TextButton.icon(
              onPressed: d == null
                  ? null
                  : () => NewSkuDialog.show(
                        context,
                        getOrPut(() => InventoryController()),
                        initial: d,
                        detailCtrl: ctrl,
                      ),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: CustomText(
                TKeys.edit.tr,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandNavy,
              ),
            );
          }),
          const SizedBox(width: 6),
        ],
      ),
      body: Obx(() {
        if (ctrl.isLoadingDetail && ctrl.detail == null) {
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
            ),
          );
        }

        if (ctrl.detailError != null && ctrl.detail == null) {
          return _DetailError(message: ctrl.detailError!, onRetry: ctrl.fetchDetail);
        }

        final d = ctrl.detail;
        if (d == null) return const SizedBox.shrink();

        return BrandedRefreshIndicator(
          onRefresh: () async {
            await ctrl.fetchDetail();
            await ctrl.fetchPlacements();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _Header(detail: d),
              const SizedBox(height: 20),
              _TagsCard(detail: d),
              const SizedBox(height: 24),

              // ── Assign product ──────────────────────────────────────────
              CustomText(
                TKeys.stAssignProductCaps.tr,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 4),
              CustomText(
                TKeys.stAssignProductBody.tr,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              AssignProductsPanel(
                ctrl: getOrPut(() => InventoryController()),
                locationId: widget.locationId,
                onAdded: () {
                  ctrl.fetchDetail();
                  ctrl.fetchPlacements();
                  // An unknown UPC becomes a pending product, so refresh that
                  // list too (it backs the Pending tab below).
                  ctrl.fetchPendingUnknown();
                },
                // Known product → open its quick view right after it's assigned.
                onKnownProductAdded: _onKnownProductAdded,
              ),

              const SizedBox(height: 24),
              CustomText(
                TKeys.stProductsInSkuCaps.tr,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 12),
              // Assigned + pending lists with edit / delete (shared with the
              // Assign screen).
              SkuProductsSection(
                detailCtrl: ctrl,
                inventoryCtrl: getOrPut(() => InventoryController()),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — code, name, status badges
// ─────────────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.detail});
  final InventoryLocationDetail detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(
          TKeys.stSkuCodeCaps.tr,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 4),
        CustomText(
          detail.code,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          color: AppColors.textPrimary,
        ),
        if (detail.name.isNotEmpty) ...[
          const SizedBox(height: 4),
          CustomText(
            detail.name,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusBadge(
              label: detail.isActive ? 'ACTIVE' : 'INACTIVE',
              color: detail.isActive
                  ? AppColors.mascotShadow
                  : AppColors.textMuted,
              filled: true,
            ),
            _StatusBadge(
              label: (detail.placementCount == 1
                      ? TKeys.stProductAssignedBadge
                      : TKeys.stProductsAssignedBadge)
                  .trParams({'count': '${detail.placementCount}'}),
              color: AppColors.textSecondary,
            ),
            Obx(() {
              final ctrl = Get.find<SkuDetailController>(tag: detail.id);
              return _StatusBadge(
                label: TKeys.stPrimaryCountCaps
                    .trParams({'count': '${ctrl.primaryCount}'}),
                color: AppColors.brandYellow,
              );
            }),
          ],
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    this.filled = false,
  });
  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(filled ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomText(
        label,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
        color: color,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tags + location path card
// ─────────────────────────────────────────────────────────────────────────────
class _TagsCard extends StatelessWidget {
  const _TagsCard({required this.detail});
  final InventoryLocationDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            TKeys.stSkuTagsCaps.tr,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          if (detail.tags.isEmpty && detail.tagSlugs.isEmpty)
            CustomText(
              TKeys.stNoTags.tr,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in _tagLabels(detail))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.brandNavy,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: CustomText(
                      label.toUpperCase(),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: AppColors.white,
                    ),
                  ),
              ],
            ),
          if (detail.locationPath.isNotEmpty) ...[
            const SizedBox(height: 16),
            CustomText(
              detail.locationPath,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }

  /// Prefer the rich tag list (labels); fall back to slugs if the detail
  /// response only carried `tagSlugs`.
  List<String> _tagLabels(InventoryLocationDetail detail) {
    if (detail.tags.isNotEmpty) return detail.tags.map((t) => t.label).toList();
    return detail.tagSlugs;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared error card
// ─────────────────────────────────────────────────────────────────────────────
class _DetailError extends StatelessWidget {
  const _DetailError({
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 18, color: AppColors.vipps),
              const SizedBox(width: 8),
              Expanded(
                child: CustomText(
                  message,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.brandNavy,
                borderRadius: BorderRadius.circular(10),
              ),
              child: CustomText(
                TKeys.tryAgain.tr,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.white,
              ),
            ),
          ),
        ],
      ),
    );
    return Center(
        child: Padding(padding: const EdgeInsets.all(20), child: card));
  }
}
