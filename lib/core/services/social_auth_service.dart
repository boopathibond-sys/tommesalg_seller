import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState;
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env_config.dart';
import '../localization/translation_keys.dart';

enum SocialProvider { google, apple }

/// A Google / Apple sign-in that did not produce a session. [message] is
/// already localized; [cancelled] means the user backed out — show nothing.
class SocialAuthException implements Exception {
  const SocialAuthException(this.message, {this.cancelled = false});

  final String message;
  final bool cancelled;

  @override
  String toString() => 'SocialAuthException(cancelled: $cancelled)';
}

/// The tokens and identity a successful exchange hands back. Never log it.
class SocialAuthResult {
  const SocialAuthResult({
    required this.provider,
    required this.accessToken,
    required this.refreshToken,
    this.expiresIn,
    this.userId,
    this.email,
    this.displayName,
  });

  final SocialProvider provider;
  final String accessToken;
  final String refreshToken;
  final int? expiresIn;

  /// App user id (`users.id`) — never the Cognito `sub`.
  final String? userId;
  final String? email;
  final String? displayName;
}

/// "Continue with Google / Apple" through the backend's Cognito Hosted UI.
/// See `lib/raw/GOOGLE_APPLE_SIGN_IN_IMPLEMENTATION.md`.
///
/// There is no native ID-token API: the authorize URL opens in the OS auth
/// browser (iOS `ASWebAuthenticationSession` over a method channel, Android a
/// Custom Tab), the backend deep-links back with a one-time `code`, and
/// `POST /api/auth/cognito/mobile-exchange` swaps it for Cognito tokens.
/// Storing those and the seller gate are [AuthService]'s and the caller's job.
///
/// Deliberately does not go through [ApiClient]: that client logs every body,
/// and the exchange response carries the refresh token.
class SocialAuthService {
  SocialAuthService({AppLinks? appLinks, http.Client? client})
      : _appLinks = appLinks ?? AppLinks(),
        _client = client ?? http.Client();

  final AppLinks _appLinks;
  final http.Client _client;

  // ── Callback deep link ─────────────────────────────────────────────────
  // The same return URL as the buyer app (`no.tommesalg.buyer://auth/vipps/
  // google|apple`): it is the only prefix production's
  // MOBILE_AUTH_DEEP_LINK_PREFIXES allows today — a seller-specific one
  // (`tommesalgseller://auth/`) gets `400 invalid_redirect` (guide §1).
  //
  //  * iOS: ASWebAuthenticationSession catches the return inside its own
  //    session, so nothing is registered in Info.plist and the buyer app's
  //    own links are untouched.
  //  * Android: the intent-filter matches only `/vipps/google` and
  //    `/vipps/apple`, never the buyer's Vipps return. With both apps
  //    installed, Android asks which app opens a Google / Apple return.
  //
  // Swap all three constants (and the Android filter) for a seller scheme once
  // the backend allowlists one.
  static const String _callbackScheme = 'no.tommesalg.buyer';
  static const String _callbackHost = 'auth';
  static const String _callbackPrefix = '/vipps';
  static const MethodChannel _webAuth =
      MethodChannel('com.tommesalg.seller/web_auth');
  // ───────────────────────────────────────────────────────────────────────

  static const String _authorizePath = '/api/auth/cognito/authorize';
  static const String _exchangePath = '/api/auth/cognito/mobile-exchange';
  static const String _kPending = 'social_auth.pending';
  static const Duration _pendingTtl = Duration(minutes: 5);

  static String get _origin => EnvConfig.baseUrl;

  static String _redirectFor(SocialProvider p) =>
      '$_callbackScheme://$_callbackHost$_callbackPrefix/${p.name}';

  /// Case-sensitive — `Apple` is `400 unsupported_identity_provider`.
  static String _idp(SocialProvider p) =>
      p == SocialProvider.google ? 'Google' : 'SignInWithApple';

  static SocialAuthException get _failed =>
      SocialAuthException(TKeys.authSocialFailed.tr);
  static SocialAuthException get _cancelled =>
      const SocialAuthException('', cancelled: true);

  Future<SocialAuthResult> signIn(SocialProvider provider) async {
    final authUrl =
        Uri.parse('$_origin$_authorizePath').replace(queryParameters: {
      'identity_provider': _idp(provider),
      'mobile': '1',
      'redirect': _redirectFor(provider),
      'mode': 'login',
    });

    final startUrl = _withAccountChooser(provider, await _preflight(authUrl));

    final callback = Platform.isIOS
        ? await _authenticateIos(startUrl)
        : await _authenticateAndroid(provider, startUrl);

    final error = callback.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      final e = error.toLowerCase();
      if (e.contains('cancel') || e.contains('access_denied')) throw _cancelled;
      final description = callback.queryParameters['error_description'] ?? '';
      // The real reason (`code_exchange_failed`, …) — debug builds only.
      if (kDebugMode) {
        log('[social-auth] callback error=$error description=$description');
      }
      // The email already has a password account the backend won't link to
      // this Google / Apple identity. The callback carries no code for it, so
      // the description is all there is to go on.
      if (description.toLowerCase().contains('already exists')) {
        throw SocialAuthException(TKeys.authSocialAccountExists.tr);
      }
      throw _failed;
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) throw _failed;
    return _exchange(provider, code);
  }

  /// Asks the authorize route first so its JSON errors become a message
  /// instead of a raw JSON page in the browser. A 3xx means go ahead; the
  /// redirect it minted simply expires unused.
  ///
  /// Returns the URL to open in the auth browser: the authorize route's own
  /// redirect (the Cognito `/oauth2/authorize` URL carrying the `state` the
  /// backend just stored server-side — no cookie binds it to a browser), or
  /// [authUrl] itself when the redirect is missing.
  Future<Uri> _preflight(Uri authUrl) async {
    final http.Response res;
    try {
      final request = http.Request('GET', authUrl)..followRedirects = false;
      res = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 30)),
      );
    } catch (_) {
      throw SocialAuthException(TKeys.authNetworkError.tr);
    }
    final s = res.statusCode;
    if (s >= 300 && s < 400) {
      final location = res.headers['location'];
      final next = location == null ? null : Uri.tryParse(location);
      return next != null && next.hasScheme ? next : authUrl;
    }

    final err = _decode(res.body)?['error'];
    if (kDebugMode) log('[social-auth] authorize $s error=$err');
    throw s == 503 || err == 'mobile_auth_unavailable'
        ? SocialAuthException(TKeys.authTemporarilyUnavailable.tr)
        : _failed;
  }

  /// Makes Google show its "Choose an account" list (the accounts signed in
  /// to the browser — on Android, Chrome's, which are the phone's Google
  /// accounts) instead of silently reusing the last one.
  ///
  /// Cognito forwards `prompt=select_account` to Google, but the backend's
  /// authorize route doesn't pass `prompt` on, so it's added to the Cognito
  /// URL the preflight returned. Only that exact Cognito endpoint is touched;
  /// anything else opens unchanged.
  static Uri _withAccountChooser(SocialProvider provider, Uri url) {
    if (provider != SocialProvider.google) return url;
    if (!url.host.endsWith('.amazoncognito.com') ||
        url.path != '/oauth2/authorize') {
      return url;
    }
    return url.replace(queryParameters: {
      ...url.queryParameters,
      'prompt': 'select_account',
    });
  }

  Future<Uri> _authenticateIos(Uri authUrl) async {
    try {
      final result = await _webAuth.invokeMethod<String>('authenticate', {
        'url': authUrl.toString(),
        'callbackScheme': _callbackScheme,
      });
      final uri = result == null ? null : Uri.tryParse(result);
      if (uri == null || !_isOurCallback(uri)) throw _failed;
      return uri;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') throw _cancelled;
      throw _failed;
    }
  }

  Future<Uri> _authenticateAndroid(SocialProvider provider, Uri authUrl) async {
    final completer = Completer<Uri>();
    // Subscribed before launching, or a fast return is missed.
    final sub = _appLinks.uriLinkStream.listen((uri) {
      if (_isOurCallback(uri) && !completer.isCompleted) completer.complete(uri);
    }, onError: (Object e) {
      if (!completer.isCompleted) completer.completeError(_failed);
    });

    // Closing the Custom Tab resumes the app without a link: give a real
    // callback 3 s to arrive, then treat it as a cancel.
    Timer? grace;
    final lifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state != AppLifecycleState.resumed) return;
      grace?.cancel();
      grace = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) completer.completeError(_cancelled);
      });
    });

    await _markPending(provider);
    try {
      var ok = await launchUrl(authUrl, mode: LaunchMode.inAppBrowserView);
      if (!ok) ok = await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      if (!ok) throw SocialAuthException(TKeys.authSocialNoBrowser.tr);
      try {
        return await completer.future.timeout(_pendingTtl);
      } on TimeoutException {
        throw _cancelled;
      }
    } finally {
      grace?.cancel();
      lifecycle.dispose();
      await sub.cancel();
      await _clearPending();
    }
  }

  /// `POST /api/auth/cognito/mobile-exchange` — one attempt only: the code is
  /// single-use and lives 60 s. Flat snake_case JSON, no V1 envelope.
  Future<SocialAuthResult> _exchange(SocialProvider provider, String code) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$_origin$_exchangePath'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'code': code}),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      // The code is burnt either way — the user starts over.
      throw SocialAuthException(TKeys.authTemporarilyUnavailable.tr);
    }

    final s = res.statusCode;
    final body = _decode(res.body);
    if (s < 200 || s >= 300 || body == null) {
      if (kDebugMode) log('[social-auth] exchange $s error=${body?['error']}');
      if (s == 400 || s == 410) {
        throw SocialAuthException(TKeys.authSocialCodeExpired.tr);
      }
      if (s == 429) {
        final retry = res.headers['retry-after'];
        throw SocialAuthException(retry == null
            ? TKeys.authTooManyAttempts.tr
            : TKeys.authSocialRetryIn.trParams({'seconds': retry}));
      }
      if (s >= 500) {
        throw SocialAuthException(TKeys.authTemporarilyUnavailable.tr);
      }
      throw _failed;
    }

    final access = body['access_token'];
    final refresh = body['refresh_token'];
    if (access is! String || access.isEmpty ||
        refresh is! String || refresh.isEmpty) {
      throw _failed;
    }
    final user = body['user'] is Map
        ? Map<String, dynamic>.from(body['user'] as Map)
        : const <String, dynamic>{};

    return SocialAuthResult(
      provider: provider,
      accessToken: access,
      refreshToken: refresh,
      expiresIn: (body['expires_in'] as num?)?.toInt(),
      userId: user['id'] as String?,
      email: user['email'] as String?,
      displayName: user['name'] as String?,
    );
  }

  // ── Android cold start ─────────────────────────────────────────────────

  /// Finishes a sign-in whose Custom Tab outlived the app process: the return
  /// link cold-starts the app with no listener alive. Only honoured while a
  /// fresh "pending" marker exists, so an unsolicited link can't sign anyone
  /// in. Call once from the splash, before the session check. Never throws.
  static Future<SocialAuthResult?> completeColdStartCallback() async {
    if (!Platform.isAndroid) return null;
    try {
      final provider = await _takePending();
      if (provider == null) return null;
      final service = SocialAuthService();
      final initial = await service._appLinks.getInitialLink();
      if (initial == null || !service._isOurCallback(initial)) return null;
      final code = initial.queryParameters['code'];
      if (code == null || code.isEmpty) return null;
      return await service._exchange(provider, code);
    } catch (_) {
      return null;
    }
  }

  /// `"<provider>|<startMillis>"` — never the code.
  static Future<void> _markPending(SocialProvider p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kPending, '${p.name}|${DateTime.now().millisecondsSinceEpoch}');
  }

  static Future<void> _clearPending() async =>
      (await SharedPreferences.getInstance()).remove(_kPending);

  static Future<SocialProvider?> _takePending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPending);
    await prefs.remove(_kPending);
    if (raw == null) return null;
    final parts = raw.split('|');
    final started = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (started == null) return null;
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(started));
    if (age.isNegative || age > _pendingTtl) return null;
    for (final p in SocialProvider.values) {
      if (p.name == parts[0]) return p;
    }
    return null;
  }

  bool _isOurCallback(Uri uri) =>
      uri.scheme == _callbackScheme &&
      uri.host == _callbackHost &&
      SocialProvider.values
          .any((p) => uri.path == '$_callbackPrefix/${p.name}');

  static Map<String, dynamic>? _decode(String raw) {
    try {
      final body = jsonDecode(raw);
      return body is Map<String, dynamic> ? body : null;
    } catch (_) {
      return null;
    }
  }
}
