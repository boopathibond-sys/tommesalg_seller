import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the two shipped catalogues against drift: a key added to one and
/// forgotten in the other renders the raw key (or English) to the seller.
void main() {
  final en = jsonDecode(File('assets/translations/en.json').readAsStringSync())
      as Map<String, dynamic>;
  final nb = jsonDecode(File('assets/translations/nb.json').readAsStringSync())
      as Map<String, dynamic>;

  test('nb and en carry the same keys', () {
    expect(nb.keys.toSet().difference(en.keys.toSet()), isEmpty,
        reason: 'keys present in nb.json but missing from en.json');
    expect(en.keys.toSet().difference(nb.keys.toSet()), isEmpty,
        reason: 'keys present in en.json but missing from nb.json');
  });

  test('no catalogue value is blank', () {
    for (final entry in {...en, ...nb}.entries) {
      expect((entry.value as String).trim(), isNotEmpty,
          reason: 'empty value for ${entry.key}');
    }
  });

  test('every TKeys constant resolves in both catalogues', () {
    final dart =
        File('lib/core/localization/translation_keys.dart').readAsStringSync();
    final keys = RegExp(r"static const \w+\s*=\s*'([^']+)'")
        .allMatches(dart)
        .map((m) => m.group(1)!);
    for (final k in keys) {
      expect(en.containsKey(k), isTrue, reason: 'en.json is missing "$k"');
      expect(nb.containsKey(k), isTrue, reason: 'nb.json is missing "$k"');
    }
  });

  test('placeholders match between languages', () {
    // Only keys fed through `trParams` carry real placeholders; e-mail hints
    // such as `you@example.com` contain an @ that is just text.
    final code = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    final dart =
        File('lib/core/localization/translation_keys.dart').readAsStringSync();
    final const2key = {
      for (final m
          in RegExp(r"static const (\w+)\s*=\s*'([^']+)'").allMatches(dart))
        m.group(1)!: m.group(2)!
    };
    final parameterised = RegExp(r'TKeys\.(\w+)\.trParams')
        .allMatches(code)
        .map((m) => const2key[m.group(1)!])
        .whereType<String>()
        .toSet();

    final ph = RegExp(r'@\w+');
    for (final k in parameterised) {
      final a = ph.allMatches(en[k] as String).map((m) => m.group(0)).toSet();
      final b = ph.allMatches(nb[k] as String).map((m) => m.group(0)).toSet();
      expect(b, a, reason: 'placeholder mismatch for "$k"');
    }
  });
}
