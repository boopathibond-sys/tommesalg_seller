import 'dart:async';
import 'dart:developer';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../models/seller_order.dart';
import '../models/seller_order_detail.dart';

/// Drives the Orders screen — `GET /api/v1/seller/orders`, which answers
/// `{ data: { orders: [...], nextCursor } }`.
///
/// Every filter is server-side: picking a payment or freight status, or typing
/// an order number, re-queries the API with that param appended
/// (`?limit=20&paymentStatus=PAID&shippingStatus=CANCELLED&orderNumber=300`).
/// A filter left on "all" is simply left out of the URL. Pagination is
/// cursor-based and carries whatever filters are active.
class SellerOrdersController extends GetxController {
  final _api = ApiClient.instance;

  static const int _limit = 20;

  /// The "no filter" sentinel — never sent to the API.
  static const String anyStatus = 'ALL';

  /// `paymentStatus` values the API accepts.
  static const List<String> paymentOptions = [
    anyStatus,
    'PAID',
    'PENDING_PAYMENT',
    'FAILED',
    'REFUNDED',
  ];

  /// `shippingStatus` values the API accepts.
  static const List<String> shippingOptions = [
    anyStatus,
    'NOT_CREATED',
    'CREATED',
    'IN_TRANSIT',
    'DELIVERED',
    'CANCELLED',
  ];

  final RxList<SellerOrder> _orders = <SellerOrder>[].obs;
  List<SellerOrder> get orders => _orders;

  final RxBool _isLoading = false.obs;
  bool get isLoading => _isLoading.value;

  final RxBool _isLoadingMore = false.obs;
  bool get isLoadingMore => _isLoadingMore.value;

  final RxnString _error = RxnString();
  String? get error => _error.value;

  /// Order-number search. Digits only — the API matches on `orderNumber`.
  final RxString _query = ''.obs;
  String get query => _query.value;

  final RxString _paymentFilter = anyStatus.obs;
  String get paymentFilter => _paymentFilter.value;

  final RxString _shippingFilter = anyStatus.obs;
  String get shippingFilter => _shippingFilter.value;

  final RxnString _nextCursor = RxnString();
  final RxBool _hasMore = true.obs;
  bool get hasMore => _hasMore.value;

  /// Typing fires one request per pause, not one per keystroke.
  Timer? _searchDebounce;

  /// Bumped on every request so a response that lost the race — the seller
  /// changed a filter while it was in flight — is dropped instead of painting
  /// the previous filter's rows over the new ones.
  int _fetchSeq = 0;

  @override
  void onInit() {
    super.onInit();
    fetchOrders();
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    super.onClose();
  }

  // ---------- Filters ----------

  bool get hasActiveFilters =>
      _query.value.isNotEmpty ||
      _paymentFilter.value != anyStatus ||
      _shippingFilter.value != anyStatus;

  /// Typed search text. Non-digits are stripped (the endpoint matches an order
  /// number), and the reload waits out a short pause in typing.
  void setQuery(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits == _query.value) return;
    _query.value = digits;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  void setPaymentFilter(String value) {
    if (value == _paymentFilter.value) return;
    _paymentFilter.value = value;
    _reload();
  }

  void setShippingFilter(String value) {
    if (value == _shippingFilter.value) return;
    _shippingFilter.value = value;
    _reload();
  }

  void clearFilters() {
    if (!hasActiveFilters) return;
    _searchDebounce?.cancel();
    _query.value = '';
    _paymentFilter.value = anyStatus;
    _shippingFilter.value = anyStatus;
    _reload();
  }

  /// Drops the rows belonging to the previous filter set and re-queries from
  /// page one — leaving them on screen would show orders the new filter
  /// excludes until the response lands.
  void _reload() {
    _orders.clear();
    _nextCursor.value = null;
    _hasMore.value = true;
    fetchOrders(refresh: true);
  }

  // ---------- Fetching ----------

  /// Loads the first page with the active filters (also used by pull-to-refresh
  /// and the error retry).
  Future<bool> fetchOrders({bool refresh = false}) {
    if (refresh) _nextCursor.value = null;
    return _loadPage(cursor: null, replace: true);
  }

  /// Appends the next page. No-op once the server stops handing out a cursor.
  Future<void> loadMore() async {
    if (_isLoading.value || _isLoadingMore.value || !_hasMore.value) return;
    final cursor = _nextCursor.value;
    if (cursor == null) {
      _hasMore.value = false;
      return;
    }
    await _loadPage(cursor: cursor);
  }

  /// Reads one order in full — `GET /api/v1/seller/orders/{orderId}`. Returns
  /// null when the call fails; the details screen shows its own error state and
  /// offers a retry, so no controller-level error is stored here.
  Future<SellerOrderDetail?> fetchOrderDetail(String orderId) async {
    final url = '${EnvConfig.baseUrl}/api/v1/seller/orders/$orderId';
    log('[OrderDetail] GET $url');
    try {
      final response = await _api.get(
        url,
        headers: AuthService.instance.authHeaders,
      );
      if (!response.isSuccess) {
        log('[OrderDetail] status=${response.statusCode}');
        return null;
      }

      final body = response.json;
      final data = body['data'];
      if (body['success'] != true || data is! Map<String, dynamic>) return null;

      return SellerOrderDetail.fromJson(data);
    } catch (e) {
      log('[OrderDetail] error: $e');
      return null;
    }
  }

  /// The query the current filter state maps to. Anything left on "all" (or an
  /// empty search) is omitted from the URL entirely.
  Uri _buildUri({String? cursor}) {
    final payment = _paymentFilter.value;
    final shipping = _shippingFilter.value;
    final orderNumber = _query.value;

    return Uri.parse('${EnvConfig.baseUrl}/api/v1/seller/orders').replace(
      queryParameters: {
        'limit': '$_limit',
        if (payment != anyStatus) 'paymentStatus': payment,
        if (shipping != anyStatus) 'shippingStatus': shipping,
        if (orderNumber.isNotEmpty) 'orderNumber': orderNumber,
        if (cursor != null) 'cursor': cursor,
      },
    );
  }

  Future<bool> _loadPage({String? cursor, bool replace = false}) async {
    final seq = ++_fetchSeq;
    final firstPage = cursor == null;
    if (firstPage) {
      _isLoading.value = true;
      _error.value = null;
    } else {
      _isLoadingMore.value = true;
    }

    try {
      final uri = _buildUri(cursor: cursor);
      log('[Orders] GET $uri');

      final response = await _api.get(
        uri.toString(),
        headers: AuthService.instance.authHeaders,
      );

      // Superseded — a newer filter/search request is already in flight.
      if (seq != _fetchSeq) return false;

      if (!response.isSuccess) {
        _error.value = 'Could not load orders (${response.statusCode}).';
        return false;
      }

      final body = response.json;
      if (body['success'] != true || body['data'] is! Map) {
        _error.value = 'Unexpected response format.';
        return false;
      }

      final data = body['data'] as Map<String, dynamic>;
      final parsed = ((data['orders'] ?? data['items']) as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SellerOrder.fromJson)
          .toList();

      if (replace) {
        _orders.assignAll(parsed);
      } else {
        // Dedupe by id: if the cursor param is ever ignored the server replays
        // page one, and appending it blindly would both duplicate rows and
        // loop "Load more" forever.
        final seen = _orders.map((o) => o.id).toSet();
        final fresh = parsed.where((o) => !seen.contains(o.id)).toList();
        if (fresh.isEmpty) {
          _hasMore.value = false;
          return true;
        }
        _orders.addAll(fresh);
      }

      final next = data['nextCursor'];
      _nextCursor.value = next is String && next.isNotEmpty ? next : null;
      // A short page means the server has nothing left, cursor or not.
      _hasMore.value = _nextCursor.value != null && parsed.length >= _limit;
      _error.value = null;
      return true;
    } catch (e) {
      log('Orders fetch error: $e');
      if (seq == _fetchSeq) _error.value = 'Network error. Please try again.';
      return false;
    } finally {
      // A superseded request must not clear the flags under the newer one.
      if (seq == _fetchSeq) {
        if (firstPage) {
          _isLoading.value = false;
        } else {
          _isLoadingMore.value = false;
        }
      }
    }
  }
}
