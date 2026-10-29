import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One hit from Kartverket's address register.
class NorwayAddress {
  const NorwayAddress({
    required this.street,
    required this.postalCode,
    required this.city,
  });

  final String street;
  final String postalCode;
  final String city;

  /// Kartverket returns post towns in capitals ("TROMSØ") — title-case them so
  /// they read like the rest of the form.
  static String _titleCase(String s) => s
      .toLowerCase()
      .split(RegExp(r'(?<=[\s-])'))
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join();

  factory NorwayAddress.fromJson(Map<String, dynamic> json) => NorwayAddress(
        street: (json['adressetekst'] as String? ?? '').trim(),
        postalCode: (json['postnummer'] as String? ?? '').trim(),
        city: _titleCase((json['poststed'] as String? ?? '').trim()),
      );
}

/// Address autocomplete backed by Kartverket's open address API
/// (ws.geonorge.no) — public, keyless, and Norway-only, which matches the
/// product.
class NorwayAddressService {
  NorwayAddressService._();

  static const _host = 'ws.geonorge.no';
  static const _path = '/adresser/v1/sok';

  /// Returns up to [limit] matches for a partially typed street address.
  /// Never throws — a failed lookup just means no suggestions.
  static Future<List<NorwayAddress>> search(String query,
      {int limit = 6}) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    try {
      final uri = Uri.https(_host, _path, {
        // Trailing wildcard so "Storgata 1" also matches "Storgata 12".
        'sok': '$q*',
        'treffPerSide': '$limit',
        'filtrer':
            'adresser.adressetekst,adresser.postnummer,adresser.poststed',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final list = (body is Map ? body['adresser'] : null) as List? ?? const [];
      final seen = <String>{};
      return list
          .whereType<Map<String, dynamic>>()
          .map(NorwayAddress.fromJson)
          .where((a) => a.street.isNotEmpty && a.postalCode.isNotEmpty)
          .where((a) => seen.add('${a.street}|${a.postalCode}'))
          .toList();
    } catch (e) {
      debugPrint('NorwayAddressService.search failed: $e');
      return const [];
    }
  }
}
