import 'package:get/get.dart';

/// GetX [Translations] adapter — feeds the catalogue loaded by
/// [LocalizationService] into the framework. Kept as a thin shim so the
/// service can stay free of GetX types and the controller can stay free of
/// JSON-loading concerns.
///
/// The map is keyed by `<languageCode>_<countryCode>` (e.g. `en_US`, `ta_IN`).
/// When a key is missing in the active locale GetX falls back to
/// `GetMaterialApp.fallbackLocale` automatically; if it's also missing there,
/// `'<key>'.tr` returns the literal key — handy for catching gaps in QA.
class AppTranslations extends Translations {
  AppTranslations(this._keys);

  final Map<String, Map<String, String>> _keys;

  @override
  Map<String, Map<String, String>> get keys => _keys;
}
