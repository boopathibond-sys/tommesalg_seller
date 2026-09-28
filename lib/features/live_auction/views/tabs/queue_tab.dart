import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../../../core/widgets/image_pick_crop.dart';
import '../../controllers/auction_room_controller.dart';
import '../../data/models/auction_room_snapshot.dart';
import '../../data/models/catalog_product.dart';
import '../widgets/room_sheets.dart';
import '../../../../core/localization/translation_keys.dart';

/// The queue as its own page, pushed from the circular queue button beside the
/// Live tab's chat field.
///
/// The room lost its bottom nav so the camera could own the whole screen, so
/// the queue is no longer a sibling tab — it is a route over the stage, with a
/// back arrow that returns straight to the broadcast. The controller is passed
/// in (already `Get.put` under the stream tag by the room), so pushing this
/// never re-creates a session.
class QueuePage extends StatelessWidget {
  const QueuePage({super.key, required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
        ),
        title: Obx(() => CustomText(
              // The count is the reason the seller opened this page, and the
              // round button in the stream no longer badges it, so the title is
              // the one place it shows.
              TKeys.qtProductQueueTitle
                  .trParams({'count': '${ctrl.queueView.length}'}),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            )),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: QueueTab(ctrl: ctrl),
        ),
      ),
    );
  }
}

/// The Queue tab: ordered product list with add / remove / reorder / clear.
/// Mutations are snapshot-authoritative — a spinner shows while the server
/// applies the change; no optimistic reordering.
class QueueTab extends StatelessWidget {
  const QueueTab({super.key, required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _QueueActions(ctrl: ctrl),
            Expanded(
              child: Obx(() {
                final canManage = ctrl.canManageQueue;
                final queue = ctrl.queueView;
                if (queue.isEmpty) return _EmptyQueue(canManage: canManage);
                // Drag-to-reorder: grab the handle on the left and drop the lot
                // wherever you want; the position is persisted on release.
                return ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  physics: const BouncingScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: queue.length,
                  onReorder: ctrl.moveProduct,
                  proxyDecorator: _dragProxy,
                  itemBuilder: (_, i) => _QueueRow(
                    key: ValueKey(queue[i].productId),
                    ctrl: ctrl,
                    product: queue[i],
                    index: i,
                    canDrag: canManage,
                  ),
                );
              }),
            ),
          ],
        ),
        Obx(() => ctrl.queueActionLoading.value
            ? Positioned.fill(
                child: Container(
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppColors.brandNavy)),
                ),
              )
            : const SizedBox.shrink()),
      ],
    );
  }
}

class _QueueActions extends StatelessWidget {
  const _QueueActions({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Obx(() {
        // Queue management (add / clear / reorder / remove) only needs a live
        // session — NOT auction control. Per the V1 API, only Start / End /
        // Dutch-reduce are controller-gated (lib/api_details §2).
        // Two sellers rearranging one queue from two handsets is how a lot
        // gets started on the wrong product, so the queue stays with whoever
        // is running the auction. A watcher is told why and can ask for it.
        if (!ctrl.isController) return const _QueueLockedNote();
        final canManage = ctrl.canManageQueue;
        return Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: TKeys.qtAddProduct.tr,
                icon: Icons.add_rounded,
                enabled: canManage,
                onTap: () => _openAddSheet(context, ctrl),
              ),
            ),
            const SizedBox(width: 10),
            _ActionButton(
              label: TKeys.ctClear.tr,
              icon: Icons.clear_all_rounded,
              outlined: true,
              enabled: canManage && ctrl.productQueue.isNotEmpty,
              onTap: () => _confirmClear(context, ctrl),
            ),
          ],
        );
      }),
    );
  }
}

/// Replaces the Add / Clear row on a device without auction control: says why
/// the queue is read-only here, rather than leaving two greyed-out buttons to
/// be read as a bug.
class _QueueLockedNote extends StatelessWidget {
  const _QueueLockedNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: CustomText(TKeys.qtQueueLocked.tr,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmClear(BuildContext context, AuctionRoomController ctrl) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: CustomText(TKeys.qtClearQueueTitle.tr, fontSize: 18,
          fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      content: CustomText(TKeys.qtClearQueueBody.tr,
          fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: CustomText(TKeys.cancelAction.tr, fontSize: 14,
              fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(true),
          child: CustomText(TKeys.ctClear.tr, fontSize: 14,
              fontWeight: FontWeight.w800, color: AppColors.vipps),
        ),
      ],
    ),
  );
  if (ok == true) await ctrl.clearQueue();
}

/// Confirms before pulling a lot out of the queue — the row's Remove button is
/// a single tap next to Pre-bids, so a misfire would otherwise silently drop a
/// product the seller lined up.
Future<void> _confirmRemove(
  BuildContext context,
  AuctionRoomController ctrl,
  AuctionProduct product,
) async {
  final ok = await showConfirmDialog(
    context: context,
    title: TKeys.qtRemoveFromQueue.tr,
    message: '"${product.title}" will be taken out of this stream\'s queue.',
    confirmLabel: TKeys.removeAction.tr,
    icon: Icons.remove_shopping_cart_outlined,
  );
  if (ok) await ctrl.removeProduct(product.productId);
}

Future<void> _openAddSheet(BuildContext context, AuctionRoomController ctrl) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CatalogSheet(ctrl: ctrl),
  );
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.ctrl,
    required this.product,
    required this.index,
    required this.canDrag,
  });
  final AuctionRoomController ctrl;
  final AuctionProduct product;
  final int index;
  final bool canDrag;

  @override
  Widget build(BuildContext context) {
    // Reorder / remove need only a live session, not auction control (§2).
    final canManage = ctrl.canManageQueue;
    return Container(
      // ReorderableListView.builder has no separators — space rows via margin.
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Drag handle on the left — press and drag to move the lot anywhere
          // in the queue.
          if (canDrag) ...[
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                child: Icon(Icons.drag_indicator_rounded,
                    size: 22, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Container(
            width: 26, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.brandYellow.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomText('${index + 1}', fontSize: 12,
                fontWeight: FontWeight.w800, color: AppColors.brandNavy),
          ),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 46, height: 46, color: AppColors.inputFill,
              child: product.image != null
                  ? Image.network(product.image!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_outlined, color: AppColors.textMuted))
                  : const Icon(Icons.shopping_bag_outlined, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(product.title, fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _TypeTag(isDutch: product.isDutch),
                    if (product.startingPrice != null) ...[
                      const SizedBox(width: 6),
                      CustomText(
                      TKeys.qtFromKr
                          .trParams({'price': _n(product.startingPrice!)}),
                          fontSize: 11.5, fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Row actions stack vertically so both can carry a readable label
          // rather than an icon; a fixed width keeps them equal.
          SizedBox(
            width: 88,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TextBtn(
                  label: TKeys.qtPreBids.tr,
                  onTap: () => showPreBidsSheet(
                    context,
                    ctrl,
                    productId: product.productId,
                    productTitle: product.title,
                  ),
                ),
                if (canManage) ...[
                  const SizedBox(height: 6),
                  _TextBtn(
                    label: TKeys.removeAction.tr,
                    destructive: true,
                    onTap: () => _confirmRemove(context, ctrl, product),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lifts the dragged row with a subtle scale + shadow so it reads as "picked
/// up" while being dragged to its new slot.
Widget _dragProxy(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = Curves.easeInOut.transform(animation.value);
      return Transform.scale(
        scale: 1 + 0.03 * t,
        child: Material(
          color: Colors.transparent,
          elevation: 10 * t,
          shadowColor: Colors.black.withOpacity(0.28),
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
      );
    },
  );
}

/// Multi-select product picker backed by `GET /auction-room/queue/catalog`.
/// Tapping rows toggles a selection; "Add" batch-enqueues them all, then the
/// controller reloads the catalog so `inQueue` flags refresh.
class _CatalogSheet extends StatefulWidget {
  const _CatalogSheet({required this.ctrl});
  final AuctionRoomController ctrl;
  @override
  State<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends State<_CatalogSheet> {
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    widget.ctrl.fetchCatalog();
  }

  void _toggle(CatalogProduct p) {
    setState(() {
      if (!_selected.remove(p.productId)) _selected.add(p.productId);
    });
  }

  /// Products already queued can't be picked again, so bulk actions only ever
  /// touch the selectable rows.
  Iterable<CatalogProduct> get _selectable =>
      widget.ctrl.catalogProducts.where((p) => !p.inQueue);

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_selectable.map((p) => p.productId));
    });
  }

  void _clearAll() => setState(_selected.clear);

  Future<void> _submit() async {
    if (_selected.isEmpty) return;
    final ids = _selected.toList();
    Navigator.of(context).pop();
    await widget.ctrl.addCatalogProducts(ids);
  }

  /// Opens the "create random product" form over this sheet. On success the lot
  /// is already created *and* queued, and the catalog behind refreshes with it
  /// flagged as queued.
  Future<void> _addRandom() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RandomProductSheet(ctrl: widget.ctrl),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.inputBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: CustomText(TKeys.qtAddProduct.tr, fontSize: 19,
                          fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    TextButton.icon(
                      onPressed: _addRandom,
                      icon: const Icon(Icons.shuffle_rounded,
                          size: 16, color: AppColors.brandNavy),
                      label: CustomText(TKeys.qtAddRandomProduct.tr,
                          fontSize: 12.5, fontWeight: FontWeight.w700,
                          color: AppColors.brandNavy),
                    ),
                  ],
                ),
              ),
              // Bulk selection: "Select all" picks every selectable row;
              // "Clear all" only appears once something is selected.
              Obx(() {
                final selectableCount = _selectable.length;
                if (selectableCount == 0) return const SizedBox(height: 4);
                final allSelected = _selected.length >= selectableCount;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      _BulkAction(
                        label: TKeys.qtSelectAll
                  .trParams({'count': '$selectableCount'}),
                        icon: Icons.done_all_rounded,
                        onTap: allSelected ? null : _selectAll,
                      ),
                      if (_selected.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _BulkAction(
                          label: TKeys.qtClearAll.tr,
                          icon: Icons.remove_done_rounded,
                          onTap: _clearAll,
                        ),
                      ],
                      const Spacer(),
                      CustomText('${_selected.length} selected',
                          fontSize: 11.5, fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary),
                    ],
                  ),
                );
              }),
              Expanded(
                child: Obx(() {
                  if (ctrl.loadingCatalog.value && ctrl.catalogProducts.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(AppColors.brandNavy)),
                    );
                  }
                  final products = ctrl.catalogProducts;
                  if (products.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CustomText(
                          'No products available to add. Prepare products for '
                          'this stream first.',
                          fontSize: 13, fontWeight: FontWeight.w500,
                          textAlign: TextAlign.center, color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final p = products[i];
                      return _CatalogRow(
                        product: p,
                        selected: _selected.contains(p.productId),
                        onTap: p.inQueue ? null : () => _toggle(p),
                      );
                    },
                  );
                }),
              ),
              _CatalogFooter(
                count: _selected.length,
                onCancel: () => Navigator.of(context).pop(),
                onAdd: _submit,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Create random product" — the mystery-lot form from the web console, as a
/// keyboard-aware bottom sheet.
///
/// All four parts (title, description, stock, image) are required by the API,
/// and the image travels with the create call as a multipart file rather than
/// being uploaded separately first. Creating also queues the lot, so the seller
/// is done in one step.
class _RandomProductSheet extends StatefulWidget {
  const _RandomProductSheet({required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  State<_RandomProductSheet> createState() => _RandomProductSheetState();
}

class _RandomProductSheetState extends State<_RandomProductSheet> {
  /// The API's cap on the image part.
  static const int _maxImageBytes = 5 * 1024 * 1024;

  final _title = TextEditingController();
  final _description =
      TextEditingController(text: TKeys.qtRandomStreamProduct.tr);
  final _stock = TextEditingController(text: '1');

  String? _imagePath;

  AuctionRoomController get ctrl => widget.ctrl;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    // Same picker the stream thumbnail uses — source sheet, then a crop framed
    // to the square the lot is displayed in.
    final path = await pickAndCropImage(
      context,
      title: TKeys.qtProductImage.tr,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      maxWidth: 1600,
    );
    if (path == null || !mounted) return;

    if (await File(path).length() > _maxImageBytes) {
      if (!mounted) return;
      Get.snackbar(TKeys.qtImageTooLarge.tr, TKeys.qtPickSmallerImage.tr);
      return;
    }
    if (!mounted) return;
    setState(() => _imagePath = path);
  }

  String? _validate() {
    if (_title.text.trim().isEmpty) return TKeys.qtGiveTitle.tr;
    if (_description.text.trim().isEmpty) return TKeys.qtAddShortDescription.tr;
    final stock = int.tryParse(_stock.text.trim());
    if (stock == null || stock < 1 || stock > 1000) {
      return TKeys.qtStockRange.tr;
    }
    if (_imagePath == null) return TKeys.qtPickProductImage.tr;
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final problem = _validate();
    if (problem != null) {
      Get.snackbar(TKeys.checkTheForm.tr, problem);
      return;
    }

    final title = _title.text.trim();
    final ok = await ctrl.createRandomProduct(
      title: title,
      description: _description.text.trim(),
      stock: int.parse(_stock.text.trim()),
      imagePath: _imagePath!,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      Get.snackbar(TKeys.qtAddedToQueue.tr, '"$title" is lined up as a random lot.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.inputBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
                child: Row(
                  children: [
                    const Icon(Icons.shuffle_rounded,
                        size: 18, color: Color(0xFF6A1B9A)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CustomText(TKeys.qtCreateRandomProduct.tr,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      // Echoes the highlighted panel the web form uses for this
                      // block, so it reads as a distinct create action rather
                      // than part of the picker behind it.
                      color: AppColors.brandYellow.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.brandYellow.withOpacity(0.55)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SheetField(
                          label: TKeys.csTitle.tr,
                          controller: _title,
                          hint: TKeys.qtMysteryItem.tr,
                        ),
                        const SizedBox(height: 12),
                        _SheetField(
                          label: TKeys.fieldDescription.tr,
                          controller: _description,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        _SheetField(
                          label: TKeys.qtStock.tr,
                          controller: _stock,
                          hint: '1–1000',
                          numeric: true,
                        ),
                        const SizedBox(height: 14),
                        CustomText(TKeys.qtImage.tr,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary),
                        const SizedBox(height: 8),
                        _ImagePickerTile(
                          path: _imagePath,
                          onTap: _pickImage,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Obx(() {
                  final busy = ctrl.creatingRandomProduct.value;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: busy ? null : () => Navigator.of(context).pop(),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.inputBorder),
                          ),
                          child: CustomText(TKeys.cancelAction.tr,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Opacity(
                        opacity: busy ? 0.6 : 1,
                        child: GestureDetector(
                          onTap: busy ? null : _submit,
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 26),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.brandNavy,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      valueColor: AlwaysStoppedAnimation(
                                          AppColors.white),
                                    ),
                                  )
                                : CustomText(TKeys.qtCreate.tr,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square image slot for the random-product form: empty prompt, or the picked
/// shot with a "Change" affordance.
class _ImagePickerTile extends StatelessWidget {
  const _ImagePickerTile({required this.path, required this.onTap});
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        height: 104,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.inputBorder),
        ),
        child: path == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_outlined,
                      size: 24, color: AppColors.brandNavy),
                  const SizedBox(height: 6),
                  CustomText(TKeys.qtChooseFile.tr,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandNavy),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(path!), fit: BoxFit.cover),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: AppColors.brandNavy.withOpacity(0.75),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      alignment: Alignment.center,
                      child: CustomText(TKeys.csChange.tr,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.white),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Labelled input used by the random-product form.
class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.numeric = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(label,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType:
              numeric ? TextInputType.number : TextInputType.multiline,
          inputFormatters:
              numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
            filled: true,
            fillColor: AppColors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.brandNavy, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small pill used for the catalog sheet's bulk-selection actions.
class _BulkAction extends StatelessWidget {
  const _BulkAction({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.brandNavy),
              const SizedBox(width: 5),
              CustomText(label, fontSize: 11.5,
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.product,
    required this.selected,
    required this.onTap,
  });
  final CatalogProduct product;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final disabled = p.inQueue;
    final image = p.displayImage;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandNavy.withOpacity(0.05) : AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brandNavy : AppColors.inputBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _Checkbox(checked: selected || disabled, dimmed: disabled),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 44, height: 44, color: AppColors.inputFill,
                  child: image != null
                      ? Image.network(image, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.image_outlined, color: AppColors.textMuted))
                      : const Icon(Icons.shopping_bag_outlined,
                          color: AppColors.textMuted),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(p.name, fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _CatalogTypeTag(isRandom: p.isRandom),
                        if (p.inQueue) ...[
                          const SizedBox(width: 6),
                          CustomText(TKeys.qtInQueue.tr, fontSize: 11,
                              fontWeight: FontWeight.w700, color: AppColors.textMuted),
                        ] else if (p.startingPrice != null) ...[
                          const SizedBox(width: 6),
                          CustomText(
                      TKeys.qtFromKr.trParams({'price': _n(p.startingPrice!)}),
                              fontSize: 11.5, fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.checked, required this.dimmed});
  final bool checked;
  final bool dimmed;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22, height: 22, alignment: Alignment.center,
      decoration: BoxDecoration(
        color: checked
            ? (dimmed ? AppColors.textMuted : AppColors.brandNavy)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked ? Colors.transparent : AppColors.inputBorder,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 15, color: AppColors.white)
          : const SizedBox.shrink(),
    );
  }
}

class _CatalogTypeTag extends StatelessWidget {
  const _CatalogTypeTag({required this.isRandom});
  final bool isRandom;
  @override
  Widget build(BuildContext context) {
    final c = isRandom ? const Color(0xFF6A1B9A) : AppColors.brandNavy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomText(isRandom ? 'RANDOM' : 'USUAL', fontSize: 9.5,
          fontWeight: FontWeight.w800, color: c),
    );
  }
}

class _CatalogFooter extends StatelessWidget {
  const _CatalogFooter({
    required this.count,
    required this.onCancel,
    required this.onAdd,
  });
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    final canAdd = count > 0;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.inputBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: onCancel,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.inputBorder),
              ),
              child: CustomText(TKeys.cancelAction.tr, fontSize: 13.5,
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 10),
          Opacity(
            opacity: canAdd ? 1 : 0.45,
            child: GestureDetector(
              onTap: canAdd ? onAdd : null,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandNavy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CustomText(
                    canAdd
                        ? TKeys.qtAddCount.trParams({'count': '$count'})
                        : TKeys.addAction.tr,
                    fontSize: 13.5, fontWeight: FontWeight.w800,
                    color: AppColors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.isDutch});
  final bool isDutch;
  @override
  Widget build(BuildContext context) {
    final c = isDutch ? const Color(0xFF6A1B9A) : AppColors.brandNavy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomText(
          isDutch
              ? TKeys.auctionTypeDutchCaps.tr
              : TKeys.auctionTypeNormalCaps.tr,
          fontSize: 9.5,
          fontWeight: FontWeight.w800, color: c),
    );
  }
}

/// Compact labelled pill for a queue row's inline actions. Reads clearer than a
/// bare icon for something as un-iconic as "Pre-bids".
class _TextBtn extends StatelessWidget {
  const _TextBtn({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
  final String label;
  final VoidCallback onTap;

  /// Tints the pill red for actions that take something away.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? AppColors.vipps : AppColors.brandNavy;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: destructive ? fg.withOpacity(0.06) : AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: destructive ? fg.withOpacity(0.35) : AppColors.inputBorder),
        ),
        child: CustomText(label, fontSize: 11.5,
            fontWeight: FontWeight.w800, maxLines: 1, color: fg),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.outlined = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final bool outlined;
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: outlined ? AppColors.white : AppColors.brandNavy,
            borderRadius: BorderRadius.circular(12),
            border: outlined ? Border.all(color: AppColors.inputBorder) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18,
                  color: outlined ? AppColors.brandNavy : AppColors.brandYellow),
              const SizedBox(width: 7),
              CustomText(label, fontSize: 13.5, fontWeight: FontWeight.w800,
                  color: outlined ? AppColors.textPrimary : AppColors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.canManage});

  /// Whether this device may fill the queue. A watcher is pointed at the device
  /// that can, instead of at an "Add product" button it doesn't have.
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 12),
            CustomText(TKeys.qtQueueEmpty.tr, fontSize: 16,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            const SizedBox(height: 4),
            CustomText(
                canManage ? TKeys.qtTapAddProduct.tr : TKeys.qtQueueLocked.tr,
                fontSize: 13, fontWeight: FontWeight.w500,
                textAlign: TextAlign.center, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

String _n(num v) => v % 1 == 0 ? '${v.toInt()}' : '$v';
