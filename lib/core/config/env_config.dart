import 'package:flutter/services.dart';

/// Backend the whole app talks to. Picked once in `main.dart`; every REST
/// call and the auction WebSocket derive their host from [baseUrl].
enum AppEnvironment {
  staging('https://staging.tommesalg.no'),
  live('https://tommesalg.no');

  const AppEnvironment(this.baseUrl);

  final String baseUrl;
}

/// Reads the `.env` file that ships as a Flutter asset.
///
/// Assets are stored unencrypted inside the IPA/APK, so every value exposed
/// here is effectively public. Only hostnames belong in it — server-side credentials (payment, shipping, AI provider keys) must
/// stay behind the backend. Adding a getter here for a real secret puts that
/// secret in every user's hands.
class EnvConfig {
  EnvConfig._();

  static final Map<String, String> _vars = {};

  static AppEnvironment _environment = AppEnvironment.live;

  static AppEnvironment get environment => _environment;

  static bool get isStaging => _environment == AppEnvironment.staging;

  static Future<void> init({
    AppEnvironment environment = AppEnvironment.live,
  }) async {
    _environment = environment;
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

  static String get baseUrl => _environment.baseUrl;

  /// Buyer backend host (separate from [baseUrl] — the main REST API).
  static String get buyerBaseUrl => _get('BUYER_BASE_URL');
}
