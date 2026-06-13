import 'dart:async';
import 'dart:developer';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../views/auth/reset_password_view.dart';
import 'auth_service.dart';

/// Handles the Supabase password-recovery deep link.
///
/// The recovery email opens:
///   `tommesalgseller://auth/reset-password#access_token=…&refresh_token=…&type=recovery`
///
/// Two things make this easy to get wrong, so they are deliberate here:
///  * Supabase puts the tokens in the URL **fragment**, not the query string,
///    so `uri.queryParameters` is empty — we parse `uri.fragment` with
///    [Uri.splitQueryString].
///  * We install the recovery session via [AuthService.setRecoverySession]
///    BEFORE routing, so [ResetPasswordView] can call `updateUser`.
///
/// We filter on scheme + host + path so this doesn't collide with other deep
/// links (e.g. a future Vipps return URL).
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  static const String _scheme = 'tommesalgseller';
  static const String _host = 'auth';
  static const String _path = '/reset-password';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  /// Idempotent: safe to call again after a hot restart without stacking
  /// stream subscriptions. Handles both cold start (link that launched the
  /// app) and warm start (link arriving while the app is alive).
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Cold start — the link that launched the app, if any.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e) {
      log('DeepLinkService: failed to read initial link: $e');
    }

    // Warm start — links arriving while the app is already running.
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) => log('DeepLinkService: link stream error: $e'),
    );
  }

  Future<void> _handle(Uri uri) async {
    // Ignore anything that isn't our recovery link.
    if (uri.scheme != _scheme || uri.host != _host || uri.path != _path) {
      return;
    }

    // Tokens live in the fragment, NOT the query string.
    final params = Uri.splitQueryString(uri.fragment);
    final accessToken = params['access_token'] ?? '';
    final refreshToken = params['refresh_token'] ?? '';

    if (accessToken.isEmpty || refreshToken.isEmpty) {
      log('DeepLinkService: recovery link missing tokens — ignoring.');
      return;
    }

    try {
      // Exchange the refresh token for a live recovery session so the next
      // screen's updateUser(password) call is authorized.
      await AuthService.instance.setRecoverySession(refreshToken);
    } catch (e) {
      log('DeepLinkService: setSession failed: $e');
      return;
    }

    // Wait for a frame so the navigator exists before pushing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.to(() => const ResetPasswordView());
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
