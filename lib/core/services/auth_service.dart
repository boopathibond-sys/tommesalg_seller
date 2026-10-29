import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import '../config/env_config.dart';
import 'api_client.dart';
import 'session_token_store.dart';
import 'social_auth_service.dart';

/// Where the app is in the auth lifecycle, per the auto-login workflow doc.
///
/// The distinction that matters is [bootstrapping] vs [unauthenticated]:
/// routing to Login while session restoration is still running is what makes a
/// signed-in seller see the login form on a cold start.
enum AuthStatus {
  /// Startup is still deciding — a persisted session may be restoring or
  /// refreshing. Keep the splash on screen.
  bootstrapping,

  /// A usable session exists (restored or just created). Enter the app.
  authenticated,

  /// No session, or one that could not be refreshed. Show Login.
  unauthenticated,
}

/// Why an auth call failed, so screens can map it to localized copy instead
/// of showing server or exception text.
enum AuthFailure {
  /// `401` on login (wrong password, unknown / unverified account — the
  /// backend deliberately doesn't say which).
  invalidCredentials,

  /// `403` — the account is suspended.
  restricted,

  /// `400 VALIDATION_ERROR` — on reset, a wrong or expired code.
  validation,

  /// `429` — wait before trying again.
  rateLimited,

  /// `5xx` — Cognito or the session store is down.
  unavailable,

  /// No response at all.
  network,
}

class AuthApiException implements Exception {
  const AuthApiException(this.failure, {this.statusCode, this.code});

  final AuthFailure failure;
  final int? statusCode;

  /// The server's `error.code`, when there was one.
  final String? code;

  @override
  String toString() => 'AuthApiException($failure, $statusCode, $code)';
}

/// What a refresh attempt established about the session.
enum _RefreshOutcome {
  /// New access token saved.
  ok,

  /// The refresh token is dead (`400` / `401` / `403`) — sign in again.
  dead,

  /// `429`, `5xx` or no network. The tokens are kept; try again later.
  transient,
}

/// The seller's session against the Tommesalg API (Cognito behind it).
///
/// See `lib/raw/MOBILE_LOGIN_API_FLOW.md`. The app talks only to the Tommesalg
/// API: it holds a Cognito access + refresh token pair in [SessionTokenStore]
/// and sends `Authorization: Bearer <access>` on every call.
///
/// The rest of the app reads [authHeaders] / [accessToken] / [isLoggedIn]
/// synchronously. Keeping that token fresh is this class's job:
///
///  * [ApiClient] asks [ensureAccessToken] before every bearer request, which
///    refreshes when the token expires within a minute;
///  * an `AUTH_EXPIRED` answer forces one [refreshSession] and one retry;
///  * concurrent refreshes share one in-flight call, because the refresh
///    token can rotate and two racing calls would fight over it.
///
/// Only a dead refresh token or an explicit [logout] ends the session —
/// never a network blip or a 5xx (keep-login goal).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String _loginPath = '/api/v1/auth/login';
  static const String _refreshPath = '/api/v1/auth/refresh';
  static const String _logoutPath = '/api/v1/auth/logout';
  static const String _ensureProfilePath = '/api/v1/auth/ensure-profile';

  /// Shared with the buyer app: there is no seller-specific variant.
  static const String _forgotPasswordPath =
      '/api/v1/buyer/auth/forgot-password';
  static const String _resetPasswordPath = '/api/v1/auth/reset-password';

  /// Refresh this long before the access token actually expires, so a request
  /// never leaves with a token that dies in flight.
  static const Duration _refreshLeeway = Duration(seconds: 60);

  final SessionTokenStore _store = SessionTokenStore();

  /// Where startup / the current session stands. Starts at
  /// [AuthStatus.bootstrapping] so nothing can route to Login before
  /// [bootstrap] has run.
  final ValueNotifier<AuthStatus> status =
      ValueNotifier<AuthStatus>(AuthStatus.bootstrapping);

  Future<_RefreshOutcome>? _refreshInFlight;

  /// Invoked whenever the user ends up fully signed out after startup — a
  /// manual logout, or a refresh token the backend no longer accepts. Wire
  /// this in `main()` to bounce back to the login screen.
  void Function()? onSignedOut;

  // ---------- Synchronous session façade ----------

  String? get accessToken => _store.accessToken;
  String? get refreshToken => _store.refreshToken;

  /// The app user id (`users.id`, from `/me`). Use it for every comparison
  /// with ids the API returns — never the Cognito `sub`.
  String? get userId => _store.userId;
  String? get email => _store.email;
  String? get displayName => _store.displayName;

  /// `true` while a session is held. Survives app restarts and only flips to
  /// `false` on sign-out — never on access-token expiry, which refreshes.
  bool get isLoggedIn => _store.hasSession;

  Map<String, String> get authHeaders => {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

  /// [authHeaders] after making sure the bearer is not about to expire. For
  /// callers that build headers far from [ApiClient] (WebSocket, Agora).
  Future<Map<String, String>> ensuredAuthHeaders() async {
    await ensureAccessToken();
    return authHeaders;
  }

  /// Returns an access token that is valid for at least another minute,
  /// refreshing first when needed. Null when there is no session — or when a
  /// refresh was needed and failed, in which case the stale token is still
  /// returned so the server can answer for itself.
  Future<String?> ensureAccessToken() async {
    if (!isLoggedIn) return null;
    if (_store.expiresWithin(_refreshLeeway)) await refreshSession();
    _logTokenOnce();
    return accessToken;
  }

  /// Set after the bearer token has been printed for this run.
  static bool _tokenLogged = false;

  /// Prints the bearer token once per app launch, so it can be copied into
  /// Postman / curl. Debug builds only — never in a release log.
  void _logTokenOnce() {
    if (!kDebugMode || _tokenLogged) return;
    final token = accessToken;
    if (token == null || token.isEmpty) return;
    _tokenLogged = true;
    debugPrint('[auth] Bearer $token');
  }

  /// Alias kept for startup call sites that want "a usable session".
  Future<void> ensureFreshSession() => ensureAccessToken();

  // ---------- Lifecycle ----------

  /// Loads the persisted session from secure storage. Awaited in `main()`
  /// before the first frame, so the synchronous getters are populated by the
  /// time anything reads them.
  Future<void> init() => _store.load();

  /// Decides the app's first route.
  ///
  ///  * no session → [AuthStatus.unauthenticated]
  ///  * access token expired (or about to) → refresh once. A dead refresh
  ///    token clears the session and shows Login; a network or server failure
  ///    keeps the tokens and enters the app, which recovers on the next call.
  ///  * live token → [AuthStatus.authenticated]
  ///
  /// Never throws.
  Future<AuthStatus> bootstrap() async {
    status.value = AuthStatus.bootstrapping;

    try {
      if (!isLoggedIn) {
        log('[auth-boot] no persisted session → login');
        return _setStatus(AuthStatus.unauthenticated);
      }

      if (_store.expiresWithin(_refreshLeeway)) {
        final outcome = await _refreshShared();
        if (outcome == _RefreshOutcome.dead) {
          log('[auth-boot] refresh token rejected → clearing session');
          // Cleared without [onSignedOut]: the splash is about to route to
          // Login itself, and a second navigation would race it.
          await _store.clear();
          return _setStatus(AuthStatus.unauthenticated);
        }
        log('[auth-boot] refresh $outcome → authenticated');
      }

      return _setStatus(AuthStatus.authenticated);
    } catch (e) {
      log('[auth-boot] error: ${e.runtimeType}');
      return _setStatus(
        isLoggedIn ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      );
    }
  }

  /// Refreshes the access token. Returns whether a new one was saved.
  /// Concurrent callers share one call. A dead refresh token signs out.
  Future<bool> refreshSession() async {
    if (!isLoggedIn) return false;
    final outcome = await _refreshShared();
    if (outcome == _RefreshOutcome.dead) await _endSession();
    return outcome == _RefreshOutcome.ok;
  }

  /// Best-effort refresh for the auction WebSocket on `WS_AUTH_EXPIRED`.
  Future<void> refreshSessionSafe() => refreshSession();

  /// [ApiClient] hook for a `401 AUTH_EXPIRED`: refresh once and hand back the
  /// new token for a single retry, or null when there is none.
  Future<String?> refreshForRetry() async =>
      await refreshSession() ? accessToken : null;

  Future<_RefreshOutcome> _refreshShared() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _refresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<_RefreshOutcome> _refresh() async {
    final token = refreshToken;
    if (token == null) return _RefreshOutcome.dead;

    final ApiResponse res;
    try {
      res = await ApiClient.instance.post(
        _url(_refreshPath),
        headers: _jsonHeaders,
        body: {'refreshToken': token},
        suppressAuthHandlers: true,
      );
    } catch (e) {
      log('[auth-refresh] network failure — keeping tokens');
      return _RefreshOutcome.transient;
    }

    final code = res.statusCode;
    if (res.isSuccess) {
      final data = _data(res.body);
      final access = data?['accessToken'];
      if (access is! String || access.isEmpty) {
        log('[auth-refresh] 2xx without accessToken — keeping tokens');
        return _RefreshOutcome.transient;
      }
      await _store.saveTokens(
        accessToken: access,
        refreshToken: data?['refreshToken'] as String?,
        expiresIn: (data?['expiresIn'] as num?)?.toInt(),
      );
      log('[auth-refresh] ok expiresAt=${_store.expiresAt}');
      return _RefreshOutcome.ok;
    }
    if (code == 400 || code == 401 || code == 403) {
      log('[auth-refresh] rejected ($code)');
      return _RefreshOutcome.dead;
    }
    log('[auth-refresh] transient failure ($code) — keeping tokens');
    return _RefreshOutcome.transient;
  }

  AuthStatus _setStatus(AuthStatus next) {
    if (status.value != next) status.value = next;
    return next;
  }

  // ---------- Sign-in ----------

  /// `POST /api/v1/auth/login` with `client: "mobile"` — without it the server
  /// answers as for the web (cookie, no tokens).
  ///
  /// On success the tokens are stored and, when the backend reports the
  /// Cognito identity as `unmapped`, the app profile is provisioned. The
  /// caller still has to run the seller `/me` gate.
  ///
  /// Throws [AuthApiException]. Any failure leaves no tokens behind.
  Future<void> login({required String email, required String password}) async {
    final ApiResponse res;
    try {
      res = await ApiClient.instance.post(
        _url(_loginPath),
        headers: _jsonHeaders,
        body: {'email': email, 'password': password, 'client': 'mobile'},
        suppressAuthHandlers: true,
      );
    } catch (_) {
      await _store.clear();
      throw const AuthApiException(AuthFailure.network);
    }

    final data = _data(res.body);
    final access = data?['accessToken'];
    if (!res.isSuccess || access is! String || access.isEmpty) {
      await _store.clear();
      throw _failureFor(res);
    }

    await _store.saveTokens(
      accessToken: access,
      refreshToken: data?['refreshToken'] as String?,
      expiresIn: (data?['expiresIn'] as num?)?.toInt(),
    );
    await _store.saveProfile(email: email);

    if (data?['appIdentity'] == 'unmapped') await ensureProfile();

    _setStatus(AuthStatus.authenticated);
  }

  /// Installs the session a Google / Apple [SocialAuthService] exchange
  /// produced, then provisions the app profile (idempotent, and defensive: a
  /// first-time federated user can otherwise get `AUTH_USER_NOT_FOUND` from
  /// `/me`). Its failure never blocks sign-in. The caller still has to run the
  /// seller `/me` gate — a new federated identity is only a buyer.
  Future<void> signInWithSocial(SocialAuthResult result) async {
    await _store.saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      expiresIn: result.expiresIn,
    );
    await _store.saveProfile(
      userId: result.userId,
      email: result.email,
      displayName: result.displayName,
    );
    await ensureProfile();
    _setStatus(AuthStatus.authenticated);
  }

  /// `POST /api/v1/auth/ensure-profile` — idempotent. Maps the Cognito
  /// identity onto an app user. Returns whether the profile now exists.
  Future<bool> ensureProfile() async {
    if (accessToken == null) return false;
    try {
      final res = await ApiClient.instance.post(
        _url(_ensureProfilePath),
        headers: authHeaders,
        suppressAuthHandlers: true,
      );
      log('[auth-profile] ensure-profile ${res.statusCode}');
      return res.isSuccess;
    } catch (_) {
      log('[auth-profile] ensure-profile network failure');
      return false;
    }
  }

  /// Remembers who the session belongs to, from the seller `/me` result.
  Future<void> rememberProfile({String? userId, String? displayName}) =>
      _store.saveProfile(userId: userId, displayName: displayName);

  // ---------- Password reset ----------

  /// Step 1: `POST /api/v1/buyer/auth/forgot-password`. Emails a numeric code.
  ///
  /// Anti-enumeration: a 2xx means "request accepted", not "an account
  /// exists". Throws [AuthApiException] on 429 / 5xx / network.
  Future<void> requestPasswordReset({required String email}) async {
    final ApiResponse res;
    try {
      res = await ApiClient.instance.post(
        _url(_forgotPasswordPath),
        headers: _jsonHeaders,
        body: {'email': email},
        suppressAuthHandlers: true,
      );
    } catch (_) {
      throw const AuthApiException(AuthFailure.network);
    }
    if (!res.isSuccess) throw _failureFor(res);
  }

  /// Step 2: `POST /api/v1/auth/reset-password` with the emailed code. A wrong
  /// or expired code is `400 VALIDATION_ERROR` → [AuthFailure.validation].
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final ApiResponse res;
    try {
      res = await ApiClient.instance.post(
        _url(_resetPasswordPath),
        headers: _jsonHeaders,
        body: {'email': email, 'code': code, 'newPassword': newPassword},
        suppressAuthHandlers: true,
      );
    } catch (_) {
      throw const AuthApiException(AuthFailure.network);
    }
    if (!res.isSuccess) throw _failureFor(res);
  }

  // ---------- Sign-out ----------

  /// `POST /api/v1/auth/logout`, then clears local storage whatever the
  /// result. Fires [onSignedOut].
  Future<void> logout() async {
    final token = refreshToken;
    if (token != null) {
      try {
        await ApiClient.instance
            .post(
              _url(_logoutPath),
              headers: _jsonHeaders,
              body: {'refreshToken': token},
              suppressAuthHandlers: true,
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Best-effort: the local session goes regardless.
        log('[auth-logout] server logout failed — clearing locally');
      }
    }
    await _endSession(force: true);
  }

  /// Clears the session and notifies. Idempotent, so concurrent requests that
  /// all discover a dead refresh token sign out only once.
  Future<void> _endSession({bool force = false}) async {
    if (!force && !isLoggedIn) return;
    await _store.clear();
    _setStatus(AuthStatus.unauthenticated);
    onSignedOut?.call();
  }

  // ---------- Helpers ----------

  static const Map<String, String> _jsonHeaders = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  String _url(String path) => '${EnvConfig.baseUrl}$path';

  /// `data` of a V1 `{success, data}` envelope.
  Map<String, dynamic>? _data(String raw) {
    try {
      final body = jsonDecode(raw);
      if (body is Map && body['data'] is Map) {
        return Map<String, dynamic>.from(body['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Maps a non-2xx V1 response onto an [AuthFailure]. Branches on the status
  /// and `error.code`, never on the message.
  AuthApiException _failureFor(ApiResponse res) {
    String? code;
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] is Map) {
        code = (body['error'] as Map)['code'] as String?;
      }
    } catch (_) {}

    final status = res.statusCode;
    final AuthFailure failure;
    if (status == 429 || code == 'RATE_LIMITED') {
      failure = AuthFailure.rateLimited;
    } else if (status == 401) {
      failure = AuthFailure.invalidCredentials;
    } else if (status == 403) {
      failure = AuthFailure.restricted;
    } else if (status == 400) {
      failure = AuthFailure.validation;
    } else {
      // 5xx, or a 2xx that carried no tokens.
      failure = AuthFailure.unavailable;
    }
    return AuthApiException(failure, statusCode: status, code: code);
  }
}
