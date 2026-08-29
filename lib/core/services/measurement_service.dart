import 'dart:developer';

import '../../models/measurement.dart';
import '../config/env_config.dart';
import 'api_client.dart';
import 'auth_service.dart';
import '../localization/translation_keys.dart';
import 'package:get/get.dart';

/// Seller measurement endpoints, backing the "Measurements" section of the
/// product quick views.
///
/// Covers the quick-view bundle, the mobile save and the by-id delete, plus
/// the size / spec photo trio (upload → save, where save replaces the set). State is per-dialog and
/// short-lived, so this is a plain service rather than a GetX controller.
class MeasurementService {
  MeasurementService._();

  static final MeasurementService instance = MeasurementService._();

  final _api = ApiClient.instance;

  String get _base => '${EnvConfig.baseUrl}/api/v1/seller';

  /// `GET /products/{id}/measurement-bundle` — recorded measurements plus the
  /// measurement-type catalog in one request. Returns null when the request
  /// fails, matching the read convention elsewhere in the app.
  Future<MeasurementBundle?> fetchBundle({required String productId}) async {
    try {
      final url =
          '$_base/products/${Uri.encodeComponent(productId)}/measurement-bundle';

      final response = await _api.get(
        url,
        headers: AuthService.instance.authHeaders,
      );

      if (!response.isSuccess) return null;

      final body = response.json;
      final data = body['data'];
      if (body['success'] == true && data is Map<String, dynamic>) {
        return MeasurementBundle.fromJson(data);
      }
      return null;
    } catch (e) {
      log('Measurement bundle fetch error: $e');
      return null;
    }
  }

  /// `POST /measurements/{id}` with the bare `[{fieldKey, valueCm}]` array
  /// (mobile shape).
  ///
  /// The response's own `measurements` are returned so callers can render the
  /// saved set directly. Re-reading the bundle instead would risk showing
  /// pre-write data — the same read-after-write staleness `movePlacement`
  /// guards against.
  Future<MeasurementSaveResult> saveMeasurements({
    required String productId,
    required List<MeasurementInput> measurements,
  }) async {
    try {
      final url = '$_base/measurements/${Uri.encodeComponent(productId)}';

      final response = await _api.post(
        url,
        headers: AuthService.instance.authHeaders,
        body: measurements.map((m) => m.toJson()).toList(),
      );

      if (!response.isSuccess) {
        return MeasurementSaveResult(
          error: _errorMessage(response) ?? 'Could not save measurements.',
        );
      }

      final data = response.json['data'];
      final rows = data is Map<String, dynamic> ? data['measurements'] : null;
      return MeasurementSaveResult(
        measurements: (rows as List? ?? const [])
            .whereType<Map>()
            .map((e) => Measurement.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
    } catch (e) {
      log('Measurement save error: $e');
      return MeasurementSaveResult(
        error: TKeys.svcNetworkError.tr,
      );
    }
  }

  /// `DELETE /measurements/by-id/{id}` — drops a previously saved measurement
  /// the seller removed. A 404 counts as success: the row is gone either way.
  Future<String?> deleteMeasurement(String measurementId) async {
    try {
      final response = await _api.delete(
        '$_base/measurements/by-id/${Uri.encodeComponent(measurementId)}',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess || response.statusCode == 404) return null;
      return _errorMessage(response) ?? 'Could not remove a measurement.';
    } catch (e) {
      log('Measurement delete error: $e');
      return 'Network error. Please try again.';
    }
  }

  // ---------- Size / spec photos ----------
  //
  // The current set is read from the measurement bundle
  // (`data.product.sizeSpecImages`), so there is no read call here.

  String _sizeSpecUrl(String productId) =>
      '$_base/products/${Uri.encodeComponent(productId)}/size-spec-images';

  /// `POST /products/{id}/size-spec-images` — uploads one JPEG/PNG/WebP
  /// (multipart field `file`, max 5 MB) and returns its `s3Key`. Nothing is
  /// attached to the product until [saveSizeSpecImages] runs.
  Future<SizeSpecUploadResult> uploadSizeSpecImage({
    required String productId,
    required String filePath,
  }) async {
    try {
      final response = await _api.uploadFile(
        _sizeSpecUrl(productId),
        fieldName: 'file',
        filePath: filePath,
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        final data = body['data'];
        final map = data is Map<String, dynamic> ? data : body;

        final key = (map['s3Key'] ?? map['key']) as String?;
        final url = (map['url'] ?? map['signedUrl'] ?? map['imageUrl'])
            as String?;

        if (key != null && key.trim().isNotEmpty) {
          return SizeSpecUploadResult(
            image: SizeSpecImage(key: key.trim(), url: url),
          );
        }
        return SizeSpecUploadResult(
          error: TKeys.svcNoFileKey.tr,
        );
      }

      return SizeSpecUploadResult(
        error: _errorMessage(response) ??
            (response.statusCode == 413
                ? 'That photo is too large — the limit is 5 MB.'
                : 'Could not upload the photo (${response.statusCode}).'),
      );
    } catch (e) {
      log('Size-spec image upload error: $e', name: 'Measurements');
      return SizeSpecUploadResult(
        error: TKeys.svcNetworkError.tr,
      );
    }
  }

  /// `PUT /products/{id}/size-spec-images` with `{ imageUrls: [...] }`.
  ///
  /// There is no remove endpoint by design — this call *replaces* the set, so
  /// the list passed in is exactly what the product ends up with (an empty
  /// list clears it). Returns null on success, or the message to show.
  Future<String?> saveSizeSpecImages({
    required String productId,
    required List<String> imageKeys,
  }) async {
    try {
      final response = await _api.put(
        _sizeSpecUrl(productId),
        headers: AuthService.instance.authHeaders,
        body: {'imageUrls': imageKeys},
      );

      log(
        '[SizeSpec] PUT ${imageKeys.length} key(s) → ${response.statusCode} '
        '${response.body}',
        name: 'Measurements',
      );

      if (response.isSuccess) return null;
      return _errorMessage(response) ??
          'Could not save the photos (${response.statusCode}).';
    } catch (e) {
      log('Size-spec images save error: $e', name: 'Measurements');
      return 'Network error. Please try again.';
    }
  }

  /// Pulls `error.message` out of the envelope, falling back to a status-based
  /// message for the codes these endpoints document.
  String? _errorMessage(ApiResponse response) {
    try {
      final error = response.json['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.trim().isNotEmpty) return message;
      }
    } catch (_) {}

    switch (response.statusCode) {
      case 400:
        return 'This measurement type is not supported for this product.';
      case 403:
        return 'Measurements are only available for managed sellers.';
      case 404:
        return 'This product no longer exists.';
      case 422:
        return 'Please check the measurements and try again.';
      case 429:
        return 'Too many attempts. Please wait a moment and try again.';
    }
    return null;
  }
}
