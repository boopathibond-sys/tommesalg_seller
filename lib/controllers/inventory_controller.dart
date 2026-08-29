import 'dart:developer';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../models/inventory_location.dart';
import '../models/inventory_location_detail.dart';
import '../models/inventory_search.dart';
import '../models/location_suggestion.dart';
import '../models/inventory_stats.dart';
import '../models/inventory_tag.dart';
import '../models/product_request_model.dart';
import '../core/localization/translation_keys.dart';

/// Drives the Warehouse / Stock tab's data.
///
/// Today this only wraps `GET /api/v1/seller/inventory/stats` (guide §5.1) to
/// power the Overview cards; extend it with locations / events / search as
/// those sections get wired.
class InventoryController extends GetxController {
  final _api = ApiClient.instance;

  // ---------- Stats state ----------

  final RxBool _isLoadingStats = false.obs;
  bool get isLoadingStats => _isLoadingStats.value;

  final RxnString _statsError = RxnString();
  String? get statsError => _statsError.value;

  final Rxn<InventoryStats> _stats = Rxn<InventoryStats>();
  InventoryStats? get stats => _stats.value;

  // ---------- Locations (SKUs) state ----------

  final RxBool _isLoadingLocations = false.obs;
  bool get isLoadingLocations => _isLoadingLocations.value;

  final RxnString _locationsError = RxnString();
  String? get locationsError => _locationsError.value;

  final RxList<InventoryLocation> _locations = <InventoryLocation>[].obs;
  List<InventoryLocation> get locations => _locations;

  /// Whether the SKU list is filtered to `isActive=true`. Drives the
  /// "Active only / All" toggle and the query param on [fetchLocations].
  final RxBool _activeOnly = true.obs;
  bool get activeOnly => _activeOnly.value;

  // ---------- Resolve-by-code state ----------

  /// True while [fetchLocationByCode] is in flight (Overview SKU search).
  final RxBool _isResolvingCode = false.obs;
  bool get isResolvingCode => _isResolvingCode.value;

  final RxnString _byCodeError = RxnString();
  String? get byCodeError => _byCodeError.value;

  /// The SKU resolved by the last [fetchLocationByCode], or null if none /
  /// not found. Drives the Overview "assign products" card.
  final Rxn<InventoryLocationDetail> _byCode = Rxn<InventoryLocationDetail>();
  InventoryLocationDetail? get byCodeResult => _byCode.value;

  // ---------- Search state ----------

  /// True while [searchByUpc] / [searchByTag] is in flight.
  final RxBool _isSearching = false.obs;
  bool get isSearching => _isSearching.value;

  final RxnString _searchError = RxnString();
  String? get searchError => _searchError.value;

  /// The most recent search result, or null before any search / after a clear.
  final Rxn<InventorySearchResult> _searchResult = Rxn<InventorySearchResult>();
  InventorySearchResult? get searchResult => _searchResult.value;

  /// True once a search has run, so the UI can tell "no results" apart from
  /// "haven't searched yet".
  final RxBool _hasSearched = false.obs;
  bool get hasSearched => _hasSearched.value;

  // ---------- Tags state ----------

  final RxBool _isLoadingTags = false.obs;
  bool get isLoadingTags => _isLoadingTags.value;

  final RxnString _tagsError = RxnString();
  String? get tagsError => _tagsError.value;

  final RxList<InventoryTag> _tags = <InventoryTag>[].obs;
  List<InventoryTag> get tags => _tags;

  /// True while a new tag is being created via [createTag].
  final RxBool _isCreatingTag = false.obs;
  bool get isCreatingTag => _isCreatingTag.value;

  /// True while a new SKU is being created via [createLocation].
  final RxBool _isCreatingLocation = false.obs;
  bool get isCreatingLocation => _isCreatingLocation.value;

  // ---------- Lifecycle ----------

  @override
  void onInit() {
    super.onInit();
    fetchStats();
  }

  // ---------- Intents ----------

  /// Loads aggregate warehouse counts. Managed-seller only — independent
  /// sellers get 403 (`AUTH_FORBIDDEN`), surfaced as a friendly message.
  Future<bool> fetchStats() async {
    _isLoadingStats.value = true;
    _statsError.value = null;

    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/stats',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          _stats.value = InventoryStats.fromJson(
            body['data'] as Map<String, dynamic>,
          );
          return true;
        }
        _statsError.value = 'Unexpected response format.';
        return false;
      }

      if (response.statusCode == 403) {
        _statsError.value = 'Warehouse is only available for managed sellers.';
        return false;
      }

      _statsError.value = 'Failed to load stats: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Inventory stats fetch error: $e');
      _statsError.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoadingStats.value = false;
    }
  }

  /// Loads warehouse SKUs from
  /// `GET /api/v1/seller/inventory/locations?limit=25[&isActive=true]`
  /// (guide §5.2). Pass [activeOnly] to flip the filter; when omitted the
  /// current [activeOnly] value is reused.
  Future<bool> fetchLocations({bool? activeOnly}) async {
    if (activeOnly != null) _activeOnly.value = activeOnly;

    _isLoadingLocations.value = true;
    _locationsError.value = null;

    try {
      final query = <String, String>{'limit': '25'};
      if (_activeOnly.value) query['isActive'] = 'true';

      final uri = Uri.parse(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/locations',
      ).replace(queryParameters: query);

      final response = await _api.get(
        uri.toString(),
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final data = body['data'] as Map<String, dynamic>;
          final items = (data['items'] as List?) ?? const [];
          _locations.value = items
              .whereType<Map<String, dynamic>>()
              .map(InventoryLocation.fromJson)
              .toList();
          return true;
        }
        _locationsError.value = 'Unexpected response format.';
        return false;
      }

      if (response.statusCode == 403) {
        _locationsError.value =
            'Warehouse is only available for managed sellers.';
        return false;
      }

      _locationsError.value = 'Failed to load SKUs: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Inventory locations fetch error: $e');
      _locationsError.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoadingLocations.value = false;
    }
  }

  /// Resolves a single SKU by its label code via
  /// `GET /api/v1/seller/inventory/locations/by-code/{code}` (guide §5.2).
  /// Returns the full bin record (location + tags + `placementCount`) on an
  /// exact match, or null when the code is blank / not found / errors — in
  /// which case [byCodeError] carries a friendly message.
  Future<InventoryLocationDetail?> fetchLocationByCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      clearByCode();
      return null;
    }

    _isResolvingCode.value = true;
    _byCodeError.value = null;

    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/locations/by-code/'
        '${Uri.encodeComponent(trimmed)}',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final detail = InventoryLocationDetail.fromJson(
            body['data'] as Map<String, dynamic>,
          );
          _byCode.value = detail;
          return detail;
        }
        _byCodeError.value = 'Unexpected response format.';
        return null;
      }

      _byCode.value = null;
      if (response.statusCode == 404) {
        _byCodeError.value = 'No SKU found for "$trimmed".';
        return null;
      }
      if (response.statusCode == 403) {
        _byCodeError.value = 'Warehouse is only available for managed sellers.';
        return null;
      }

      _byCodeError.value = 'Failed to resolve SKU: ${response.statusCode}';
      return null;
    } catch (e) {
      log('Inventory by-code fetch error: $e');
      _byCodeError.value = 'Network error. Please try again.';
      return null;
    } finally {
      _isResolvingCode.value = false;
    }
  }

  /// Clears the resolved SKU + any error (Overview search reset).
  void clearByCode() {
    _byCode.value = null;
    _byCodeError.value = null;
  }

  // ---------- Location suggestions (Overview SKU search) ----------

  final RxBool _isSuggesting = false.obs;
  bool get isSuggesting => _isSuggesting.value;

  final RxnString _suggestError = RxnString();
  String? get suggestError => _suggestError.value;

  final RxList<LocationSuggestion> _suggestions = <LocationSuggestion>[].obs;
  List<LocationSuggestion> get suggestions => _suggestions;

  /// True once a suggest query has run (to distinguish "no matches" from idle).
  final RxBool _hasSuggested = false.obs;
  bool get hasSuggested => _hasSuggested.value;

  /// Live SKU search via
  /// `GET /api/v1/seller/inventory/locations/suggest?q={q}`. A blank query
  /// just clears the current suggestions.
  Future<void> suggestLocations(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      clearSuggestions();
      return;
    }

    _isSuggesting.value = true;
    _suggestError.value = null;
    _hasSuggested.value = true;

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
          _suggestions.value = items
              .whereType<Map<String, dynamic>>()
              .map(LocationSuggestion.fromJson)
              .toList();
          return;
        }
        _suggestions.clear();
        _suggestError.value = 'Unexpected response format.';
        return;
      }

      _suggestions.clear();
      if (response.statusCode == 403) {
        _suggestError.value = 'Warehouse is only available for managed sellers.';
        return;
      }
      _suggestError.value = 'Search failed: ${response.statusCode}';
    } catch (e) {
      log('Location suggest error: $e');
      _suggestions.clear();
      _suggestError.value = 'Network error. Please try again.';
    } finally {
      _isSuggesting.value = false;
    }
  }

  /// Resets the suggestion list + error.
  void clearSuggestions() {
    _suggestions.clear();
    _suggestError.value = null;
    _hasSuggested.value = false;
  }

  // ---------- Tag suggestions (SKU tag search) ----------

  final RxBool _isSuggestingTags = false.obs;
  bool get isSuggestingTags => _isSuggestingTags.value;

  final RxList<InventoryTag> _tagSuggestions = <InventoryTag>[].obs;
  List<InventoryTag> get tagSuggestions => _tagSuggestions;

  /// True once a tag-suggest query has run.
  final RxBool _hasSuggestedTags = false.obs;
  bool get hasSuggestedTags => _hasSuggestedTags.value;

  /// Live tag search via
  /// `GET /api/v1/seller/inventory/location-tags/suggest?q={q}`. A blank query
  /// clears the current suggestions.
  Future<void> suggestTags(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      clearTagSuggestions();
      return;
    }

    _isSuggestingTags.value = true;
    _hasSuggestedTags.value = true;

    try {
      final uri = Uri.parse(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/location-tags/suggest',
      ).replace(queryParameters: {'q': query});

      final response = await _api.get(
        uri.toString(),
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final items = (body['data']['items'] as List?) ?? const [];
          _tagSuggestions.value = items
              .whereType<Map<String, dynamic>>()
              .map(InventoryTag.fromJson)
              .toList();
          return;
        }
      }
      _tagSuggestions.clear();
    } catch (e) {
      log('Tag suggest error: $e');
      _tagSuggestions.clear();
    } finally {
      _isSuggestingTags.value = false;
    }
  }

  /// Resets the tag suggestion list.
  void clearTagSuggestions() {
    _tagSuggestions.clear();
    _hasSuggestedTags.value = false;
  }

  /// Searches the warehouse by product UPC via
  /// `GET /api/v1/seller/inventory/search/by-upc?upc={upc}`. The result lands
  /// in [searchResult]; a blank query just clears the current result.
  Future<void> searchByUpc(String upc) async {
    final trimmed = upc.trim();
    if (trimmed.isEmpty) {
      clearSearch();
      return;
    }

    final uri = Uri.parse(
      '${EnvConfig.baseUrl}/api/v1/seller/inventory/search/by-upc',
    ).replace(queryParameters: {'upc': trimmed});

    await _runSearch(uri);
  }

  /// Searches the warehouse by tag slug via
  /// `GET /api/v1/seller/inventory/search/by-tag?tagSlug={slug}&includeProducts=true`.
  Future<void> searchByTag(String tagSlug) async {
    final trimmed = tagSlug.trim();
    if (trimmed.isEmpty) {
      clearSearch();
      return;
    }

    final uri = Uri.parse(
      '${EnvConfig.baseUrl}/api/v1/seller/inventory/search/by-tag',
    ).replace(queryParameters: {
      'tagSlug': trimmed,
      'includeProducts': 'true',
    });

    await _runSearch(uri);
  }

  /// Shared request/parse path for both search endpoints.
  Future<void> _runSearch(Uri uri) async {
    _isSearching.value = true;
    _searchError.value = null;
    _hasSearched.value = true;

    try {
      final response = await _api.get(
        uri.toString(),
        headers: AuthService.instance.authHeaders,
      );

      // Log which search API was hit and what it returned.
      log('[inventory-search] GET ${uri.toString()}');
      log('[inventory-search] status=${response.statusCode} body=${response.body}');

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          _searchResult.value = InventorySearchResult.fromJson(
            body['data'] as Map<String, dynamic>,
          );
          return;
        }
        _searchResult.value = null;
        _searchError.value = 'Unexpected response format.';
        return;
      }

      _searchResult.value = null;
      if (response.statusCode == 404) {
        // Treat "not found" as an empty result, not an error.
        _searchResult.value = null;
        return;
      }
      if (response.statusCode == 403) {
        _searchError.value = 'Warehouse is only available for managed sellers.';
        return;
      }
      _searchError.value = 'Search failed: ${response.statusCode}';
    } catch (e) {
      log('Inventory search error: $e');
      _searchResult.value = null;
      _searchError.value = 'Network error. Please try again.';
    } finally {
      _isSearching.value = false;
    }
  }

  /// Loads full product info for a search-result quick view via
  /// `GET /api/v1/seller/products/{productId}/preview`.
  ///
  /// Search only carries `{ id, name, upc }`, so the quick view fetches the
  /// richer fields (brand, images, prices, colour, sizes, description) here.
  /// Returns a best-effort [ProductRequestProduct], or `null` on failure — the
  /// quick view then falls back to the search hit's own fields.
  Future<ProductRequestProduct?> fetchQuickViewProduct(String productId) async {
    if (productId.isEmpty) return null;

    final url = '${EnvConfig.baseUrl}/api/v1/seller/products/'
        '${Uri.encodeComponent(productId)}/preview';

    try {
      final response = await _api.get(
        url,
        headers: AuthService.instance.authHeaders,
      );

      log('[quick-view] GET $url');
      log('[quick-view] status=${response.statusCode} body=${response.body}');

      if (!response.isSuccess) return null;

      final body = response.json;
      final data = body['data'];
      if (body['success'] == true && data is Map<String, dynamic>) {
        // The preview payload may carry the product directly or nested under
        // `product` — handle both shapes.
        final product =
            (data['product'] as Map?)?.cast<String, dynamic>() ?? data;
        return ProductRequestProduct.fromJson(product);
      }
      return null;
    } catch (e) {
      log('[quick-view] product fetch error: $e');
      return null;
    }
  }

  /// Fetches any reported discrepancy for a product via
  /// `GET /api/v1/seller/inventory/products/{productId}/issue` (optionally
  /// scoped to a `locationId`). Returns a [ProductRequestIssue] (description →
  /// message + image urls), or null when there is no issue. Used to prefill the
  /// search quick view's report form.
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
        final images =
            (issue['imageUrls'] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
        return ProductRequestIssue(
          message: (issue['description'] ?? issue['message']) as String? ?? '',
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
    }
  }

  /// Resets the search result + error (e.g. when clearing the query).
  void clearSearch() {
    _searchResult.value = null;
    _searchError.value = null;
    _hasSearched.value = false;
  }

  /// Uploads one product-request image to
  /// `POST /api/v1/seller/product-request-issue-images` (multipart `file`,
  /// JPEG/PNG/WebP ≤ 5 MB) and returns the resulting `s3Key`, or null on
  /// failure. Shared endpoint with stream issue photos.
  Future<String?> uploadProductRequestImage(String filePath) async {
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
          final s3Key = data['s3Key'] as String?;
          if (s3Key != null && s3Key.isNotEmpty) return s3Key;
        }
      }
      return null;
    } catch (e) {
      log('Product-request image upload error: $e');
      return null;
    }
  }

  /// Looks up a UPC in the catalog via
  /// `GET /api/v1/seller/inventory/search/by-upc?upc={upc}` for the Assign
  /// flow. Returns [UpcLookupStatus.found] with the first item's product id
  /// when the catalog has a match, [UpcLookupStatus.notFound] when there are no
  /// items / the API reports `NOT_FOUND` (the caller then opens the manual
  /// add sheet), or [UpcLookupStatus.error] with a friendly message otherwise.
  Future<UpcLookupResult> lookupUpcForAssign(String upc) async {
    final trimmed = upc.trim();
    if (trimmed.isEmpty) {
      return const UpcLookupResult(UpcLookupStatus.notFound);
    }

    try {
      final uri = Uri.parse(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/search/by-upc',
      ).replace(queryParameters: {'upc': trimmed});

      final response = await _api.get(
        uri.toString(),
        headers: AuthService.instance.authHeaders,
      );

      final body = response.json;

      if (response.isSuccess && body['success'] == true && body['data'] is Map) {
        final result = InventorySearchResult.fromJson(
          body['data'] as Map<String, dynamic>,
        );
        // Take the first item that carries a product.
        for (final item in result.items) {
          final product = item.product;
          if (product != null && product.id.isNotEmpty) {
            return UpcLookupResult(
              UpcLookupStatus.found,
              productId: product.id,
              productName: product.name,
            );
          }
        }
        // No products in the result → fall through to manual add.
        return const UpcLookupResult(UpcLookupStatus.notFound);
      }

      final errorCode = (body['error'] as Map?)?['code'];
      if (response.statusCode == 404 || errorCode == 'NOT_FOUND') {
        return const UpcLookupResult(UpcLookupStatus.notFound);
      }
      if (response.statusCode == 403) {
        return UpcLookupResult(
          UpcLookupStatus.error,
          message: TKeys.svcManagedSellersOnly.tr,
        );
      }
      return UpcLookupResult(
        UpcLookupStatus.error,
        message: TKeys.svcLookupFailed
            .trParams({'code': '${response.statusCode}'}),
      );
    } catch (e) {
      log('UPC lookup error: $e');
      return UpcLookupResult(
        UpcLookupStatus.error,
        message: TKeys.svcNetworkError.tr,
      );
    }
  }

  /// Adds (or increments) a catalog product placement at a SKU via
  /// `POST /api/v1/seller/inventory/locations/{locationId}/placements/batch`.
  /// Used by the Assign flow once a UPC resolves to a known product. Returns
  /// null on success, or a friendly error message on failure.
  Future<String?> addProductPlacement({
    required String locationId,
    required String productId,
    int quantity = 1,
    bool isPrimary = true,
  }) async {
    try {
      final response = await _api.post(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/locations/'
        '${Uri.encodeComponent(locationId)}/placements/batch',
        headers: AuthService.instance.authHeaders,
        body: {
          'items': [
            {
              'productId': productId,
              'quantity': quantity,
              'quantityMode': 'increment',
              'isPrimary': isPrimary,
            }
          ],
        },
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true) return null;
        return 'Unexpected response format.';
      }

      if (response.statusCode == 403) {
        return 'Warehouse is only available for managed sellers.';
      }
      if (response.statusCode == 404) {
        return 'SKU not found.';
      }
      if (response.statusCode == 422) {
        return 'Please check the product details and try again.';
      }
      return 'Failed to add product: ${response.statusCode}';
    } catch (e) {
      log('Add placement error: $e');
      return 'Network error. Please try again.';
    }
  }

  /// Requests an unknown product be added to a SKU via
  /// `POST /api/v1/seller/inventory/locations/{locationId}/unknown-product`.
  /// [imageS3Keys] are keys from [uploadProductRequestImage]. Returns null on
  /// success, or a friendly error message on failure.
  Future<String?> addUnknownProductToLocation({
    required String locationId,
    required String upc,
    required String name,
    List<String> imageS3Keys = const [],
    int quantityRequested = 1,
  }) async {
    try {
      final response = await _api.post(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/locations/'
        '${Uri.encodeComponent(locationId)}/unknown-product',
        headers: AuthService.instance.authHeaders,
        body: {
          'upc': upc.trim(),

          'quantityRequested': quantityRequested,
          'requestedImageUrls': imageS3Keys,
          'requestedName': name.trim(),
        },
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true) return null;
        return 'Unexpected response format.';
      }

      if (response.statusCode == 403) {
        return 'Warehouse is only available for managed sellers.';
      }
      if (response.statusCode == 404) {
        return 'SKU not found.';
      }
      if (response.statusCode == 422) {
        return 'Please check the product details and try again.';
      }
      return 'Failed to add product: ${response.statusCode}';
    } catch (e) {
      log('Add unknown product error: $e');
      return 'Network error. Please try again.';
    }
  }

  /// Loads the SKU tag dictionary from
  /// `GET /api/v1/seller/inventory/location-tags` (guide §5.5). Called when the
  /// New SKU dialog opens so the user can pick existing tags.
  Future<bool> fetchTags() async {
    _isLoadingTags.value = true;
    _tagsError.value = null;

    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/location-tags',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final data = body['data'] as Map<String, dynamic>;
          final items = (data['items'] as List?) ?? const [];
          _tags.value = items
              .whereType<Map<String, dynamic>>()
              .map(InventoryTag.fromJson)
              .toList();
          return true;
        }
        _tagsError.value = 'Unexpected response format.';
        return false;
      }

      if (response.statusCode == 403) {
        _tagsError.value = 'Warehouse is only available for managed sellers.';
        return false;
      }

      _tagsError.value = 'Failed to load tags: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Inventory tags fetch error: $e');
      _tagsError.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoadingTags.value = false;
    }
  }

  /// Creates a new SKU tag via
  /// `POST /api/v1/seller/inventory/location-tags` with `{ slug, label }`
  /// (guide §5.5). On success the canonical tag list is re-fetched and the
  /// newly created tag (matched by [slug]) is returned so the caller can
  /// auto-select it.
  ///
  /// The list is reloaded rather than trusting the POST response body: the
  /// create response can wrap the tag differently from the GET `items[]`
  /// shape, which previously yielded a blank, unlabeled chip until the next
  /// reload.
  Future<InventoryTag?> createTag({
    required String slug,
    required String label,
  }) async {
    _isCreatingTag.value = true;
    _tagsError.value = null;

    try {
      final response = await _api.post(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/location-tags',
        headers: AuthService.instance.authHeaders,
        body: {'slug': slug, 'label': label},
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true) {
          // Reload so the chip renders from the same shape as the list.
          await fetchTags();

          // Select by slug — it's unique and we just sent it.
          for (final tag in _tags) {
            if (tag.slug == slug) return tag;
          }

          // Fallback: parse the tag straight from the create response in case
          // the reload didn't surface it (e.g. eventual consistency).
          final fromResponse = _tagFromCreateResponse(body['data']);
          if (fromResponse != null && fromResponse.id.isNotEmpty) {
            if (_tags.indexWhere((t) => t.id == fromResponse.id) < 0) {
              _tags.add(fromResponse);
            }
            return fromResponse;
          }
          return null;
        }
        _tagsError.value = 'Unexpected response format.';
        return null;
      }

      if (response.statusCode == 409) {
        _tagsError.value = 'A tag with that slug already exists.';
        return null;
      }

      _tagsError.value = 'Failed to create tag: ${response.statusCode}';
      return null;
    } catch (e) {
      log('Inventory tag create error: $e');
      _tagsError.value = 'Network error. Please try again.';
      return null;
    } finally {
      _isCreatingTag.value = false;
    }
  }

  /// Extracts a tag from a `POST /location-tags` response `data` payload,
  /// tolerating the tag being either at the root or nested under a common
  /// wrapper key (`item` / `tag` / `locationTag`).
  InventoryTag? _tagFromCreateResponse(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    if (data['id'] != null || data['slug'] != null) {
      return InventoryTag.fromJson(data);
    }
    for (final key in const ['item', 'tag', 'locationTag']) {
      final nested = data[key];
      if (nested is Map<String, dynamic>) return InventoryTag.fromJson(nested);
    }
    return null;
  }

  /// Creates a new warehouse SKU via
  /// `POST /api/v1/seller/inventory/locations` (guide §5.2). On success the
  /// SKU list and stats are refreshed so the new bin shows immediately.
  /// Returns an error message on failure, or `null` on success.
  Future<String?> createLocation({
    required String code,
    String? name,
    String? zone,
    String? aisle,
    String? shelf,
    int sortOrder = 0,
    String? notes,
    List<String> tagIds = const [],
  }) async {
    _isCreatingLocation.value = true;

    String? orNull(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();

    try {
      final response = await _api.post(
        '${EnvConfig.baseUrl}/api/v1/seller/inventory/locations',
        headers: AuthService.instance.authHeaders,
        body: {
          'code': code.trim(),
          'name': orNull(name),
          'zone': orNull(zone),
          'aisle': orNull(aisle),
          'shelf': orNull(shelf),
          'sortOrder': sortOrder,
          'notes': orNull(notes),
          'tagIds': tagIds,
        },
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true) {
          // Refresh so the new SKU + counts appear without a manual reload.
          await fetchLocations();
          fetchStats();
          return null;
        }
        return 'Unexpected response format.';
      }

      if (response.statusCode == 409) {
        return 'A SKU with that code already exists.';
      }
      if (response.statusCode == 403) {
        return 'Warehouse is only available for managed sellers.';
      }
      if (response.statusCode == 422) {
        return 'Please check the SKU details and try again.';
      }

      return 'Failed to create SKU: ${response.statusCode}';
    } catch (e) {
      log('Inventory location create error: $e');
      return 'Network error. Please try again.';
    } finally {
      _isCreatingLocation.value = false;
    }
  }
}

/// Outcome of [InventoryController.lookupUpcForAssign].
enum UpcLookupStatus { found, notFound, error }

/// Result of a UPC catalog lookup in the Assign flow. On [UpcLookupStatus.found]
/// the [productId] (and [productName]) are set; on [UpcLookupStatus.error] the
/// [message] carries a friendly description.
class UpcLookupResult {
  const UpcLookupResult(
    this.status, {
    this.productId,
    this.productName,
    this.message,
  });

  final UpcLookupStatus status;
  final String? productId;
  final String? productName;
  final String? message;
}
