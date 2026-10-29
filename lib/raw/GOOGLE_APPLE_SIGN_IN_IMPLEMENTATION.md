# Google & Apple Sign-In — Implementation Guide (for a second app on the same API)

**Status:** Taken from the Tømmesalg **Buyer** app (`no.tommesalg.buyer`), where Google sign-in works end to end in production.
**Use it to:** add "Continue with Google" and "Continue with Apple" to another Flutter app (Seller app, etc.) that talks to the same backend (`https://tommesalg.no`, staging `https://staging.tommesalg.no`).
**Authoritative backend contract:** `Tommesalg_Mobile_Google_Apple_Auth_Integration_Guide.docx` (same folder). This file turns that contract into working code and adds what we found by probing the live backend.

> ⚠️ **Read §1 first.** Two backend items block a new app until the backend team acts on them.

---

## 0. TL;DR

- There is **no native ID-token API**. Do **not** use `google_sign_in` or `sign_in_with_apple` to get an ID token and POST it anywhere. Do **not** use Supabase, which is gone.
- Both providers use the **same browser round-trip** through the backend's Cognito Hosted UI:

```text
Tap button
  → open  GET /api/auth/cognito/authorize?identity_provider=Google|SignInWithApple&mobile=1&redirect=<deep link>&mode=login
          in the OS auth browser (iOS: ASWebAuthenticationSession · Android: Custom Tab)
  → Cognito ↔ Google/Apple ↔ backend /api/auth/cognito/callback   (no app involvement)
  → deep link back:  <scheme>://auth/...?code=<one-time code>   (or ?error=…)
  → POST /api/auth/cognito/mobile-exchange {"code": "..."}   — ONCE, within 60 s
  → save access/refresh tokens (secure storage)
  → POST /api/v1/auth/ensure-profile   (Bearer, empty body, idempotent)
  → GET  /api/v1/auth/me               (Buyer)   or   GET /api/v1/seller/auth/me   (Seller)
  → home
```

- The provider names are case-sensitive: `Google` and `SignInWithApple`. `Apple` → `400 unsupported_identity_provider`.
- The exchange response is **flat snake_case JSON** and has **no** `{success, data}` envelope. Every `/api/v1/...` route uses the V1 envelope.

---

## 1. Backend prerequisites (ask the backend team BEFORE coding)

| # | What | Why |
|---|------|-----|
| 1 | **Allowlist the new app's deep-link prefix** in `MOBILE_AUTH_DEEP_LINK_PREFIXES` (e.g. `no.tommesalg.seller://auth/`). | The authorize route rejects any redirect that isn't allowlisted: `400 {"error":"invalid_redirect","reason":"redirect_not_allowed"}`. Production today accepts **only** `no.tommesalg.buyer://auth/vipps…`, which is why the buyer app uses `…://auth/vipps/google` and `…://auth/vipps/apple` as a workaround. Ask for the exact approved value and do **not** invent one. |
| 2 | **Fix Apple on the backend callback.** | Apple currently comes back as `…?error=auth_failed&error_description=code_exchange_failed`. Apple and Cognito succeed, and the failure is in `/api/auth/cognito/callback`. The likely cause is Apple claims (missing `name`/`email_verified`, a relay e-mail, `email_verified` as the string `"true"`). See `BACKEND_CHANGES_NEEDED.md` §1. The buyer app hides its Apple button until this is fixed. |
| 3 | Confirm that the Google and Apple IdPs are enabled on the **Cognito app client** for the environment you test (staging vs production). | — |

The Flutter app **never** needs Google/Apple client secrets, a `.p8` key, a Cognito secret or AWS credentials. It also needs **no** Google OAuth iOS/Android client, `GIDClientID`, SHA-1 or `serverClientId`. Those belong to the old native flow and are obsolete.

---

## 2. Dependencies

```yaml
dependencies:
  dio: ^5.4.3+1
  app_links: ^6.3.2            # Android deep-link return + cold start
  url_launcher: ^6.3.0         # Android Custom Tab
  shared_preferences: ^2.2.3   # Android "pending sign-in" marker
  flutter_secure_storage: ^9.2.4
```

iOS needs no plugin. A ~60-line `ASWebAuthenticationSession` method channel (§5) does the job.

---

## 3. API contract

### 3.1 Authorize (opened in the browser, not called with Dio)

```
GET {ORIGIN}/api/auth/cognito/authorize
    ?identity_provider=Google          (or SignInWithApple)
    &mobile=1
    &redirect=<allowlisted deep link, URL-encoded>
    &mode=login                        (signup also allowed; same path)
```

| Response | Meaning | App action |
|---|---|---|
| 302/307 → Cognito | OK | open in browser |
| 400 `unsupported_identity_provider` | wrong provider string | developer bug |
| 400 `invalid_redirect` | deep link not allowlisted | backend allowlist (§1) |
| 503 `mobile_auth_unavailable` | OAuth state store (Redis) down | "temporarily unavailable" toast |

**Preflight tip:** these errors come back as raw JSON. If you open the URL straight in the browser, the user sees JSON. The buyer app first does a `GET` with `followRedirects: false`: a 3xx means go ahead, anything else is mapped to a localized error. The redirect it mints just expires unused.

### 3.2 Deep-link return

```
<scheme>://auth/<path>?code=<opaque one-time code>
<scheme>://auth/<path>?error=<code>&error_description=<reason>
```

- `error` containing `cancel` or `access_denied` means the user backed out. Stay silent.
- Anything else (`auth_failed`, …) shows a generic "sign-in failed" message. Log `error_description` in debug builds **only**, because it holds the real reason (`code_exchange_failed`, …).

### 3.3 Exchange — `POST {ORIGIN}/api/auth/cognito/mobile-exchange`

Request: `{"code": "<code>"}`. The code is **single use** and lives for **60 s**. Never retry it, never persist it, never log it.

Success (flat, no envelope):
```json
{
  "access_token": "…",
  "refresh_token": "…",
  "expires_in": 3600,
  "user": { "id": "<APP_USER_UUID>", "name": "Alex", "email": "alex@example.com", "phone": null, "verified": true },
  "needs_profile_completion": false
}
```

- Use `user.id` (or later `/me.data.id`) as the user id. **Never** use the Cognito `sub`.
- There is **no** `appIdentity` field here. That field only exists on password `/api/v1/auth/login`.

Errors (top-level `{"error": "…"}`):

| Status | Body | App action |
|---|---|---|
| 400 | `missing_code` / `invalid_code` | "code expired, try again" → new browser sign-in |
| 410 | `invalid_code` (replayed) | same, never resend the code |
| 429 | `rate_limited` + `Retry-After` | show "try again in N s" |
| 5xx / network | — | "temporarily unavailable"; the code is burnt, so the user starts over |

### 3.4 After the exchange (V1 envelope, `Authorization: Bearer <access_token>`)

| Call | Notes |
|---|---|
| `POST /api/v1/auth/ensure-profile` (no body) | Idempotent. Returns `data.created: true\|false`. Call it once, defensively: the callback normally provisions the profile, but without it a first-time user can get `401 AUTH_USER_NOT_FOUND` from `/me`. **Mobile uses this `/api/v1` route.** The cookie route `/api/auth/ensure-profile` is web only. |
| `GET /api/v1/auth/me` (Buyer) / `GET /api/v1/seller/auth/me` (Seller) | The role gate. A new federated identity is provisioned as a **buyer**. Signing in on the Seller app does **not** grant the seller role, so the Seller app must handle "not a seller" (e.g. send the user to onboarding or sign them out). |
| `POST /api/v1/auth/refresh` `{"refreshToken": "…"}` | Same refresh as password login. Share one in-flight refresh. Only 400/401/403 mean "signed out"; offline and 5xx must **not** wipe the session. |
| `POST /api/v1/auth/logout` `{"refreshToken": "…"}` | Always clear local tokens, even if this call fails. Nothing provider-side lives on the device, so there is no Google/Apple sign-out. |

If `/me` still returns `AUTH_USER_NOT_FOUND` **after** a successful ensure-profile, sign the user out. Don't loop.

---

## 4. Choose your deep link

Use a custom scheme equal to your **bundle id / package**. For example, the Seller app would use:

```
no.tommesalg.seller://auth/google
no.tommesalg.seller://auth/apple
```

…or whatever path the backend actually allowlists (§1). The code below keeps scheme, host and path prefix in three constants, so a later change is a one-line edit.

---

## 5. iOS — `ASWebAuthenticationSession` channel

### 5.1 `ios/Runner/AppDelegate.swift`

```swift
import UIKit
import Flutter
import AuthenticationServices

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var webAuth: WebAuthSession?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let authChannel = FlutterMethodChannel(
        name: "<YOUR_BUNDLE_ID>/web_auth",          // e.g. no.tommesalg.seller/web_auth
        binaryMessenger: controller.binaryMessenger
      )
      let auth = WebAuthSession(anchor: { [weak self] in self?.window })
      webAuth = auth
      authChannel.setMethodCallHandler { call, result in
        auth.handle(call: call, result: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// Dart: authenticate({url, callbackScheme}) → callback URL string,
/// or FlutterError code CANCELED | BUSY | FAILED.
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
  private let anchor: () -> UIWindow?
  private var session: ASWebAuthenticationSession?

  init(anchor: @escaping () -> UIWindow?) { self.anchor = anchor }

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "authenticate" else { result(FlutterMethodNotImplemented); return }
    guard let args = call.arguments as? [String: Any],
          let urlString = args["url"] as? String,
          let url = URL(string: urlString),
          let scheme = args["callbackScheme"] as? String else {
      result(FlutterError(code: "FAILED", message: "bad arguments", details: nil)); return
    }
    if session != nil { result(FlutterError(code: "BUSY", message: nil, details: nil)); return }

    let authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) {
      [weak self] callback, error in
      DispatchQueue.main.async {
        self?.session = nil
        if let callback = callback {
          result(callback.absoluteString)
        } else if let error = error as? ASWebAuthenticationSessionError,
                  error.code == .canceledLogin {
          result(FlutterError(code: "CANCELED", message: nil, details: nil))
        } else {
          result(FlutterError(code: "FAILED", message: error?.localizedDescription, details: nil))
        }
      }
    }
    authSession.presentationContextProvider = self
    // Share Safari cookies so users already signed in to Google/Apple skip the password.
    authSession.prefersEphemeralWebBrowserSession = false
    session = authSession
    if !authSession.start() {
      session = nil
      result(FlutterError(code: "FAILED", message: "could not start", details: nil))
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    anchor() ?? ASPresentationAnchor()
  }
}
```

### 5.2 `ios/Runner/Info.plist`

Register the scheme. Append to the existing `CFBundleURLTypes`; do not replace it:

```xml
<dict>
  <key>CFBundleTypeRole</key><string>Editor</string>
  <key>CFBundleURLSchemes</key>
  <array><string>no.tommesalg.seller</string></array>
</dict>
```

`ASWebAuthenticationSession` catches the return itself, so the delegate never sees it. Registering the scheme still keeps cold-start and Universal-Link behavior predictable.

- You need **no** "Sign in with Apple" capability or entitlement, because Apple runs on the web inside the session. (Keep the capability if the app has it for other reasons; it does no harm.)
- iOS cancel is reliable (`CANCELED`), and there is no process-death problem: the session lives inside your app.

---

## 6. Android — Custom Tab + `app_links`

### 6.1 `android/app/src/main/AndroidManifest.xml`

```xml
<!-- launchMode singleTop/singleTask: the return must reach the SAME activity -->
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTop"
    ...>

    <!-- Google / Apple sign-in return: <scheme>://auth/... -->
    <intent-filter>
        <action android:name="android.intent.action.VIEW"/>
        <category android:name="android.intent.category.DEFAULT"/>
        <category android:name="android.intent.category.BROWSABLE"/>
        <data android:scheme="no.tommesalg.seller" android:host="auth"/>
    </intent-filter>
</activity>

<!-- Android 11+ package visibility, so url_launcher can find a browser -->
<queries>
    <intent>
        <action android:name="android.intent.action.VIEW"/>
        <category android:name="android.intent.category.BROWSABLE"/>
        <data android:scheme="https"/>
    </intent>
</queries>
```

No `autoVerify` is needed, because that is only for https App Links.

### 6.2 Android-specific behavior you must handle

1. **Cancel:** closing the Custom Tab (Back/✕) resumes the app **without** a link. Watch `AppLifecycleState.resumed`. If no callback arrives within **3 s**, treat it as a cancel. Otherwise the button spins until the timeout.
2. **Subscribe before launching:** start listening to `uriLinkStream` **before** `launchUrl`, or a fast return is missed.
3. **Process death:** Android may kill the app while the tab is open. The return link then **cold-starts** the app, and no listener is alive. To cover this, before launching, write a `SharedPreferences` marker `"<provider>|<startMillis>"` (never the code). On splash, if the marker is fresh (< 5 min) **and** `getInitialLink()` is our callback with a `code`, finish the exchange there. Clear the marker either way. Without a marker, ignore the link, so an unsolicited link can't sign anyone in.
4. Use `LaunchMode.inAppBrowserView` (Custom Tab) and fall back to `externalApplication`. **Never a WebView**: Google blocks sign-in in embedded WebViews.

---

## 7. Dart — the repository (drop-in, adapt the constants)

`lib/data/repositories/social_auth_repository.dart`

```dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum SocialProvider { google, apple }

class SocialAuthException implements Exception {
  const SocialAuthException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled; // true → user backed out, show nothing
}

class SocialAuthResult {
  const SocialAuthResult({
    required this.provider, required this.accessToken, required this.refreshToken,
    this.expiresIn, this.userId, this.email, this.phone, this.displayName,
  });
  final SocialProvider provider;
  final String accessToken;
  final String refreshToken;
  final int? expiresIn;
  final String? userId;
  final String? email;
  final String? phone;
  final String? displayName;
}

class SocialAuthRepository {
  SocialAuthRepository({AppLinks? appLinks, Dio? dio})
      : _appLinks = appLinks ?? AppLinks(),
        _dio = dio ?? _buildDio();

  final AppLinks _appLinks;
  final Dio _dio;

  // ── Adapt these ────────────────────────────────────────────────────
  static const String origin = 'https://tommesalg.no';          // staging: https://staging.tommesalg.no
  static const String _callbackScheme = 'no.tommesalg.seller';  // = bundle id / package
  static const String _callbackHost = 'auth';
  static const String _callbackPrefix = '';                     // buyer app uses '/vipps' (allowlist workaround)
  static const MethodChannel _webAuth = MethodChannel('no.tommesalg.seller/web_auth');
  // ───────────────────────────────────────────────────────────────────

  static const String _authorizePath = '/api/auth/cognito/authorize';
  static const String _exchangePath = '/api/auth/cognito/mobile-exchange';
  static const String _kPending = 'social_auth.pending';
  static const Duration _pendingTtl = Duration(minutes: 5);

  static String _redirectFor(SocialProvider p) =>
      '$_callbackScheme://$_callbackHost$_callbackPrefix/${p.name}';

  static String _idp(SocialProvider p) =>
      p == SocialProvider.google ? 'Google' : 'SignInWithApple';

  // NO logging interceptor: the exchange response carries the refresh token.
  static Dio _buildDio() => Dio(BaseOptions(
        baseUrl: origin,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (_) => true,
        headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
      ));

  Future<SocialAuthResult> signInWithGoogle() => _signIn(SocialProvider.google);
  Future<SocialAuthResult> signInWithApple() => _signIn(SocialProvider.apple);

  Future<SocialAuthResult> _signIn(SocialProvider provider) async {
    final authUrl = Uri.parse('$origin$_authorizePath').replace(queryParameters: {
      'identity_provider': _idp(provider),
      'mobile': '1',
      'redirect': _redirectFor(provider),
      'mode': 'login',
    });

    await _preflight(authUrl);

    final callback = Platform.isIOS
        ? await _authenticateIos(authUrl)
        : await _authenticateAndroid(provider, authUrl);

    final error = callback.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      final e = error.toLowerCase();
      final aborted = e.contains('cancel') || e.contains('access_denied');
      throw SocialAuthException(aborted ? 'Cancelled' : 'Sign-in failed', cancelled: aborted);
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) throw const SocialAuthException('Sign-in failed');
    return _exchange(provider, code);
  }

  /// Turns authorize-route JSON errors into a message instead of raw JSON in the browser.
  Future<void> _preflight(Uri authUrl) async {
    final res = await _dio.getUri<dynamic>(authUrl, options: Options(followRedirects: false));
    final s = res.statusCode ?? 0;
    if (s >= 300 && s < 400) return;
    final err = res.data is Map ? (res.data as Map)['error'] : null;
    throw SocialAuthException(
      s == 503 || err == 'mobile_auth_unavailable'
          ? 'Sign-in is temporarily unavailable'
          : 'Sign-in failed',
    );
  }

  Future<Uri> _authenticateIos(Uri authUrl) async {
    try {
      final result = await _webAuth.invokeMethod<String>('authenticate', {
        'url': authUrl.toString(),
        'callbackScheme': _callbackScheme,
      });
      final uri = result == null ? null : Uri.tryParse(result);
      if (uri == null || !_isOurCallback(uri)) throw const SocialAuthException('Sign-in failed');
      return uri;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') throw const SocialAuthException('Cancelled', cancelled: true);
      throw const SocialAuthException('Sign-in failed');
    }
  }

  Future<Uri> _authenticateAndroid(SocialProvider provider, Uri authUrl) async {
    final completer = Completer<Uri>();
    final sub = _appLinks.uriLinkStream.listen((uri) {
      if (_isOurCallback(uri) && !completer.isCompleted) completer.complete(uri);
    }, onError: (Object e) {
      if (!completer.isCompleted) completer.completeError(e);
    });

    Timer? grace;
    final lifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state != AppLifecycleState.resumed) return;
      grace?.cancel();
      grace = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) {
          completer.completeError(const SocialAuthException('Cancelled', cancelled: true));
        }
      });
    });

    await _markPending(provider);
    try {
      var ok = await launchUrl(authUrl, mode: LaunchMode.inAppBrowserView);
      if (!ok) ok = await launchUrl(authUrl, mode: LaunchMode.externalApplication);
      if (!ok) throw const SocialAuthException('No browser available');
      try {
        return await completer.future.timeout(_pendingTtl);
      } on TimeoutException {
        throw const SocialAuthException('Cancelled', cancelled: true);
      }
    } finally {
      grace?.cancel();
      lifecycle.dispose();
      await sub.cancel();
      await _clearPending();
    }
  }

  /// Single attempt — the code is one-time.
  Future<SocialAuthResult> _exchange(SocialProvider provider, String code) async {
    final res = await _dio.post<dynamic>(_exchangePath, data: {'code': code});
    final s = res.statusCode ?? 0;
    final body = res.data;
    if (s < 200 || s >= 300 || body is! Map) {
      if (s == 400 || s == 410) throw const SocialAuthException('Code expired, please try again');
      if (s == 429) {
        final retry = res.headers.value('retry-after');
        throw SocialAuthException('Too many attempts${retry != null ? ', try again in ${retry}s' : ''}');
      }
      if (s >= 500) throw const SocialAuthException('Sign-in is temporarily unavailable');
      throw const SocialAuthException('Sign-in failed');
    }
    final access = body['access_token'] as String?;
    final refresh = body['refresh_token'] as String?;
    if (access == null || refresh == null) throw const SocialAuthException('Sign-in failed');
    final user = body['user'] is Map ? Map<String, dynamic>.from(body['user'] as Map) : const {};

    final result = SocialAuthResult(
      provider: provider,
      accessToken: access,
      refreshToken: refresh,
      expiresIn: (body['expires_in'] as num?)?.toInt(),
      userId: user['id'] as String?,          // app user id — never the Cognito sub
      email: user['email'] as String?,
      phone: user['phone'] as String?,
      displayName: user['name'] as String?,
    );
    // TODO: save into YOUR secure token store (same one password login uses), e.g.
    // await TokenStore.save(access: access, refresh: refresh, expiresIn: result.expiresIn, userId: result.userId);
    return result;
  }

  // ── Android cold start (process death mid-flow) — call once from splash ──
  static Future<SocialAuthResult?> completeColdStartCallback() async {
    if (!Platform.isAndroid) return null;
    try {
      final provider = await _takePending();
      if (provider == null) return null;
      final repo = SocialAuthRepository();
      final initial = await repo._appLinks.getInitialLink();
      if (initial == null || !repo._isOurCallback(initial)) return null;
      final code = initial.queryParameters['code'];
      if (code == null || code.isEmpty) return null;
      return await repo._exchange(provider, code);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _markPending(SocialProvider p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPending, '${p.name}|${DateTime.now().millisecondsSinceEpoch}');
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
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(started));
    if (age.isNegative || age > _pendingTtl) return null;
    for (final p in SocialProvider.values) {
      if (p.name == parts[0]) return p;
    }
    return null;
  }

  bool _isOurCallback(Uri uri) =>
      uri.scheme == _callbackScheme &&
      uri.host == _callbackHost &&
      SocialProvider.values.any((p) => uri.path == '$_callbackPrefix/${p.name}');
}
```

> In production code, replace the hard-coded English strings with your localization keys. Never show raw server text or a Dio exception message on screen.

---

## 8. Dart — wiring the button (post-login bootstrap)

```dart
Future<void> onSocialLogin(Future<SocialAuthResult> Function() start) async {
  if (_busy) return;               // debounce double taps
  _busy = true;
  try {
    final result = await start();  // tokens already saved by the repository

    // 1. Defensive, idempotent provisioning. Never block sign-in on its failure.
    await dio.post('/api/v1/auth/ensure-profile',
        options: Options(headers: {'Authorization': 'Bearer ${result.accessToken}'}));

    // 2. Role gate — app-specific.
    final me = await dio.get('/api/v1/seller/auth/me',   // Buyer app: /api/v1/auth/me
        options: Options(headers: {'Authorization': 'Bearer ${result.accessToken}'}));
    // V1 envelope: { success, data: { id, role, email, hasVerifiedPrimaryEmail, ... } }
    // Not allowed in this app → logout (clear tokens) and show a message.
    // 401 AUTH_USER_NOT_FOUND → ensure-profile once more, re-read /me; still missing → sign out.

    goHome();
  } on SocialAuthException catch (e) {
    if (!e.cancelled) showToast(e.message);   // a cancel is silent
  } finally {
    _busy = false;
  }
}
```

Splash, **before** the "do I have a session?" check:

```dart
final cold = await SocialAuthRepository.completeColdStartCallback();
if (cold != null) {
  await ensureProfile();
  // continue as a normal signed-in start
}
```

---

## 9. Apple-specific rules

- **Hide My Email:** the identity e-mail may be `…@privaterelay.appleid.com`, and `/me.email` may be `null`. Read these from `/me`: `identityEmailIsPrivateRelay`, `notificationEmail`, `hasVerifiedPrimaryEmail`.
- `needsNotificationEmailCollection` is frozen at `false`. **Do not block home** on it.
- When a real address is needed (Account screen, before saving a delivery address or applying as a seller): call `POST /api/v1/auth/notification-email/request {email}`, then `POST /api/v1/auth/notification-email/verify {email, code}`. The code has 6 digits and lasts 10 minutes, with a 60 s resend cooldown. Re-read `/me` afterwards.
- `409 CONFLICT` means the address belongs to another account. Show it, and **never auto-merge** accounts.
- The name arrives only on the first Apple authorization. Don't require it.
- Button copy and look must follow Apple's branding rules (black or white button, Apple logo, "Fortsett med Apple" / "Continue with Apple").
- App Store: if the app offers Google sign-in, guideline 4.8 expects Sign in with Apple too, so ship both once §1-2 is fixed.

---

## 10. Security checklist

- [ ] The exchange code and tokens are never logged, never sent to analytics or crash reports, and never stored (apart from tokens in Keychain/Keystore via `flutter_secure_storage`).
- [ ] No logging interceptor on the Dio instance that calls `mobile-exchange`.
- [ ] Callbacks are accepted only for our exact scheme/host/paths **and** only while a flow is pending (iOS: the session; Android: listener or fresh marker).
- [ ] No WebView anywhere in the flow.
- [ ] Logout clears local tokens even if `/auth/logout` fails.
- [ ] Never use the Google/Apple/Cognito **ID token** as a bearer. Only the Cognito **access token** goes in `Authorization`.

---

## 11. QA matrix

| Test | Expected |
|---|---|
| Google, first-time user (iOS + Android) | code → exchange OK → ensure-profile `created:true/false` → `/me` OK |
| Google, returning user | same `user.id`, no duplicate profile |
| Apple, Share My Email | exchange OK, `/me` shows the address *(blocked until §1-2 is fixed)* |
| Apple, Hide My Email | home reachable, optional add-email OTP works |
| Cancel (iOS Cancel / Android Back) | no error toast, button re-enabled |
| Android: enable "Don't keep activities", sign in | cold-start path finishes the sign-in |
| Replay the same code | 410, no second session |
| Wait > 60 s before the exchange | 400 → "try again" |
| Unallowlisted redirect | localized error from the preflight, no JSON page |
| Access token expiry | one refresh, request retried once |
| Seller app signing in with a buyer-only account | role gate rejects it cleanly (no escalation) |
| Password + OTP registration | unaffected |

Always test on **installed real builds**. Simulators and localhost can't prove deep-link behavior. On the iOS Simulator the auth sheet sometimes shows "network connection lost" even when the device network is fine, so retest on a device first.

---

## 12. Reference files in the Buyer app

| File | What |
|---|---|
| `lib/data/repositories/social_auth_repository.dart` | the full production version of §7 (plus debug-only redirect hop tracing) |
| `ios/Runner/AppDelegate.swift` | `WebAuthSession` channel (§5) |
| `android/app/src/main/AndroidManifest.xml` | `no.tommesalg.buyer://auth` intent-filter (§6) |
| `lib/views/auth/login_view.dart` → `_onSocialLogin` | bootstrap order (§8) |
| `lib/views/splash/splash_view.dart` → `_finishColdStartSocialSignIn` | cold-start completion |
| `lib/raw/Tommesalg_Mobile_Google_Apple_Auth_Integration_Guide.docx` | backend contract |
| `lib/raw/BACKEND_CHANGES_NEEDED.md` | open Apple `auth_failed` issue + redirect allowlist request |

**Obsolete, do not follow:** `lib/raw/FLUTTER_GOOGLE_SIGN_IN.md` (old Supabase + native `google_sign_in` flow).
