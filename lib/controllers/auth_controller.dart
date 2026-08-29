import 'dart:developer';

import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../features/notifications/application/push_notification_service.dart';
import 'notification_controller.dart';

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

  /// Step 1 of email-code login: asks Supabase to mail a 6-digit code to
  /// [email]. Returns `true` when the mail was accepted for delivery.
  ///
  /// Unlike the password-reset flow this is *not* anti-enumeration — the app
  /// creates no accounts, so an unknown address comes back as a Supabase
  /// error, which we translate into a message the seller can act on.
  Future<bool> sendLoginCode({required String email}) async {
    if (email.isEmpty) {
      _errorMessage.value = 'Please enter your email.';
      return false;
    }

    _isLoading.value = true;
    _errorMessage.value = null;

    log('[auth-otp] ➡️  signInWithOtp email=$email');

    try {
      await _authService.sendEmailOtp(email: email);
      log('[auth-otp] ✅ code sent');
      return true;
    } on AuthException catch (e) {
      log('[auth-otp] ❌ AuthException status=${e.statusCode} message=${e.message}');
      _errorMessage.value = _otpSendError(e);
      return false;
    } catch (e) {
      log('[auth-otp] 🔥 error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoading.value = false;
    }
  }

  /// Step 2 of email-code login: exchanges the typed [code] for a session.
  /// On success the SDK persists it and auto-refreshes, so the caller can go
  /// straight on to [fetchMe] for the seller-role gate.
  Future<bool> verifyLoginCode({
    required String email,
    required String code,
  }) async {
    if (code.isEmpty) {
      _errorMessage.value = 'Please enter the code from your email.';
      return false;
    }

    _isLoading.value = true;
    _errorMessage.value = null;

    log('[auth-otp] ➡️  verifyOTP email=$email');

    try {
      final res = await _authService.verifyEmailOtp(email: email, token: code);

      log('[auth-otp] ✅ verified userId=${res.user?.id} '
          'hasSession=${res.session != null}');

      if (res.session != null) {
        _isLoggedIn.value = true;
        _displayName.value =
            res.user?.userMetadata?['display_name'] as String?;
        return true;
      }

      _errorMessage.value = 'Login failed. Please request a new code.';
      return false;
    } on AuthException catch (e) {
      // Wrong digits, an expired code, or too many attempts.
      log('[auth-otp] ❌ AuthException status=${e.statusCode} message=${e.message}');
      _errorMessage.value = _otpVerifyError(e);
      return false;
    } catch (e) {
      log('[auth-otp] 🔥 error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoading.value = false;
    }
  }

  /// Supabase's send-side messages are developer-facing ("Signups not allowed
  /// for otp"), so the two cases a seller can actually hit get rewritten.
  String _otpSendError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('signups not allowed') ||
        msg.contains('not found') ||
        e.statusCode == '422') {
      return 'No account found for that email. Email code login is only for '
          'existing members.';
    }
    if (msg.contains('rate limit') ||
        msg.contains('security purposes') ||
        e.statusCode == '429') {
      return 'Too many code requests. Please wait a minute and try again.';
    }
    return e.message;
  }

  String _otpVerifyError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('expired') || msg.contains('invalid')) {
      return 'That code is invalid or has expired. Request a new one.';
    }
    return e.message;
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
    // Detach this handset from the account *first* — the DELETE needs the
    // bearer token that signing out throws away. Best-effort and internally
    // capped at 5s, so a dead network can't stall the sign-out.
    await PushNotificationService.instance.onSignedOut();
    await _authService.logout();
    _isLoggedIn.value = false;
    _displayName.value = null;
    // The inbox controller is permanent, so without this the next seller to
    // sign in on this handset sees the previous account's rows and badge.
    if (Get.isRegistered<NotificationController>()) {
      Get.find<NotificationController>().clearNotifications();
    }
  }
}
