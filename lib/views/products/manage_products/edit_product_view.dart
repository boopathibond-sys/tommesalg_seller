import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../controllers/seller_products_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/seller_product.dart';
import '../../../models/seller_product_preview.dart';
import '../../../core/localization/translation_keys.dart';

/// Edit form for one of the seller's products, opened from the details page.
///
/// Pre-fills from the product preview (the richest payload we have) and PATCHes
/// through `SellerProductsController.updateProduct`. Only the fields the seller
/// actually changed are sent: the endpoint treats every present key as an edit
/// and logs it to the audit trail, so echoing untouched values back would fill
/// the trail with edits that never happened.
///
/// The web console splits these fields across a left-hand section menu; on a
/// phone that becomes a horizontal tab strip over one section at a time, so the
/// seller never scrolls through 20 unrelated inputs to reach the one they came
/// for. The save bar (and the change count) stays pinned, so any section can be
/// saved from where it is.
class EditProductView extends StatefulWidget {
  const EditProductView({
    super.key,
    required this.product,
    required this.ctrl,
    this.preview,
  });

  final SellerProduct product;
  final SellerProductsController ctrl;

  /// Detail payload for the prefill. Null when the preview never loaded — the
  /// form then starts from the list row's fields only.
  final SellerProductPreview? preview;

  @override
  State<EditProductView> createState() => _EditProductViewState();
}

class _EditProductViewState extends State<EditProductView> {
  static const int _maxImages = 10;
  static const Set<String> _allowedImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  // Getter, not `const`: these are visible tab labels, so they have to
  // re-resolve when the seller switches language.
  static List<String> get _sections => [
        TKeys.secGeneral.tr,
        TKeys.secAuction.tr,
        TKeys.secWarehouse.tr,
        TKeys.secShipping.tr,
        TKeys.secAttributes.tr,
      ];

  /// Gender values the web console offers.
  static const List<String> _genders = ['Men', 'Women', 'Unisex'];

  /// The colour vocabulary, as supplied by the product team. Kept verbatim
  /// (including the near-duplicates like Grey/Gray) so the values match what
  /// the rest of the platform already stores.
  static const List<String> _colourOptions = [
    'Beige',
    'Without',
    'Blueberry Stripe',
    'Blue',
    'Blue/Navy',
    'Brown',
    'Burgundy',
    'coastal beige',
    'Creme',
    'Grey',
    'Green',
    'Gray',
    'Gul',
    'Gull',
    'White',
    'White,Silver',
    'Khaki/Navy blue',
    'Small',
    'Navy blue',
    'Midnight blue sapphire',
    'Midnight Sapphire',
    'Multi',
    'Nude',
    'Orange',
    'Red',
    'Rosa',
    'Black',
    'Black / Grey',
    'Silver',
    'Wine red',
  ];

  final ImagePicker _picker = ImagePicker();

  int _tab = 0;

  /// Every text input, keyed by the API field it maps to. Keeping them in one
  /// map is what lets the change-diff below stay a loop instead of 20 manual
  /// comparisons.
  final Map<String, TextEditingController> _fields = {};

  /// Field values as the form was opened, for the same diff.
  final Map<String, String> _initial = {};

  String? _gender;
  String? _initialGender;

  /// List-valued fields, edited as chips rather than comma-separated text.
  final List<String> _tags = [];
  final List<String> _colours = [];
  late List<String> _initialTags;
  late List<String> _initialColours;

  late bool _useDefaultShipping;
  late bool _initialUseDefaultShipping;

  final List<_GalleryImage> _images = [];
  late List<String> _initialImageRefs;
  bool _uploadingImages = false;

  SellerProductsController get _ctrl => widget.ctrl;
  SellerProductPreview? get _preview => widget.preview;

  @override
  void initState() {
    super.initState();
    final p = _preview;

    void field(String key, String? value) {
      final text = (value ?? '').trim();
      _fields[key] = TextEditingController(text: text);
      _initial[key] = text;
    }

    String? number(num? value) {
      if (value == null) return null;
      return value % 1 == 0 ? value.toInt().toString() : value.toString();
    }

    field('name', p?.name.isNotEmpty == true ? p!.name : widget.product.name);
    field('brand', p?.brand);
    field('shortDescription', p?.shortDescription);
    field('description', p?.description);

    field('originalPrice',
        number(p?.originalPrice ?? widget.product.originalPrice));
    field('startingPrice',
        number(p?.startingPrice ?? widget.product.buyNowPrice));
    field('bottomPrice', number(p?.bottomPrice));

    field('colour', p?.colour);
    field('material', p?.material);
    field('weight', number(p?.weight));

    field('size', p?.size);
    field('usSize', p?.usSize);
    field('euSize', p?.euSize);
    field('sizeType', p?.sizeType);
    field('sizesAvailable', p?.sizesAvailable.join(', '));

    field('features', p?.features);
    field('materialsAndCare', p?.materialsAndCare);

    field('sku', p?.sku);
    field('upc', p?.upc);
    field('stockCount', p?.stockCount?.toString());
    field('taxonomyNodeId', p?.taxonomyNodeId);
    field('shippingPriceNok', number(p?.shippingPriceNok));

    _gender = _initialGender = _blankToNull(p?.gender);

    _tags.addAll(p?.tags ?? const []);
    _colours.addAll(p?.colorsAvailable ?? const []);
    _initialTags = List.of(_tags);
    _initialColours = List.of(_colours);

    _useDefaultShipping = p?.useDefaultShipping ?? true;
    _initialUseDefaultShipping = _useDefaultShipping;

    _images.addAll(_initialGallery());
    _initialImageRefs = _images.map((e) => e.ref).toList();

    // The save bar reports how many fields will be sent, so every keystroke
    // has to re-run the diff.
    for (final c in _fields.values) {
      c.addListener(_onFormChanged);
    }
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Pairs the raw image refs (S3 keys, what the API wants back) with the
  /// pre-signed URLs from the preview (what we can actually render). The list
  /// endpoint and the preview return the gallery in the same order, so they zip
  /// index-wise; anything unpaired falls back to whichever of the two is a
  /// loadable URL.
  List<_GalleryImage> _initialGallery() {
    final refs = widget.product.images;
    final signed = _preview?.imageUrls ?? const <String>[];
    if (refs.isEmpty) {
      return signed.map((url) => _GalleryImage(ref: url, display: url)).toList();
    }
    return [
      for (var i = 0; i < refs.length; i++)
        _GalleryImage(
          ref: refs[i],
          display: i < signed.length
              ? signed[i]
              : (refs[i].startsWith('http') ? refs[i] : null),
        ),
    ];
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _c(String key) => _fields[key]!;

  // ── Change diff ────────────────────────────────────────────────────────────

  bool get _imagesChanged =>
      !_listEquals(_images.map((e) => e.ref).toList(), _initialImageRefs);

  /// The PATCH body's editable half: only what differs from the opened state.
  Map<String, dynamic> _buildChanges() {
    final changes = <String, dynamic>{};

    void text(String key) {
      final value = _c(key).text.trim();
      if (value != _initial[key]) changes[key] = value;
    }

    /// Numbers are sent typed. An emptied field is only sent when the API
    /// accepts null for it — the rest have no "clear" semantics, so clearing
    /// them is treated as "leave alone" rather than silently sending "".
    void number(String key, {bool integer = false, bool nullable = false}) {
      final value = _c(key).text.trim();
      if (value == _initial[key]) return;
      if (value.isEmpty) {
        if (nullable) changes[key] = null;
        return;
      }
      final parsed = integer
          ? int.tryParse(value)
          : num.tryParse(value.replaceAll(',', '.'));
      if (parsed != null) changes[key] = parsed;
    }

    text('name');
    text('brand');
    text('shortDescription');
    text('description');

    if (_gender != _initialGender) changes['gender'] = _gender ?? '';

    number('originalPrice');
    number('startingPrice');
    number('bottomPrice');

    text('colour');
    text('material');
    number('weight');

    // Chip fields go out as arrays (the API takes either, and an array can
    // carry a value with a comma in it — e.g. the "White,Silver" colour).
    if (!_listEquals(_colours, _initialColours)) {
      changes['colorsAvailable'] = List.of(_colours);
    }
    if (!_listEquals(_tags, _initialTags)) {
      changes['tags'] = List.of(_tags);
    }

    text('size');
    text('usSize');
    text('euSize');
    text('sizeType');
    // `sizesAvailable` is specified as a CSV string, not an array.
    text('sizesAvailable');

    text('features');
    text('materialsAndCare');

    text('sku');
    text('upc');
    number('stockCount', integer: true);
    number('shippingPriceNok', nullable: true);

    // A cleared taxonomy node is an explicit null (the API accepts one).
    final taxonomy = _c('taxonomyNodeId').text.trim();
    if (taxonomy != _initial['taxonomyNodeId']) {
      changes['taxonomyNodeId'] = taxonomy.isEmpty ? null : taxonomy;
    }

    if (_useDefaultShipping != _initialUseDefaultShipping) {
      changes['useDefaultShipping'] = _useDefaultShipping;
      // Switching back to platform shipping clears any custom price, so the two
      // can't disagree.
      if (_useDefaultShipping) changes['shippingPriceNok'] = null;
    }

    if (_imagesChanged) {
      // The gallery is replaced wholesale — `imageUrls` is ignored without it.
      changes['replaceImages'] = true;
      changes['imageUrls'] = _images.map((e) => e.ref).toList();
    }

    return changes;
  }

  /// `replaceImages` + `imageUrls` are one change as far as the seller is
  /// concerned, so the count in the save bar doesn't say "2 fields" for a
  /// single photo swap.
  int get _changeCount => _buildChanges().length - (_imagesChanged ? 1 : 0);

  /// Fields that must parse as numbers before anything is sent, with the
  /// section that holds them so a complaint can point the seller at it.
  // Getter, not `const`: the labels are translated, so they must re-resolve
  // when the language changes.
  static List<({String key, String label, int tab, bool integer})>
      get _numeric => [
    (key: 'originalPrice', label: TKeys.fieldOriginalPrice.tr, tab: 1, integer: false),
    (key: 'startingPrice', label: TKeys.fieldStartingPrice.tr, tab: 1, integer: false),
    (key: 'bottomPrice', label: TKeys.fieldBottomPrice.tr, tab: 1, integer: false),
    (key: 'stockCount', label: TKeys.fieldStockCount.tr, tab: 2, integer: true),
    (key: 'shippingPriceNok', label: TKeys.fieldShippingPrice.tr, tab: 3, integer: false),
    (key: 'weight', label: TKeys.fieldWeight.tr, tab: 3, integer: false),
      ];

  /// Returns the problem to show, and jumps to the section that owns it —
  /// with the form split across tabs, a complaint about a field the seller
  /// can't see would be a dead end.
  String? _validate(Map<String, dynamic> changes) {
    for (final f in _numeric) {
      final value = _c(f.key).text.trim();
      if (value.isEmpty) continue;
      final ok = f.integer
          ? int.tryParse(value) != null
          : num.tryParse(value.replaceAll(',', '.')) != null;
      if (!ok) {
        _goToTab(f.tab);
        return TKeys.mustBeNumber.trParams({'field': f.label});
      }
    }
    if (_c('name').text.trim().isEmpty) {
      _goToTab(0);
      return TKeys.productNameEmpty.tr;
    }
    if (_imagesChanged && _images.isEmpty) {
      _goToTab(0);
      return TKeys.keepOnePhoto.tr;
    }
    if (changes.isEmpty) {
      return TKeys.nothingChangedYet.tr;
    }
    return null;
  }

  void _goToTab(int index) {
    if (_tab != index) setState(() => _tab = index);
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final changes = _buildChanges();
    final problem = _validate(changes);
    if (problem != null) {
      Get.snackbar(TKeys.checkTheForm.tr, problem,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    // The reason is mandatory on every PATCH and goes to the audit trail. It is
    // asked for here rather than living in a section, so it can't be missed by
    // saving from a different tab.
    final reason = await _askReason(changes.length);
    if (reason == null || !mounted) return;

    final ok = await _ctrl.updateProduct(
      productId: widget.product.id,
      editReason: reason,
      changes: changes,
    );
    if (!mounted) return;

    if (ok) {
      Get.snackbar(TKeys.savedTitle.tr, TKeys.productUpdated.tr,
          snackPosition: SnackPosition.BOTTOM);
      Navigator.of(context).pop(true);
    } else {
      Get.snackbar(TKeys.couldNotSave.tr, _ctrl.editError ?? TKeys.pleaseTryAgain.tr,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Asks for the mandatory audit-trail reason before the PATCH goes out.
  ///
  /// The sheet owns its text controller ([_ReasonSheet]) so the controller
  /// outlives the pop animation. Disposing it from the show future's
  /// `whenComplete` used to fire while the sheet was still animating away and
  /// the field was still rebuilding, which threw "A TextEditingController was
  /// used after being disposed" and left the sheet mid-layout.
  Future<String?> _askReason(int fieldCount) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReasonSheet(fieldCount: fieldCount),
    );
  }

  Future<void> _pickColours() async {
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ColourPickerSheet(
        // Any colour already on the product that isn't in the vocabulary is
        // merged in, so opening the picker can never silently drop it.
        options: {..._colourOptions, ..._colours}.toList(),
        selected: _colours,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _colours
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _addImages() async {
    if (_images.length >= _maxImages) {
      Get.snackbar(TKeys.galleryFull.tr,
          TKeys.upToPhotos.trParams({'max': '$_maxImages'}),
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final source = await _chooseImageSource();
    if (source == null || !mounted) return;

    final List<XFile> picked;
    if (source == ImageSource.camera) {
      final shot = await _picker.pickImage(source: ImageSource.camera);
      picked = shot == null ? const [] : [shot];
    } else {
      picked = await _picker.pickMultiImage();
    }
    if (picked.isEmpty || !mounted) return;

    final room = _maxImages - _images.length;
    final accepted = picked.where(_isAllowedImage).take(room).toList();
    if (accepted.isEmpty) {
      Get.snackbar(TKeys.unsupportedFile.tr, TKeys.useJpgPngWebp.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    setState(() => _uploadingImages = true);
    final uploaded = <_GalleryImage>[];
    for (final file in accepted) {
      final key = await _ctrl.uploadProductImage(file.path);
      if (key != null) {
        uploaded.add(_GalleryImage(ref: key, localPath: file.path));
      }
    }
    if (!mounted) return;
    setState(() {
      _images.addAll(uploaded);
      _uploadingImages = false;
    });

    if (uploaded.length != accepted.length) {
      Get.snackbar(
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
    if (dot < 0) return false;
    return _allowedImageExtensions.contains(name.substring(dot + 1));
  }

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
                color: AppColors.borderGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.brandNavy),
              title: CustomText(TKeys.cameraSource.tr,
                  fontSize: 15, fontWeight: FontWeight.w700),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.brandNavy),
              title: CustomText(TKeys.gallerySource.tr,
                  fontSize: 15, fontWeight: FontWeight.w700),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Warns before dropping edits the seller has already made.
  Future<bool> _confirmDiscard() async {
    if (_buildChanges().isEmpty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: CustomText(TKeys.discardChangesTitle.tr,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary),
        content: CustomText(
          TKeys.discardChangesBody.tr,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: AppColors.textSecondary,
        ),
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          title: CustomText(TKeys.editProduct.tr,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _TabStrip(
                labels: _sections,
                index: _tab,
                onChanged: (i) {
                  FocusScope.of(context).unfocus();
                  setState(() => _tab = i);
                },
              ),
              Expanded(
                // IndexedStack keeps every section's fields (and their scroll
                // position) alive while switching, so a half-typed value in one
                // tab survives a trip to another.
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _sectionScroll(_generalSection()),
                    _sectionScroll(_auctionSection()),
                    _sectionScroll(_warehouseSection()),
                    _sectionScroll(_shippingSection()),
                    _sectionScroll(_attributesSection()),
                  ],
                ),
              ),
              Obx(() => _SaveBar(
                    count: _changeCount,
                    busy: _ctrl.isSavingEdit,
                    blocked: _uploadingImages,
                    onSave: _save,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionScroll(List<Widget> children) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  List<Widget> _generalSection() {
    return [
      _InfoBanner(
        TKeys.editLoggedNote.tr,
      ),
      // Without the preview we only have the list row's fields, so most inputs
      // start blank — say so rather than letting the seller read empty boxes as
      // "this product has no brand".
      if (_preview == null) ...[
        const SizedBox(height: 12),
        _WarningBanner(TKeys.editPartialLoadNote.tr),
      ],
      const SizedBox(height: 16),
      _Field(label: TKeys.fieldNameRequired.tr, controller: _c('name')),
      _Field(label: TKeys.fieldBrand.tr, controller: _c('brand')),
      _Dropdown(
        label: TKeys.fieldGender.tr,
        value: _gender,
        // A stored value outside the standard three still has to be selectable,
        // or opening the form would silently reset it.
        options: [
          ..._genders,
          if (_gender != null && !_genders.contains(_gender)) _gender!,
        ],
        hint: TKeys.selectAction.tr,
        onChanged: (v) => setState(() => _gender = v),
      ),
      _Field(
        label: TKeys.fieldTaxonomy.tr,
        controller: _c('taxonomyNodeId'),
        helper: TKeys.fieldTaxonomyHelp.tr,
      ),
      _Field(
        label: TKeys.fieldShortDescription.tr,
        controller: _c('shortDescription'),
        maxLines: 3,
      ),
      _Field(
        label: TKeys.fieldDescription.tr,
        controller: _c('description'),
        maxLines: 6,
      ),
      _SubLabel(TKeys.fieldImages.tr),
      const SizedBox(height: 8),
      _ImageEditor(
        images: _images,
        uploading: _uploadingImages,
        onAdd: _addImages,
        onRemove: (i) => setState(() => _images.removeAt(i)),
      ),
      if (_imagesChanged) ...[
        const SizedBox(height: 8),
        _Note(TKeys.savingReplacesGallery.tr),
      ],
    ];
  }

  List<Widget> _auctionSection() {
    return [
      Row(
        children: [
          Expanded(
            child: _Field(
              label: TKeys.fieldOriginalPrice.tr,
              controller: _c('originalPrice'),
              numeric: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Field(
              label: TKeys.fieldStartingPrice.tr,
              controller: _c('startingPrice'),
              numeric: true,
            ),
          ),
        ],
      ),
      _Field(
        label: TKeys.fieldBottomPrice.tr,
        controller: _c('bottomPrice'),
        numeric: true,
        helper: TKeys.bottomPriceHelp.tr,
      ),
    ];
  }

  List<Widget> _warehouseSection() {
    return [
      Row(
        children: [
          Expanded(child: _Field(label: 'SKU', controller: _c('sku'))),
          const SizedBox(width: 12),
          Expanded(child: _Field(label: 'UPC', controller: _c('upc'))),
        ],
      ),
      _Field(
        label: TKeys.fieldStockCount.tr,
        controller: _c('stockCount'),
        numeric: true,
        integer: true,
      ),
    ];
  }

  List<Widget> _shippingSection() {
    return [
      _SwitchRow(
        label: TKeys.usePlatformShipping.tr,
        value: _useDefaultShipping,
        onChanged: (v) => setState(() => _useDefaultShipping = v),
      ),
      const SizedBox(height: 8),
      if (!_useDefaultShipping)
        _Field(
          label: TKeys.shippingPriceNok.tr,
          controller: _c('shippingPriceNok'),
          numeric: true,
        ),
      _Field(
        label: TKeys.fieldWeight.tr,
        controller: _c('weight'),
        numeric: true,
        helper: TKeys.weightHelp.tr,
      ),
    ];
  }

  List<Widget> _attributesSection() {
    return [
      _Field(label: TKeys.fieldPrimaryColour.tr, controller: _c('colour')),
      _ChipPickerField(
        label: TKeys.fieldColoursAvailable.tr,
        values: _colours,
        emptyHint: TKeys.noColoursSelected.tr,
        actionLabel: TKeys.chooseAction.tr,
        actionIcon: Icons.palette_outlined,
        onAction: _pickColours,
        onRemove: (value) => setState(() => _colours.remove(value)),
      ),
      _ChipInputField(
        label: TKeys.fieldTags.tr,
        values: _tags,
        hint: TKeys.addTagHint.tr,
        onAdd: (value) {
          setState(() {
            for (final tag in _splitCsv(value)) {
              if (!_tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
                _tags.add(tag);
              }
            }
          });
        },
        onRemove: (value) => setState(() => _tags.remove(value)),
      ),
      _Field(label: TKeys.fieldMaterial.tr, controller: _c('material')),

      _SubLabel(TKeys.fieldSizing.tr),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _Field(label: TKeys.fieldSize.tr, controller: _c('size'))),
          const SizedBox(width: 12),
          Expanded(
            child: _Field(label: TKeys.fieldSizeType.tr, controller: _c('sizeType')),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(child: _Field(label: TKeys.fieldUsSize.tr, controller: _c('usSize'))),
          const SizedBox(width: 12),
          Expanded(child: _Field(label: TKeys.fieldEuSize.tr, controller: _c('euSize'))),
        ],
      ),
      _Field(
        label: TKeys.fieldSizesAvailable.tr,
        controller: _c('sizesAvailable'),
        hint: TKeys.sizesHint.tr,
      ),

      _SubLabel(TKeys.fieldDetails.tr),
      const SizedBox(height: 10),
      _Field(label: TKeys.fieldFeatures.tr, controller: _c('features'), maxLines: 4),
      _Field(
        label: TKeys.fieldMaterialsCare.tr,
        controller: _c('materialsAndCare'),
        maxLines: 4,
      ),
    ];
  }
}

/// One image in the editor: [ref] is what the API gets back (an existing S3 key
/// or a freshly uploaded one), [display] / [localPath] are only for rendering.
class _GalleryImage {
  _GalleryImage({required this.ref, this.display, this.localPath});

  final String ref;
  final String? display;
  final String? localPath;
}

List<String> _splitCsv(String value) => value
    .split(',')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ── Chrome ───────────────────────────────────────────────────────────────────

/// The web console's left-hand section menu, folded into a scrollable pill row
/// so it works on a phone.
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderGrey, width: 1),
        ),
      ),
      child: SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final selected = i == index;
            return GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.brandNavy : AppColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? AppColors.brandNavy : AppColors.borderGrey,
                  ),
                ),
                child: CustomText(
                  labels[i],
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? AppColors.white : AppColors.textSecondary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Pinned footer: what will be sent, and the save action. Stays put so any
/// section can be saved without hunting for a button at the end of a scroll.
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
        border: Border(top: BorderSide(color: AppColors.borderGrey, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
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
                  color: count == 0
                      ? AppColors.textMuted
                      : AppColors.brandNavy,
                ),
              ),
              const SizedBox(width: 12),
              _PrimaryButton(
                label: TKeys.saveChanges.tr,
                loading: busy,
                enabled: !blocked && count > 0,
                onTap: onSave,
                expand: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The blue "your edits are logged" notice from the web form.
class _InfoBanner extends StatelessWidget {
  const _InfoBanner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryBlue.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: CustomText(text,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
                color: AppColors.primaryBlue),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandYellow.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomText(text,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: AppColors.textPrimary),
    );
  }
}

/// Horizontal gallery strip with per-photo remove and an "add" tile.
class _ImageEditor extends StatelessWidget {
  const _ImageEditor({
    required this.images,
    required this.uploading,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_GalleryImage> images;
  final bool uploading;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (i == images.length) {
            return GestureDetector(
              onTap: uploading ? null : onAdd,
              child: Container(
                width: 96,
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderGrey),
                ),
                child: uploading
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo_outlined,
                              color: AppColors.brandNavy, size: 22),
                          const SizedBox(height: 6),
                          CustomText(TKeys.addAction.tr,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandNavy),
                        ],
                      ),
              ),
            );
          }

          final image = images[i];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 96,
                  height: 104,
                  color: AppColors.inputFill,
                  child: _thumb(image),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => onRemove(i),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _thumb(_GalleryImage image) {
    const fallback = Center(
      child: Icon(Icons.image_not_supported_outlined,
          color: AppColors.textMuted, size: 22),
    );
    final local = image.localPath;
    if (local != null) {
      return Image.file(
        File(local),
        fit: BoxFit.cover,
        width: 96,
        height: 104,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    final url = image.display;
    if (url == null || !url.startsWith('http')) return fallback;
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: 96,
      height: 104,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

// ── Chip fields ──────────────────────────────────────────────────────────────

/// A free-text chip list — type a value, tap Add, get a chip. Mirrors the SKU
/// dialog's tag block (navy chips with a × and a field + button beneath), which
/// is what sellers already know from the warehouse form.
class _ChipInputField extends StatefulWidget {
  const _ChipInputField({
    required this.label,
    required this.values,
    required this.onAdd,
    required this.onRemove,
    this.hint,
  });

  final String label;
  final List<String> values;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final String? hint;

  @override
  State<_ChipInputField> createState() => _ChipInputFieldState();
}

class _ChipInputFieldState extends State<_ChipInputField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    widget.onAdd(value);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(widget.label),
          const SizedBox(height: 8),
          if (widget.values.isNotEmpty) ...[
            _ChipWrap(values: widget.values, onRemove: widget.onRemove),
            const SizedBox(height: 10),
          ],
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderGrey),
                    ),
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: widget.hint,
                        hintStyle: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _submit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.brandNavy,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded, size: 16,
                            color: AppColors.white),
                        const SizedBox(width: 5),
                        CustomText(TKeys.addAction.tr,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.white),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip list whose values come from a picker rather than free text.
class _ChipPickerField extends StatelessWidget {
  const _ChipPickerField({
    required this.label,
    required this.values,
    required this.onAction,
    required this.onRemove,
    required this.actionLabel,
    required this.actionIcon,
    required this.emptyHint,
  });

  final String label;
  final List<String> values;
  final VoidCallback onAction;
  final ValueChanged<String> onRemove;
  final String actionLabel;
  final IconData actionIcon;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _FieldLabel(label)),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.brandNavy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(actionIcon, size: 14, color: AppColors.white),
                      const SizedBox(width: 6),
                      CustomText(actionLabel,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (values.isEmpty)
            CustomText(emptyHint,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted)
          else
            _ChipWrap(values: values, onRemove: onRemove),
        ],
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.values, required this.onRemove});

  final List<String> values;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          Container(
            padding:
                const EdgeInsets.only(left: 14, right: 8, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.brandNavy,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomText(
                  value.toUpperCase(),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: AppColors.white,
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => onRemove(value),
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
          ),
      ],
    );
  }
}

/// Searchable multi-select over the colour vocabulary. Returns the new
/// selection, or null when the seller backs out.
class _ColourPickerSheet extends StatefulWidget {
  const _ColourPickerSheet({required this.options, required this.selected});

  final List<String> options;
  final List<String> selected;

  @override
  State<_ColourPickerSheet> createState() => _ColourPickerSheetState();
}

class _ColourPickerSheetState extends State<_ColourPickerSheet> {
  late final List<String> _picked = List.of(widget.selected);
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _visible {
    if (_query.isEmpty) return widget.options;
    final q = _query.toLowerCase();
    return widget.options
        .where((o) => o.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _visible;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: CustomText(TKeys.fieldColoursAvailable.tr,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                  CustomText(
                      TKeys.selectedCount
                          .trParams({'count': '${_picked.length}'}),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderGrey),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        size: 19, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v.trim()),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          hintText: TKeys.searchColours.tr,
                          hintStyle: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: CustomText(TKeys.noMatchingColours.tr,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted),
                    )
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final option = results[i];
                        final checked = _picked.contains(option);
                        return CheckboxListTile(
                          value: checked,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppColors.brandNavy,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          title: CustomText(option,
                              fontSize: 14,
                              fontWeight:
                                  checked ? FontWeight.w800 : FontWeight.w600,
                              color: AppColors.textPrimary),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              if (!checked) _picked.add(option);
                            } else {
                              _picked.remove(option);
                            }
                          }),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: _PrimaryButton(
                  label: TKeys.doneAction.tr,
                  onTap: () => Navigator.of(context).pop(_picked),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Inputs ───────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => CustomText(text,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary);
}

/// Sub-heading inside a section (e.g. "Sizing" within Attributes).
class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: CustomText(text.toUpperCase(),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: AppColors.textPrimary),
    );
  }
}

/// The "reason for change" sheet shown before a save.
///
/// Owns its [TextEditingController] so it is disposed with the sheet's own
/// element — after the pop animation has finished and the field is really
/// gone — rather than the moment the show future completes.
///
/// The body scrolls inside the space the keyboard leaves, so a small screen
/// (or a tall keyboard) shrinks the sheet instead of overflowing the column.
class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({required this.fieldCount});

  final int fieldCount;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      Get.snackbar(
        TKeys.reasonRequired.tr,
        TKeys.describeChange.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final count = widget.fieldCount;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: media.size.height * 0.85 - media.viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderGrey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CustomText(TKeys.reasonForChange.tr,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                  const SizedBox(height: 6),
                  CustomText(
                    TKeys.reasonLoggedNote.tr,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: TKeys.whyChange.tr,
                    controller: _reason,
                    maxLines: 3,
                    maxLength: 2000,
                    autofocus: true,
                    hint: TKeys.whyChangeHint.tr,
                  ),
                  const SizedBox(height: 4),
                  _PrimaryButton(
                    label:
                        (count == 1 ? TKeys.saveChangeCount : TKeys.saveChangesCount)
                            .trParams({'count': '$count'}),
                    onTap: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labelled input styled like the rest of the app's forms.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.maxLines = 1,
    this.numeric = false,
    this.integer = false,
    this.maxLength,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final int maxLines;
  final bool numeric;
  final bool integer;
  final int? maxLength;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: maxLines,
            maxLength: maxLength,
            autofocus: autofocus,
            keyboardType: numeric
                ? TextInputType.numberWithOptions(decimal: !integer)
                : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
            inputFormatters:
                integer ? [FilteringTextInputFormatter.digitsOnly] : null,
            textCapitalization: numeric
                ? TextCapitalization.none
                : TextCapitalization.sentences,
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
              counterText: '',
              filled: true,
              fillColor: AppColors.inputFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.borderGrey),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.borderGrey),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.brandNavy, width: 1.4),
              ),
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 5),
            _Note(helper!),
          ],
        ],
      ),
    );
  }
}

/// Labelled select, matching the field chrome.
class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderGrey),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: value,
                isExpanded: true,
                borderRadius: BorderRadius.circular(14),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary),
                hint: CustomText(hint ?? TKeys.selectAction.tr,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: CustomText(hint ?? TKeys.selectAction.tr,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted),
                  ),
                  for (final option in options)
                    DropdownMenuItem<String?>(
                      value: option,
                      child: CustomText(option,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CustomText(label,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.brandNavy,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return CustomText(text,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: AppColors.textMuted);
  }
}

/// Navy action button — full width by default, hug-content in the save bar.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
    this.expand = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool loading;
  final bool enabled;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final off = !enabled || loading;
    return Opacity(
      opacity: off ? 0.5 : 1,
      child: GestureDetector(
        onTap: off ? null : onTap,
        child: Container(
          width: expand ? double.infinity : null,
          height: 48,
          padding: expand ? null : const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.brandNavy,
            borderRadius: BorderRadius.circular(14),
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(AppColors.white),
                  ),
                )
              : CustomText(label,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white),
        ),
      ),
    );
  }
}
