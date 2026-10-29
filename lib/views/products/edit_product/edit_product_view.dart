import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../controllers/seller_products_controller.dart';
import '../../../core/localization/translation_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../core/widgets/image_source_picker.dart';
import '../../../models/seller_product.dart';
import 'product_edit_form.dart';
import 'sections/attributes_section.dart';
import 'sections/general_section.dart';
import 'sections/history_section.dart';
import 'sections/inventory_section.dart';
import 'sections/pricing_section.dart';
import 'sections/shipping_section.dart';
import 'widgets/edit_inputs.dart';
import 'widgets/edit_reason_sheet.dart';

/// Edit screen for a product on one of the seller's stream product requests.
///
/// Layout only — the field state, change diff and validation live in
/// [ProductEditForm], and each tab is its own widget under `sections/`.
///
/// Flow (see `lib/raw/MOBILE_SELLER_PRODUCT_EDIT_API.md`):
/// 1. `GET /seller/products/{id}` prefills the form (fresh on every open).
/// 2. The seller edits; the pinned save bar counts the changes.
/// 3. Save asks for the mandatory reason, then `PATCH`es only what changed.
/// 4. A `403` means the request was submitted — the form turns read-only and
///    stays viewable, History included.
class EditProductView extends StatefulWidget {
  const EditProductView({
    super.key,
    required this.product,
    required this.ctrl,
  });

  /// The list row. Its `images` carry the stored image references the PATCH
  /// expects back, and its `editable` flag can lock the form up front.
  final SellerProduct product;
  final SellerProductsController ctrl;

  @override
  State<EditProductView> createState() => _EditProductViewState();
}

class _EditProductViewState extends State<EditProductView> {
  static const Set<String> _allowedImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  ProductEditForm? _form;
  bool _loadFailed = false;
  bool _uploading = false;
  EditSection _tab = EditSection.general;

  SellerProductsController get _ctrl => widget.ctrl;
  String get _id => widget.product.id;

  bool get _locked =>
      widget.product.editable == false || _ctrl.isEditLocked(_id);

  // Getter, not a stored list: the labels must re-resolve on a language switch.
  static Map<EditSection, String> get _labels => {
        EditSection.general: TKeys.secGeneral.tr,
        EditSection.pricing: TKeys.secPricing.tr,
        EditSection.inventory: TKeys.secWarehouse.tr,
        EditSection.shipping: TKeys.secShipping.tr,
        EditSection.attributes: TKeys.secAttributes.tr,
        EditSection.history: TKeys.secHistory.tr,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _form?.dispose();
    super.dispose();
  }

  /// Always re-reads the product: the form must diff against what the server
  /// holds now, not against a copy cached before someone else's edit.
  Future<void> _load() async {
    setState(() => _loadFailed = false);
    final detail = await _ctrl.loadDetail(_id, force: true) ??
        _ctrl.detailFor(_id);
    if (!mounted) return;
    if (detail == null) {
      setState(() => _loadFailed = true);
      return;
    }
    setState(() {
      _form = ProductEditForm(detail, imageRefs: widget.product.images);
    });
  }

  void _goTo(EditSection section) {
    FocusScope.of(context).unfocus();
    if (_tab != section) setState(() => _tab = section);
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _save(ProductEditForm form) async {
    FocusScope.of(context).unfocus();
    final problem = form.validate();
    if (problem != null) {
      _goTo(problem.section);
      AppSnackbar.show(TKeys.checkTheForm.tr, problem.message,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    // Asked at save time rather than living in a tab, so it can't be missed
    // by saving from whichever tab the seller happens to be on.
    final reason =
        await showEditReasonSheet(context, fieldCount: form.changeCount);
    if (reason == null || !mounted) return;

    final ok = await _ctrl.updateProduct(
      productId: _id,
      editReason: reason,
      changes: form.changes(),
    );
    if (!mounted) return;

    if (ok) {
      AppSnackbar.show(TKeys.savedTitle.tr, TKeys.productUpdated.tr,
          snackPosition: SnackPosition.BOTTOM);
      Navigator.of(context).pop(true);
    } else if (_locked) {
      setState(() {});
      AppSnackbar.show(TKeys.editLockedTitle.tr, TKeys.editLockedBody.tr,
          snackPosition: SnackPosition.BOTTOM);
    } else {
      AppSnackbar.show(
          TKeys.couldNotSave.tr, _ctrl.editError ?? TKeys.pleaseTryAgain.tr,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _addImages(ProductEditForm form) async {
    final room = ProductEditForm.maxImages - form.images.length;
    if (room <= 0) {
      AppSnackbar.show(TKeys.galleryFull.tr,
          TKeys.upToPhotos.trParams({'max': '${ProductEditForm.maxImages}'}),
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final picked = await ImageSourcePicker.pick(context, maxImages: room);
    if (picked.isEmpty || !mounted) return;

    final accepted = picked.where(_isAllowedImage).take(room).toList();
    if (accepted.isEmpty) {
      AppSnackbar.show(TKeys.unsupportedFile.tr, TKeys.useJpgPngWebp.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    setState(() => _uploading = true);
    final uploaded = <GalleryImage>[];
    for (final file in accepted) {
      final key = await _ctrl.uploadProductImage(file.path);
      if (key != null) uploaded.add(GalleryImage(ref: key, localPath: file.path));
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    form.addImages(uploaded);

    if (uploaded.length != accepted.length) {
      AppSnackbar.show(
        TKeys.somePhotosFailed.tr,
        TKeys.photosNotUploaded.trParams({
          'failed': '${accepted.length - uploaded.length}',
          'total': '${accepted.length}',
        }),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  bool _isAllowedImage(XFile file) {
    final name = file.name.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot >= 0 && _allowedImageExtensions.contains(name.substring(dot + 1));
  }

  /// Warns before dropping edits the seller has already made.
  Future<bool> _confirmDiscard() async {
    final form = _form;
    if (form == null || _locked || form.changes().isEmpty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: CustomText(TKeys.discardChangesTitle.tr,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary),
        content: CustomText(TKeys.discardChangesBody.tr,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: AppColors.textSecondary),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: CustomText(TKeys.keepEditing.tr,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: CustomText(TKeys.discardAction.tr,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.vipps),
          ),
        ],
      ),
    );
    return leave == true;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final form = _form;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: editCanvas,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomText(TKeys.editProduct.tr,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
              if (widget.product.name.isNotEmpty)
                CustomText(widget.product.name,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: AppColors.textMuted),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: form != null
              ? ListenableBuilder(
                  listenable: form,
                  builder: (_, __) => _content(form),
                )
              : _loadFailed
                  ? _LoadFailed(onRetry: _load)
                  : const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
      ),
    );
  }

  Widget _content(ProductEditForm form) {
    final locked = _locked;
    final dirty = form.dirtySections;

    return Column(
      children: [
        _TabStrip(
          labels: _labels,
          selected: _tab,
          dirty: dirty,
          onChanged: _goTo,
        ),
        Expanded(
          // IndexedStack keeps every tab's fields and scroll position alive,
          // so a half-typed value survives a trip to another tab.
          child: IndexedStack(
            index: _tab.index,
            children: [
              for (final section in EditSection.values)
                _scroll(section, form, locked),
            ],
          ),
        ),
        if (!locked && _tab != EditSection.history)
          Obx(() => _SaveBar(
                count: form.changeCount,
                busy: _ctrl.isSavingEdit,
                blocked: _uploading,
                onSave: () => _save(form),
              )),
      ],
    );
  }

  Widget _scroll(EditSection section, ProductEditForm form, bool locked) {
    final body = switch (section) {
      EditSection.general => GeneralSection(
          form: form,
          uploading: _uploading,
          onAddImages: () => _addImages(form),
        ),
      EditSection.pricing => PricingSection(form: form),
      EditSection.inventory => InventorySection(form: form),
      EditSection.shipping => ShippingSection(form: form),
      EditSection.attributes => AttributesSection(form: form),
      EditSection.history => HistorySection(productId: _id, ctrl: _ctrl),
    };
    final editable = section != EditSection.history;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (locked && editable)
            EditBanner(TKeys.editLockedBody.tr,
                title: TKeys.editLockedTitle.tr, tone: EditBannerTone.locked)
          else if (section == EditSection.general)
            EditBanner(TKeys.editLoggedNote.tr),
          // Locked fields stay readable (the scroll view is outside) but take
          // no input.
          if (locked && editable)
            AbsorbPointer(child: Opacity(opacity: 0.6, child: body))
          else
            body,
        ],
      ),
    );
  }
}

// ── Chrome ───────────────────────────────────────────────────────────────────

/// The web console's left-hand section menu as a scrollable pill row. A dot
/// marks tabs holding unsaved changes.
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.labels,
    required this.selected,
    required this.dirty,
    required this.onChanged,
  });

  final Map<EditSection, String> labels;
  final EditSection selected;
  final Set<EditSection> dirty;
  final ValueChanged<EditSection> onChanged;

  @override
  Widget build(BuildContext context) {
    const sections = EditSection.values;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderGrey)),
      ),
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final section = sections[i];
          final on = section == selected;
          return GestureDetector(
            onTap: () => onChanged(section),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.brandNavy : AppColors.inputFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: on ? AppColors.brandNavy : AppColors.borderGrey,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomText(labels[section]!,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: on ? AppColors.white : AppColors.textSecondary),
                  if (dirty.contains(section)) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.brandYellow,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Pinned footer: how many changes will be sent, and the save action.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.count,
    required this.busy,
    required this.blocked,
    required this.onSave,
  });

  final int count;
  final bool busy;
  final bool blocked;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderGrey)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: CustomText(
              count == 0
                  ? TKeys.noChangesYet.tr
                  : (count == 1 ? TKeys.fieldChanged : TKeys.fieldsChanged)
                      .trParams({'count': '$count'}),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: count == 0 ? AppColors.textMuted : AppColors.brandNavy,
            ),
          ),
          const SizedBox(width: 12),
          EditPrimaryButton(
            label: TKeys.saveChanges.tr,
            loading: busy,
            enabled: !blocked && count > 0,
            onTap: onSave,
            expand: false,
          ),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 40, color: AppColors.textMuted),
            const SizedBox(height: 12),
            CustomText(TKeys.editLoadFailed.tr,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                textAlign: TextAlign.center,
                color: AppColors.textSecondary),
            const SizedBox(height: 16),
            EditPrimaryButton(
              label: TKeys.retry.tr,
              onTap: onRetry,
              expand: false,
            ),
          ],
        ),
      ),
    );
  }
}
