import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/localization/translation_keys.dart';
import '../../../models/seller_product_detail.dart';

/// The tabs of the edit screen. Every editable field belongs to exactly one,
/// which is what lets a validation problem jump to the tab that owns it and
/// lets the tab strip mark the tabs holding unsaved changes.
enum EditSection { general, pricing, inventory, shipping, attributes, history }

/// How a text field is sent back.
enum _Kind { text, decimal, integer, nullableText }

/// One text-backed field of the PATCH body.
class _Spec {
  const _Spec(this.key, this.section, [this.kind = _Kind.text]);

  final String key;
  final EditSection section;
  final _Kind kind;
}

/// One photo in the gallery: [ref] is what the API gets back (an existing
/// image reference or a freshly uploaded S3 key); [display] / [localPath] are
/// only for rendering.
class GalleryImage {
  const GalleryImage({required this.ref, this.display, this.localPath});

  final String ref;
  final String? display;
  final String? localPath;
}

/// A reason the form can't be saved yet, and the tab to show it on.
class EditProblem {
  const EditProblem(this.section, this.message);

  final EditSection section;
  final String message;
}

/// State of the product edit form, independent of any widget.
///
/// Prefilled from `GET /seller/products/{id}`, it keeps the opened values so
/// [changes] can produce the PATCH body with *only* what the seller touched —
/// the endpoint logs every present key as an edit, and rejects unknown ones,
/// so neither untouched echoes nor extra keys may go out.
class ProductEditForm extends ChangeNotifier {
  ProductEditForm(this.detail, {List<String> imageRefs = const []}) {
    String? number(num? v) =>
        v == null ? null : (v % 1 == 0 ? v.toInt().toString() : v.toString());

    final d = detail;
    final initial = <String, String?>{
      'name': d.name,
      'brand': d.brand,
      'shortDescription': d.shortDescription,
      'description': d.description,
      'taxonomyNodeId': d.taxonomyNodeId,
      'veilPris': number(d.originalPrice),
      'startingPrice': number(d.startingPrice),
      'bottomPrice': number(d.bottomPrice),
      'sku': d.sku,
      'upc': d.upc,
      'stockCount': d.stockCount?.toString(),
      'weight': number(d.weight),
      'colour': d.colour,
      'material': d.material,
      'size': d.size,
      'usSize': d.usSize,
      'euSize': d.euSize,
      'sizesAvailable': d.sizesAvailable.join(', '),
      'features': d.features,
      'materialsAndCare': d.materialsAndCare,
    };
    for (final spec in _specs) {
      final text = (initial[spec.key] ?? '').trim();
      _initial[spec.key] = text;
      _text[spec.key] = TextEditingController(text: text)
        ..addListener(notifyListeners);
    }

    tags = List.of(d.tags);
    _initialTags = List.of(tags);

    useDefaultShipping = !d.shippingOverrideEnabled;
    shippingPriceNok = d.shippingOverrideEnabled ? d.shippingPriceNok : null;
    _initialUseDefaultShipping = useDefaultShipping;
    _initialShippingPriceNok = shippingPriceNok;

    images = _pairGallery(imageRefs, d.imageUrls);
    _initialImageRefs = images.map((e) => e.ref).toList();
  }

  final SellerProductDetail detail;

  static const List<_Spec> _specs = [
    _Spec('name', EditSection.general),
    _Spec('brand', EditSection.general),
    _Spec('shortDescription', EditSection.general),
    _Spec('description', EditSection.general),
    _Spec('taxonomyNodeId', EditSection.general, _Kind.nullableText),
    _Spec('veilPris', EditSection.pricing, _Kind.decimal),
    _Spec('startingPrice', EditSection.pricing, _Kind.decimal),
    _Spec('bottomPrice', EditSection.pricing, _Kind.decimal),
    _Spec('sku', EditSection.inventory),
    _Spec('upc', EditSection.inventory),
    _Spec('stockCount', EditSection.inventory, _Kind.integer),
    _Spec('weight', EditSection.inventory, _Kind.decimal),
    _Spec('colour', EditSection.attributes),
    _Spec('material', EditSection.attributes),
    _Spec('size', EditSection.attributes),
    _Spec('usSize', EditSection.attributes),
    _Spec('euSize', EditSection.attributes),
    // Specified as a CSV string, not an array.
    _Spec('sizesAvailable', EditSection.attributes),
    _Spec('features', EditSection.attributes),
    _Spec('materialsAndCare', EditSection.attributes),
  ];

  static const int maxImages = 10;

  final Map<String, TextEditingController> _text = {};
  final Map<String, String> _initial = {};

  late List<String> tags;
  late final List<String> _initialTags;

  late bool useDefaultShipping;
  num? shippingPriceNok;
  late final bool _initialUseDefaultShipping;
  late final num? _initialShippingPriceNok;

  late List<GalleryImage> images;
  late final List<String> _initialImageRefs;

  /// The controller behind the text field for API key [key].
  TextEditingController operator [](String key) => _text[key]!;

  PlatformShippingSettings? get platformShipping => detail.platformShipping;

  /// Fixed shipping amounts the seller may pick, capped by the platform's
  /// per-product maximum — anything above it would only be bounced.
  List<num> get shippingAmounts {
    final all = platformShipping?.allowedShippingAmountsNok ?? const <num>[];
    final max = platformShipping?.maxShippingPerProductNok;
    return max == null ? all : all.where((a) => a <= max).toList();
  }

  /// False when the platform forbids per-product shipping prices.
  bool get canOverrideShipping =>
      (platformShipping?.allowSellerOverride ?? true) &&
      shippingAmounts.isNotEmpty;

  // ── Mutations ──────────────────────────────────────────────────────────────

  /// Adds one or more comma-separated tags, skipping case-insensitive dupes.
  void addTags(String raw) {
    for (final tag in raw.split(',').map((e) => e.trim())) {
      if (tag.isEmpty) continue;
      if (tags.any((t) => t.toLowerCase() == tag.toLowerCase())) continue;
      tags.add(tag);
    }
    notifyListeners();
  }

  void removeTag(String tag) {
    tags.remove(tag);
    notifyListeners();
  }

  void setUseDefaultShipping(bool value) {
    useDefaultShipping = value;
    notifyListeners();
  }

  void setShippingPrice(num value) {
    shippingPriceNok = value;
    notifyListeners();
  }

  void addImages(Iterable<GalleryImage> added) {
    images.addAll(added);
    notifyListeners();
  }

  void removeImageAt(int index) {
    images.removeAt(index);
    notifyListeners();
  }

  // ── Diff ───────────────────────────────────────────────────────────────────

  bool get imagesChanged =>
      !_listEquals(images.map((e) => e.ref).toList(), _initialImageRefs);

  bool get _shippingChanged =>
      useDefaultShipping != _initialUseDefaultShipping ||
      (!useDefaultShipping && shippingPriceNok != _initialShippingPriceNok);

  bool _textChanged(String key) => _text[key]!.text.trim() != _initial[key];

  /// The PATCH body minus `editReason`: only what differs from the opened
  /// state.
  Map<String, dynamic> changes() {
    final out = <String, dynamic>{};

    for (final spec in _specs) {
      if (!_textChanged(spec.key)) continue;
      final value = _text[spec.key]!.text.trim();
      switch (spec.kind) {
        case _Kind.text:
          out[spec.key] = value;
        case _Kind.nullableText:
          out[spec.key] = value.isEmpty ? null : value;
        case _Kind.decimal:
        case _Kind.integer:
          // Numbers have no "clear" semantics on this endpoint, so emptying
          // one means "leave alone" rather than sending "".
          final parsed = _parse(value, integer: spec.kind == _Kind.integer);
          if (parsed != null) out[spec.key] = parsed;
      }
    }

    if (!_listEquals(tags, _initialTags)) out['tags'] = List.of(tags);

    if (_shippingChanged) {
      if (useDefaultShipping) {
        out['useDefaultShipping'] = true;
      } else if (shippingPriceNok != null) {
        out['useDefaultShipping'] = false;
        out['shippingPriceNok'] = shippingPriceNok;
      }
    }

    if (imagesChanged) {
      // `imageUrls` is ignored without `replaceImages` — the gallery is
      // replaced wholesale.
      out['replaceImages'] = true;
      out['imageUrls'] = images.map((e) => e.ref).toList();
    }

    return out;
  }

  /// What the seller would call "changes": a photo swap or a shipping switch
  /// is one change even though each sends two keys.
  int get changeCount {
    final c = changes();
    var n = c.length;
    if (c.containsKey('replaceImages')) n--;
    if (c.containsKey('useDefaultShipping') &&
        c.containsKey('shippingPriceNok')) {
      n--;
    }
    return n;
  }

  /// Tabs holding at least one unsaved change, for the tab-strip dots.
  Set<EditSection> get dirtySections => {
        for (final spec in _specs)
          if (_textChanged(spec.key)) spec.section,
        if (imagesChanged) EditSection.general,
        if (!_listEquals(tags, _initialTags)) EditSection.attributes,
        if (_shippingChanged) EditSection.shipping,
      };

  // ── Validation ─────────────────────────────────────────────────────────────

  /// The first thing blocking a save, or null when the form can go out.
  /// Prices below the payment provider's minimum are left to the server, whose
  /// error message states the exact figure.
  EditProblem? validate() {
    final numeric = <(String, String, EditSection, bool)>[
      ('veilPris', TKeys.fieldOriginalPrice.tr, EditSection.pricing, false),
      ('startingPrice', TKeys.fieldStartingPrice.tr, EditSection.pricing, false),
      ('bottomPrice', TKeys.fieldBottomPrice.tr, EditSection.pricing, false),
      ('stockCount', TKeys.fieldStockCount.tr, EditSection.inventory, true),
      ('weight', TKeys.fieldWeight.tr, EditSection.inventory, false),
    ];
    for (final (key, label, section, integer) in numeric) {
      final value = _text[key]!.text.trim();
      if (value.isNotEmpty && _parse(value, integer: integer) == null) {
        return EditProblem(
            section, TKeys.mustBeNumber.trParams({'field': label}));
      }
    }
    if (_text['name']!.text.trim().isEmpty) {
      return EditProblem(EditSection.general, TKeys.productNameEmpty.tr);
    }
    if (imagesChanged && images.isEmpty) {
      return EditProblem(EditSection.general, TKeys.keepOnePhoto.tr);
    }
    if (!useDefaultShipping && shippingPriceNok == null) {
      return EditProblem(EditSection.shipping, TKeys.shippingPickAmount.tr);
    }
    if (changes().isEmpty) {
      return EditProblem(EditSection.general, TKeys.nothingChangedYet.tr);
    }
    return null;
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static num? _parse(String value, {required bool integer}) => integer
      ? int.tryParse(value)
      : num.tryParse(value.replaceAll(',', '.').replaceAll(' ', ''));

  /// Pairs the raw image refs from the list row (what the API stored) with the
  /// renderable HTTPS URLs from the detail payload. Both come back in gallery
  /// order, so they zip index-wise; without refs the URLs are sent back as-is.
  static List<GalleryImage> _pairGallery(
      List<String> refs, List<String> urls) {
    if (refs.length != urls.length || refs.isEmpty) {
      return [for (final url in urls) GalleryImage(ref: url, display: url)];
    }
    return [
      for (var i = 0; i < refs.length; i++)
        GalleryImage(ref: refs[i], display: urls[i]),
    ];
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
