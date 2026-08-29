import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_config.dart';
import 'api_client.dart';

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

/// Thin façade over `supabase_flutter`'s auth client.
///
/// The rest of the app reads [authHeaders] / [accessToken] / [isLoggedIn]
/// synchronously to authorize calls to our own backend with the Supabase JWT.
/// We keep those getters synchronous and let the SDK do the heavy lifting:
///
///  * Session persistence — `Supabase.initialize()` writes the session to disk
///    and restores it on the next cold start, so [currentUser] / [session] are
///    already populated by the time [init] runs.
///  * Token refresh — the SDK refreshes the access token in the background
///    before it expires (and on app resume) and rotates the refresh token.
///    We deliberately add NO manual refresh logic.
///
/// Because the SDK keeps [session] fresh, every read of [accessToken] returns a
/// valid token, so the existing `authHeaders` call sites keep working
/// unchanged.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Path on the buyer backend that triggers the Supabase recovery email.
  /// The backend owns the redirect URL + service secret, so this stays a
  /// dumb `{email}` POST. The same endpoint serves the seller flow.
  static const String forgotPasswordPath = '/api/v1/buyer/auth/forgot-password';

  GoTrueClient get _auth => Supabase.instance.client.auth;

  StreamSubscription<AuthState>? _sub;

  /// Where startup / the current session stands. Starts at
  /// [AuthStatus.bootstrapping] so nothing can route to Login before
  /// [bootstrap] has run, and is kept in step with every SDK auth event.
  final ValueNotifier<AuthStatus> status =
      ValueNotifier<AuthStatus>(AuthStatus.bootstrapping);

  /// Dedupes concurrent refreshes — two in flight would race over the same
  /// (rotating) refresh token and one would lose.
  Future<bool>? _refreshInFlight;

  /// Invoked whenever the user ends up fully signed out — either a manual
  /// logout or because the refresh token was revoked/expired and the SDK could
  /// not refresh. Wire this in `main()` to bounce back to the login screen.
  /// These are the ONLY cases that should log the user out (keep-login goal).
  void Function()? onSignedOut;

  // ---------- Synchronous session façade ----------

  Session? get session => _auth.currentSession;
  User? get currentUser => _auth.currentUser;

  String? get accessToken => session?.accessToken;
  String? get refreshToken => session?.refreshToken;
  Map<String, dynamic>? get user => currentUser?.toJson();

  /// `true` while a session exists. Survives app restarts (persisted by the
  /// SDK) and only flips to `false` on sign-out — never on access-token expiry,
  /// because the SDK refreshes silently.
  bool get isLoggedIn => session != null;

  Map<String, String> get authHeaders => {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

  /// Like [authHeaders] but guarantees the `Authorization` header is present
  /// whenever a session exists.
  ///
  /// The SDK briefly clears [session] while it rotates tokens — e.g. the WS
  /// auth-refresh fired on entering the auction room. Reading [authHeaders]
  /// synchronously in that window yields **no** `Authorization` header and the
  /// backend rejects the call with `AUTH_MISSING_TOKEN`. This awaits any
  /// in-flight rotation (and forces one as a last resort) so live-room calls
  /// always carry the bearer token.
  Future<Map<String, String>> ensuredAuthHeaders() async {
    await ensureAccessToken();
    return authHeaders;
  }

  /// Returns a non-null access token when a session exists, waiting out a
  /// transient token rotation before forcing a refresh. See [ensuredAuthHeaders].
  Future<String?> ensureAccessToken() async {
    if (accessToken != null) return accessToken;
    // Give an in-flight rotation (started elsewhere, e.g. the WS layer) a brief
    // window to repopulate the session before we trigger our own refresh — two
    // concurrent refreshes would fight over the refresh token.
    for (var i = 0; i < 20 && accessToken == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (accessToken == null) {
      await refreshSessionSafe();
    }
    return accessToken;
  }

  /// Waits until the restored session is actually usable, refreshing it when
  /// the persisted access token has already expired.
  ///
  /// A cold start after the token's lifetime (~1 h) restores a session whose
  /// token is expired; the SDK refreshes it in the background, but a request
  /// fired before that lands carries the stale token and comes back
  /// `AUTH_EXPIRED` — which [ApiClient.onSessionExpired] turns into a bounce to
  /// the login screen. Anything that hits the API immediately on startup should
  /// await this first. No-op when there is no session, or the token is valid.
  Future<void> ensureFreshSession() async {
    final current = session;
    if (current == null) return;
    if (current.isExpired) {
      await refreshSessionSafe();
      return;
    }
    await ensureAccessToken();
  }

  // ---------- Lifecycle ----------

  /// Subscribes to auth-state events. Session restoration already happened
  /// inside `Supabase.initialize()` (awaited in `main()`), so there is nothing
  /// to load here — we only attach the listener.
  Future<void> init() async {
    _sub ??= _auth.onAuthStateChange.listen(_onAuthStateChange);
  }

  /// Handles the auth events. Most need no action because the synchronous
  /// getters above always reflect the current session; we log them for
  /// observability and only react to a real sign-out.
  void _onAuthStateChange(AuthState state) {
    final event = state.event;
    log('Supabase auth event: $event');

    switch (event) {
      case AuthChangeEvent.initialSession:
        // Cold-start: the persisted session (if any) was restored. [bootstrap]
        // makes the routing decision; this only reflects what arrived.
        if (state.session != null) _setStatus(AuthStatus.authenticated);
        break;
      case AuthChangeEvent.signedIn:
        // Fresh login, or a restored session on startup.
        _setStatus(AuthStatus.authenticated);
        break;
      case AuthChangeEvent.tokenRefreshed:
        // Access token silently refreshed + refresh token rotated. Nothing to
        // do beyond staying authenticated: the next authHeaders read already
        // carries the new token.
        _setStatus(AuthStatus.authenticated);
        break;
      case AuthChangeEvent.userUpdated:
        // User metadata/email changed — currentUser is already updated.
        break;
      case AuthChangeEvent.signedOut:
        _setStatus(AuthStatus.unauthenticated);
        onSignedOut?.call();
        break;
      default:
        // passwordRecovery, mfaChallengeVerified, etc. — not used here.
        break;
    }
  }

  /// Decides the app's first route: the whole of the doc's startup workflow in
  /// one call.
  ///
  /// `Supabase.initialize()` (awaited in `main()`) has already restored any
  /// persisted session, so this only has to judge whether that session is
  /// *usable*:
  ///
  ///  * no session → [AuthStatus.unauthenticated]
  ///  * session with an expired access token → refresh once; a success keeps
  ///    the seller in, a failure means the refresh token was revoked or
  ///    expired, so the dead session is cleared and Login is shown
  ///  * live session → [AuthStatus.authenticated]
  ///
  /// Never throws: any unexpected failure resolves to unauthenticated, because
  /// the safe fallback is asking for credentials, not entering the app with a
  /// session we can't vouch for.
  Future<AuthStatus> bootstrap() async {
    status.value = AuthStatus.bootstrapping;

    try {
      final current = session;
      if (current == null) {
        log('[auth-boot] no persisted session → login');
        return _setStatus(AuthStatus.unauthenticated);
      }

      log('[auth-boot] restored session for ${_redactedUser()} '
          'expiresAt=${current.expiresAt} expired=${current.isExpired}');

      if (current.isExpired) {
        final refreshed = await refreshSession();
        if (!refreshed || session == null) {
          log('[auth-boot] refresh failed → clearing session, showing login');
          // Leaves nothing half-alive on disk: the next launch starts clean
          // rather than restoring the same dead session.
          await logout();
          return _setStatus(AuthStatus.unauthenticated);
        }
        log('[auth-boot] token refreshed → authenticated');
        return _setStatus(AuthStatus.authenticated);
      }

      // Live token, but the SDK can still be mid-rotation — make sure a bearer
      // token is actually readable before anything fires a request.
      await ensureAccessToken();
      return _setStatus(
        accessToken == null
            ? AuthStatus.unauthenticated
            : AuthStatus.authenticated,
      );
    } catch (e) {
      log('[auth-boot] error: $e');
      return _setStatus(
        isLoggedIn ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      );
    }
  }

  /// Refreshes the access token using the persisted refresh token. Returns
  /// whether a usable session came back. Concurrent callers share one call.
  Future<bool> refreshSession() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _refresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _refresh() async {
    try {
      final result = await _auth.refreshSession();
      final ok = result.session != null;
      log('[auth-refresh] ${ok ? 'ok' : 'no session returned'}'
          '${ok ? ' expiresAt=${result.session?.expiresAt}' : ''}');
      return ok;
    } catch (e) {
      log('[auth-refresh] failed: $e');
      return false;
    }
  }

  /// What to do when our backend answers `401 AUTH_EXPIRED`.
  ///
  /// A 401 is not proof the seller has to sign in again — the access token may
  /// simply have aged out while the refresh token is still good. So try one
  /// refresh first and only sign out when that fails, which is the difference
  /// between a silent recovery and kicking someone out of a live auction.
  Future<void> recoverOrLogout() async {
    if (session == null) return;

    final refreshed = await refreshSession();
    if (refreshed && session != null) {
      log('[auth-401] recovered by refresh — staying signed in');
      return;
    }

    log('[auth-401] refresh failed — signing out');
    await logout();
  }

  AuthStatus _setStatus(AuthStatus next) {
    if (status.value != next) status.value = next;
    return next;
  }

  /// `se***@tommesalg.no` — enough to tell accounts apart in a log without
  /// printing the address (and never the token).
  String _redactedUser() {
    final email = currentUser?.email;
    if (email == null || email.isEmpty) return currentUser?.id ?? 'unknown';
    final at = email.indexOf('@');
    if (at <= 2) return '***${email.substring(at == -1 ? 0 : at)}';
    return '${email.substring(0, 2)}***${email.substring(at)}';
  }

  // ---------- Intents ----------

  /// Email/password sign-in. The SDK persists the session and schedules the
  /// first refresh automatically.
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _auth.signInWithPassword(email: email, password: password);
  }

  // ---------- Email code (OTP) sign-in ----------

  /// Sends a 6-digit one-time code to [email].
  ///
  /// `shouldCreateUser: false` is deliberate: the Seller app never signs
  /// anyone up — accounts are created after business approval — so an unknown
  /// address must fail rather than silently provision a user. Supabase answers
  /// that case with an `AuthException` ("Signups not allowed for otp").
  ///
  /// Requires the Supabase **Magic Link** email template to include
  /// `{{ .Token }}`; without it the recipient gets a link and no code to type.
  Future<void> sendEmailOtp({required String email}) {
    return _auth.signInWithOtp(email: email, shouldCreateUser: false);
  }

  /// Exchanges the emailed [token] for a real session. On success the SDK
  /// persists it and starts auto-refresh, exactly as after a password login.
  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) {
    return _auth.verifyOTP(type: OtpType.email, email: email, token: token);
  }

  // ---------- Password reset (step 1: request the email) ----------

  /// Kicks off the password-reset flow by POSTing `{email}` to the buyer
  /// backend, which triggers Supabase's `resetPasswordForEmail` with the
  /// correct mobile redirect URL server-side.
  ///
  /// The backend is **anti-enumeration**: a 2xx with `success: true` means
  /// "request accepted", NOT "an account exists". Callers must surface a
  /// generic message either way.
  ///
  /// Surfaces: 429 -> "too many attempts"; other non-2xx -> the server's
  /// `error.message` if present, else a generic HTTP error. Network failures
  /// throw with the underlying message.
  ///
  /// [ApiClient] is the project's equivalent of a Dio client with
  /// `validateStatus: (_) => true` — it returns the status code on 4xx
  /// instead of throwing, so 4xx stays part of the contract here.
  Future<void> sendPasswordResetEmail({required String email}) async {
    final base = EnvConfig.buyerBaseUrl.isNotEmpty
        ? EnvConfig.buyerBaseUrl
        : EnvConfig.baseUrl;
    final url = '$base$forgotPasswordPath';

    final ApiResponse res;
    try {
      res = await ApiClient.instance.post(
        url,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: {'email': email},
      );
    } catch (e) {
      throw Exception('Network error. Please try again.');
    }

    final status = res.statusCode;
    final body = _tryDecode(res.body);

    if (status >= 200 && status < 300) {
      // 2xx with or without a `success: true` envelope — both mean accepted.
      return;
    }
    if (status == 429) {
      throw Exception(
        'Too many password-reset requests. Please try again in a few minutes.',
      );
    }
    throw Exception(_readableError(body, status));
  }

  /// Pulls a human-readable message out of an error envelope, falling back to
  /// a generic HTTP message. Mirrors the backend's `{error: {message}}` shape
  /// with `{message}` / `{error_description}` fallbacks.
  String _readableError(dynamic body, int status) {
    if (body is Map) {
      final err = body['error'];
      if (err is Map &&
          err['message'] is String &&
          (err['message'] as String).isNotEmpty) {
        return err['message'] as String;
      }
      final top = body['message'] ?? body['error_description'];
      if (top is String && top.isNotEmpty) return top;
    }
    return 'Request failed (HTTP $status).';
  }

  dynamic _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  // ---------- Password reset (step 2: recovery session + new password) ----------

  /// Installs the recovery session carried in the deep-link tokens so the
  /// subsequent [updatePassword] call is authorized. supabase_flutter's
  /// `setSession` exchanges the refresh token for a live session.
  Future<void> setRecoverySession(String refreshToken) =>
      _auth.setSession(refreshToken);

  /// Sets the new password on the recovery-authenticated user.
  Future<void> updatePassword(String password) =>
      _auth.updateUser(UserAttributes(password: password));

  /// Forces a Supabase token refresh (best-effort). The SDK normally refreshes
  /// silently, but the auction WebSocket calls this on a `WS_AUTH_EXPIRED` push
  /// to guarantee a fresh `access_token` before reconnecting. Errors are
  /// swallowed — the caller falls back to the reconnect/backoff path.
  Future<void> refreshSessionSafe() => refreshSession();

  /// Signs out locally and clears the persisted session. Emits `signedOut`,
  /// which fires [onSignedOut].
  Future<void> logout() => _auth.signOut();

  /// Cancels the auth-state subscription (call only if you ever tear down the
  /// singleton — normally lives for the whole app).
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
