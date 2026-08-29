import 'seller_product_preview.dart';

/// The `data` block of `GET /api/v1/seller/products/{id}` — the fullest view of
/// one of the seller's products, plus the platform shipping rules that apply
/// to it.
///
/// The list endpoint only carries name / status / prices / image keys and the
/// `/preview` payload drops the auction, warehouse and shipping fields, so the
/// details page reads this one. Text columns come back as the *string* `"null"`
/// for a few legacy rows, which is why every string goes through [_str].
class SellerProductDetail {
  final String id;
  final String name;
  final String? description;
  final String? shortDescription;
  final String? features;
  final String? materialsAndCare;
  final String? sellerNote;
  final String? shippingAndReturns;
  final String? productReferralLink;

  /// Pre-signed S3 URLs — renderable as-is.
  final List<String> images;

  final String? category;
  final String? subCategory;
  final String? brand;
  final String? gender;
  final List<String> tags;

  final num? originalPrice;
  final num? buyNowPrice;
  final num? regularPrice;
  final num? startingPrice;
  final num? bidIncrement;
  final num? bottomPrice;

  final int? stockCount;
  final String status;
  final bool isVisible;

  final String? sku;
  final String? upc;
  final String? barcodeLookup;
  final num? weight;
  final String? material;
  final String? colour;
  final List<String> sizesAvailable;
  final List<String> colorsAvailable;
  final String? taxonomyNodeId;
  final String? sizeType;
  final String? size;
  final String? vendorStyle;
  final String? importTag;

  /// How many sellers this product is assigned to across the platform.
  final int? assignedSellerCount;

  final num? shippingPriceNok;
  final bool shippingOverrideEnabled;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Platform-wide shipping rules, sent alongside the product.
  final PlatformShippingSettings? platformShipping;

  /// The untouched `product` object, so fields the model doesn't name yet stay
  /// reachable — and so the edit form can be prefilled from it.
  final Map<String, dynamic> raw;

  SellerProductDetail({
    required this.id,
    required this.name,
    this.description,
    this.shortDescription,
    this.features,
    this.materialsAndCare,
    this.sellerNote,
    this.shippingAndReturns,
    this.productReferralLink,
    this.images = const [],
    this.category,
    this.subCategory,
    this.brand,
    this.gender,
    this.tags = const [],
    this.originalPrice,
    this.buyNowPrice,
    this.regularPrice,
    this.startingPrice,
    this.bidIncrement,
    this.bottomPrice,
    this.stockCount,
    this.status = '',
    this.isVisible = false,
    this.sku,
    this.upc,
    this.barcodeLookup,
    this.weight,
    this.material,
    this.colour,
    this.sizesAvailable = const [],
    this.colorsAvailable = const [],
    this.taxonomyNodeId,
    this.sizeType,
    this.size,
    this.vendorStyle,
    this.importTag,
    this.assignedSellerCount,
    this.shippingPriceNok,
    this.shippingOverrideEnabled = false,
    this.createdAt,
    this.updatedAt,
    this.platformShipping,
    this.raw = const {},
  });

  /// Parses the whole `data` block (`{ product, platformShippingSettings }`).
  /// Older builds of the endpoint returned the product at the root, so a
  /// payload without a `product` key is read as the product itself.
  factory SellerProductDetail.fromData(Map<String, dynamic> data) {
    final product =
        (data['product'] as Map?)?.cast<String, dynamic>() ?? data;
    final shipping = (data['platformShippingSettings'] as Map?)
        ?.cast<String, dynamic>();

    return SellerProductDetail.fromJson(
      product,
      platformShipping: shipping == null
          ? null
          : PlatformShippingSettings.fromJson(shipping),
    );
  }

  factory SellerProductDetail.fromJson(
    Map<String, dynamic> json, {
    PlatformShippingSettings? platformShipping,
  }) {
    return SellerProductDetail(
      id: _str(json['id']) ?? '',
      name: _str(json['name']) ?? '',
      description: _str(json['description']),
      shortDescription: _str(json['shortDescription']),
      features: _str(json['features']),
      materialsAndCare: _str(json['materialsAndCare']),
      sellerNote: _str(json['sellerNote']),
      shippingAndReturns: _str(json['shippingAndReturns']),
      productReferralLink: _str(json['productReferralLink']),
      images: _stringList(json['images']),
      category: _str(json['category']),
      subCategory: _str(json['subCategory']),
      brand: _str(json['brand']),
      gender: _str(json['gender']),
      tags: _stringList(json['tags']),
      originalPrice: _num(json['originalPrice']),
      buyNowPrice: _num(json['buyNowPrice']),
      regularPrice: _num(json['regularPrice']),
      startingPrice: _num(json['startingPrice']),
      bidIncrement: _num(json['bidIncrement']),
      bottomPrice: _num(json['bottomPrice']),
      stockCount: _num(json['stockCount'])?.toInt(),
      status: _str(json['status']) ?? '',
      isVisible: json['isVisible'] as bool? ?? false,
      sku: _str(json['sku']),
      upc: _str(json['upc']),
      barcodeLookup: _str(json['barcodeLookup']),
      weight: _num(json['weight']),
      material: _str(json['material']),
      colour: _str(json['colour']),
      sizesAvailable: _stringList(json['sizesAvailable']),
      colorsAvailable: _stringList(json['colorsAvailable']),
      taxonomyNodeId: _str(json['taxonomyNodeId']),
      sizeType: _str(json['sizeType']),
      size: _str(json['size']),
      vendorStyle: _str(json['vendorStyle']),
      importTag: _str(json['importTag']),
      assignedSellerCount: _num(json['assignedSellerCount'])?.toInt(),
      shippingPriceNok: _num(json['shippingPriceNok']),
      shippingOverrideEnabled:
          json['shippingOverrideEnabled'] as bool? ?? false,
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      platformShipping: platformShipping,
      raw: json,
    );
  }

  /// Images that can go straight into `Image.network`.
  List<String> get imageUrls =>
      images.where((e) => e.startsWith('http')).toList();

  /// Price the buyer actually pays, falling back to the list price.
  num? get effectivePrice => buyNowPrice ?? regularPrice ?? originalPrice;

  /// True when [effectivePrice] undercuts [originalPrice].
  bool get hasDiscount {
    final price = effectivePrice;
    return price != null && originalPrice != null && price < originalPrice!;
  }

  /// `1500 → 800` ⇒ `47`. Null when there is no discount to show.
  int? get discountPercent {
    if (!hasDiscount || originalPrice == 0) return null;
    final off = (originalPrice! - effectivePrice!) / originalPrice! * 100;
    return off.round();
  }

  /// What the buyer pays for shipping: the seller's own price when they've
  /// overridden it, otherwise the platform default.
  num? get effectiveShippingNok => shippingOverrideEnabled
      ? (shippingPriceNok ?? platformShipping?.defaultShippingPriceNok)
      : (platformShipping?.defaultShippingPriceNok ?? shippingPriceNok);

  /// The same product shaped for the edit form's prefill, which reads the
  /// preview model. Both are parsed from the same field names.
  SellerProductPreview toPreview() => SellerProductPreview.fromJson(raw);

  /// Trimmed string, with SQL-ish `"null"` / `"undefined"` leftovers and blanks
  /// treated as absent.
  static String? _str(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty ||
        text.toLowerCase() == 'null' ||
        text.toLowerCase() == 'undefined') {
      return null;
    }
    return text;
  }

  /// Lists arrive either as an array or as a comma-separated string.
  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => _str(e))
          .whereType<String>()
          .toList();
    }
    final text = _str(value);
    if (text == null) return const [];
    return text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static num? _num(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value.trim());
    return null;
  }

  static DateTime? _date(dynamic value) {
    final text = _str(value);
    return text == null ? null : DateTime.tryParse(text);
  }
}

/// The `platformShippingSettings` block — the rules the seller's shipping
/// price has to live inside.
class PlatformShippingSettings {
  final num? defaultShippingPriceNok;
  final num? dailyFreeShippingCapNok;
  final num? maxShippingPerProductNok;
  final bool allowSellerOverride;

  /// The fixed shipping prices a seller may pick from, when overrides are on.
  final List<num> allowedShippingAmountsNok;

  PlatformShippingSettings({
    this.defaultShippingPriceNok,
    this.dailyFreeShippingCapNok,
    this.maxShippingPerProductNok,
    this.allowSellerOverride = false,
    this.allowedShippingAmountsNok = const [],
  });

  factory PlatformShippingSettings.fromJson(Map<String, dynamic> json) {
    return PlatformShippingSettings(
      defaultShippingPriceNok:
          SellerProductDetail._num(json['defaultShippingPriceNok']),
      dailyFreeShippingCapNok:
          SellerProductDetail._num(json['dailyFreeShippingCapNok']),
      maxShippingPerProductNok:
          SellerProductDetail._num(json['maxShippingPerProductNok']),
      allowSellerOverride: json['allowSellerOverride'] as bool? ?? false,
      allowedShippingAmountsNok: (json['allowedShippingAmountsNok'] as List?)
              ?.map(SellerProductDetail._num)
              .whereType<num>()
              .toList() ??
          const [],
    );
  }
}
