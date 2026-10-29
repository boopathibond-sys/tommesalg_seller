import 'dart:async';
import 'dart:developer';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../core/services/shipping_options_service.dart';
import '../models/product_edit_log.dart';
import '../models/seller_product.dart';
import '../models/seller_product_detail.dart';
import '../models/seller_product_preview.dart';

/// Drives the "Mine produkter" tab — the web `/seller/products` page's list
/// from `GET /api/v1/seller/products` (paged:
/// `{ items, page, pageSize, total, availableSizes }`): every product the
/// seller scanned into their own stream requests, across all streams, newest
/// first and each product once. Products are no longer assigned, so an edit
/// only goes through while the product sits on a `draft` request (the PATCH
/// answers `403` otherwise).
///
/// Search, status and size are filtered on the server: any change resets to
/// page 1 and refetches, and a response for an older set of filters is
/// dropped. [loadMore] pulls the next page while the server has more.
class SellerProductsController extends GetxController {
  final _api = ApiClient.instance;

  static const int _pageSize = 20;

  /// How long typing in the search box settles before it refetches — keeps
  /// the list within the endpoint's 60 requests/minute.
  static const Duration _searchDebounce = Duration(milliseconds: 350);

  /// Status values the filter menu offers. `ALL` is the "no filter" sentinel.
  static const List<String> statusOptions = [
    'ALL',
    'AVAILABLE',
    'RESERVED',
    'SOLD',
  ];

  final RxList<SellerProduct> _products = <SellerProduct>[].obs;
  List<SellerProduct> get products => _products;

  final RxBool _isLoading = false.obs;
  bool get isLoading => _isLoading.value;

  final RxBool _isLoadingMore = false.obs;
  bool get isLoadingMore => _isLoadingMore.value;

  final RxnString _error = RxnString();
  String? get error => _error.value;

  final RxString _query = ''.obs;
  String get query => _query.value;

  final RxString _statusFilter = 'ALL'.obs;
  String get statusFilter => _statusFilter.value;

  /// Size bucket filter; empty = all sizes.
  final RxString _sizeFilter = ''.obs;
  String get sizeFilter => _sizeFilter.value;

  /// Size buckets present on the seller's products (server order). Doesn't
  /// shrink while filtering; empty → the size menu is hidden.
  final RxList<String> _availableSizes = <String>[].obs;
  List<String> get availableSizes => _availableSizes;

  /// True when any server filter is set — picks the empty-state wording.
  bool get hasFilters =>
      _query.value.trim().isNotEmpty ||
      _statusFilter.value != 'ALL' ||
      _sizeFilter.value.isNotEmpty;

  Timer? _searchTimer;

  final RxBool _isSavingEdit = false.obs;
  bool get isSavingEdit => _isSavingEdit.value;

  /// Why the last edit was rejected (server message where there is one), so the
  /// edit form can show it inline instead of a generic failure.
  final RxnString _editError = RxnString();
  String? get editError => _editError.value;

  /// Products whose edit came back `403` — the request line they sit on has
  /// been submitted, so the form flips to read-only for the rest of the
  /// session instead of letting the seller fill it in again.
  final RxSet<String> _editLocked = <String>{}.obs;
  bool isEditLocked(String id) => _editLocked.contains(id);

  /// Edit history per product id, loaded on demand by [loadEditLogs].
  final RxMap<String, List<ProductEditLog>> _editLogs =
      <String, List<ProductEditLog>>{}.obs;
  List<ProductEditLog>? editLogsFor(String id) => _editLogs[id];

  int _page = 1;
  int _total = 0;

  /// Set when a page comes back empty, so paging stops even if `total` and
  /// the loaded rows disagree.
  bool _reachedEnd = false;

  /// Bumped by every page-1 load so a page still in flight for an older set
  /// of filters can't land in the current list (last request wins).
  int _loadSeq = 0;

  /// True while the server still has rows we haven't pulled.
  bool get hasMore => !_reachedEnd && _page * _pageSize < _total;

  /// Previews (signed image URLs + the richer catalog fields) keyed by product
  /// id. Populated lazily by [imagesFor] / [loadPreview] so each product is
  /// only fetched once per session.
  final RxMap<String, SellerProductPreview> _previews =
      <String, SellerProductPreview>{}.obs;

  /// Full product payloads (`GET /api/v1/seller/products/{id}`) keyed by id —
  /// what the details page renders. Loaded on demand by [loadDetail].
  final RxMap<String, SellerProductDetail> _details =
      <String, SellerProductDetail>{}.obs;

  /// Ids whose detail call is in flight / has failed, so the details page can
  /// show a spinner and an inline retry without firing duplicate requests.
  final Set<String> _loadingDetails = <String>{};
  final Set<String> _failedDetails = <String>{};

  /// Product ids currently being fetched, so overlapping card builds don't fire
  /// duplicate preview requests.
  final Set<String> _loadingPreviews = <String>{};

  /// Ids whose preview call failed. Kept so a rebuilding card doesn't retry the
  /// same failing request forever; the details sheet can still force a retry.
  final Set<String> _failedPreviews = <String>{};

  @override
  void onInit() {
    super.onInit();
    fetchProducts();
  }

  @override
  void onClose() {
    _searchTimer?.cancel();
    super.onClose();
  }

  // ---------- Filtering ----------

  /// The rows the grid renders. Filtering happens on the server, so this is
  /// simply what has been loaded for the current filters.
  List<SellerProduct> get filteredProducts => _products;

  /// Debounced: the refetch fires once typing pauses.
  void setQuery(String value) {
    if (value == _query.value) return;
    _query.value = value;
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () => fetchProducts(refresh: true));
  }

  void setStatusFilter(String value) {
    if (value == _statusFilter.value) return;
    _statusFilter.value = value;
    fetchProducts(refresh: true);
  }

  void setSizeFilter(String value) {
    if (value == _sizeFilter.value) return;
    _sizeFilter.value = value;
    fetchProducts(refresh: true);
  }

  void clearFilters() {
    _searchTimer?.cancel();
    _query.value = '';
    _statusFilter.value = 'ALL';
    _sizeFilter.value = '';
    fetchProducts(refresh: true);
  }

  // ---------- Fetching ----------

  /// Loads page 1 for the current filters, replacing the list. A newer call
  /// supersedes one still in flight.
  Future<bool> fetchProducts({bool refresh = false}) async {
    final seq = ++_loadSeq;
    _isLoading.value = true;
    _isLoadingMore.value = false;
    if (refresh) _error.value = null;

    final ok = await _loadPage(1, seq: seq);
    if (seq == _loadSeq) _isLoading.value = false;
    return ok;
  }

  /// Appends the next page when the seller scrolls past what's loaded.
  Future<void> loadMore() async {
    if (_isLoading.value || _isLoadingMore.value || !hasMore) return;

    final seq = _loadSeq;
    _isLoadingMore.value = true;
    await _loadPage(_page + 1, seq: seq);
    if (seq == _loadSeq) _isLoadingMore.value = false;
  }

  Future<bool> _loadPage(int page, {required int seq}) async {
    try {
      final query = _query.value.trim();
      final uri = Uri.parse('${EnvConfig.baseUrl}/api/v1/seller/products')
          .replace(queryParameters: {
        'page': '$page',
        'pageSize': '$_pageSize',
        if (query.isNotEmpty) 'search': query,
        if (_statusFilter.value != 'ALL') 'status': _statusFilter.value,
        if (_sizeFilter.value.isNotEmpty) 'size': _sizeFilter.value,
      });

      final response = await _api.get(
        uri.toString(),
        headers: AuthService.instance.authHeaders,
      );

      // The filters changed (or a refresh started) while this was loading.
      if (seq != _loadSeq) return false;

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final data = body['data'] as Map<String, dynamic>;
          final items = (data['items'] as List?) ?? const [];
          final parsed = items
              .whereType<Map<String, dynamic>>()
              .map(SellerProduct.fromJson)
              .toList();

          if (page == 1) {
            _products.value = parsed;
          } else {
            _products.addAll(parsed);
          }

          _page = (data['page'] as num?)?.toInt() ?? page;
          _total = (data['total'] as num?)?.toInt() ?? _products.length;
          _reachedEnd = parsed.isEmpty;
          final sizes = data['availableSizes'];
          if (sizes is List) {
            _availableSizes.value = sizes.map((e) => e.toString()).toList();
          }
          _error.value = null;
          return true;
        }
        _error.value = 'Unexpected response format.';
        return false;
      }

      _error.value = _errorMessage(response) ??
          'Failed to load products: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Seller products fetch error: $e');
      if (seq == _loadSeq) _error.value = 'Network error. Please try again.';
      return false;
    }
  }

  // ---------- Preview / images ----------

  /// The cached preview for [id], or null when it hasn't been loaded yet.
  /// Reading this inside an `Obx` subscribes to later loads.
  SellerProductPreview? previewFor(String id) => _previews[id];

  /// True while the preview for [id] is in flight.
  bool isLoadingPreview(String id) => _loadingPreviews.contains(id);

  /// Best-effort displayable images for [product].
  ///
  /// The list endpoint mostly returns bare S3 keys, which can't be loaded
  /// directly, so anything without a usable URL falls back to the preview
  /// endpoint, which hands back pre-signed URLs. Cached per product id.
  List<String> imagesFor(SellerProduct product) {
    // Read the reactive map first so an `Obx` around this call always has an
    // observable to subscribe to, even for products whose list images are
    // already usable.
    final cached = _previews[product.id];

    final direct = product.remoteImageUrls;
    if (direct.isNotEmpty) return direct;
    if (cached != null) return cached.imageUrls;

    if (!_failedPreviews.contains(product.id)) loadPreview(product.id);
    return const [];
  }

  /// True while [imagesFor] is still waiting on the preview call for [id].
  bool isResolvingImages(String id) =>
      !_previews.containsKey(id) && _loadingPreviews.contains(id);

  /// The cached full product for [id], or null when it hasn't loaded yet.
  /// Reading this inside an `Obx` subscribes to later loads.
  SellerProductDetail? detailFor(String id) => _details[id];

  /// True while the detail call for [id] is in flight.
  bool isLoadingDetail(String id) => _loadingDetails.contains(id);

  /// True when the last detail call for [id] failed — the details page offers
  /// a retry rather than silently re-requesting on every rebuild.
  bool detailFailed(String id) => _failedDetails.contains(id);

  /// Loads `GET /api/v1/seller/products/{id}` — the fullest payload we have
  /// (auction prices, warehouse codes, shipping, plus the platform shipping
  /// rules) — and caches it per id.
  ///
  /// Returns the cached copy straight away unless [force] is set (used after
  /// an edit and by the details page's retry), and de-dupes overlapping calls.
  Future<SellerProductDetail?> loadDetail(
    String id, {
    bool force = false,
  }) async {
    if (id.isEmpty) return null;
    if (!force && _details.containsKey(id)) return _details[id];
    if (_loadingDetails.contains(id)) return _details[id];

    _loadingDetails.add(id);
    _failedDetails.remove(id);
    // Nudge listeners so the spinner appears on this frame.
    _details.refresh();

    final url = '${EnvConfig.baseUrl}/api/v1/seller/products/'
        '${Uri.encodeComponent(id)}';

    // Fetched alongside the product: the amounts a seller may pick come from
    // here now, not from the product's `platformShippingSettings`.
    final shippingOptions = ShippingOptionsService.instance.load();

    try {
      log('[ProductDetail] GET $url', name: 'SellerProducts');

      final response = await _api.get(
        url,
        headers: AuthService.instance.authHeaders,
      );

      log(
        '[ProductDetail] ${response.statusCode} ($id) '
        '${response.body.length} bytes\n${response.body}',
        name: 'SellerProducts',
      );

      if (response.isSuccess) {
        final body = response.json;
        final data = body['data'];
        if (body['success'] == true && data is Map<String, dynamic>) {
          await shippingOptions;
          final detail = SellerProductDetail.fromData(
            data,
            shippingAmountsNok:
                ShippingOptionsService.instance.fetched?.amountsNok,
          );
          _details[id] = detail;
          log(
            '[ProductDetail] parsed "${detail.name}" — '
            'status ${detail.status}, stock ${detail.stockCount}, '
            'buyNow ${detail.buyNowPrice}, images ${detail.imageUrls.length}, '
            'platformShipping ${detail.platformShipping != null}',
            name: 'SellerProducts',
          );
          return detail;
        }
        log(
          '[ProductDetail] unexpected payload shape ($id): '
          'success=${body['success']}, data=${data.runtimeType}',
          name: 'SellerProducts',
        );
      }

      log(
        '[ProductDetail] failed ($id): ${response.statusCode}',
        name: 'SellerProducts',
      );
      _failedDetails.add(id);
      return null;
    } catch (e, stack) {
      log(
        '[ProductDetail] error ($id): $e',
        name: 'SellerProducts',
        error: e,
        stackTrace: stack,
      );
      _failedDetails.add(id);
      return null;
    } finally {
      _loadingDetails.remove(id);
      // Nudge listeners so a failed load clears any spinner bound to
      // [isLoadingDetail].
      _details.refresh();
    }
  }

  /// Loads `GET /api/v1/seller/products/{id}/preview` and caches it.
  ///
  /// Returns the cached copy straight away unless [force] is set (used by the
  /// details sheet's retry), and de-dupes overlapping calls for the same id.
  Future<SellerProductPreview?> loadPreview(
    String id, {
    bool force = false,
  }) async {
    if (id.isEmpty) return null;
    if (!force && _previews.containsKey(id)) return _previews[id];
    if (_loadingPreviews.contains(id)) return _previews[id];

    _loadingPreviews.add(id);
    _failedPreviews.remove(id);

    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/products/'
        '${Uri.encodeComponent(id)}/preview',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        final data = body['data'];
        if (body['success'] == true && data is Map<String, dynamic>) {
          // The payload may carry the product directly or nested under
          // `product` — handle both shapes, same as the quick view does.
          final product =
              (data['product'] as Map?)?.cast<String, dynamic>() ?? data;
          final preview = SellerProductPreview.fromJson(product);
          _previews[id] = preview;
          return preview;
        }
      }

      log('Seller product preview failed ($id): ${response.statusCode}');
      _failedPreviews.add(id);
      return null;
    } catch (e) {
      log('Seller product preview error ($id): $e');
      _failedPreviews.add(id);
      return null;
    } finally {
      _loadingPreviews.remove(id);
      // Nudge listeners so a failed load clears any spinner bound to
      // [isLoadingPreview].
      _previews.refresh();
    }
  }

  // ---------- Editing ----------

  /// `PATCH /api/v1/seller/products/{id}` — applies [changes] to the product.
  ///
  /// [editReason] (1–2000 chars) is mandatory on every call and goes to the
  /// audit trail. [changes] should carry *only* the fields the seller actually
  /// touched — every present key is logged as an edit. The body is strict
  /// (an unknown key is a `400`), so anything outside [editableFields] is
  /// dropped here rather than failing the whole save.
  ///
  /// A `403` means the product's request line is no longer a draft; the id is
  /// remembered in [isEditLocked]. On success the detail, preview and list are
  /// re-read so every screen shows the server's own values.
  Future<bool> updateProduct({
    required String productId,
    required String editReason,
    required Map<String, dynamic> changes,
  }) async {
    final reason = editReason.trim();
    if (productId.isEmpty) return false;
    if (reason.isEmpty || reason.length > 2000) {
      _editError.value = 'An edit reason of 1–2000 characters is required.';
      return false;
    }
    if (_isSavingEdit.value) return false;

    _isSavingEdit.value = true;
    _editError.value = null;

    try {
      final body = <String, dynamic>{
        for (final entry in changes.entries)
          if (editableFields.contains(entry.key)) entry.key: entry.value,
        'editReason': reason,
      };

      final response = await _api.patch(
        '${EnvConfig.baseUrl}/api/v1/seller/products/'
        '${Uri.encodeComponent(productId)}',
        headers: AuthService.instance.authHeaders,
        body: body,
      );

      if (response.isSuccess) {
        final json = response.json;
        final data = json['data'];
        final ok = json['success'] == true &&
            (data is! Map || data['ok'] != false);
        if (ok) {
          // Pull the authoritative product back rather than patching locally —
          // the server normalises prices, CSV fields and image keys.
          _editLogs.remove(productId);
          await Future.wait([
            loadDetail(productId, force: true),
            loadPreview(productId, force: true),
          ]);
          await fetchProducts(refresh: true);
          return true;
        }
      }

      if (response.statusCode == 403) _editLocked.add(productId);

      _editError.value = _errorMessage(response) ??
          (response.statusCode == 429
              ? 'Too many edits — the limit is 30 per minute. Try again shortly.'
              : 'Could not save the changes (${response.statusCode}).');
      return false;
    } catch (e) {
      log('Product edit error ($productId): $e');
      _editError.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isSavingEdit.value = false;
    }
  }

  /// Every key `PATCH /seller/products/{id}` accepts besides `editReason`.
  /// `sizeType` is accepted but never persisted, so it is left out.
  static const Set<String> editableFields = {
    'name',
    'shortDescription',
    'description',
    'brand',
    'material',
    'colour',
    'features',
    'materialsAndCare',
    'sku',
    'upc',
    'veilPris',
    'weight',
    'startingPrice',
    'bottomPrice',
    'tags',
    'size',
    'usSize',
    'euSize',
    'sizesAvailable',
    'stockCount',
    'taxonomyNodeId',
    'imageUrls',
    'replaceImages',
    'useDefaultShipping',
    'shippingPriceNok',
  };

  /// `GET /api/v1/seller/products/{id}/edit-logs` — the latest 200 field
  /// changes, newest first. Cached per id; [force] re-reads. Returns null on
  /// failure so the caller can offer a retry.
  Future<List<ProductEditLog>?> loadEditLogs(
    String id, {
    bool force = false,
  }) async {
    if (id.isEmpty) return null;
    if (!force && _editLogs.containsKey(id)) return _editLogs[id];

    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/products/'
        '${Uri.encodeComponent(id)}/edit-logs',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        final data = body['data'];
        if (body['success'] == true && data is Map) {
          final logs = ((data['items'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(ProductEditLog.fromJson)
              .toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(0))
                .compareTo(a.createdAt ?? DateTime(0)));
          _editLogs[id] = logs;
          return logs;
        }
      }
      log('Product edit logs failed ($id): ${response.statusCode}');
      return null;
    } catch (e) {
      log('Product edit logs error ($id): $e');
      return null;
    }
  }

  /// Uploads one product photo and returns its `s3Key`, or null on failure.
  ///
  /// Uses the shared seller image endpoint the rest of the app uploads to
  /// (`POST /api/v1/seller/product-request-issue-images`, multipart `file`,
  /// JPEG/PNG/WebP ≤ 5 MB). The returned key is what goes into `imageUrls` on
  /// the PATCH.
  Future<String?> uploadProductImage(String filePath) async {
    try {
      final response = await _api.uploadFile(
        '${EnvConfig.baseUrl}/api/v1/seller/product-request-issue-images',
        fieldName: 'file',
        filePath: filePath,
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        // The endpoint has shipped the key both at the root and under `data`.
        final key = (body['s3Key'] ??
            (body['data'] is Map ? (body['data'] as Map)['s3Key'] : null))
            as String?;
        if (key != null && key.isNotEmpty) return key;
      }
      log('Product image upload failed: ${response.statusCode}');
      return null;
    } catch (e) {
      log('Product image upload error: $e');
      return null;
    }
  }

  /// The server's `error.message` for a failed call, when it sent one.
  String? _errorMessage(ApiResponse response) {
    try {
      final error = response.json['error'];
      final message = error is Map ? error['message'] : null;
      if (message is String && message.trim().isNotEmpty) return message.trim();
    } catch (_) {}
    return null;
  }
}
