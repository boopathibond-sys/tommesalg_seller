import 'dart:developer';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../models/seller_product_request_summary.dart';

/// Filter pills on the My requests screen.
enum RequestFilter { all, active, invalid }

/// Drives the "My requests" screen: the seller's product requests across all
/// streams (`GET /api/v1/seller/product-requests`), paged with
/// `?page=&pageSize=` and filtered client-side (the endpoint has no filter
/// parameter).
///
/// Owned by the screen — created when it opens, disposed when it closes — so
/// nothing carries over between sessions.
class MyRequestsController extends GetxController {
  static const pageSize = 20;

  final _api = ApiClient.instance;

  final RxList<SellerProductRequestSummary> _items =
      <SellerProductRequestSummary>[].obs;

  final RxBool _isLoading = false.obs;
  bool get isLoading => _isLoading.value;

  final RxBool _isLoadingMore = false.obs;
  bool get isLoadingMore => _isLoadingMore.value;

  final RxBool _hasMore = true.obs;
  bool get hasMore => _hasMore.value;

  /// Set when the first page fails; a failed *next* page only stops paging.
  final RxnString _error = RxnString();
  String? get error => _error.value;

  final Rx<RequestFilter> _filter = RequestFilter.all.obs;
  RequestFilter get filter => _filter.value;

  bool _loaded = false;
  bool get loaded => _loaded;

  int _page = 0;

  List<SellerProductRequestSummary> get allItems => _items;

  /// Rows for the current filter, newest first.
  List<SellerProductRequestSummary> get items {
    final list = switch (_filter.value) {
      RequestFilter.all => _items.toList(),
      RequestFilter.active => _items.where((r) => r.isActive).toList(),
      RequestFilter.invalid => _items.where((r) => !r.isActive).toList(),
    };
    list.sort((a, b) {
      final da = a.sentAt, db = b.sentAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return list;
  }

  int countFor(RequestFilter f) => switch (f) {
        RequestFilter.all => _items.length,
        RequestFilter.active => _items.where((r) => r.isActive).length,
        RequestFilter.invalid => _items.where((r) => !r.isActive).length,
      };

  void setFilter(RequestFilter f) => _filter.value = f;

  /// Reloads from page 1.
  Future<void> refreshRequests() async {
    if (_isLoading.value) return;
    _isLoading.value = true;
    _error.value = null;
    try {
      final page = await _fetchPage(1);
      if (page == null) {
        _error.value ??= 'load_failed';
        return;
      }
      _items.assignAll(page);
      _page = 1;
    } finally {
      _loaded = true;
      _isLoading.value = false;
    }
  }

  /// Appends the next page. No-op while loading or at the end.
  Future<void> loadMore() async {
    if (_isLoading.value || _isLoadingMore.value || !_hasMore.value) return;
    _isLoadingMore.value = true;
    try {
      final page = await _fetchPage(_page + 1);
      if (page == null) return;
      // The backend slices a bounded set in memory today, so a row can shift
      // pages between calls — skip anything already shown.
      final seen = _items.map((r) => r.id).toSet();
      _items.addAll(page.where((r) => seen.add(r.id)));
      _page++;
    } finally {
      _isLoadingMore.value = false;
    }
  }

  /// One page of rows, or null on failure. Updates [hasMore].
  Future<List<SellerProductRequestSummary>?> _fetchPage(int page) async {
    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/product-requests'
        '?page=$page&pageSize=$pageSize',
        headers: AuthService.instance.authHeaders,
      );
      if (!response.isSuccess) {
        log('product-requests page $page → ${response.statusCode}');
        return null;
      }
      final body = response.json;
      final data = body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final rows = (data['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SellerProductRequestSummary.fromJson)
          .toList();
      final meta = data['meta'] is Map<String, dynamic>
          ? data['meta'] as Map<String, dynamic>
          : const <String, dynamic>{};
      _hasMore.value = meta['hasMore'] is bool
          ? meta['hasMore'] as bool
          : rows.length >= pageSize;
      return rows;
    } catch (e) {
      log('product-requests page $page failed: $e');
      return null;
    }
  }
}
