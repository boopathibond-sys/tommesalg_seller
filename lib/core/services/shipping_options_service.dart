import 'dart:convert';
import 'dart:developer';

import '../config/env_config.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// The shipping amounts a seller may pick, as
/// `GET /api/v1/seller/shipping-options` returns them.
class ShippingOptions {
  const ShippingOptions({required this.amountsNok, required this.defaultNok});

  /// Allowed amounts in NOK, ascending.
  final List<num> amountsNok;

  /// The platform's standard amount — 99 when it's on offer, otherwise the
  /// server's default or the first amount.
  final num defaultNok;

  /// Used until the endpoint answers, and whenever it can't be read.
  static const ShippingOptions fallback = ShippingOptions(
    amountsNok: <num>[79, 99, 129, 169, 249],
    defaultNok: 99,
  );

  /// Accepts the `data` payload as a bare list, a list of option objects, or
  /// a map wrapping either (`allowedShippingAmountsNok` / `options` / …).
  /// Null when no amount could be read.
  static ShippingOptions? fromData(Object? data) {
    num? serverDefault;
    Object? list = data;
    if (data is Map) {
      serverDefault = _num(data['defaultShippingPriceNok'] ??
          data['defaultAmountNok'] ??
          data['default']);
      list = data['allowedShippingAmountsNok'] ??
          data['amountsNok'] ??
          data['options'] ??
          data['shippingOptions'] ??
          data['amounts'];
    }
    if (list is! List) return null;

    final amounts = list
        .map((e) => e is Map
            ? _num(e['amountNok'] ??
                e['shippingPriceNok'] ??
                e['priceNok'] ??
                e['amount'] ??
                e['value'])
            : _num(e))
        .whereType<num>()
        .where((v) => v > 0)
        .toSet()
        .toList()
      ..sort();
    if (amounts.isEmpty) return null;

    final def = amounts.contains(99)
        ? 99
        : (serverDefault != null && amounts.contains(serverDefault)
            ? serverDefault
            : amounts.first);
    return ShippingOptions(amountsNok: amounts, defaultNok: def);
  }

  static num? _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');
}

/// Loads [ShippingOptions] once per session; screens read [current]
/// synchronously and call [load] to refresh it.
class ShippingOptionsService {
  ShippingOptionsService._();

  static final ShippingOptionsService instance = ShippingOptionsService._();

  final _api = ApiClient.instance;

  ShippingOptions? _cached;
  Future<ShippingOptions>? _inFlight;

  /// The last list read from the server, or [ShippingOptions.fallback].
  ShippingOptions get current => _cached ?? ShippingOptions.fallback;

  /// The server's list, or null until a fetch has succeeded — for callers
  /// that have their own source to fall back on instead of the fixed list.
  ShippingOptions? get fetched => _cached;

  /// Fetches the list unless it's already cached. Never throws — on failure
  /// it returns [current] and retries on the next call.
  Future<ShippingOptions> load() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<ShippingOptions> _fetch() async {
    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/shipping-options',
        headers: AuthService.instance.authHeaders,
      );
      if (!response.isSuccess) return current;
      final body = jsonDecode(response.body);
      final parsed = ShippingOptions.fromData(
          body is Map && body.containsKey('data') ? body['data'] : body);
      if (parsed != null) _cached = parsed;
    } catch (e) {
      log('Fetch shipping options error: $e');
    }
    return current;
  }
}
