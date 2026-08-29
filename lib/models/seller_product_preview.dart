/// Full product payload from `GET /api/v1/seller/products/{id}/preview`.
///
/// The list endpoint only carries name / status / prices / image keys, so the
/// details sheet loads this for the richer fields (brand, description, colour,
/// sizes, size chart) and — importantly — for pre-signed image URLs that can
/// actually be rendered. It doubles as the prefill source for the edit form,
/// which is why the editable catalog fields are all parsed here.
class SellerProductPreview {
  final String id;
  final String name;
  final String? brand;
  final String? shortDescription;
  final String? description;
  final String? gender;
  final String? image;
  final List<String> images;
  final String? colour;
  final List<String> colorsAvailable;
  final List<String> tags;
  final List<String> sizesAvailable;
  final String? size;
  final String? usSize;
  final String? euSize;
  final num? originalPrice;
  final num? regularPrice;
  final num? startingPrice;
  final num? bottomPrice;
  final num? weight;
  final String? material;
  final String? features;
  final String? materialsAndCare;
  final String? sku;
  final String? upc;
  final int? stockCount;
  final bool? useDefaultShipping;
  final num? shippingPriceNok;
  final String? taxonomyNodeId;
  final String? sizeType;
  final SellerSizeChart? sizeChart;

  /// The untouched payload, so fields the model doesn't name yet stay
  /// reachable without a model change.
  final Map<String, dynamic> raw;

  SellerProductPreview({
    required this.id,
    required this.name,
    this.brand,
    this.shortDescription,
    this.description,
    this.gender,
    this.image,
    this.images = const [],
    this.colour,
    this.colorsAvailable = const [],
    this.tags = const [],
    this.sizesAvailable = const [],
    this.size,
    this.usSize,
    this.euSize,
    this.originalPrice,
    this.regularPrice,
    this.startingPrice,
    this.bottomPrice,
    this.weight,
    this.material,
    this.features,
    this.materialsAndCare,
    this.sku,
    this.upc,
    this.stockCount,
    this.useDefaultShipping,
    this.shippingPriceNok,
    this.taxonomyNodeId,
    this.sizeType,
    this.sizeChart,
    this.raw = const {},
  });

  factory SellerProductPreview.fromJson(Map<String, dynamic> json) {
    return SellerProductPreview(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String?,
      shortDescription: json['shortDescription'] as String?,
      description: json['description'] as String?,
      gender: json['gender'] as String?,
      image: (json['image'] ?? json['thumbnailUrl']) as String?,
      images: _stringList(json['images']),
      colour: json['colour'] as String?,
      colorsAvailable: _stringList(json['colorsAvailable']),
      tags: _stringList(json['tags']),
      sizesAvailable: _stringList(json['sizesAvailable']),
      size: json['size'] as String?,
      usSize: json['usSize'] as String?,
      euSize: json['euSize'] as String?,
      originalPrice: _num(json['originalPrice']),
      regularPrice: _num(json['regularPrice']),
      startingPrice: _num(json['startingPrice']),
      bottomPrice: _num(json['bottomPrice']),
      weight: _num(json['weight']),
      material: json['material'] as String?,
      features: json['features'] as String?,
      materialsAndCare: json['materialsAndCare'] as String?,
      sku: json['sku'] as String?,
      upc: json['upc'] as String?,
      stockCount: _num(json['stockCount'])?.toInt(),
      useDefaultShipping: json['useDefaultShipping'] as bool?,
      shippingPriceNok: _num(json['shippingPriceNok']),
      taxonomyNodeId: json['taxonomyNodeId'] as String?,
      sizeType: json['sizeType'] as String?,
      sizeChart: json['sizeChart'] is Map<String, dynamic>
          ? SellerSizeChart.fromJson(json['sizeChart'] as Map<String, dynamic>)
          : null,
      raw: json,
    );
  }

  /// Every image that can go straight into `Image.network`, `images` first and
  /// the standalone `image` appended when it isn't already in there.
  List<String> get imageUrls {
    final urls = images.where((e) => e.startsWith('http')).toList();
    final single = image;
    if (single != null && single.startsWith('http') && !urls.contains(single)) {
      urls.add(single);
    }
    return urls;
  }

  /// Lists come back either as an array or as a comma-separated string
  /// (`tags`, `colorsAvailable` and `sizesAvailable` are all accepted as CSV
  /// on the way in, and the server echoes them back in either shape).
  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static num? _num(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value.trim());
    return null;
  }
}

/// The `sizeChart` block of the preview payload.
class SellerSizeChart {
  final bool found;
  final String? chartId;
  final String? title;
  final List<String> images;

  SellerSizeChart({
    required this.found,
    this.chartId,
    this.title,
    this.images = const [],
  });

  factory SellerSizeChart.fromJson(Map<String, dynamic> json) {
    return SellerSizeChart(
      found: json['found'] as bool? ?? false,
      chartId: json['chartId'] as String?,
      title: json['title'] as String?,
      images: (json['images'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }
}
