import 'dart:developer';

import '../../../../core/config/env_config.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../models/display_name_entry.dart';

/// Resolves chat senders' display names, so the live chat renders "Anna" rather
/// than a raw user id.
///
/// RTM only hands the seller a publisher id, so the name has to come from the
/// API — but it is looked up **per unknown sender, in batches, once**: the
/// caller (the room controller) keeps a `userId -> name` cache and only ever
/// asks for ids it hasn't resolved yet. One chatty buyer costs one lookup, no
/// matter how many lines they send.
class DisplayNameService {
  final _api = ApiClient.instance;

  /// Server-side cap on a single lookup.
  static const int maxIdsPerRequest = 50;

  /// Both known routes, in preference order. The web console calls the first
  /// (no `/v1`); the second is the buyer app's and is role-gated, so it answers
  /// `403 AUTH_ROLE_REQUIRED "Buyer role required"` for a seller. Trying both
  /// means the names appear on whichever the deployment actually exposes.
  static const List<String> _paths = [
    '/api/users/display-names',
    '/api/v1/users/display-names',
  ];

  /// The route that last answered, so we stop probing after the first success.
  static String? _workingPath;

  /// Set once every route has refused repeatedly, so we stop asking for the
  /// rest of the app run instead of firing a failing request per batch.
  static bool _disabled = false;
  static int _consecutiveFailures = 0;
  static const int _maxFailuresBeforeGivingUp = 3;

  /// `GET …/display-names?ids=a,b,c` → `{ names: { id: {...} } }`.
  ///
  /// De-dupes and caps at [maxIdsPerRequest]; ids the server doesn't know are
  /// simply absent from the result.
  Future<Map<String, DisplayNameEntry>> fetch(List<String> userIds) async {
    if (_disabled) return const {};
    final ids = userIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return const {};
    final query = ids.take(maxIdsPerRequest).join(',');

    // Bearer from ensuredAuthHeaders (waits out a token rotation) — the same
    // header source every other room call uses.
    final headers = await AuthService.instance.ensuredAuthHeaders();

    for (final path in [if (_workingPath != null) _workingPath! else ..._paths]) {
      final url = Uri.parse('${EnvConfig.baseUrl}$path')
          .replace(queryParameters: {'ids': query}).toString();

      log('[display-names] ➡️  GET $url  (bearer: '
          '${headers.containsKey('Authorization') ? 'yes' : 'MISSING'})');

      // suppressAuthHandlers: an auth/role error on this cosmetic lookup must
      // never trip the global sign-out — `AUTH_ROLE_REQUIRED` here means "wrong
      // role *for this endpoint*", not "this account isn't a seller".
      final res = await _api.get(url,
          headers: headers, suppressAuthHandlers: true);

      log('[display-names] ⬅️  [${res.statusCode}] ${res.body}');

      if (!res.isSuccess) continue;

      Map<String, dynamic> body;
      try {
        body = res.json;
      } catch (_) {
        log('[display-names] body is not JSON — skipping');
        continue;
      }

      final out = _parse(body);
      if (out.isEmpty) {
        log('[display-names] parsed 0 names out of that body — shape unknown');
        continue;
      }
      log('[display-names] resolved ${out.length}: '
          '${out.map((id, e) => MapEntry(id, e.displayName ?? e.email))}');
      _workingPath = path;
      _consecutiveFailures = 0;
      return out;
    }

    // Every route failed. Forget any remembered one so the next attempt probes
    // the full list again, and give up only after this keeps happening.
    _workingPath = null;
    if (++_consecutiveFailures >= _maxFailuresBeforeGivingUp) {
      _disabled = true;
      log('display-names: no usable route — chat keeps short ids this run');
      return const {};
    }
    // Throwing (rather than returning empty) lets the caller drop these ids
    // from its "already asked" set, so the next message from the same sender
    // retries instead of being stuck on a short id forever.
    throw StateError('display-names lookup failed');
  }

  /// Pulls `userId -> entry` out of whatever envelope the endpoint uses. The
  /// V1 route wraps in `data.names`; the `/api/users` route is a separate
  /// handler with its own shape, so accept the plausible ones rather than
  /// silently rendering ids if it differs.
  Map<String, DisplayNameEntry> _parse(Map<String, dynamic> body) {
    final data = body['data'];
    final names = (data is Map ? (data['names'] ?? data['users']) : null) ??
        body['names'] ??
        body['users'] ??
        body['items'];

    // `{ "<id>": { displayName, email }, … }`
    if (names is Map) {
      final out = <String, DisplayNameEntry>{};
      names.forEach((id, entry) {
        if (id is String && entry is Map) {
          out[id] = DisplayNameEntry.fromJson(Map<String, dynamic>.from(entry));
        }
      });
      return out;
    }

    // `[ { id|userId, displayName, email }, … ]`
    if (names is List) {
      final out = <String, DisplayNameEntry>{};
      for (final entry in names.whereType<Map>()) {
        final map = Map<String, dynamic>.from(entry);
        final id = (map['userId'] ?? map['id']) as String?;
        if (id != null && id.isNotEmpty) {
          out[id] = DisplayNameEntry.fromJson(map);
        }
      }
      return out;
    }

    // Unwrapped `{ "<id>": {...} }` at the top level.
    final out = <String, DisplayNameEntry>{};
    body.forEach((id, entry) {
      if (entry is Map && entry.containsKey('displayName')) {
        out[id] = DisplayNameEntry.fromJson(Map<String, dynamic>.from(entry));
      }
    });
    return out;
  }
}
