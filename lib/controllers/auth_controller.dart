import 'dart:convert';
import 'dart:developer';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/config/session_scope.dart';
import '../core/localization/translation_keys.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../core/services/social_auth_service.dart';
import '../features/notifications/application/push_notification_service.dart';

/// Outcome of the post-login seller `/me` account check.
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

  /// The Google / Apple sign-in in flight, if any — that button spins and
  /// every sign-in control is disabled.
  final Rxn<SocialProvider> _socialBusy = Rxn<SocialProvider>();
  SocialProvider? get socialBusy => _socialBusy.value;
  bool get isBusy => _isLoading.value || _socialBusy.value != null;

  // ---------- Services ----------

  final _authService = AuthService.instance;

  // ---------- Convenience ----------

  Map<String, String> get authHeaders => _authService.authHeaders;
  String? get accessToken => _authService.accessToken;

  @override
  void onInit() {
    super.onInit();
    // Reflect any session restored from secure storage on cold start.
    _syncFromSession();
    // Keep following it: a token refresh that fails, a revoked session, or a
    // sign-out triggered from anywhere else all move [AuthService.status], and
    // any screen bound to `isLoggedIn` has to see that without being told.
    _authService.status.addListener(_syncFromSession);
  }

  @override
  void onClose() {
    _authService.status.removeListener(_syncFromSession);
    super.onClose();
  }

  void _syncFromSession() {
    _isLoggedIn.value = _authService.isLoggedIn;
    _displayName.value = _authService.displayName;
  }

  // ---------- Intents ----------

  /// Signs in with email + password against `POST /api/v1/auth/login`.
  /// [AuthService] stores the Cognito tokens and provisions the profile when
  /// the identity is unmapped; the caller still runs the seller gate.
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading.value = true;
    _errorMessage.value = null;

    try {
      await _authService.login(email: email, password: password);
      _syncFromSession();
      return true;
    } on AuthApiException catch (e) {
      log('[auth-login] failed status=${e.statusCode} code=${e.code}');
      _errorMessage.value = _loginError(e.failure);
      return false;
    } catch (e) {
      log('[auth-login] error: ${e.runtimeType}');
      _errorMessage.value = TKeys.authSomethingWrong.tr;
      return false;
    } finally {
      _isLoading.value = false;
    }
  }

  /// "Continue with Google / Apple": browser round-trip, code exchange,
  /// tokens saved and ensure-profile run. The caller still runs the seller
  /// gate. On `false`, [errorMessage] is the message to show — or null when
  /// the user simply backed out, which stays silent.
  Future<bool> socialLogin(SocialProvider provider) async {
    if (isBusy) return false;
    _socialBusy.value = provider;
    _errorMessage.value = null;

    try {
      final result = await SocialAuthService().signIn(provider);
      await _authService.signInWithSocial(result);
      _syncFromSession();
      return true;
    } on SocialAuthException catch (e) {
      if (!e.cancelled) _errorMessage.value = e.message;
      return false;
    } catch (e) {
      log('[auth-social] error: ${e.runtimeType}');
      _errorMessage.value = TKeys.authSocialFailed.tr;
      return false;
    } finally {
      _socialBusy.value = null;
    }
  }

  String _loginError(AuthFailure failure) {
    switch (failure) {
      case AuthFailure.invalidCredentials:
      case AuthFailure.validation:
        return TKeys.authInvalidCredentials.tr;
      case AuthFailure.restricted:
        return TKeys.authAccountRestricted.tr;
      case AuthFailure.rateLimited:
        return TKeys.authTooManyAttempts.tr;
      case AuthFailure.unavailable:
        return TKeys.authTemporarilyUnavailable.tr;
      case AuthFailure.network:
        return TKeys.authNetworkError.tr;
    }
  }

  /// Gates entry on `GET /api/v1/seller/auth/me`, the seller-specific profile.
  ///
  ///  * 2xx → a seller, unless the payload names some other role.
  ///  * 403 / `AUTH_ROLE_REQUIRED` → signed in, but not an approved seller.
  ///  * 404 → the seller route isn't deployed on this backend; fall back to
  ///    the shared `/api/v1/auth/me` and gate on `role == "seller"`.
  ///  * anything else → an error to retry, never a logout.
  ///
  /// `401 AUTH_EXPIRED` and `AUTH_USER_NOT_FOUND` are recovered inside
  /// [ApiClient] before this sees the response.
  Future<AuthMeResult> fetchMe() async {
    _isLoading.value = true;
    _errorMessage.value = null;

    try {
      var response = await _getMe('/api/v1/seller/auth/me');
      if (response.statusCode == 404) {
        log('[auth-me] seller /me missing — falling back to /auth/me');
        response = await _getMe('/api/v1/auth/me');
      }

      log('[auth-me] status=${response.statusCode}');

      if (response.isSuccess) {
        final body = _decode(response.body);
        final data = body?['data'];
        if (body?['success'] == true && data is Map) {
          await _rememberProfile(data);
          final role = data['role'] as String?;
          log('[auth-me] role=$role');
          return role == null || role == 'seller'
              ? AuthMeResult.seller
              : AuthMeResult.notSeller;
        }
        _errorMessage.value = TKeys.gateVerifyFailed.tr;
        return AuthMeResult.error;
      }

      final code = (_decode(response.body)?['error'] as Map?)?['code'];
      if (response.statusCode == 403 || code == 'AUTH_ROLE_REQUIRED') {
        return AuthMeResult.notSeller;
      }

      _errorMessage.value = TKeys.gateVerifyFailed.tr;
      return AuthMeResult.error;
    } catch (e) {
      log('[auth-me] error: ${e.runtimeType}');
      _errorMessage.value = TKeys.authNetworkError.tr;
      return AuthMeResult.error;
    } finally {
      _isLoading.value = false;
    }
  }

  /// The gate handles a non-seller itself, so the global
  /// `AUTH_ROLE_REQUIRED` → sign-out handler must not fire on top of it.
  Future<ApiResponse> _getMe(String path) => ApiClient.instance.get(
        '${EnvConfig.baseUrl}$path',
        headers: _authService.authHeaders,
        suppressAuthHandlers: true,
      );

  /// Persists the app user id (for chat / winner comparisons) and a display
  /// name. The seller payload's exact shape isn't pinned down in the contract
  /// yet, so this reads the likely spellings.
  Future<void> _rememberProfile(Map data) async {
    final user = data['user'] is Map ? data['user'] as Map : const {};
    String? pick(List<Object?> values) {
      for (final v in values) {
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    await _authService.rememberProfile(
      userId: pick([data['id'], data['userId'], user['id']]),
      displayName: pick([
        data['displayName'],
        data['businessName'],
        data['name'],
        user['displayName'],
        user['name'],
      ]),
    );
    _syncFromSession();
  }

  Map<String, dynamic>? _decode(String raw) {
    try {
      final body = jsonDecode(raw);
      return body is Map<String, dynamic> ? body : null;
    } catch (_) {
      return null;
    }
  }

  /// Step 1 of password reset: emails a numeric code. Returns `true` for
  /// "request accepted" — the backend is anti-enumeration, so this does NOT
  /// confirm the account exists and the UI must stay generic.
  Future<bool> requestPasswordReset({required String email}) async {
    if (email.isEmpty) {
      _errorMessage.value = TKeys.authEnterEmail.tr;
      return false;
    }

    _isLoading.value = true;
    _errorMessage.value = null;

    try {
      await _authService.requestPasswordReset(email: email);
      return true;
    } on AuthApiException catch (e) {
      _errorMessage.value = _resetError(e.failure);
      return false;
    } finally {
      _isLoading.value = false;
    }
  }

  /// Step 2 of password reset: the emailed [code] plus the new password.
  Future<bool> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    _isLoading.value = true;
    _errorMessage.value = null;

    try {
      await _authService.resetPassword(
        email: email,
        code: code,
        newPassword: newPassword,
      );
      return true;
    } on AuthApiException catch (e) {
      _errorMessage.value = _resetError(e.failure);
      return false;
    } finally {
      _isLoading.value = false;
    }
  }

  String _resetError(AuthFailure failure) {
    switch (failure) {
      case AuthFailure.validation:
      case AuthFailure.invalidCredentials:
        return TKeys.authInvalidResetCode.tr;
      case AuthFailure.rateLimited:
        return TKeys.authTooManyAttempts.tr;
      case AuthFailure.network:
        return TKeys.authNetworkError.tr;
      case AuthFailure.restricted:
      case AuthFailure.unavailable:
        return TKeys.authTemporarilyUnavailable.tr;
    }
  }

  Future<void> logout() async {
    // Detach this handset from the account *first* — the DELETE needs the
    // bearer token that signing out throws away. Best-effort and internally
    // capped at 5s, so a dead network can't stall the sign-out.
    await PushNotificationService.instance.onSignedOut();
    await _authService.logout();
    _isLoggedIn.value = false;
    _displayName.value = null;
    // Nothing un-registers the home shell's controllers on its own, so the
    // next seller to sign in on this handset would otherwise be handed the
    // previous account's profile, dashboard, streams, stock and inbox.
    resetSessionControllers();
  }
}
