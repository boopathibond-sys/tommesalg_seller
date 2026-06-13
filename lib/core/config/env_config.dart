import 'package:flutter/services.dart';

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
  static String get supabaseProdAnonKey => _get('SUPABASE_PROD_ANON_KEY');
  static String get supabaseStagingUrl => _get('SUPABASE_STAGING_URL');
  static String get supabaseStagingAnonKey => _get('SUPABASE_STAGING_ANON_KEY');
  static String get googleMapKey => _get('GOOGLE_MAP_KEY');
  static String get geminiApiKey => _get('GEMINI_API_KEY');
  static String get bringApiUid => _get('BRING_API_UID');
  static String get bringApiKey => _get('BRING_API_KEY');
  static String get vippsClientId => _get('VIPPS_CLIENT_ID');
  static String get vippsSubscriptionKey => _get('VIPPS_SUBSCRIPTION_KEY');
  static String get vippsEnvironment => _get('VIPPS_ENVIRONMENT');
  static String get stripePublishableKey => _get('STRIPE_PUBLISHABLE_KEY');
}
