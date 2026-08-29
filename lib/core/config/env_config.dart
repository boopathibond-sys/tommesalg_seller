import 'package:flutter/services.dart';

/// Reads the `.env` file that ships as a Flutter asset.
///
/// Assets are stored unencrypted inside the IPA/APK, so every value exposed
/// here is effectively public. Only hostnames and the Supabase anon key belong
/// in it — server-side credentials (payment, shipping, AI provider keys) must
/// stay behind the backend. Adding a getter here for a real secret puts that
/// secret in every user's hands.
class EnvConfig {
  EnvConfig._();

  static final Map<String, String> _vars = {};

  static Future<void> init() async {
    final raw = await rootBundle.loadString('.env');
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final idx = trimmed.indexOf('=');
      if (idx < 0) continue;
      final key = trimmed.substring(0, idx).trim();
      final value = trimmed.substring(idx + 1).trim();
      _vars[key] = value;
    }
  }

  static String _get(String key) => _vars[key] ?? '';

  static String get baseUrl => _get('BASE_URL');

  /// Buyer backend host (separate from [baseUrl] — the main REST API). Hosts
  /// the anti-enumeration `/api/v1/buyer/auth/forgot-password` endpoint that
  /// kicks off the Supabase password-reset email server-side, so the redirect
  /// URL / service secret never ship in the app.
  static String get buyerBaseUrl => _get('BUYER_BASE_URL');
  static String get supabaseProdUrl => _get('SUPABASE_PROD_URL');

  /// Supabase's *anon* key — public by design (row-level security is what
  /// protects the data), which is why it is the only key still allowed in the
  /// bundled `.env`.
  static String get supabaseProdAnonKey => _get('SUPABASE_PROD_ANON_KEY');
}
