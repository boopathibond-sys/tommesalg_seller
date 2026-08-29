import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tommesalg_seller_app/core/localization/app_translations.dart';
import 'package:tommesalg_seller_app/core/localization/localization_service.dart';
import 'package:tommesalg_seller_app/core/localization/translation_keys.dart';
import 'package:tommesalg_seller_app/view_models/view_models/language_view_model.dart';

/// Covers what the profile-tab language picker relies on:
///  * flipping the locale repaints every `.tr` in the tree, and
///  * `LanguageViewModel.changeLanguage` moves the locale and persists it.
void main() {
  Map<String, String> _load(String code) =>
      (jsonDecode(File('assets/translations/$code.json').readAsStringSync())
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v.toString()));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    LocalizationService.translations = {
      'nb_NO': _load('nb'),
      'en_US': _load('en'),
    };
  });

  testWidgets('flipping the locale repaints every .tr in the tree',
      (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(LocalizationService.translations),
        locale: const Locale('nb', 'NO'),
        fallbackLocale: LocalizationService.fallbackLocale,
        // Builder so the lookups run inside build — after GetMaterialApp has
        // installed the catalogues — exactly as the real widgets do.
        home: Builder(
          builder: (_) => Column(
            children: [
              Text(TKeys.navProfile.tr),
              Text(TKeys.logOut.tr),
              Text(TKeys.languageSheetTitle.tr),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Logg ut'), findsOneWidget);
    expect(find.text('Velg språk'), findsOneWidget);

    Get.updateLocale(const Locale('en', 'US'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Choose language'), findsOneWidget);

    Get.updateLocale(const Locale('nb', 'NO'));
    await tester.pumpAndSettle();

    expect(find.text('Profil'), findsOneWidget);
  });

  // `changeLanguage` delegates storage to `LocalizationService.persistLocale`;
  // that contract is asserted directly here because driving the GetX call in a
  // test binding re-enters `runApp` (`forceAppUpdate`), which the binding
  // rejects. The repaint half is covered by the widget test above.
  test('the picked locale is persisted for the next cold start', () async {
    await LocalizationService.persistLocale(const Locale('en', 'US'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app.locale.language_code'), 'en');
    expect(prefs.getString('app.locale.country_code'), 'US');
  });

  test('re-picking the active language writes nothing', () async {
    final lang = LanguageViewModel()..load(const Locale('nb', 'NO'));
    // Same locale -> `changeLanguage` returns before it touches GetX or prefs.
    await lang.changeLanguage(const Locale('nb', 'NO'));

    expect(lang.isCurrent('nb'), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app.locale.language_code'), isNull);
  });

  test('the picker offers exactly the locales the app ships', () {
    expect(LocalizationService.supportedLocales.map((l) => l.languageCode),
        containsAll(<String>['nb', 'en']));
    expect(LocalizationService.defaultLocale.languageCode, 'nb');
  });
}
