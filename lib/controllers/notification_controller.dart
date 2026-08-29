import 'dart:convert';
import 'dart:developer';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../models/notification_model.dart';

/// Which slice of the inbox the list is showing.
enum NotificationFilter {
  /// Everything that isn't archived — the default inbox.
  all,

  /// Unread only (`?unreadOnly=true`).
  unread,

  /// The archive (`?archived=true`).
  archived,
}

/// Notification inbox controller.
///
/// Source of truth for `GET /api/notifications` (cursor-paginated) plus the
/// read / unread / archive mutations that hang off it, and for the unread
/// badge on the home bell. Uses the app's [ApiClient] + [AuthService] like
/// every other seller controller, with one difference from the paged seller
/// endpoints: paging is by opaque `cursor`, not by page number.
///
/// Note the paths carry **no `/v1` segment**, unlike the seller routes
/// elsewhere in the app: `{BASE_URL}/api/notifications`.
///
/// Mutations are optimistic. `POST …/read` answers with a bare success
/// envelope, so the row is patched locally and rolled back if the call fails;
/// that keeps the list from flickering through a full re-fetch on every tap.
class NotificationController extends GetxController {
  // ---------- Reactive state ----------

  /// Accumulated rows for the active [filter]. The first page replaces the
  /// list, every cursor page appends.
  final RxList<NotificationModel> _notifications = <NotificationModel>[].obs;
  List<NotificationModel> get notifications => _notifications.toList();

  final Rx<NotificationListMeta?> _meta = Rx<NotificationListMeta?>(null);
  NotificationListMeta? get meta => _meta.value;
  bool get hasMore => _meta.value?.hasMore ?? false;

  /// Server-side unread tally — drives the bell badge. Kept in step locally
  /// after each mutation and re-synced by [fetchUnreadCount].
  final RxInt _unreadCount = 0.obs;
  int get unreadCount => _unreadCount.value;
  bool get hasUnread => _unreadCount.value > 0;

  final RxBool _isLoading = false.obs;
  bool get isLoading => _isLoading.value;

  final RxBool _isLoadingMore = false.obs;
  bool get isLoadingMore => _isLoadingMore.value;

  /// True while a read-all / archive-all / bulk is in flight, so the top-bar
  /// action can show a spinner instead of accepting a second tap.
  final RxBool _isMutating = false.obs;
  bool get isMutating => _isMutating.value;

  final RxnString _errorMessage = RxnString();
  String? get errorMessage => _errorMessage.value;

  final Rx<NotificationFilter> _filter = NotificationFilter.all.obs;
  NotificationFilter get filter => _filter.value;

  /// Active `?category=…` (`auction` | `order` | `offer` | `payment` |
  /// `shipping` | `stream` | `social` | `seller` | `buyer` | `admin` |
  /// `security` | `marketing`), or `null` for every category.
  ///
  /// An independent axis from [filter] — the server applies both, so
  /// "unread + auction" is a valid view.
  final RxnString _category = RxnString();
  String? get category => _category.value;

  /// Set when the backend answers `403 FEATURE_DISABLED` — the notification
  /// platform is switched off server-side. Not an error the seller can retry
  /// away, so the screen says so plainly instead of offering a Retry button.
  final RxBool _featureDisabled = false.obs;
  bool get featureDisabled => _featureDisabled.value;

  /// Cursor for the *next* page, carried between [fetchNotifications] calls.
  String? _cursor;

  // ---------- Services ----------

  final _api = ApiClient.instance;

  static const String _base = '/api/notifications';

  // ---------- Intents ----------

  /// Calls
  /// `GET /api/notifications?limit=…[&cursor=…][&unreadOnly|archived][&category=…]`.
  ///
  /// Passing a [cursor] appends the next page; omitting it reloads from the
  /// top and replaces the list. Returns `true` on a 2xx `success: true`.
  Future<bool> fetchNotifications({String? cursor, int limit = 20}) async {
    final isFirstPage = cursor == null || cursor.isEmpty;
    if (isFirstPage) {
      _isLoading.value = true;
    } else {
      _isLoadingMore.value = true;
    }
    _errorMessage.value = null;

    try {
      final active = _filter.value;
      final activeCategory = _category.value;

      final uri = Uri.parse('${EnvConfig.baseUrl}$_base').replace(
        queryParameters: <String, String>{
          'limit': '$limit',
          if (!isFirstPage) 'cursor': cursor,
          if (active == NotificationFilter.unread) 'unreadOnly': 'true',
          if (activeCategory != null && activeCategory.isNotEmpty)
            'category': activeCategory,
          // The default view is the live inbox; `archived=true` swaps it for
          // the archive. Omitting the param entirely is what the server treats
          // as "not archived".
          if (active == NotificationFilter.archived) 'archived': 'true',
        },
      );

      final response = await _api.get(
        uri.toString(),
        headers: await AuthService.instance.ensuredAuthHeaders(),
      );
      final body = _decode(response.body);

      if (response.isSuccess && body is Map && body['success'] == true) {
        _featureDisabled.value = false;

        final data  = body['data'];
        final items = _itemsIn(data)
            .map((m) => NotificationModel.fromJson(Map<String, dynamic>.from(m)))
            .toList();

        if (isFirstPage) {
          _notifications.assignAll(items);
        } else {
          _notifications.addAll(items);
        }

        final metaJson = (body['meta'] is Map)
            ? Map<String, dynamic>.from(body['meta'] as Map)
            : (data is Map ? Map<String, dynamic>.from(data) : null);
        _meta.value = metaJson == null
            ? null
            : NotificationListMeta.fromJson(metaJson);
        _cursor = _meta.value?.nextCursor;

        log('NotificationController ⇒ ${items.length} rows '
            '(${isFirstPage ? 'first page' : 'cursor page'}, '
            'total now ${_notifications.length})');
        return true;
      }

      if (_isFeatureDisabled(response.statusCode, body)) return false;
      _errorMessage.value =
          _messageIn(body) ?? 'Failed to load notifications (HTTP ${response.statusCode}).';
      return false;
    } catch (e) {
      log('Notifications fetch error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoading.value     = false;
      _isLoadingMore.value = false;
    }
  }

  /// Loads the next cursor page when there is one and nothing is in flight.
  Future<void> loadMore({int limit = 20}) async {
    if (!hasMore || _isLoading.value || _isLoadingMore.value) return;
    await fetchNotifications(cursor: _cursor, limit: limit);
  }

  /// Switches the visible slice and reloads from the top. Leaves [category]
  /// alone — the two filters compose. No-op when the filter is unchanged.
  Future<void> setFilter(NotificationFilter next) async {
    if (_filter.value == next) return;
    _filter.value = next;
    await _reload();
  }

  /// Switches the `?category=…` filter and reloads from the top. Passing
  /// `null` clears it (every category). No-op when unchanged.
  Future<void> setCategory(String? next) async {
    final normalised = (next == null || next.isEmpty) ? null : next;
    if (_category.value == normalised) return;
    _category.value = normalised;
    await _reload();
  }

  /// Drops the loaded page and re-fetches from the first cursor. Clearing the
  /// list up front matters: the rows on screen belong to the *previous* filter,
  /// and leaving them there would flash the wrong content under the spinner.
  Future<void> _reload() async {
    _cursor = null;
    _meta.value = null;
    _notifications.clear();
    await fetchNotifications();
  }

  /// Syncs the badge from `GET /api/notifications/unread-count`. Cheap enough
  /// (180/min) to call on every home mount and after every mutation.
  Future<void> fetchUnreadCount() async {
    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}$_base/unread-count',
        headers: await AuthService.instance.ensuredAuthHeaders(),
      );
      final body = _decode(response.body);
      if (!response.isSuccess || body is! Map) {
        _isFeatureDisabled(response.statusCode, body);
        return;
      }
      final data = body['data'];
      final raw = data is Map
          ? (data['unreadCount'] ?? data['unread'] ?? data['count'])
          : data;
      final count = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
      if (count != null) {
        _featureDisabled.value = false;
        _unreadCount.value = count < 0 ? 0 : count;
      }
    } catch (e) {
      // The badge is decoration — never surface its failure to the seller.
      log('notifications: unread-count failed — $e');
    }
  }

  /// Marks one row read (`POST …/{id}/read`, idempotent). No-op when it is
  /// already read. Optimistic: the row flips immediately and reverts if the
  /// call fails.
  Future<bool> markRead(String id) async {
    final index = _indexOf(id);
    if (index < 0) return false;
    if (_notifications[index].isRead) return true;
    return _mutate(
      id: id,
      path: '$_base/$id/read',
      apply: (row) => row.copyWith(isRead: true),
      unreadDelta: -1,
    );
  }

  /// Marks one row unread again (`POST …/{id}/unread`).
  Future<bool> markUnread(String id) async {
    final index = _indexOf(id);
    if (index < 0) return false;
    if (!_notifications[index].isRead) return true;
    return _mutate(
      id: id,
      path: '$_base/$id/unread',
      apply: (row) => row.copyWith(isRead: false),
      unreadDelta: 1,
    );
  }

  /// Archives one row (`POST …/{id}/archive`, idempotent).
  ///
  /// The archive is a separate slice, so outside the archive filter the row
  /// leaves the list entirely; inside it, it just stays put. Archiving an
  /// unread row also drops it out of the badge — it is no longer in the inbox.
  Future<bool> archive(String id) async {
    final index = _indexOf(id);
    if (index < 0) return false;

    final original = _notifications[index];
    final showingArchive = _filter.value == NotificationFilter.archived;

    if (showingArchive) {
      _notifications[index] = original.copyWith(isArchived: true);
    } else {
      _notifications.removeAt(index);
    }
    if (original.isUnread) _bumpUnread(-1);

    final ok = await _post('$_base/$id/archive');
    if (!ok) {
      // Roll back — put the row back exactly where it was.
      if (showingArchive) {
        if (index < _notifications.length) _notifications[index] = original;
      } else {
        _notifications.insert(
          index.clamp(0, _notifications.length),
          original,
        );
      }
      if (original.isUnread) _bumpUnread(1);
    }
    return ok;
  }

  /// `POST /api/notifications/read-all` — marks the whole inbox read, then
  /// flips every loaded row and zeroes the badge.
  ///
  /// Deliberately **not** scoped to the active [category]: the endpoint takes
  /// no filters, so it always clears the entire inbox. Use [bulk] with the
  /// visible ids when a scoped version is needed.
  Future<bool> markAllRead() async {
    if (_isMutating.value) return false;
    _isMutating.value = true;
    try {
      final ok = await _post('$_base/read-all');
      if (!ok) return false;

      _notifications.assignAll(
        _notifications.map((n) => n.copyWith(isRead: true)).toList(),
      );
      _unreadCount.value = 0;

      // The unread filter's contents just became empty by definition; reload
      // so the screen shows its empty state rather than stale rows.
      if (_filter.value == NotificationFilter.unread) {
        _cursor = null;
        await fetchNotifications();
      }
      return true;
    } finally {
      _isMutating.value = false;
    }
  }

  /// `POST /api/notifications/archive-all` — empties the inbox into the
  /// archive. Reloads afterwards because every loaded row has moved slice.
  Future<bool> markAllArchived() async {
    if (_isMutating.value) return false;
    _isMutating.value = true;
    try {
      final ok = await _post('$_base/archive-all');
      if (!ok) return false;
      _unreadCount.value = 0;
      _cursor = null;
      await fetchNotifications();
      return true;
    } finally {
      _isMutating.value = false;
    }
  }

  /// `POST /api/notifications/bulk` — mutates up to 100 ids in one call.
  /// [action] is `read` | `archive` | `restore`. Reloads the list on success
  /// because a `restore` can pull rows into the current slice.
  Future<bool> bulk({
    required List<String> ids,
    required String action,
  }) async {
    if (ids.isEmpty) return true;
    if (ids.length > 100) {
      _errorMessage.value = 'Select at most 100 notifications at a time.';
      return false;
    }
    if (_isMutating.value) return false;
    _isMutating.value = true;
    try {
      final ok = await _post(
        '$_base/bulk',
        body: {'ids': ids, 'action': action},
      );
      if (!ok) return false;
      _cursor = null;
      await fetchNotifications();
      await fetchUnreadCount();
      return true;
    } finally {
      _isMutating.value = false;
    }
  }

  /// Clears in-memory state — call from the logout flow so the next signed-in
  /// seller never sees the previous account's notifications flash on screen.
  void clearNotifications() {
    _notifications.clear();
    _meta.value            = null;
    _errorMessage.value    = null;
    _unreadCount.value     = 0;
    _filter.value          = NotificationFilter.all;
    _category.value        = null;
    _featureDisabled.value = false;
    _cursor                = null;
  }

  // ---------- Helpers ----------

  int _indexOf(String id) => _notifications.indexWhere((n) => n.id == id);

  void _bumpUnread(int delta) {
    final next = _unreadCount.value + delta;
    _unreadCount.value = next < 0 ? 0 : next;
  }

  /// Optimistic single-row mutation: apply locally, call the endpoint, revert
  /// on failure. [unreadDelta] adjusts the badge alongside the row.
  Future<bool> _mutate({
    required String id,
    required String path,
    required NotificationModel Function(NotificationModel) apply,
    required int unreadDelta,
  }) async {
    final index = _indexOf(id);
    if (index < 0) return false;

    final original = _notifications[index];
    _notifications[index] = apply(original);
    _bumpUnread(unreadDelta);

    final ok = await _post(path);
    if (!ok) {
      final current = _indexOf(id);
      if (current >= 0) _notifications[current] = original;
      _bumpUnread(-unreadDelta);
    }
    return ok;
  }

  /// Shared `POST` for the mutation endpoints — they all take an empty (or
  /// tiny) body and answer with the same success envelope. Sets
  /// [errorMessage] on failure.
  Future<bool> _post(String path, {Object? body}) async {
    try {
      final response = await _api.post(
        '${EnvConfig.baseUrl}$path',
        headers: await AuthService.instance.ensuredAuthHeaders(),
        body: body,
      );
      final decoded = _decode(response.body);
      if (response.isSuccess &&
          (decoded is! Map || decoded['success'] != false)) {
        return true;
      }
      if (_isFeatureDisabled(response.statusCode, decoded)) return false;
      _errorMessage.value =
          _messageIn(decoded) ?? 'That action could not be completed.';
      return false;
    } catch (e) {
      log('Notifications mutate error ($path): $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    }
  }

  /// [ApiResponse.json] throws on an empty or non-JSON body (a bare 204, an
  /// HTML error page from a proxy). Every caller here treats "couldn't decode"
  /// as "no envelope", so decoding is done once, defensively.
  dynamic _decode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// Pulls the row list out of whichever envelope the server used:
  /// `data.items`, `data.notifications`, or a bare `data` array.
  List<Map> _itemsIn(dynamic data) {
    if (data is List) return data.whereType<Map>().toList();
    if (data is Map) {
      for (final key in const ['items', 'notifications', 'results', 'rows']) {
        final value = data[key];
        if (value is List) return value.whereType<Map>().toList();
      }
    }
    return const [];
  }

  /// Human-readable failure text out of the error envelope, when there is one.
  String? _messageIn(dynamic body) {
    if (body is! Map) return null;
    final error = body['error'];
    final candidates = <dynamic>[
      body['message'],
      body['error_description'],
      if (error is Map) error['message'],
      if (error is String) error,
    ];
    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) return candidate;
    }
    return null;
  }

  /// `403 FEATURE_DISABLED` — the notification platform is off server-side.
  /// Flags the state and returns true so callers stop treating it as an error.
  bool _isFeatureDisabled(int? status, dynamic body) {
    if (status != 403) return false;

    final error = body is Map ? body['error'] : null;
    final code = [
      body is Map ? body['code'] : null,
      body is Map ? body['errorCode'] : null,
      if (error is Map) error['code'],
      if (error is String) error,
    ].where((c) => c != null).join(' ').toUpperCase();

    if (code.contains('FEATURE_DISABLED')) {
      _featureDisabled.value = true;
      _errorMessage.value = null;
      _notifications.clear();
      _unreadCount.value = 0;
      return true;
    }
    return false;
  }
}
