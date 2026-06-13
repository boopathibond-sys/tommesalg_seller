import 'dart:developer';

import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';

/// Outcome of the post-login `GET /api/v1/auth/me` account check.
enum AuthMeResult {
  /// Account is a seller — proceed into the app.
  seller,

  /// Account exists but isn't a seller (e.g. `role: "buyer"`) — block entry.
  notSeller,

  /// The check could not be completed (network / unexpected response).
  error,
}

class AuthController extends GetxController {
  // ---------- Reactive state ----------

  final RxBool _isLoading = false.obs;
  bool get isLoading => _isLoading.value;

  final RxnString _errorMessage = RxnString();
  String? get errorMessage => _errorMessage.value;

  final RxBool _isLoggedIn = false.obs;
  bool get isLoggedIn => _isLoggedIn.value;

  final RxnString _displayName = RxnString();
  String? get displayName => _displayName.value;

  // ---------- Services ----------

  final _authService = AuthService.instance;

  // ---------- Convenience ----------

  Map<String, String> get authHeaders => _authService.authHeaders;
  String? get accessToken => _authService.accessToken;

  @override
  void onInit() {
    super.onInit();
    // Reflect any session the SDK restored on cold start.
    _isLoggedIn.value = _authService.isLoggedIn;
    _displayName.value =
        _authService.currentUser?.userMetadata?['display_name'] as String?;
  }

  // ---------- Intents ----------

  /// Signs in with email + password via the Supabase SDK. The SDK persists the
  /// session and starts auto-refreshing the token — no manual token handling.
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading.value = true;
    _errorMessage.value = null;

    log('[auth-login] ➡️  signInWithPassword email=$email');

    try {
      final res = await _authService.signInWithPassword(
        email: email,
        password: password,
      );

      log('[auth-login] ✅ response'
          'userId=${res.user?.id} '
          'hasSession=${res.session != null} '
          'expiresAt=${res.session?.expiresAt}');

      if (res.session != null) {
        _isLoggedIn.value = true;
        _displayName.value =
            res.user?.userMetadata?['display_name'] as String?;
        log('[auth-login] logged in as ${_displayName.value ?? email}');
        return true;
      }

      log('[auth-login] ❌ no session returned');
      _errorMessage.value = 'Login failed.';
      return false;
    } on AuthException catch (e) {
      // Wrong credentials, unconfirmed email, rate limiting, etc.
      log('[auth-login] ❌ AuthException status=${e.statusCode} message=${e.message}');
      _errorMessage.value = e.message;
      return false;
    } catch (e) {
      log('[auth-login] 🔥 error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoading.value = false;
    }
  }

  /// Verifies the signed-in account via `GET /api/v1/auth/me`. Called right
  /// after a successful login to gate entry to the app. The endpoint returns a
  /// 2xx with `success: true` for any authenticated account, so the seller
  /// check is on `data.role` — only `role == "seller"` may proceed. A buyer
  /// (or any other role) yields [AuthMeResult.notSeller] so the caller can
  /// block entry and explain why.
  Future<AuthMeResult> fetchMe() async {
    _isLoading.value = true;
    _errorMessage.value = null;

    final url = '${EnvConfig.baseUrl}/api/v1/auth/me';
    log('[auth-me] ➡️  GET $url');

    try {
      final response = await ApiClient.instance.get(
        url,
        headers: _authService.authHeaders,
      );

      log('[auth-me] status=${response.statusCode} body=${response.body}');

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final role = (body['data'] as Map)['role'] as String?;
          log('[auth-me] role=$role');
          return role == 'seller'
              ? AuthMeResult.seller
              : AuthMeResult.notSeller;
        }
        _errorMessage.value = 'Unexpected response. Please try again.';
        return AuthMeResult.error;
      }

      if (response.statusCode == 403) {
        // Backend rejected the role outright.
        return AuthMeResult.notSeller;
      }

      _errorMessage.value = 'Failed to verify account: ${response.statusCode}';
      return AuthMeResult.error;
    } catch (e) {
      log('[auth-me] 🔥 error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return AuthMeResult.error;
    } finally {
      _isLoading.value = false;
    }
  }

  /// Step 1 of password reset: asks the buyer backend to send the recovery
  /// email. Returns `true` for "request accepted" — because the backend is
  /// anti-enumeration, this does NOT confirm the account exists, so the UI
  /// must show a generic message regardless.
  Future<bool> requestPasswordReset({required String email}) async {
    if (email.isEmpty) {
      _errorMessage.value = 'Email is required.';
      return false;
    }

    _isLoading.value = true;
    _errorMessage.value = null;

    try {
      await _authService.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      _errorMessage.value = _humanise(e);
      return false;
    } finally {
      _isLoading.value = false;
    }
  }

  /// Strips the leading "Exception: " that `Exception(...)` toString adds, so
  /// the snackbar shows the bare message.
  String _humanise(Object e) {
    final text = e.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }

  Future<void> logout() async {
    await _authService.logout();
    _isLoggedIn.value = false;
    _displayName.value = null;
  }
}
