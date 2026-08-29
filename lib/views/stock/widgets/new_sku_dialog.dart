import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../controllers/inventory_controller.dart';
import '../../../controllers/sku_detail_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/inventory_location_detail.dart';
import '../../../models/inventory_tag.dart';
import '../../../core/localization/translation_keys.dart';

/// SKU create / edit dialog (see design in
/// `lib/raw/Screenshot 2026-06-04 at 7.42.37 PM.png`).
///
/// Collects the SKU fields, lets the seller pick from existing tags (loaded
/// from `GET /location-tags` when the dialog opens) and create brand-new tags
/// inline (`POST /location-tags`).
///
/// In **create** mode it posts a new SKU via `POST /locations`. In **edit**
/// mode ([initial] + [detailCtrl] supplied) it prefills every field, marks the
/// SKU's current tags as selected, and saves via `PATCH /locations/{id}`
/// (sending `tagIds` so tag changes persist).
class NewSkuDialog extends StatefulWidget {
  const NewSkuDialog({
    super.key,
    required this.ctrl,
    this.initial,
    this.detailCtrl,
  });

  /// Owns the tag dictionary + create-SKU call.
  final InventoryController ctrl;

  /// When non-null the dialog runs in edit mode, prefilled from this record.
  final InventoryLocationDetail? initial;

  /// Required in edit mode — used to PATCH the SKU.
  final SkuDetailController? detailCtrl;

  bool get isEdit => initial != null;

  /// Opens the dialog as a full-height, scroll-controlled bottom sheet.
  ///
  /// Pass [initial] + [detailCtrl] to open in edit mode.
  static Future<void> show(
    BuildContext context,
    InventoryController ctrl, {
    InventoryLocationDetail? initial,
    SkuDetailController? detailCtrl,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewSkuDialog(
        ctrl: ctrl,
        initial: initial,
        detailCtrl: detailCtrl,
      ),
    );
  }

  @override
  State<NewSkuDialog> createState() => _NewSkuDialogState();
}

class _NewSkuDialogState extends State<NewSkuDialog> {
  final _codeCtrl  = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _zoneCtrl  = TextEditingController();
  final _aisleCtrl = TextEditingController();
  final _shelfCtrl = TextEditingController();
  final _sortCtrl  = TextEditingController();
  final _notesCtrl = TextEditingController();

  // New-tag sub-form (manual add removed — tags are now created from the
  // search field's "New tag" button, see _addTagFromSearch).
  // final _tagLabelCtrl = TextEditingController();
  // final _tagSlugCtrl  = TextEditingController();
  // bool _slugEdited = false;

  /// True once the user has manually edited the SKU code. Stops the auto-compose
  /// from zone/rack/shelf/sort so their typed value is preserved.
  bool _codeEdited = false;

  // Tag search.
  final _tagSearchCtrl = TextEditingController();
  Timer? _tagDebounce;

  /// Selected tags — sent as `tagIds[]` when creating / updating the SKU.
  final List<InventoryTag> _selectedTags = [];

  InventoryController get ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    // Fresh tag search each time the dialog opens.
    ctrl.clearTagSuggestions();

    // Edit mode — prefill every field and pre-select the SKU's current tags.
    final init = widget.initial;
    if (init != null) {
      _codeCtrl.text = init.code;
      _nameCtrl.text = init.name;
      _zoneCtrl.text = init.zone ?? '';
      _aisleCtrl.text = init.aisle ?? '';
      _shelfCtrl.text = init.shelf ?? '';
      _sortCtrl.text = '${init.sortOrder}';
      _notesCtrl.text = init.notes ?? '';
      _selectedTags.addAll(init.tags);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _zoneCtrl.dispose();
    _aisleCtrl.dispose();
    _shelfCtrl.dispose();
    _sortCtrl.dispose();
    _notesCtrl.dispose();
    // _tagLabelCtrl.dispose();
    // _tagSlugCtrl.dispose();
    _tagSearchCtrl.dispose();
    _tagDebounce?.cancel();
    super.dispose();
  }

  /// Concatenates the location components (zone + rack + shelf + sort order)
  /// into a single uppercase SKU code, e.g. PL · L8 · 06 · 10 → "PLL80610".
  String _composeCode() {
    final parts = [
      _zoneCtrl.text.trim(),
      _aisleCtrl.text.trim(),
      _shelfCtrl.text.trim(),
      _sortCtrl.text.trim(),
    ];
    return parts.join().toUpperCase();
  }

  /// Re-fills the SKU code from the location components as the user edits them —
  /// only in create mode, and only until the user manually edits the code field
  /// (after which their value is kept). Setting `.text` here does not trip
  /// [_codeEdited] because programmatic changes don't fire the field's onChanged.
  void _onCodeComponentChanged(String _) {
    if (widget.isEdit || _codeEdited) return;
    _codeCtrl.text = _composeCode();
  }

  /// Debounced live tag search.
  void _onTagQueryChanged(String value) {
    _tagDebounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      ctrl.clearTagSuggestions();
      return;
    }
    _tagDebounce = Timer(const Duration(milliseconds: 300), () {
      ctrl.suggestTags(q);
    });
  }

  void _addSelectedTag(InventoryTag tag) {
    if (_selectedTags.any((t) => t.id == tag.id)) return;
    setState(() => _selectedTags.add(tag));
  }

  void _removeSelectedTag(InventoryTag tag) {
    setState(() => _selectedTags.removeWhere((t) => t.id == tag.id));
  }

  /// Converts a label into a url-friendly slug ("Cold Storage" → "cold-storage").
  String _slugify(String input) {
    final lower = input.trim().toLowerCase();
    final dashed = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return dashed.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// Creates a brand-new tag from the current search text (label = query,
  /// slug = slugified query) via `POST /location-tags`, selects it, and clears
  /// the search. Backs the "New tag" button next to the search field.
  Future<void> _addTagFromSearch() async {
    final label = _tagSearchCtrl.text.trim();
    if (label.isEmpty) {
      Get.snackbar(TKeys.stMissingInfo.tr, TKeys.stTypeTagName.tr);
      return;
    }
    final slug = _slugify(label);
    if (slug.isEmpty) {
      Get.snackbar(TKeys.stMissingInfo.tr, TKeys.stEnterValidTag.tr);
      return;
    }

    final tag = await ctrl.createTag(slug: slug, label: label);
    if (!mounted) return;
    if (tag == null) {
      Get.snackbar(TKeys.errorTitle.tr, ctrl.tagsError ?? TKeys.stCouldNotCreateTag.tr);
      return;
    }

    setState(() {
      if (!_selectedTags.any((t) => t.id == tag.id)) {
        _selectedTags.add(tag);
      }
      _tagSearchCtrl.clear();
    });
    ctrl.clearTagSuggestions();
  }

  // Manual "new tag" sub-form removed — tags are now created from the search
  // field's "New tag" button (see _addTagFromSearch above).
  // void _onTagLabelChanged(String value) {
  //   // Auto-fill the slug from the label until the user edits the slug directly.
  //   if (!_slugEdited) {
  //     _tagSlugCtrl.text = _slugify(value);
  //   }
  // }
  //
  // Future<void> _addTag() async {
  //   final label = _tagLabelCtrl.text.trim();
  //   final slug = _slugify(_tagSlugCtrl.text.trim().isEmpty
  //       ? label
  //       : _tagSlugCtrl.text.trim());
  //
  //   if (label.isEmpty || slug.isEmpty) {
  //     Get.snackbar("Missing info", 'Enter a label for the new tag.');
  //     return;
  //   }
  //
  //   final tag = await ctrl.createTag(slug: slug, label: label);
  //   if (tag == null) {
  //     Get.snackbar("Error", ctrl.tagsError ?? "Could not create tag.");
  //     return;
  //   }
  //
  //   setState(() {
  //     if (!_selectedTags.any((t) => t.id == tag.id)) {
  //       _selectedTags.add(tag);
  //     }
  //     _tagLabelCtrl.clear();
  //     _tagSlugCtrl.clear();
  //     _slugEdited = false;
  //   });
  // }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      Get.snackbar(TKeys.stMissingInfo.tr, TKeys.stSkuCodeRequired.tr);
      return;
    }

    final String? error;
    if (widget.isEdit) {
      // PATCH the existing SKU — code stays fixed; tags persist via tagIds.
      error = await widget.detailCtrl!.updateLocation(
        name: _nameCtrl.text,
        zone: _zoneCtrl.text,
        aisle: _aisleCtrl.text,
        shelf: _shelfCtrl.text,
        notes: _notesCtrl.text,
        tagIds: _selectedTags.map((t) => t.id).toList(),
      );
    } else {
      error = await ctrl.createLocation(
        code: code,
        name: _nameCtrl.text,
        zone: _zoneCtrl.text,
        aisle: _aisleCtrl.text,
        shelf: _shelfCtrl.text,
        sortOrder: int.tryParse(_sortCtrl.text.trim()) ?? 0,
        notes: _notesCtrl.text,
        tagIds: _selectedTags.map((t) => t.id).toList(),
      );
    }

    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pop();
      Get.snackbar(
        widget.isEdit ? TKeys.savedTitle.tr : TKeys.stCreatedTitle.tr,
        widget.isEdit ? TKeys.stSkuUpdated.trParams({'code': code}) : TKeys.stSkuCreated.trParams({'code': code}),
      );
    } else {
      Get.snackbar(TKeys.errorTitle.tr, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.92;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: CustomText(
                    widget.isEdit ? TKeys.stEditSku.tr : TKeys.stNewSku.tr,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
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
          ),
          const Divider(height: 1, color: AppColors.inputBorder),

          // ── Body ─────────────────────────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + viewInsets),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location components first — these auto-compose the SKU code
                  // below (zone + rack + shelf + sort order).
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: TKeys.stZoneCaps.tr,
                          controller: _zoneCtrl,
                          onChanged: _onCodeComponentChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: TKeys.stRackCaps.tr,
                          controller: _aisleCtrl,
                          onChanged: _onCodeComponentChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: TKeys.stShelfCaps.tr,
                          controller: _shelfCtrl,
                          onChanged: _onCodeComponentChanged,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Sort order is create-only (the PATCH edit body omits it).
                  if (!widget.isEdit) ...[
                    _Field(
                      label: TKeys.stSortOrderCaps.tr,
                      controller: _sortCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: _onCodeComponentChanged,
                    ),
                    const SizedBox(height: 16),
                  ],
                  // SKU code — auto-filled from the fields above, but fully
                  // editable. Editing it stops the auto-compose and never
                  // changes the location fields.
                  _Field(
                    label: widget.isEdit ? TKeys.stSkuCodeCaps.tr : TKeys.stSkuCodeRequiredCaps.tr,
                    controller: _codeCtrl,
                    hint: TKeys.stAutoFilled.tr,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => _codeEdited = true,
                  ),
                  const SizedBox(height: 16),
                  _Field(
                    label: TKeys.stNameCaps.tr,
                    controller: _nameCtrl,
                    hint: TKeys.stOptionalDisplayName.tr,
                  ),
                  const SizedBox(height: 16),
                  _Field(
                    label: TKeys.stNotesCaps.tr,
                    controller: _notesCtrl,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 22),

                  // ── SKU tags ───────────────────────────────────────────
                  _SectionLabel(TKeys.stSkuTagsCaps.tr),
                  const SizedBox(height: 10),

                  // Selected tags — chips with a remove (×) action.
                  if (_selectedTags.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in _selectedTags)
                          _SelectedTagChip(
                            label: tag.label,
                            onRemove: () => _removeSelectedTag(tag),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Tag search → suggest, with a "New tag" button that creates
                  // a tag from the current query via the add-tag API.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _TagSearchField(
                            controller: _tagSearchCtrl,
                            onChanged: _onTagQueryChanged,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Obx(
                          () => _AddTagButton(
                            loading: ctrl.isCreatingTag,
                            onTap: _addTagFromSearch,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Suggestions list.
                  Obx(() {
                    if (ctrl.isSuggestingTags) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.brandNavy),
                          ),
                        ),
                      );
                    }
                    if (!ctrl.hasSuggestedTags) return const SizedBox.shrink();

                    final results = ctrl.tagSuggestions
                        .where((t) =>
                            !_selectedTags.any((s) => s.id == t.id))
                        .toList();
                    if (results.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: CustomText(
                          TKeys.stNoMatchingTags.tr,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.inputBorder, width: 1),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < results.length; i++) ...[
                            if (i > 0)
                              const Divider(
                                  height: 1, color: AppColors.inputBorder),
                            _TagSuggestionRow(
                              tag: results[i],
                              onTap: () => _addSelectedTag(results[i]),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  // ── New tag sub-form (manual add — replaced by the "New tag"
                  //    button beside the search field above) ─────────────────
                  // const SizedBox(height: 16),
                  // _NewTagForm(
                  //   labelCtrl: _tagLabelCtrl,
                  //   slugCtrl: _tagSlugCtrl,
                  //   onLabelChanged: _onTagLabelChanged,
                  //   onSlugChanged: (_) => _slugEdited = true,
                  //   onAdd: _addTag,
                  //   ctrl: ctrl,
                  // ),
                ],
              ),
            ),
          ),

          // ── Footer CTA ───────────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Obx(
                () => _PrimaryButton(
                  label: widget.isEdit ? TKeys.saveChanges.tr : TKeys.stCreateSku.tr,
                  loading: widget.isEdit
                      ? (widget.detailCtrl?.isSaving ?? false)
                      : ctrl.isCreatingLocation,
                  onTap: _submit,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A selected-tag chip with a remove (×) button.
class _SelectedTagChip extends StatelessWidget {
  const _SelectedTagChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 8, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.brandNavy,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomText(
            label.toUpperCase(),
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: AppColors.white,
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  size: 13, color: AppColors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search field for finding existing tags via the suggest endpoint.
class _TagSearchField extends StatelessWidget {
  const _TagSearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 19, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: TKeys.stSearchTagsShort.tr,
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "New tag" button shown beside the tag search — creates a tag from the
/// current query. Shows a spinner while the create-tag request is in flight.
class _AddTagButton extends StatelessWidget {
  const _AddTagButton({required this.onTap, this.loading = false});
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brandNavy,
          borderRadius: BorderRadius.circular(12),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppColors.white),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 16, color: AppColors.white),
                  const SizedBox(width: 5),
                  CustomText(
                    TKeys.stNewTag.tr,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ],
              ),
      ),
    );
  }
}

/// One tag suggestion row — label + an add (+) affordance.
class _TagSuggestionRow extends StatelessWidget {
  const _TagSuggestionRow({required this.tag, required this.onTap});
  final InventoryTag tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: CustomText(
                tag.label,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.add_circle_outline_rounded,
                size: 20, color: AppColors.brandNavy),
          ],
        ),
      ),
    );
  }
}

// Manual "NEW SKU TAG" sub-form — replaced by the "New tag" button beside the
// tag search field. Kept (commented) in case the manual form is needed again.
/*
/// The framed "NEW SKU TAG" sub-form (label + slug + add button).
class _NewTagForm extends StatelessWidget {
  const _NewTagForm({
    required this.labelCtrl,
    required this.slugCtrl,
    required this.onLabelChanged,
    required this.onSlugChanged,
    required this.onAdd,
    required this.ctrl,
  });

  final TextEditingController labelCtrl;
  final TextEditingController slugCtrl;
  final ValueChanged<String> onLabelChanged;
  final ValueChanged<String> onSlugChanged;
  final VoidCallback onAdd;
  final InventoryController ctrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('NEW SKU TAG'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Field(
                  label: 'LABEL',
                  controller: labelCtrl,
                  hint: 'e.g. Jackets',
                  filled: false,
                  onChanged: onLabelChanged,
                ),
              ),
              const SizedBox(width: 12),
              // Expanded(
              //   child: _Field(
              //     label: 'SLUG',
              //     controller: slugCtrl,
              //     hint: 'e.g. cold-storage',
              //     filled: false,
              //     onChanged: onSlugChanged,
              //   ),
              // ),
            ],
          ),
          const SizedBox(height: 12),
          Obx(
            () => GestureDetector(
              onTap: ctrl.isCreatingTag ? null : onAdd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.inputBorder, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (ctrl.isCreatingTag)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.brandNavy),
                        ),
                      )
                    else
                      const Icon(Icons.add_rounded,
                          size: 16, color: AppColors.brandNavy),
                    const SizedBox(width: 6),
                    const CustomText(
                      'Add SKU tag',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: AppColors.brandNavy,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
*/

/// Small uppercase form-section caption.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return CustomText(
      text,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: AppColors.textMuted,
    );
  }
}

/// Labeled text input matching the warehouse form chrome.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label),
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
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            textCapitalization: textCapitalization,
            onChanged: onChanged,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-width primary action with an inline spinner while saving.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
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
