import 'dart:convert';
import 'dart:developer';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain / Keystore home of the Cognito session minted by the Tommesalg API
/// (`POST /api/v1/auth/login` with `client: "mobile"`).
///
/// Nothing else holds these tokens — there is no auth SDK any more — so this
/// is the one place they live:
///
///  * iOS Keychain with `first_unlock`, so a background refresh or a push
///    registration can read the token while the phone is locked.
///  * Android Keystore-backed encryption. Never plain SharedPreferences.
///  * Keys are prefixed `tommesalg.seller.` so the seller session never mixes
///    with the buyer app's, even on a shared Keychain group.
///
/// Reads are synchronous after [load]: [AuthService.authHeaders] is on the path
/// of every request, and a Keychain round-trip per request would be pure
/// latency. Writes go to memory first, then to disk, so a failed Keychain write
/// costs at worst one sign-in on the next launch — never a request sent with a
/// token that was already replaced.
class SessionTokenStore {
  static const String _kAccess = 'tommesalg.seller.access_token';
  static const String _kRefresh = 'tommesalg.seller.refresh_token';
  static const String _kExpires = 'tommesalg.seller.expires_at';
  static const String _kUserId = 'tommesalg.seller.user_id';
  static const String _kEmail = 'tommesalg.seller.email';
  static const String _kDisplayName = 'tommesalg.seller.display_name';

  static const List<String> _allKeys = [
    _kAccess,
    _kRefresh,
    _kExpires,
    _kUserId,
    _kEmail,
    _kDisplayName,
  ];

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    // v10 default: Keystore-backed ciphers (EncryptedSharedPreferences is
    // deprecated upstream).
    aOptions: AndroidOptions(),
  );

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  String? _userId;
  String? _email;
  String? _displayName;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  DateTime? get expiresAt => _expiresAt;
  String? get email => _email;
  String? get displayName => _displayName;

  /// The app user id (`/me` → `data.id`). Never the Cognito `sub` — the
  /// backend maps that onto a `users.id`, and only the latter is meaningful to
  /// the rest of the API.
  String? get userId => _userId;

  /// A session exists while either token is held. An expired access token
  /// alone is not "signed out": the refresh token can still mint a new one.
  bool get hasSession =>
      (_accessToken?.isNotEmpty ?? false) ||
      (_refreshToken?.isNotEmpty ?? false);

  /// Loads the stored session into memory. Called once from `main()` before
  /// the first frame. A failed read counts as signed out, which is the safe
  /// direction: the items are still there for the next launch.
  Future<void> load() async {
    try {
      final all = await _storage.readAll();
      _accessToken = _nonEmpty(all[_kAccess]);
      _refreshToken = _nonEmpty(all[_kRefresh]);
      final ms = int.tryParse(all[_kExpires] ?? '');
      _expiresAt = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
      _userId = _nonEmpty(all[_kUserId]);
      _email = _nonEmpty(all[_kEmail]);
      _displayName = _nonEmpty(all[_kDisplayName]);
    } catch (e) {
      log('[token-store] load failed: ${e.runtimeType}');
    }
  }

  /// Installs a login or refresh result.
  ///
  /// [refreshToken] is optional because `/auth/refresh` only returns one when
  /// the token is rotated — otherwise the stored one stays (contract §8.2).
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
    int? expiresIn,
  }) async {
    _accessToken = accessToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
    }
    _expiresAt = _expiryFor(accessToken, expiresIn);

    await _write({
      _kAccess: _accessToken,
      _kRefresh: _refreshToken,
      _kExpires: _expiresAt?.millisecondsSinceEpoch.toString(),
    });
  }

  /// Records who the session belongs to, from `/me` or the login form.
  Future<void> saveProfile({
    String? userId,
    String? email,
    String? displayName,
  }) async {
    if (userId != null && userId.isNotEmpty) _userId = userId;
    if (email != null && email.isNotEmpty) _email = email;
    if (displayName != null && displayName.isNotEmpty) {
      _displayName = displayName;
    }
    await _write({
      _kUserId: _userId,
      _kEmail: _email,
      _kDisplayName: _displayName,
    });
  }

  /// Drops everything — tokens and the profile that came with them.
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _userId = null;
    _email = null;
    _displayName = null;
    try {
      await Future.wait([for (final k in _allKeys) _storage.delete(key: k)]);
    } catch (e) {
      log('[token-store] clear failed: ${e.runtimeType}');
    }
  }

  /// True when the access token is missing, expired, or expires within
  /// [leeway]. An unknown expiry counts as expiring: refreshing once too often
  /// is cheap, sending a dead bearer is a visible failure.
  bool expiresWithin(Duration leeway) {
    final exp = _expiresAt;
    if (_accessToken == null || exp == null) return true;
    return DateTime.now().add(leeway).isAfter(exp);
  }

  Future<void> _write(Map<String, String?> values) async {
    try {
      await Future.wait([
        for (final e in values.entries)
          e.value == null
              ? _storage.delete(key: e.key)
              : _storage.write(key: e.key, value: e.value),
      ]);
    } catch (e) {
      log('[token-store] write failed: ${e.runtimeType}');
    }
  }

  /// The JWT's own `exp` when readable — it is what the server checks —
  /// otherwise now + `expiresIn`.
  static DateTime? _expiryFor(String token, int? expiresIn) {
    final exp = _claimOf(token, 'exp');
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    }
    if (expiresIn != null) {
      return DateTime.now().add(Duration(seconds: expiresIn));
    }
    return null;
  }

  /// Reads one claim from a JWT payload without verifying it — the server
  /// verifies; this is only for the expiry.
  static Object? _claimOf(String jwt, String name) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = jsonDecode(payload);
      return map is Map ? map[name] : null;
    } catch (_) {
      return null;
    }
  }

  static String? _nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;
}
