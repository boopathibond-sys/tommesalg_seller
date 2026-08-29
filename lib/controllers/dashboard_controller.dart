import 'dart:developer';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../models/seller_dashboard.dart';

/// Backs the Home tab's dashboard cards.
///
/// Wraps `GET /api/v1/seller/dashboard`, optionally scoped to a calendar month
/// via `?month=YYYY-MM`. The response carries the months the seller can pick
/// from ([SellerDashboard.availableMonths]), so the month menu is driven by the
/// same call that fills the cards — no separate lookup.
class DashboardController extends GetxController {
  final _api = ApiClient.instance;

  final RxBool _isLoading = false.obs;
  bool get isLoading => _isLoading.value;

  /// True only while switching months — the cards stay on screen showing the
  /// previous month's numbers behind a subtle spinner instead of blanking.
  final RxBool _isSwitchingMonth = false.obs;
  bool get isSwitchingMonth => _isSwitchingMonth.value;

  final RxnString _errorMessage = RxnString();
  String? get errorMessage => _errorMessage.value;

  final Rxn<SellerDashboard> _dashboard = Rxn<SellerDashboard>();
  SellerDashboard? get dashboard => _dashboard.value;

  /// The month currently displayed, `YYYY-MM`. Null until the first load, when
  /// the API tells us which month it defaulted to.
  final RxnString _selectedMonth = RxnString();
  String? get selectedMonth => _selectedMonth.value ?? _dashboard.value?.yearMonth;

  List<String> get availableMonths => _dashboard.value?.availableMonths ?? const [];

  @override
  void onInit() {
    super.onInit();
    fetchDashboard();
  }

  /// Loads the dashboard for [month] (`YYYY-MM`), or the API's default month
  /// when omitted.
  ///
  /// Set [silent] for pull-to-refresh, where the indicator is already showing.
  Future<bool> fetchDashboard({String? month, bool silent = false}) async {
    final target = month ?? _selectedMonth.value;
    // A month switch keeps the old cards up; a first/blank load takes over the
    // section with the loading state.
    final hasData = _dashboard.value != null;
    if (!silent) {
      if (hasData) {
        _isSwitchingMonth.value = true;
      } else {
        _isLoading.value = true;
      }
    }
    _errorMessage.value = null;

    try {
      var uri = Uri.parse('${EnvConfig.baseUrl}/api/v1/seller/dashboard');
      if (target != null && target.isNotEmpty) {
        uri = uri.replace(queryParameters: {'month': target});
      }

      final response = await _api.get(
        uri.toString(),
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {

        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final data = SellerDashboard.fromJson(
            body['data'] as Map<String, dynamic>,
          );
          _dashboard.value = data;
          // Trust the API's own yearMonth over what we asked for.
          if (data.yearMonth.isNotEmpty) _selectedMonth.value = data.yearMonth;
          return true;
        }
        _errorMessage.value = 'Unexpected response format.';
        return false;
      }

      if (response.statusCode == 403) {
        _errorMessage.value = "You don't have access to the dashboard.";
        return false;
      }

      _errorMessage.value = 'Failed to load dashboard: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Dashboard fetch error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoading.value = false;
      _isSwitchingMonth.value = false;
    }
  }

  /// Switches the displayed month. No-op when [month] is already showing.
  Future<void> selectMonth(String month) async {
    if (month == selectedMonth) return;
    await fetchDashboard(month: month);
  }
}
