import 'dart:developer';

import 'package:get/get.dart';

import '../config/env_config.dart';
import '../localization/translation_keys.dart';
import '../utils/image_compressor.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// A product's seller-recorded defect, as `GET /products/{id}/preview`
/// returns it. [images] are display URLs.
class ProductDefect {
  const ProductDefect({
    this.images = const [],
    this.description = '',
    this.quantity = 0,
  });

  final List<String> images;
  final String description;

  /// Draft `defect_quantity` on the request line; 0 means no defect.
  final int quantity;

  bool get isEmpty => images.isEmpty && description.isEmpty && quantity == 0;

  factory ProductDefect.fromJson(Map<String, dynamic> json) {
    final q = json['defectQuantity'];
    return ProductDefect(
      images: ((json['defectImages'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      description: (json['defectDescription'] as String?)?.trim() ?? '',
      quantity: q is num ? q.toInt() : int.tryParse('${q ?? ''}') ?? 0,
    );
  }
}

/// Seller product-defect endpoints (Phase 2.4), backing the "Defect" section
/// of the product-request quick view:
///
/// * `GET  /products/{id}/preview` — current `defectImages` /
///   `defectDescription` / `defectQuantity`
/// * `POST /products/{id}/defects` — upload one photo → `s3Key` (no DB write)
/// * `PUT  /products/{id}/defects` — replace images + description and set the
///   draft line's `defectQuantity` (0 turns the defect off)
///
/// Only a draft request line can be saved; the server rejects it after submit.
class ProductDefectService {
  ProductDefectService._();

  static final ProductDefectService instance = ProductDefectService._();

  final _api = ApiClient.instance;

  /// Max defect photos the API accepts.
  static const int maxImages = 5;

  String _productUrl(String productId) =>
      '${EnvConfig.baseUrl}/api/v1/seller/products/'
      '${Uri.encodeComponent(productId)}';

  /// Null when the preview could not be read.
  Future<ProductDefect?> fetch(String productId) async {
    try {
      final response = await _api.get(
        '${_productUrl(productId)}/preview',
        headers: AuthService.instance.authHeaders,
      );
      if (!response.isSuccess) return null;
      final body = response.json;
      final data = body['data'];
      if (data is! Map<String, dynamic>) return null;
      final product = data['product'];
      return ProductDefect.fromJson(
        product is Map<String, dynamic> ? product : data,
      );
    } catch (e) {
      log('Defect fetch error: $e');
      return null;
    }
  }

  /// Uploads one photo and returns its `s3Key`, or throws the message to show.
  Future<String> uploadImage(String productId, String filePath) async {
    final path = await ImageCompressor.compress(filePath);
    final response = await _api.uploadFile(
      '${_productUrl(productId)}/defects',
      fieldName: 'file',
      filePath: path,
      headers: AuthService.instance.authHeaders,
    );
    if (response.isSuccess) {
      final data = response.json['data'];
      final key = data is Map ? data['s3Key'] as String? : null;
      if (key != null && key.isNotEmpty) return key;
      throw TKeys.svcNoFileKey.tr;
    }
    throw _errorMessage(response) ?? TKeys.defectCouldNotSave.tr;
  }

  /// Saves the defect. Returns the server's resulting state on success, or
  /// throws the message to show.
  Future<ProductDefect> save({
    required String productId,
    required String requestItemId,
    required List<String> imageKeys,
    required String description,
    required int defectQuantity,
  }) async {
    final body = {
      'requestItemId': requestItemId,
      'imageUrls': imageKeys,
      'description': description,
      'defectQuantity': defectQuantity,
    };
    final response = await _api.put(
      '${_productUrl(productId)}/defects',
      headers: AuthService.instance.authHeaders,
      body: body,
    );
    if (response.isSuccess) {
      final data = response.json['data'];
      return data is Map<String, dynamic>
          ? ProductDefect.fromJson(data)
          : ProductDefect(description: description, quantity: defectQuantity);
    }
    throw _errorMessage(response) ?? TKeys.defectCouldNotSave.tr;
  }

  String? _errorMessage(ApiResponse response) {
    try {
      final error = response.json['error'];
      if (error is Map && error['message'] is String) {
        final message = (error['message'] as String).trim();
        if (message.isNotEmpty) return message;
      }
    } catch (_) {}
    return null;
  }
}
