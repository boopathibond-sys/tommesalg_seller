import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/localization/localization_service.dart';


/// **Reactive language controller** — the project's "LanguageController".
///
/// Lives in `view_models/` to honour the project's MVVM split (every other
/// view-state class sits here). We extend [GetxController] instead of the
/// project-wide `BaseViewModel` / `ChangeNotifier` because:
///
///   * GetX already drives the global locale via `Get.updateLocale`, and
///     mixing that with `notifyListeners` would split the source of truth.
///   * `RxString` gives us granular rebuilds in the language picker (only the
///     selected row's chrome rebuilds) without rebuilding the whole picker.
///
/// Bootstrapped by `LocalizationService.init()` and lives forever
/// (`permanent: true`), so any view can resolve it without a re-binding:
///
/// ```dart
/// final lang = Get.find<LanguageViewModel>();
/// await lang.changeLanguage(const Locale('ta', 'IN'));
/// ```
class LanguageViewModel extends GetxController {
  /// ISO-639-1 language code of the active locale (`en`, `ta`, …).
  final RxString languageCode =
      LocalizationService.defaultLocale.languageCode.obs;

  /// ISO-3166-1 country code, or empty when the locale is region-free.
  final RxString countryCode =
      (LocalizationService.defaultLocale.countryCode ?? '').obs;

  /// Current locale, derived from the two reactive fields above.
  Locale get currentLocale => countryCode.value.isEmpty
      ? Locale(languageCode.value)
      : Locale(languageCode.value, countryCode.value);

  /// `true` when [code] matches the active locale — handy for showing a check
  /// mark next to the active row in the language picker.
  bool isCurrent(String code) => languageCode.value == code;

  /// Loads the locale state without touching `Get.updateLocale`.
  /// Used at boot time after [LocalizationService] resolved the start locale.
  void load(Locale locale) {
    languageCode.value = locale.languageCode;
    countryCode.value  = locale.countryCode ?? '';
  }

  /// Switches the app to [locale], rebuilds every widget tree under
  /// `GetMaterialApp` instantly, and persists the choice for the next launch.
  ///
  /// No-op if [locale] is already active — keeps `Get.updateLocale` from
  /// triggering a redundant rebuild.
  Future<void> changeLanguage(Locale locale) async {
    if (locale.languageCode == languageCode.value &&
        (locale.countryCode ?? '') == countryCode.value) {
      return;
    }
    languageCode.value = locale.languageCode;
    countryCode.value  = locale.countryCode ?? '';
    Get.updateLocale(locale);
    await LocalizationService.persistLocale(locale);
  }

  /// Resets to [LocalizationService.defaultLocale] (Norwegian) and clears the
  /// persisted preference. Useful from a "Reset preferences" button in
  /// settings.
  Future<void> resetToDefault() =>
      changeLanguage(LocalizationService.defaultLocale);
}
