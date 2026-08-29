import '../core/localization/translation_keys.dart';
import 'package:get/get.dart';
/// Models for the seller measurement module — the "Measurements" section shown in the
/// product quick views.
///
/// Backed by `GET /api/v1/seller/products/{id}/measurement-bundle`, which
/// returns the recorded measurements plus the measurement-type catalog in one
/// call, and `POST /api/v1/seller/measurements/{id}` to save them.

/// One selectable measurement target, e.g. `{ key: 'chest', label: 'Chest' }`.
///
/// Comes from the bundle's `measurementTypes`; [kDefaultMeasurementTypes] is
/// used when the server sends none.
class MeasurementType {
  const MeasurementType({
    required this.key,
    required this.label,
    this.id,
    this.unit = 'cm',
    this.displayOrder = 0,
  });

  final String key;
  final String label;
  final String? id;
  final String unit;
  final int displayOrder;

  factory MeasurementType.fromJson(Map<String, dynamic> json) {
    final key = json['key'] as String? ?? json['fieldKey'] as String? ?? '';
    return MeasurementType(
      key: key,
      label: json['label'] as String? ?? json['name'] as String? ?? key,
      id: json['id'] as String?,
      unit: json['unit'] as String? ?? 'cm',
      displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The measurement targets offered when the bundle returns no
/// `measurementTypes` — keeps the picker usable rather than empty.
// A getter, not a `const` list: the labels are shown to the seller, so they
// have to re-resolve when the language changes. The `key`s stay the API's.
List<MeasurementType> get kDefaultMeasurementTypes => <MeasurementType>[
      MeasurementType(key: 'chest', label: TKeys.mtChest.tr, displayOrder: 1),
      MeasurementType(key: 'waist', label: TKeys.mtWaist.tr, displayOrder: 2),
      MeasurementType(
          key: 'shoulder', label: TKeys.mtShoulder.tr, displayOrder: 3),
      MeasurementType(
          key: 'sleeve_length', label: TKeys.mtSleeveLength.tr, displayOrder: 4),
      MeasurementType(
          key: 'arm_length', label: TKeys.mtArmLength.tr, displayOrder: 5),
      MeasurementType(key: 'inseam', label: TKeys.mtInseam.tr, displayOrder: 6),
      MeasurementType(
          key: 'total_length', label: TKeys.mtTotalLength.tr, displayOrder: 7),
      MeasurementType(key: 'rise', label: TKeys.mtRise.tr, displayOrder: 8),
      MeasurementType(key: 'width', label: TKeys.mtWidth.tr, displayOrder: 9),
      MeasurementType(key: 'height', label: TKeys.mtHeight.tr, displayOrder: 10),
      MeasurementType(key: 'depth', label: TKeys.mtDepth.tr, displayOrder: 11),
      MeasurementType(key: 'other', label: TKeys.mtOther.tr, displayOrder: 12),
    ];

/// One measurement already recorded against a product (+ placement).
///
/// [id] backs the delete endpoint; a row the seller adds locally has none until
/// it is saved.
class Measurement {
  const Measurement({
    required this.fieldKey,
    required this.valueCm,
    this.id,
    this.label,
    this.measurementTypeId,
  });

  final String fieldKey;
  final double valueCm;
  final String? id;
  final String? label;
  final String? measurementTypeId;

  /// Tolerant of both the mobile (`fieldKey`/`valueCm`) and web
  /// (`key`/`value` + `measurementTypeId`) row shapes, since the bundle and
  /// the save response are documented only by example.
  factory Measurement.fromJson(Map<String, dynamic> json) {
    final rawValue = json['valueCm'] ?? json['value'] ?? json['valueInCm'];
    return Measurement(
      fieldKey: json['fieldKey'] as String? ?? json['key'] as String? ?? '',
      valueCm: (rawValue as num?)?.toDouble() ?? 0,
      id: json['id'] as String?,
      label: json['label'] as String? ?? json['name'] as String?,
      measurementTypeId: json['measurementTypeId'] as String?,
    );
  }
}

/// A single `{ fieldKey, valueCm }` row of the save payload.
class MeasurementInput {
  const MeasurementInput({required this.fieldKey, required this.valueCm});

  final String fieldKey;
  final double valueCm;

  Map<String, dynamic> toJson() => {'fieldKey': fieldKey, 'valueCm': valueCm};
}

/// Outcome of a save. On success [error] is null and [measurements] is the set
/// the server echoed back — authoritative, so the form can render it without a
/// second read.
class MeasurementSaveResult {
  const MeasurementSaveResult({this.error, this.measurements = const []});

  final String? error;
  final List<Measurement> measurements;

  bool get ok => error == null;
}

/// The quick-view payload from `GET /products/{id}/measurement-bundle`.
///
/// Only the parts the mobile Measurements section needs are mapped — the
/// recorded values, the type catalog and the product's size / spec photos.
/// `suggestedMeasurements` and `referenceImage` are ignored.
class MeasurementBundle {
  const MeasurementBundle({
    this.measurements = const [],
    this.measurementTypes = const [],
    this.sizeSpecImages = const [],
    this.status,
    this.categoryId,
  });

  final List<Measurement> measurements;
  final List<MeasurementType> measurementTypes;

  /// `product.sizeSpecImages` — the photos already on the product, as signed
  /// URLs. This is what the section's photo strip renders on open.
  final List<SizeSpecImage> sizeSpecImages;

  /// `meta.measurementStatus` — "empty" | "recorded".
  final String? status;
  final String? categoryId;

  factory MeasurementBundle.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    final product =
        (json['product'] as Map?)?.cast<String, dynamic>() ?? const {};

    final types = ((json['measurementTypes'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MeasurementType.fromJson(e.cast<String, dynamic>()))
        .where((t) => t.key.isNotEmpty)
        .toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return MeasurementBundle(
      measurements: ((json['measurements'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Measurement.fromJson(e.cast<String, dynamic>()))
          .toList(),
      measurementTypes: types,
      sizeSpecImages: SizeSpecImage.listFrom(
        product['sizeSpecImages'] ?? json['sizeSpecImages'],
      ),
      status: meta['measurementStatus'] as String?,
      categoryId: meta['categoryId'] as String?,
    );
  }
}
/// One size / spec photo attached to a product.
///
/// The measurement bundle returns these as pre-signed URLs
/// (`data.product.sizeSpecImages`), while the save endpoint
/// (`PUT /products/{id}/size-spec-images`) takes the bare S3 [key]s and
/// replaces the whole set. [from] holds both, deriving the key from the URL's
/// path — `https://…/assets/product-size-spec/<product>/x.jpg?X-Amz-…` →
/// `assets/product-size-spec/<product>/x.jpg` — so a signed URL can never end
/// up in the save payload, nor a raw key in an `Image.network`.
class SizeSpecImage {
  const SizeSpecImage({required this.key, this.url});

  /// The `s3Key` — what goes back in the save payload.
  final String key;

  /// Pre-signed URL, when the server sent one.
  final String? url;

  /// What can actually be rendered, or null when we only hold a key.
  String? get displayUrl => (url != null && url!.startsWith('http'))
      ? url
      : (key.startsWith('http') ? key : null);

  /// The S3 key behind [value] — the path of a signed URL, or the string
  /// itself when it already is a key.
  static String keyOf(String value) {
    if (!value.startsWith('http')) return value;
    final path = Uri.tryParse(value)?.path ?? value;
    return path.startsWith('/') ? path.substring(1) : path;
  }

  /// `assets/product-size-spec/…/1784-ovny96.jpg` → `1784-ovny96.jpg`, for the
  /// placeholder tile shown when there is no URL to render.
  String get fileName {
    final path = key.split('?').first;
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// Reads one entry, which the API sends either as a bare key/URL string or
  /// as an object carrying both.
  static SizeSpecImage? from(dynamic value) {
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      return SizeSpecImage(
        key: keyOf(text),
        url: text.startsWith('http') ? text : null,
      );
    }
    if (value is Map) {
      final map = value.cast<String, dynamic>();
      final raw = (map['s3Key'] ??
          map['key'] ??
          map['imageUrl'] ??
          map['url']) as String?;
      if (raw == null || raw.trim().isEmpty) return null;

      final url = (map['url'] ?? map['signedUrl'] ?? map['imageUrl'])
          as String?;
      return SizeSpecImage(
        key: keyOf(raw.trim()),
        url: (url != null && url.startsWith('http')) ? url : null,
      );
    }
    return null;
  }

  /// Reads the list out of whichever envelope the endpoint used — a bare
  /// array, or an object keyed `imageUrls` / `images` / `sizeSpecImages`.
  static List<SizeSpecImage> listFrom(dynamic value) {
    if (value is List) {
      return value.map(SizeSpecImage.from).whereType<SizeSpecImage>().toList();
    }
    if (value is Map) {
      final map = value.cast<String, dynamic>();
      for (final key in const [
        'imageUrls',
        'images',
        'sizeSpecImages',
        'sizeSpecImageUrls',
        'items',
      ]) {
        final list = map[key];
        if (list is List) return listFrom(list);
      }
    }
    return const [];
  }
}

/// Outcome of one size / spec photo upload. On success [image] carries the
/// `s3Key` the save call needs.
class SizeSpecUploadResult {
  const SizeSpecUploadResult({this.image, this.error});

  final SizeSpecImage? image;
  final String? error;

  bool get ok => image != null;
}
