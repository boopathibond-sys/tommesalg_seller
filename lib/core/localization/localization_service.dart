import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../view_models/view_models/language_view_model.dart';

/// Bootstraps the localisation layer:
///
/// * Loads each `assets/translations/<code>.json` catalogue at startup so the
///   first frame already paints in the right language.
/// * Persists the active locale in SharedPreferences so it survives a cold
///   start.
/// * Owns the canonical list of supported locales and the fallback locale —
///   both new languages and the default app language are added here in **one**
///   place.
///
/// ### Adding a new language
/// 1. Drop `assets/translations/<code>.json` in the project (mirroring the
///    keys in `en.json`).
/// 2. Append `Locale('<code>', '<COUNTRY>')` to [supportedLocales] below.
/// 3. Add a row to `LanguagePickerSheet` if you want it to show up in the
///    picker (a 3-line addition).
///
/// That's the whole drill — no codegen, no `intl` boilerplate, no rebuild of
/// the controller.
class LocalizationService {
  LocalizationService._();

  // ──────────────────────────────────────────────────────────────────────
  // Configuration — everything you'd touch when shipping a new language.
  // ──────────────────────────────────────────────────────────────────────

  /// Default locale used when the user has not picked one yet AND the device
  /// locale isn't supported. Also used by GetX as the per-key fallback when a
  /// translation is missing in the active locale.
  static const Locale fallbackLocale = Locale('en', 'US');

  /// Canonical list of locales the app ships translations for. Add a new
  /// `Locale(...)` row here and a matching `<code>.json` to spread the app
  /// to a new language. English is first → it doubles as the [fallbackLocale]
  /// for any key that's missing in the active translation.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en', 'US'),
    Locale('nb', 'NO'),
  ];

  // ── SharedPreferences keys ────────────────────────────────────────────
  static const _kLangCode    = 'app.locale.language_code';
  static const _kCountryCode = 'app.locale.country_code';

  // ── Mutable state owned by the service ────────────────────────────────

  /// Filled by [init]; consumed by [AppTranslations].
  static Map<String, Map<String, String>> translations =
      const <String, Map<String, String>>{};

  /// The locale the app should boot with — either the persisted choice, the
  /// device locale (when supported), or [fallbackLocale].
  static Locale startLocale = fallbackLocale;

  // ──────────────────────────────────────────────────────────────────────
  // Bootstrap
  // ──────────────────────────────────────────────────────────────────────

  /// Call once from `main()` before `runApp`.
  static Future<void> init() async {
    translations = await _loadAllCatalogues();
    startLocale  = await _resolveStartLocale();

    // Single global controller — views resolve via `Get.find<LanguageViewModel>()`.
    // `permanent: true` keeps it alive across navigation cleanups.
    Get.put<LanguageViewModel>(
      LanguageViewModel()..load(startLocale),
      permanent: true,
    );
  }

  // ── JSON loader ───────────────────────────────────────────────────────

  static Future<Map<String, Map<String, String>>> _loadAllCatalogues() async {
    final result = <String, Map<String, String>>{};
    for (final locale in supportedLocales) {
      final path = 'assets/translations/${locale.languageCode}.json';
      final raw  = await rootBundle.loadString(path);
      final json = jsonDecode(raw) as Map<String, dynamic>;

      // GetX keys live under `<languageCode>_<COUNTRYCODE>`.
      final compositeKey =
          '${locale.languageCode}_${locale.countryCode ?? ''}';
      result[compositeKey] =
          json.map((k, v) => MapEntry(k, v.toString()));
    }
    return result;
  }

  // ── Persistence ───────────────────────────────────────────────────────

  static Future<Locale> _resolveStartLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code  = prefs.getString(_kLangCode);
    if (code != null && code.isNotEmpty) {
      final country = prefs.getString(_kCountryCode);
      final saved   = country == null || country.isEmpty
          ? Locale(code)
          : Locale(code, country);
      if (_isSupported(saved)) return saved;
    }

    // Fall back to the device locale when we ship a translation for it.
    final device = PlatformDispatcher.instance.locale;
    if (_isSupported(device)) return device;

    return fallbackLocale;
  }

  static bool _isSupported(Locale locale) =>
      supportedLocales.any((l) => l.languageCode == locale.languageCode);

  /// Persists the user's choice so we can restore it on the next cold start.
  static Future<void> persistLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangCode, locale.languageCode);
    await prefs.setString(_kCountryCode, locale.countryCode ?? '');
  }
}
