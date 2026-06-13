import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_config.dart';
import 'api_client.dart';

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
        // Cold-start: the persisted session (if any) was restored.
        break;
      case AuthChangeEvent.signedIn:
        // Fresh login, or a restored session on startup.
        break;
      case AuthChangeEvent.tokenRefreshed:
        // Access token silently refreshed + refresh token rotated. Nothing to
        // do: the next authHeaders read already carries the new token.
        break;
      case AuthChangeEvent.userUpdated:
        // User metadata/email changed — currentUser is already updated.
        break;
      case AuthChangeEvent.signedOut:
        onSignedOut?.call();
        break;
      default:
        // passwordRecovery, mfaChallengeVerified, etc. — not used here.
        break;
    }
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
