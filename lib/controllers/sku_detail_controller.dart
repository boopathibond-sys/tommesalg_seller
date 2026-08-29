import 'dart:developer';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../models/inventory_location_detail.dart';
import '../models/inventory_placement.dart';
import '../models/location_suggestion.dart';
import '../models/pending_product.dart';
import '../models/product_request_model.dart';

/// Drives a single SKU's detail page: the location record + tags
/// (`GET /locations/{id}`), its assigned products
/// (`GET /locations/{id}/placements`), and edits / deactivation
/// (`PATCH /locations/{id}`). One instance per open SKU (tagged by id).
class SkuDetailController extends GetxController {
  SkuDetailController(this.locationId);

  final String locationId;
  final _api = ApiClient.instance;

  String get _base =>
      '${EnvConfig.baseUrl}/api/v1/seller/inventory/locations/$locationId';

  // ---------- Detail state ----------

  final RxBool _isLoadingDetail = false.obs;
  bool get isLoadingDetail => _isLoadingDetail.value;

  final RxnString _detailError = RxnString();
  String? get detailError => _detailError.value;

  final Rxn<InventoryLocationDetail> _detail = Rxn<InventoryLocationDetail>();
  InventoryLocationDetail? get detail => _detail.value;

  // ---------- Placements state ----------

  final RxBool _isLoadingPlacements = false.obs;
  bool get isLoadingPlacements => _isLoadingPlacements.value;

  final RxnString _placementsError = RxnString();
  String? get placementsError => _placementsError.value;

  final RxList<InventoryPlacement> _placements = <InventoryPlacement>[].obs;
  List<InventoryPlacement> get placements => _placements;

  // ---------- Save state ----------

  final RxBool _isSaving = false.obs;
  bool get isSaving => _isSaving.value;

  /// Count of products with a primary placement (for the "N primary" badge).
  int get primaryCount => _placements.where((p) => p.isPrimary).length;

  // ---------- Pending / unknown state ----------
  // Backs the "Pending products" tab on the Assign screen.

  final RxBool _isLoadingPending = false.obs;
  bool get isLoadingPending => _isLoadingPending.value;

  final RxnString _pendingError = RxnString();
  String? get pendingError => _pendingError.value;

  final RxList<PendingProduct> _pending = <PendingProduct>[].obs;
  List<PendingProduct> get pending => _pending;

  // ---------- Lifecycle ----------

  @override
  void onInit() {
    super.onInit();
    fetchDetail();
    fetchPlacements();
  }

  // ---------- Intents ----------

  Future<bool> fetchDetail() async {
    _isLoadingDetail.value = true;
    _detailError.value = null;

    try {
      final response = await _api.get(
        _base,
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          _detail.value = InventoryLocationDetail.fromJson(
            body['data'] as Map<String, dynamic>,
          );
          return true;
        }
        _detailError.value = 'Unexpected response format.';
        return false;
      }

      _detailError.value = 'Failed to load SKU: ${response.statusCode}';
      return false;
    } catch (e) {
      log('SKU detail fetch error: $e');
      _detailError.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoadingDetail.value = false;
    }
  }

  Future<bool> fetchPlacements() async {
    _isLoadingPlacements.value = true;
    _placementsError.value = null;

    try {
      final response = await _api.get(
        '$_base/placements',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final data = body['data'] as Map<String, dynamic>;
          final items = (data['items'] as List?) ?? const [];
          _placements.value = items
              .whereType<Map<String, dynamic>>()
              .map(InventoryPlacement.fromJson)
              .toList();
          return true;
        }
        _placementsError.value = 'Unexpected response format.';
        return false;
      }

      _placementsError.value =
          'Failed to load products: ${response.statusCode}';
      return false;
    } catch (e) {
      log('SKU placements fetch error: $e');
      _placementsError.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoadingPlacements.value = false;
    }
  }

  /// Loads product info for the assigned-product quick view via
  /// `GET /api/v1/seller/products/{productId}/preview`.
  ///
  /// The raw response is logged so the exact shape can be mapped to the quick
  /// view. Returns a best-effort [ProductRequestProduct], or `null` on failure
  /// — the quick view falls back to the placement's own fields.
  Future<ProductRequestProduct?> fetchQuickViewProduct(String productId) async {
    if (productId.isEmpty) return null;

    final url = '${EnvConfig.baseUrl}/api/v1/seller/products/'
        '${Uri.encodeComponent(productId)}/preview';

    try {
      final response = await _api.get(
        url,
        headers: AuthService.instance.authHeaders,
      );

      // Log which endpoint was hit and exactly what it returned, so the
      // response shape can be inspected and mapped.
      log('[quick-view] GET $url');
      log('[quick-view] status=${response.statusCode} body=${response.body}');

      if (!response.isSuccess) return null;

      final body = response.json;
      final data = body['data'];
      if (body['success'] == true && data is Map<String, dynamic>) {
        // The preview payload may carry the product directly or nested under
        // `product` — handle both until the exact shape is confirmed.
        final product =
            (data['product'] as Map?)?.cast<String, dynamic>() ?? data;
        log('[quick-view] product fields: ${product.keys.toList()}');
        return ProductRequestProduct.fromJson(product);
      }
      return null;
    } catch (e) {
      log('[quick-view] product fetch error: $e');
      return null;
    }
  }

  /// Fetches the pending / unknown products for this SKU via
  /// `GET /locations/{id}/pending-unknown`. Returns `true` on a 2xx.
  Future<bool> fetchPendingUnknown() async {
    _isLoadingPending.value = true;
    _pendingError.value = null;

    try {
      final response = await _api.get(
        '$_base/pending-unknown',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final data = body['data'] as Map<String, dynamic>;
          final items = (data['items'] as List?) ?? const [];
          _pending.value = items
              .whereType<Map<String, dynamic>>()
              .map(PendingProduct.fromJson)
              .toList();
          return true;
        }
        _pendingError.value = 'Unexpected response format.';
        return false;
      }

      _pendingError.value =
          'Failed to load pending products: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Pending-unknown fetch error: $e');
      _pendingError.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoadingPending.value = false;
    }
  }

  /// Edits a pending / unknown product for this SKU via
  /// `PATCH /locations/{id}/pending-unknown/{itemId}`. [imageUrls] is the
  /// final set sent verbatim — kept existing keys/URLs plus any newly-uploaded
  /// `s3Key`s. Returns an error message on failure, or `null` on success
  /// (after refreshing the pending list).
  Future<String?> updatePendingUnknown({
    required String itemId,
    required String name,
    String? upc,
    required int quantity,
    required List<String> imageUrls,
  }) async {
    if (itemId.isEmpty) return 'Missing product reference.';

    _isSaving.value = true;

    try {
      final response = await _api.patch(
        '$_base/pending-unknown/${Uri.encodeComponent(itemId)}',
        headers: AuthService.instance.authHeaders,
        body: {
          'name': name.trim(),
          if (upc != null && upc.trim().isNotEmpty) 'upc': upc.trim(),
          'quantity': quantity,
          'imageUrls': imageUrls,
        },
      );

      if (response.isSuccess) {
        final json = response.json;
        if (json['success'] == true) {
          await fetchPendingUnknown();
          return null;
        }
        return 'Unexpected response format.';
      }

      if (response.statusCode == 404) {
        return 'This pending product no longer exists.';
      }
      if (response.statusCode == 403) {
        return 'Warehouse is only available for managed sellers.';
      }
      if (response.statusCode == 422) {
        return 'Please check the product details and try again.';
      }
      return 'Failed to update product: ${response.statusCode}';
    } catch (e) {
      log('Pending-unknown update error: $e');
      return 'Network error. Please try again.';
    } finally {
      _isSaving.value = false;
    }
  }

  /// Removes a pending / unknown product for this SKU via
  /// `DELETE /locations/{id}/pending-unknown/{itemId}`. Returns an error
  /// message on failure, or `null` on success (after refreshing the list).
  Future<String?> deletePendingUnknown(String itemId) async {
    if (itemId.isEmpty) return 'Missing product reference.';

    _isSaving.value = true;

    try {
      final response = await _api.delete(
        '$_base/pending-unknown/${Uri.encodeComponent(itemId)}',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final json = response.json;
        if (json['success'] == true) {
          await fetchPendingUnknown();
          return null;
        }
        return 'Unexpected response format.';
      }

      if (response.statusCode == 404) {
        return 'This pending product no longer exists.';
      }
      if (response.statusCode == 403) {
        return 'Warehouse is only available for managed sellers.';
      }
      return 'Failed to remove product: ${response.statusCode}';
    } catch (e) {
      log('Pending-unknown delete error: $e');
      return 'Network error. Please try again.';
    } finally {
      _isSaving.value = false;
    }
  }

  /// Edits / deactivates the SKU via `PATCH /locations/{id}`. Only non-null
  /// fields are sent. Returns an error message on failure, or `null` on
  /// success (after refreshing the detail record).
  Future<String?> updateLocation({
    String? name,
    String? zone,
    String? aisle,
    String? shelf,
    bool? isActive,
    String? notes,
    List<String>? tagIds,
  }) async {
    _isSaving.value = true;

    String? orNull(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();

    try {
      final body = <String, dynamic>{
        if (name != null) 'name': orNull(name),
        if (zone != null) 'zone': orNull(zone),
        if (aisle != null) 'aisle': orNull(aisle),
        if (shelf != null) 'shelf': orNull(shelf),
        if (isActive != null) 'isActive': isActive,
        if (notes != null) 'notes': orNull(notes),
        if (tagIds != null) 'tagIds': tagIds,
      };

      final response = await _api.patch(
        _base,
        headers: AuthService.instance.authHeaders,
        body: body,
      );

      if (response.isSuccess) {
        final json = response.json;
        if (json['success'] == true) {
          await fetchDetail();
          return null;
        }
        return 'Unexpected response format.';
      }

      if (response.statusCode == 403) {
        return 'Warehouse is only available for managed sellers.';
      }
      if (response.statusCode == 422) {
        return 'Please check the SKU details and try again.';
      }

      return 'Failed to update SKU: ${response.statusCode}';
    } catch (e) {
      log('SKU update error: $e');
      return 'Network error. Please try again.';
    } finally {
      _isSaving.value = false;
    }
  }

  /// Commits every currently-loaded placement in one batch via
  /// `POST /locations/{id}/placements/batch` with `quantityMode: "set"`
  /// (guide §5.4) — the Overview "Save all" action. Returns an error message
  /// on failure, or `null` on success (after refreshing the product list).
  Future<String?> saveAllPlacements() async {
    if (_placements.isEmpty) return 'No products to save.';

    _isSaving.value = true;

    try {
      final response = await _api.post(
        '$_base/placements/batch',
        headers: AuthService.instance.authHeaders,
        body: {
          'idempotencyKey':
              'saveall-$locationId-${DateTime.now().millisecondsSinceEpoch}',
          'items': [
            for (final p in _placements)
              {
                'productId': p.productId,
                'quantity': p.quantity,
                'quantityMode': 'set',
                'isPrimary': p.isPrimary,
                'clientItemKey': p.productId,
              },
          ],
        },
      );

      if (response.isSuccess) {
        final json = response.json;
        if (json['success'] == true) {
          await fetchPlacements();
          return null;
        }
        return 'Unexpected response format.';
      }

      if (response.statusCode == 422) {
        return 'Please check the products and try again.';
      }

      return 'Failed to save products: ${response.statusCode}';
    } catch (e) {
      log('Placements save-all error: $e');
      return 'Network error. Please try again.';
    } finally {
      _isSaving.value = false;
    }
  }

  /// Edits a product's placement in this bin (quantity + primary flag) via
  /// `POST /locations/{id}/placements/batch` with `quantityMode: "set"`
  /// (guide §5.4). Returns an error message on failure, or `null` on success
  /// (after refreshing the product list).
  Future<String?> savePlacement({
    required String productId,
    required int quantity,
    required bool isPrimary,
  }) async {
    _isSaving.value = true;

    try {
      final response = await _api.post(
        '$_base/placements/batch',
        headers: AuthService.instance.authHeaders,
        body: {
          'idempotencyKey':
              'edit-$locationId-$productId-${DateTime.now().millisecondsSinceEpoch}',
          'items': [
            {
              'productId': productId,
              'quantity': quantity,
              'quantityMode': 'set',
              'isPrimary': isPrimary,
              'clientItemKey': productId,
            },
          ],
        },
      );

      if (response.isSuccess) {
        final json = response.json;
        if (json['success'] == true) {
          await fetchPlacements();
          return null;
        }
        return 'Unexpected response format.';
      }

      if (response.statusCode == 422) {
        return 'Please check the quantity and try again.';
      }

      return 'Failed to save product: ${response.statusCode}';
    } catch (e) {
      log('Placement save error: $e');
      return 'Network error. Please try again.';
    } finally {
      _isSaving.value = false;
    }
  }

  /// Adds quantity to a product's placement in this bin via
  /// `POST /api/v1/seller/inventory/products/{productId}/placements` with
  /// `quantityMode: "increment"`. The API only supports increment (no
  /// decrement), so [addQuantity] is the amount to add on top of the current
  /// stock. Returns an error message on failure, or `null` on success (after
  /// refreshing the product list).
  Future<String?> incrementPlacement({
    required String productId,
    required int addQuantity,
    required bool isPrimary,
  }) async {
    if (productId.isEmpty) return 'Missing product reference.';
    if (addQuantity <= 0) return 'Enter a quantity of 1 or more to add.';

    _isSaving.value = true;

    try {
      final response = await _api.post(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/products/'
        '${Uri.encodeComponent(productId)}/placements',
        headers: AuthService.instance.authHeaders,
        body: {
          'locationId': locationId,
          'quantity': addQuantity,
          'quantityMode': 'increment',
          'isPrimary': isPrimary,
        },
      );

      if (response.isSuccess) {
        final json = response.json;
        if (json['success'] == true) {
          await fetchPlacements();
          return null;
        }
        return 'Unexpected response format.';
      }

      if (response.statusCode == 404) {
        return 'Product is no longer assigned to this SKU.';
      }
      if (response.statusCode == 403) {
        return 'Warehouse is only available for managed sellers.';
      }
      if (response.statusCode == 422) {
        return 'Please check the quantity and try again.';
      }

      return 'Failed to update product: ${response.statusCode}';
    } catch (e) {
      log('Placement increment error: $e');
      return 'Network error. Please try again.';
    } finally {
      _isSaving.value = false;
    }
  }

  /// Removes one product-from-bin link via
  /// `DELETE /api/v1/seller/inventory/placements/{placementId}` (guide §5.4).
  /// Returns an error message on failure, or `null` on success (after
  /// refreshing the product list).
  Future<String?> deletePlacement(String placementId) async {
    if (placementId.isEmpty) return 'Missing placement reference.';

    _isSaving.value = true;

    try {
      final response = await _api.delete(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/placements/'
        '${Uri.encodeComponent(placementId)}',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final json = response.json;
        if (json['success'] == true) {
          await fetchPlacements();
          return null;
        }
        return 'Unexpected response format.';
      }

      if (response.statusCode == 404) {
        return 'Product is no longer assigned to this SKU.';
      }
      if (response.statusCode == 403) {
        return 'Warehouse is only available for managed sellers.';
      }

      return 'Failed to remove product: ${response.statusCode}';
    } catch (e) {
      log('Placement delete error: $e');
      return 'Network error. Please try again.';
    } finally {
      _isSaving.value = false;
    }
  }

  /// Searches SKUs to move a placement into, via
  /// `GET /api/v1/seller/inventory/locations/suggest?q={q}`. Returns the
  /// matches (empty on blank query / error) — used by the move-placement
  /// dialog without touching any shared suggestion state.
  Future<List<LocationSuggestion>> searchLocations(String q) async {
    final query = q.trim();
    if (query.isEmpty) return const [];

    try {
      final uri = Uri.parse(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/locations/suggest',
      ).replace(queryParameters: {'q': query});

      final response = await _api.get(
        uri.toString(),
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final items = (body['data']['items'] as List?) ?? const [];
          return items
              .whereType<Map<String, dynamic>>()
              .map(LocationSuggestion.fromJson)
              .toList();
        }
      }
      return const [];
    } catch (e) {
      log('Location search (move) error: $e');
      return const [];
    }
  }

  /// Moves one product-from-bin link into another SKU via
  /// `POST /api/v1/seller/inventory/placements/{placementId}/move` with
  /// `{ "targetLocationId": ... }`. Returns an error message on failure, or
  /// `null` on success (after refreshing the product list).
  Future<String?> movePlacement({
    required String placementId,
    required String targetLocationId,
  }) async {
    if (placementId.isEmpty) return 'Missing placement reference.';
    if (targetLocationId.isEmpty) return 'Please choose a target SKU.';

    _isSaving.value = true;

    try {
      final response = await _api.post(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/placements/'
        '${Uri.encodeComponent(placementId)}/move',
        headers: AuthService.instance.authHeaders,
        body: {'targetLocationId': targetLocationId},
      );

      if (response.isSuccess) {
        final json = response.json;
        if (json['success'] == true) {
          // Optimistically drop the moved placement so the list reflects the
          // move immediately, then reconcile with the server.
          _placements.removeWhere((p) => p.placementId == placementId);
          await fetchPlacements();
          // Guard against a stale read-after-write that still returns the
          // just-moved row — keep it dropped until the next clean fetch.
          _placements.removeWhere((p) => p.placementId == placementId);
          return null;
        }
        return 'Unexpected response format.';
      }

      // Prefer what the API says — e.g. a 409 CONFLICT carries
      // "Product is already assigned to the target SKU", which is far more
      // useful than any message we could guess from the status code.
      final apiMessage = _apiErrorMessage(response);
      if (apiMessage != null) return apiMessage;

      if (response.statusCode == 404) {
        return 'This product is no longer at this SKU.';
      }
      if (response.statusCode == 403) {
        return 'Warehouse is only available for managed sellers.';
      }
      if (response.statusCode == 409) {
        return 'This product is already assigned to that SKU.';
      }
      if (response.statusCode == 422) {
        return 'Please choose a different target SKU.';
      }

      return 'Failed to move product: ${response.statusCode}';
    } catch (e) {
      log('Placement move error: $e');
      return 'Network error. Please try again.';
    } finally {
      _isSaving.value = false;
    }
  }

  /// Pulls `error.message` out of a failed response, or null when the payload
  /// doesn't carry one.
  String? _apiErrorMessage(ApiResponse response) {
    try {
      final error = response.json['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  // ---------- Product discrepancy issue (quick-view report) ----------

  /// Uploads one discrepancy image to
  /// `POST /api/v1/seller/product-request-issue-images` (multipart `file`,
  /// JPEG/PNG/WebP ≤ 5 MB) and returns the resulting `s3Key`, or null on
  /// failure. Shared upload endpoint with the other issue / pending flows.
  Future<String?> uploadIssueImage(String filePath) async {
    try {
      final response = await _api.uploadFile(
        '${EnvConfig.baseUrl}/api/v1/seller/product-request-issue-images',
        fieldName: 'file',
        filePath: filePath,
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        final data = body['data'];
        if (body['success'] == true && data is Map) {
          final key = data['s3Key'] as String?;
          if (key != null && key.isNotEmpty) return key;
        }
      }
      return null;
    } catch (e) {
      log('Issue image upload error: $e');
      return null;
    }
  }

  /// Fetches the reported discrepancy for a product+bin via
  /// `GET /api/v1/seller/inventory/products/{productId}/issue?locationId={id}`.
  /// The payload is `data.issue` ({ description, imageUrls, tags, status, … }).
  /// Returns a [ProductRequestIssue] (description → message), or null when
  /// there is no issue.
  Future<ProductRequestIssue?> fetchProductIssue({
    required String productId,
    String? locationId,
  }) async {
    if (productId.isEmpty) return null;

    final base = '${EnvConfig.baseUrl}/api/v1/seller/inventory/products/'
        '${Uri.encodeComponent(productId)}/issue';
    final uri = (locationId != null && locationId.isNotEmpty)
        ? Uri.parse(base).replace(queryParameters: {'locationId': locationId})
        : Uri.parse(base);

    try {
      final response = await _api.get(
        uri.toString(),
        headers: AuthService.instance.authHeaders,
      );

      log('[product-issue] GET $uri -> ${response.statusCode} ${response.body}');

      if (!response.isSuccess) return null;
      final body = response.json;
      final data = body['data'];
      if (body['success'] == true &&
          data is Map<String, dynamic> &&
          data['issue'] is Map<String, dynamic>) {
        final issue = data['issue'] as Map<String, dynamic>;
        final images = (issue['imageUrls'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        return ProductRequestIssue(
          message:
              (issue['description'] ?? issue['message']) as String? ?? '',
          imageUrls: images,
        );
      }
      return null;
    } catch (e) {
      log('[product-issue] fetch error: $e');
      return null;
    }
  }

  /// Reports / updates the discrepancy for a product via
  /// `PATCH /api/v1/seller/inventory/products/{productId}/issue` with
  /// `{ message, imageKeys, locationId }`. [imageKeys] are the `s3Key`s of any
  /// newly-uploaded images. Returns an error message on failure, or `null` on
  /// success.
  Future<String?> submitProductIssue({
    required String productId,
    required String message,
    List<String> imageKeys = const [],
    String? locationId,
  }) async {
    if (productId.isEmpty) return 'Missing product reference.';

    _isSaving.value = true;

    try {
      final body = <String, dynamic>{
        'message': message,
        if (imageKeys.isNotEmpty) 'imageKeys': imageKeys,
        if (locationId != null && locationId.isNotEmpty)
          'locationId': locationId,
      };

      final response = await _api.patch(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/products/'
        '${Uri.encodeComponent(productId)}/issue',
        headers: AuthService.instance.authHeaders,
        body: body,
      );

      log('[product-issue] PATCH status=${response.statusCode} body=${response.body}');

      if (response.isSuccess) {
        final json = response.json;
        if (json['success'] == true) return null;
        return 'Unexpected response format.';
      }

      if (response.statusCode == 403) {
        return 'Warehouse is only available for managed sellers.';
      }
      if (response.statusCode == 422) {
        return 'Please check the report and try again.';
      }
      return 'Failed to submit report: ${response.statusCode}';
    } catch (e) {
      log('[product-issue] submit error: $e');
      return 'Network error. Please try again.';
    } finally {
      _isSaving.value = false;
    }
  }
}
