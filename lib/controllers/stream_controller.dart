import 'dart:developer';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../features/live_auction/data/services/auction_queue_dispatch_service.dart';
import '../models/product_request_model.dart';
import '../models/stream_analytics.dart';
import '../models/stream_category.dart';
import '../models/stream_model.dart';

class StreamListController extends GetxController {
  // ---------- Reactive state ----------

  final RxBool _isLoading = false.obs;
  final RxBool _isProductNotFoundByScan = false.obs;
  final RxBool _isProductUploading = false.obs;
  bool get isLoading => _isLoading.value;
  bool get isProductNotFoundByScan => _isProductNotFoundByScan.value;
  bool get isProductUploading => _isProductUploading.value;

  final RxnString _errorMessage = RxnString();
  String? get errorMessage => _errorMessage.value;

  // The scheduled-streams list ([fetchStreamsByStatus], used by the "Assign to
  // live" tab) tracks its own loading / error / loaded state rather than
  // sharing [_isLoading] and [_errorMessage] with the paged [fetchStreams].
  // The two run from different screens and used to collide: a Streams-tab load
  // in flight made the scheduled fetch bail out entirely, leaving that tab on
  // "No streams yet" until the seller pulled to refresh, and a failure in one
  // surfaced as an error in the other.
  final RxBool _isLoadingScheduled = false.obs;
  bool get isLoadingScheduled => _isLoadingScheduled.value;

  /// True while any scheduled fetch is running, visible or silent. Guards
  /// against two overlapping requests without forcing a silent sync to raise
  /// [_isLoadingScheduled] and flash a spinner.
  bool _scheduledFetchInFlight = false;

  final RxnString _scheduledError = RxnString();
  String? get scheduledError => _scheduledError.value;

  /// False until a scheduled-streams fetch has finished (successfully or not),
  /// so the tab can show a spinner instead of flashing "no streams" before the
  /// first load has even been attempted.
  final RxBool _scheduledLoaded = false.obs;
  bool get scheduledLoaded => _scheduledLoaded.value;

  final RxList<StreamModel> _streams = <StreamModel>[].obs;
  final RxList<StreamModel> _scheduledStreams = <StreamModel>[].obs;
  final selectedStream = Rxn<StreamModel>();
  List<StreamModel> get streams => _streams.toList();
  List<StreamModel> get scheduledStreams => _scheduledStreams.toList();

  final RxInt _page = 1.obs;
  final RxBool _hasMore = true.obs;
  bool get hasMore => _hasMore.value;

  /// The server-side status filter driving the streams list (`null` = All tab,
  /// otherwise `DRAFT` / `SCHEDULED` / `LIVE` / `ENDED` / `CANCELLED`).
  /// Preserved across pagination and pull-to-refresh so `loadMore`/
  /// `fetchStreams` keep the active tab's filter.
  final RxnString _statusFilter = RxnString();
  String? get statusFilter => _statusFilter.value;

  /// Incremented on every [fetchStreams] call so a response that lost the race
  /// (the seller tapped another tab while it was in flight) can be dropped
  /// instead of overwriting the newer tab's list.
  int _fetchSeq = 0;

  final RxBool _isLoadingMore = false.obs;
  bool get isLoadingMore => _isLoadingMore.value;

  // ---------- Product requests (scanned products) ----------

  final RxList<ProductRequestItem> _productRequestItems =
      <ProductRequestItem>[].obs;
  List<ProductRequestItem> get productRequestItems =>
      _productRequestItems.toList();

  final RxBool _isLoadingProductRequests = false.obs;
  bool get isLoadingProductRequests => _isLoadingProductRequests.value;

  final RxnString _productRequestId = RxnString();
  String? get productRequestId => _productRequestId.value;

  /// Ids of the request items whose delete call is still in flight. Kept as a
  /// set (not a single flag) so each row can show its own spinner and two quick
  /// taps on different rows don't block each other.
  final RxSet<String> _deletingItemIds = <String>{}.obs;
  bool isDeletingItem(String itemId) => _deletingItemIds.contains(itemId);

  /// The UPC of the last scan that wasn't found in the catalog. Used to
  /// pre-fill the "add unknown product" request.
  final RxnString _lastScannedUpc = RxnString();
  String? get lastScannedUpc => _lastScannedUpc.value;

  // ---------- Create stream: categories, thumbnail, submit ----------

  final RxList<StreamCategory> _categories = <StreamCategory>[].obs;
  List<StreamCategory> get categories => _categories.toList();

  final RxBool _isLoadingCategories = false.obs;
  bool get isLoadingCategories => _isLoadingCategories.value;

  final RxnString _categoriesError = RxnString();
  String? get categoriesError => _categoriesError.value;

  final RxBool _isCreatingStream = false.obs;
  bool get isCreatingStream => _isCreatingStream.value;

  final RxBool _isUploadingThumbnail = false.obs;
  bool get isUploadingThumbnail => _isUploadingThumbnail.value;

  final RxnString _createError = RxnString();
  String? get createError => _createError.value;

  // ---------- Services ----------

  final _api = ApiClient.instance;

  // ---------- Intents ----------

  /// Switches the active status filter (from the list tabs) and reloads the
  /// list from the API — `GET …/streams?page=1&pageSize=20&status=<STATUS>`.
  /// Pass `null` for the All tab (no `status` param).
  ///
  /// The loaded rows are dropped up front: they belong to the previous tab, and
  /// leaving them on screen would show e.g. ended streams under "Draft" until
  /// the response lands.
  Future<bool> selectStatus(String? status) async {
    final next = (status != null && status.isEmpty) ? null : status;
    if (_statusFilter.value == next) return false;
    _statusFilter.value = next;
    _streams.clear();
    _hasMore.value = false;
    return fetchStreams(refresh: true);
  }

  Future<bool> fetchStreams({bool refresh = false}) async {
    // A refresh always runs — it may be carrying a freshly selected status
    // filter, and dropping it would leave the list on the previous tab's data.
    // Pagination still bails while a load is in flight.
    if (_isLoading.value && !refresh) return false;

    if (refresh) {
      _page.value = 1;
      _hasMore.value = true;
    }

    final seq = ++_fetchSeq;
    _isLoading.value = true;
    _errorMessage.value = null;

    try {
      final status = _statusFilter.value;
      final statusParam =
          (status != null && status.isNotEmpty) ? '&status=$status' : '';
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/streams?page=${_page.value}&pageSize=20$statusParam',
        headers: AuthService.instance.authHeaders,
      );

      // Superseded by a newer fetch (another tab was tapped meanwhile).
      if (seq != _fetchSeq) return false;

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final data = body['data'] as Map<String, dynamic>;
          final items = (data['items'] as List)
              .map((e) => StreamModel.fromJson(e as Map<String, dynamic>))
              .toList();
          final meta = data['meta'] as Map<String, dynamic>?;

          if (refresh) {
            _streams.assignAll(items);
          } else {
            _streams.addAll(items);
          }

          _hasMore.value = meta?['hasMore'] as bool? ?? false;
          _page.value = (meta?['page'] as int? ?? _page.value) + 1;
          return true;
        }
        _errorMessage.value = 'Unexpected response format.';
        return false;
      }

      _errorMessage.value = 'Could not load streams: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Stream fetch error: $e');
      if (seq == _fetchSeq) {
        _errorMessage.value = 'Network error. Please try again.';
      }
      return false;
    } finally {
      // A superseded fetch must not clear the flag out from under the newer one.
      if (seq == _fetchSeq) _isLoading.value = false;
    }
  }

  /// Flips a stream to `ENDED` in the already-loaded lists, without waiting for
  /// a refetch. Called when the auction room reports the stream ended (seller
  /// tapped "End stream", the timer ran out, or the server pushed
  /// `STREAM_ENDED`) so the card stops advertising "Live"/"Enter room" the
  /// moment the seller is back on the list.
  void markStreamEnded(String streamId) => _patchStatus(streamId, 'ENDED');

  void _patchStatus(String streamId, String status) {
    /// The patched row as it now sits in [_scheduledStreams] — the exact
    /// instance the Manage Products dropdown builds its items from.
    StreamModel? scheduled;

    void apply(RxList<StreamModel> list, {bool track = false}) {
      final i = list.indexWhere((s) => s.id == streamId);
      if (i == -1) return;
      if (list[i].status != status) {
        list[i] = list[i].copyWith(status: status);
      }
      if (track) scheduled = list[i];
    }

    apply(_streams);
    apply(_scheduledStreams, track: true);

    if (selectedStream.value?.id != streamId) return;

    // Re-point the selection at the *same instance* the list now holds.
    // StreamModel has no `==` override, so equality is identity: handing the
    // dropdown a detached `copyWith` copy leaves it with a value that matches
    // none of its items, and DropdownButton asserts "There should be exactly
    // one item with [DropdownButton]'s value".
    //
    // A stream that isn't in the scheduled list can't be in the dropdown
    // either, so a detached copy is fine (and correct) in that case.
    selectedStream.value =
        scheduled ?? selectedStream.value!.copyWith(status: status);
  }

  /// Set once the single-stream GET answers 404/405, so the pre-enter status
  /// check silently degrades to "unknown" instead of retrying a route the
  /// backend doesn't serve.
  bool _streamByIdUnsupported = false;

  /// Re-reads a single stream from `GET /api/v1/seller/streams/:streamId` and
  /// syncs its status into the loaded lists. Returns the fresh model, or null
  /// when the read fails — callers treat null as "unknown", never as "ended",
  /// so a hiccup here can't block the seller from entering their room.
  Future<StreamModel?> fetchStreamById(String streamId) async {
    if (_streamByIdUnsupported) return null;
    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId',
        headers: AuthService.instance.authHeaders,
      );
      if (!response.isSuccess) {
        // A 404 that doesn't carry the API's `{error: {...}}` envelope means
        // the route itself isn't served, so stop paying for the round-trip on
        // every tap. A 404 *with* an envelope is a real "stream not found" —
        // that's per-stream, not per-route, so the check stays enabled.
        if (response.statusCode == 404 && !_hasApiErrorEnvelope(response)) {
          _streamByIdUnsupported = true;
        }
        return null;
      }

      final body = response.json;
      final data = body['data'];
      final json = data is Map<String, dynamic>
          ? (data['stream'] is Map<String, dynamic>
              ? data['stream'] as Map<String, dynamic>
              : data)
          : (body['id'] is String ? body : null);
      if (json == null || json['id'] is! String) return null;

      final fresh = StreamModel.fromJson(json);
      _patchStatus(fresh.id, fresh.status);
      return fresh;
    } catch (e) {
      log('Fetch stream error: $e');
      return null;
    }
  }

  /// `GET /api/v1/seller/streams/:streamId` used by the stream list when a
  /// terminal card (ended, or admin-rejected) is tapped, and by the edit form
  /// to hydrate fields the list payload may omit (sizes, duration). Unlike
  /// [fetchStreamById] this always hits the network and logs the full payload.
  /// Returns the parsed stream, or null when the call fails.
  Future<StreamModel?> fetchStreamDetails(String streamId) async {
    final url = '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId';
    log('[StreamDetails] GET $url');
    try {
      final response = await _api.get(
        url,
        headers: AuthService.instance.authHeaders,
      );
      log('[StreamDetails] status=${response.statusCode}');
      log('[StreamDetails] body=${response.body}');
      if (!response.isSuccess) return null;

      final body = response.json;
      final data = body['data'];
      final json = data is Map<String, dynamic>
          ? (data['stream'] is Map<String, dynamic>
              ? data['stream'] as Map<String, dynamic>
              : data)
          : (body['id'] is String ? body : null);
      if (json == null || json['id'] is! String) return null;

      final fresh = StreamModel.fromJson(json);
      // Keep the list in sync with whatever the server just told us.
      _patchStatus(fresh.id, fresh.status);
      return fresh;
    } catch (e) {
      log('[StreamDetails] error: $e');
      return null;
    }
  }

  /// `GET /api/v1/seller/streams/:id/analytics` — the whole post-mortem for a
  /// stream (durations, viewer peaks, product/sales counters and the per-buyer
  /// breakdown) in one read. Null means the read failed; the caller keeps
  /// whatever it already had on screen.
  Future<StreamAnalytics?> fetchStreamAnalytics(String streamId) async {
    final url = '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/analytics';
    log('[StreamAnalytics] GET $url');
    try {
      final response = await _api.get(
        url,
        headers: AuthService.instance.authHeaders,
      );
      log('[StreamAnalytics] status=${response.statusCode}');
      if (!response.isSuccess) return null;

      final analytics = StreamAnalytics.fromResponse(response.json);
      // Keep the list card in sync with the status the analytics read reports.
      if (analytics != null && analytics.streamStatus != null) {
        _patchStatus(streamId, analytics.streamStatus!);
      }
      return analytics;
    } catch (e) {
      log('[StreamAnalytics] error: $e');
      return null;
    }
  }

  /// Best-effort "is this stream still open?" read used before entering the
  /// auction room. Tries the single-stream GET, then falls back to a full list
  /// refresh (always available) and looks the stream up there. Null means the
  /// status could not be established — callers must treat that as "unknown"
  /// and let the seller through.
  Future<StreamModel?> resolveStreamStatus(String streamId) async {
    final fresh = await fetchStreamById(streamId);
    if (fresh != null) return fresh;

    await fetchStreams(refresh: true);
    for (final s in _streams) {
      if (s.id == streamId) return s;
    }
    return null;
  }

  Future<void> loadMore() async {
    if (!_hasMore.value || _isLoadingMore.value || _isLoading.value) return;
    _isLoadingMore.value = true;
    try {
      await fetchStreams();
    } finally {
      _isLoadingMore.value = false;
    }
  }

  /// Loads the taxonomy nodes the seller can tag a new stream with. Cached
  /// after the first successful load; pass [force] to refetch.
  Future<void> fetchCategories({bool force = false}) async {
    if (_isLoadingCategories.value) return;
    if (!force && _categories.isNotEmpty) return;

    _isLoadingCategories.value = true;
    _categoriesError.value = null;
    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/streams/categories',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final items = StreamCategory.listFromResponse(response.json);
        _categories.assignAll(items);
        if (items.isEmpty) {
          _categoriesError.value = 'No categories available.';
        }
        return;
      }
      _categoriesError.value = 'Could not load categories (${response.statusCode}).';
    } catch (e) {
      log('Categories fetch error: $e');
      _categoriesError.value = 'Network error. Please try again.';
    } finally {
      _isLoadingCategories.value = false;
    }
  }

  /// Uploads a stream thumbnail and returns the resulting `s3Key`, or null on
  /// failure. Uses the same S3 upload endpoint as the "Add UPC manually" flow —
  /// `POST /api/v1/seller/product-request-issue-images` (multipart `file`).
  Future<String?> uploadStreamThumbnail(String filePath) async {
    if (_isUploadingThumbnail.value) return null;
    _isUploadingThumbnail.value = true;
    _createError.value = null;
    try {
      final response = await _api.uploadFile(
        '${EnvConfig.baseUrl}/api/v1/seller/product-request-issue-images',
        fieldName: 'file',
        filePath: filePath,
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        final s3Key = (body['s3Key'] ??
            (body['data'] is Map ? (body['data'] as Map)['s3Key'] : null))
            as String?;
        if (s3Key != null && s3Key.isNotEmpty) return s3Key;
      }
      _createError.value = _apiErrorMessage(response) ??
          'Thumbnail upload failed (${response.statusCode}).';
      return null;
    } catch (e) {
      log('Stream thumbnail upload error: $e');
      _createError.value = 'Thumbnail upload failed. Please try again.';
      return null;
    } finally {
      _isUploadingThumbnail.value = false;
    }
  }

  /// Creates a new stream via `POST /api/v1/seller/streams`. When [goLiveNow]
  /// is false a [scheduledStartTime] (sent as UTC ISO-8601) is required.
  /// Refreshes the streams list on success. Returns the created [StreamModel]
  /// (or a truthy result) on success, null on failure ([createError] set).
  Future<bool> createStream({
    required String title,
    String? description,
    required List<String> sizes,
    required bool goLiveNow,
    DateTime? scheduledStartTime,
    String? thumbnailUrl,
    int? streamDurationMinutes,
  }) async {
    if (_isCreatingStream.value) return false;
    _isCreatingStream.value = true;
    _createError.value = null;
    try {
      final body = <String, dynamic>{
        'title': title,
        'sizes': sizes,
        'goLiveNow': goLiveNow,
      };
      if (description != null && description.trim().isNotEmpty) {
        body['description'] = description.trim();
      }
      if (!goLiveNow && scheduledStartTime != null) {
        body['scheduledStartTime'] =
            scheduledStartTime.toUtc().toIso8601String();
      }
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
        body['thumbnailUrl'] = thumbnailUrl;
      }
      if (streamDurationMinutes != null) {
        body['streamDurationMinutes'] = streamDurationMinutes;
      }

      final response = await _api.post(
        '${EnvConfig.baseUrl}/api/v1/seller/streams',
        headers: AuthService.instance.authHeaders,
        body: body,
      );

      if (response.isSuccess && response.json['success'] == true) {
        await fetchStreams(refresh: true);
        return true;
      }

      _createError.value = _apiErrorMessage(response) ??
          'Could not create stream (${response.statusCode}).';
      return false;
    } catch (e) {
      log('Create stream error: $e');
      _createError.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isCreatingStream.value = false;
    }
  }
  /// Editing a stream — same body shape as create, sent with PATCH.
  final RxBool _isUpdatingStream = false.obs;
  bool get isUpdatingStream => _isUpdatingStream.value;

  final RxBool _isDeletingStream = false.obs;
  bool get isDeletingStream => _isDeletingStream.value;

  /// Updates a stream via `PATCH /api/v1/seller/streams/:streamId`, carrying
  /// the same body shape as [createStream] so the edit form can reuse the
  /// create form end to end. Optional fields are only sent when supplied —
  /// e.g. `thumbnailUrl` goes out only when the seller picked a new image, so
  /// an untouched thumbnail is never overwritten with a display URL.
  /// Refreshes the list on success; the API error message (when present) is
  /// stored in [createError].
  Future<bool> updateStream({
    required String streamId,
    required String title,
    String? description,
    List<String>? sizes,
    bool? goLiveNow,
    DateTime? scheduledStartTime,
    String? thumbnailUrl,
    int? streamDurationMinutes,
  }) async {
    if (_isUpdatingStream.value) return false;
    _isUpdatingStream.value = true;
    _createError.value = null;
    try {
      final body = <String, dynamic>{
        'title': title,
        'description': description ?? '',
      };
      if (sizes != null) body['sizes'] = sizes;
      if (goLiveNow != null) body['goLiveNow'] = goLiveNow;
      if (goLiveNow != true && scheduledStartTime != null) {
        body['scheduledStartTime'] =
            scheduledStartTime.toUtc().toIso8601String();
      }
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
        body['thumbnailUrl'] = thumbnailUrl;
      }
      if (streamDurationMinutes != null) {
        body['streamDurationMinutes'] = streamDurationMinutes;
      }
      log('[UpdateStream] PATCH $streamId body=$body');

      final response = await _api.patch(
        '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId',
        headers: AuthService.instance.authHeaders,
        body: body,
      );

      if (response.isSuccess && response.json['success'] == true) {
        await fetchStreams(refresh: true);
        return true;
      }

      _createError.value = _apiErrorMessage(response) ??
          'Could not update stream (${response.statusCode}).';
      return false;
    } catch (e) {
      log('Update stream error: $e');
      _createError.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isUpdatingStream.value = false;
    }
  }

  /// Deletes a stream via `DELETE /api/v1/seller/streams/:streamId`. Removes it
  /// from the local list on success. The API error message (when present) is
  /// stored in [createError].
  Future<bool> deleteStream(String streamId) async {
    if (_isDeletingStream.value) return false;
    _isDeletingStream.value = true;
    _createError.value = null;
    try {
      final response = await _api.delete(
        '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        // A 204 has an empty body; only parse JSON when there's something to read.
        final ok = response.statusCode == 204 ||
            response.body.trim().isEmpty ||
            response.json['success'] == true;
        if (ok) {
          _streams.removeWhere((s) => s.id == streamId);
          return true;
        }
      }

      _createError.value = _apiErrorMessage(response) ??
          'Could not delete stream (${response.statusCode}).';
      return false;
    } catch (e) {
      log('Delete stream error: $e');
      _createError.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isDeletingStream.value = false;
    }
  }

  /// Loads the scheduled-streams list backing the "Assign to live" tab.
  ///
  /// [silent] makes it a background sync: the loading flag is never raised (so
  /// no spinner replaces a list the seller is already using) and a failure
  /// leaves both the current list and [scheduledError] untouched — the tab
  /// keeps showing the last good data instead of an error the seller never
  /// asked for. Used by the bottom bar, which re-syncs on every Products tap.
  Future<bool> fetchStreamsByStatus({
    required String status,
    bool refresh = false,
    bool silent = false,
  }) async {
    // Without [refresh] this is a one-shot load (skipped once we already have
    // streams). Pull-to-refresh passes refresh:true to force a reload.
    if (!refresh && _scheduledStreams.isNotEmpty) {
      _scheduledLoaded.value = true;
      return false;
    }
    // Only a scheduled fetch already in flight blocks this one — the paged
    // [fetchStreams] must not, or opening "Assign to live" while the Streams
    // tab is still loading would drop this call and strand the tab empty.
    // Tracked separately from [_isLoadingScheduled] because a silent sync is
    // in flight without ever raising that flag.
    if (_scheduledFetchInFlight) return false;
    _scheduledFetchInFlight = true;
    if (!silent) {
      _isLoadingScheduled.value = true;
      _scheduledError.value = null;
    }

    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/streams?status=$status',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final data = body['data'] as Map<String, dynamic>;
          final items = (data['items'] as List)
              .map((e) => StreamModel.fromJson(e as Map<String, dynamic>))
              .toList();
          if (refresh) {
            _scheduledStreams.assignAll(items);
            // Re-point the current selection at its fresh instance (matched by
            // id) so the dropdown value stays valid after the list is replaced.
            final prevId = selectedStream.value?.id;
            if (prevId != null) {
              StreamModel? match;
              for (final s in items) {
                if (s.id == prevId) {
                  match = s;
                  break;
                }
              }
              selectedStream.value = match;
            }
          } else {
            _scheduledStreams.addAll(items);
          }
          // A silent sync that succeeds still clears a stale error banner left
          // by an earlier visible load.
          _scheduledError.value = null;
          return true;
        }
        if (!silent) _scheduledError.value = 'Unexpected response format.';
        return false;
      }

      if (!silent) {
        _scheduledError.value =
            'Could not load streams: ${response.statusCode}';
      }
      return false;
    } catch (e) {
      log('Scheduled stream fetch error: $e');
      if (!silent) _scheduledError.value = 'Network error. Please try again.';
      return false;
    } finally {
      _scheduledFetchInFlight = false;
      if (!silent) _isLoadingScheduled.value = false;
      _scheduledLoaded.value = true;
    }
  }
//{success: true, data: {action: incremented, quantity: 5, item: {id: d11ced16-1a46-4b9f-a8bf-5c1bdb87bc0b, productId: 00a21a90-4f2a-4314-b7fb-32dc8e276957, quantityRequested: 5, reservedQuantity: 0, pendingQuantity: 5, lineStatus: PENDING_STOCK, isUnknownUpc: false, requestedUpc: 193671596948, requestedName: null, requestedImageUrls: [], sortOrder: 0, createdProductId: null, fulfilledAt: null, fulfillmentNote: null, createdAt: 2026-05-27T22:25:45.311732+00:00, updatedAt: 2026-05-28T09:24:24.159028+00:00, product: {id: 00a21a90-4f2a-4314-b7fb-32dc8e276957, name: RFID-lommebok med triangel-logo, thumbnailUrl: https://tommesalgbucket.s3.eu-north-1.amazonaws.com/products/00a21a90-4f2a-4314-b7fb-32dc8e276957/0.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=AKIATON3WBARHIKRAL5E%2F20260528%2Feu-north-1%2Fs3%2Faws4_request&X-Amz-Date=20260528T092424Z&X-Amz-Expires=3600&X-Amz-Signature=28ad7aac4878bd4df1ff23c1b54fc25e2b8802bba3e2a57e0c200d53ca201b47&X-Amz-SignedHeaders=host&x-amz-checksum-mode=ENABLED&x-id=GetObject}}}, meta: {}}
  Future<bool> addScannedProductByStream({required String upc}) async {


    if (_isProductUploading.value) return false;
    _isProductUploading.value = true;
    _errorMessage.value = null;

    try {
      final response = await _api.post(
        '${EnvConfig.baseUrl}/api/v1/seller/streams/${selectedStream.value?.id}/product-requests/scan',
        headers: AuthService.instance.authHeaders,
        body: {
          "upc": upc
        }
      );
      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true && body['data'] is Map) {
          final streamId = selectedStream.value?.id;
          if (streamId != null) {
            await fetchProductRequests(streamId);
          }
          return true;
        }
        _errorMessage.value = 'Unexpected response format.';
        return false;
      }else{
        final body = response.json;
        Map<String,dynamic>? error =body["error"];
        if(error!=null){
          String? errorMessage=error['code'];
          if(errorMessage!=null){
            if(errorMessage=="PRODUCT_NOT_FOUND_IN_CATALOG"){
              _isProductNotFoundByScan.value=true;
              _lastScannedUpc.value = upc;
            }
          }
        }
      }

      _errorMessage.value = 'Could not load streams: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Stream fetch error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isProductUploading.value = false;
    }
  }

  /// Dismisses the "add unknown product" form and clears the pending UPC so the
  /// seller can scan again. The form reappears if the next scan is also unknown.
  void clearProductNotFound() {
    _isProductNotFoundByScan.value = false;
    _lastScannedUpc.value = null;
    _errorMessage.value = null;
  }

  /// Called when a stream is selected from the dropdown. Loads the product
  /// requests for that stream so the scanned-products list can be shown.
  Future<void> selectStream(StreamModel? stream) async {
    selectedStream.value = stream;
    _productRequestItems.clear();
    _productRequestId.value = null;
    if (stream == null) return;
    await fetchProductRequests(stream.id);
  }

  // ---------- Send to auction queue ----------

  final _queueDispatch = AuctionQueueDispatchService();

  final RxBool _isSendingToQueue = false.obs;
  bool get isSendingToQueue => _isSendingToQueue.value;

  /// The products currently assigned to the selected stream that the auction
  /// queue will actually accept — real catalog products only.
  ///
  /// A hand-added unknown-UPC row has no catalog `productId` yet (it exists as
  /// a product *request* until an admin resolves it), and the queue endpoint
  /// keys on product ids, so those rows are excluded rather than posted as
  /// empty ids the server would reject.
  List<String> get queueableProductIds {
    final ids = <String>{};
    for (final item in _productRequestItems) {
      if (item.isUnknownUpc) continue;
      if (item.productId.isEmpty) continue;
      ids.add(item.productId);
    }
    return ids.toList();
  }

  /// Rows that can't be queued — surfaced so the seller is told what was left
  /// behind instead of silently sending fewer products than they can see.
  int get unqueueableCount =>
      _productRequestItems.length - queueableProductIds.length;

  /// Sends every queueable product assigned to the selected stream to that
  /// stream's auction queue (`POST …/auction-room/queue`, batch form — the same
  /// endpoint the room's own multi-select add uses).
  ///
  /// Safe to call from outside the auction room: it claims a one-shot session
  /// for the mutation instead of booting the room's camera / RTM / WebSocket
  /// stack. See [AuctionQueueDispatchService].
  Future<QueueDispatchResult> sendProductsToAuctionQueue({
    String auctionType = 'NORMAL',
  }) async {
    if (_isSendingToQueue.value) {
      return const QueueDispatchResult.failed('Already sending — one moment.');
    }
    final stream = selectedStream.value;
    if (stream == null) {
      return const QueueDispatchResult.failed('Select a stream first.');
    }

    _isSendingToQueue.value = true;
    try {
      return await _queueDispatch.send(
        streamId: stream.id,
        productIds: queueableProductIds,
        auctionType: auctionType,
        skipped: unqueueableCount,
      );
    } finally {
      _isSendingToQueue.value = false;
    }
  }

  /// 1) Fetch the product-request list for the stream and grab the first
  ///    request's id, then 2) fetch that request's detail to get the items.
  Future<void> fetchProductRequests(String streamId) async {
    if (_isLoadingProductRequests.value) return;
    _isLoadingProductRequests.value = true;
    _errorMessage.value = null;

    try {
      final listResponse = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/product-requests',
        headers: AuthService.instance.authHeaders,
      );

      if (!listResponse.isSuccess) {
        _errorMessage.value =
            'Could not load product requests: ${listResponse.statusCode}';
        return;
      }

      final listBody = listResponse.json;
      final listData =
          listBody['success'] == true && listBody['data'] is Map<String, dynamic>
              ? listBody['data'] as Map<String, dynamic>
              : null;
      final items = listData?['items'] as List?;
      if (items == null || items.isEmpty) {
        _productRequestItems.clear();
        _productRequestId.value = null;
        return;
      }

      final firstRequest = items.first as Map<String, dynamic>;
      final requestId = firstRequest['id'] as String?;
      if (requestId == null) {
        _productRequestItems.clear();
        return;
      }
      _productRequestId.value = requestId;

      await _fetchProductRequestDetail(streamId, requestId);
    } catch (e) {
      log('Product requests fetch error: $e');
      _errorMessage.value = 'Network error. Please try again.';
    } finally {
      _isLoadingProductRequests.value = false;
    }
  }

  /// Fetch the reported issue (discrepancy) for a single product-request item.
  /// Returns null when there is no issue or the request fails.
  Future<ProductRequestIssue?> fetchProductRequestItemIssue(
    String itemId,
  ) async {
    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/product-requests/items/$itemId/issue',
        headers: AuthService.instance.authHeaders,
      );

      if (!response.isSuccess) return null;

      final body = response.json;
      final data = body['data'];
      if (body['success'] == true &&
          data is Map<String, dynamic> &&
          data['issue'] is Map<String, dynamic>) {
        return ProductRequestIssue.fromJson(
          data['issue'] as Map<String, dynamic>,
        );
      }
      return null;
    } catch (e) {
      log('Product request issue fetch error: $e');
      return null;
    }
  }

  /// Whether the body is one of the API's own error payloads (`{error: {...}}`)
  /// rather than a bare framework/proxy response.
  bool _hasApiErrorEnvelope(ApiResponse response) {
    try {
      return response.json['error'] is Map;
    } catch (_) {
      return false;
    }
  }

  /// Extracts a human-readable `error.message` from an API response body,
  /// or null when the body has no such field.
  String? _apiErrorMessage(ApiResponse response) {
    try {
      final error = response.json['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.trim().isNotEmpty) return message;
      }
    } catch (_) {}
    return null;
  }

  /// Uploads a single discrepancy image as `multipart/form-data` and returns
  /// the `s3Key` from the response, or null on failure. On failure the API's
  /// error message (when present) is stored in [errorMessage].
  Future<String?> uploadProductRequestIssueImage(String filePath) async {
    try {
      final response = await _api.uploadFile(
        '${EnvConfig.baseUrl}/api/v1/seller/product-request-issue-images',
        fieldName: 'file',
        filePath: filePath,
        headers: AuthService.instance.authHeaders,
      );

      if (!response.isSuccess) {
        _errorMessage.value = _apiErrorMessage(response) ??
            'Image upload failed (${response.statusCode}).';
        return null;
      }

      final body = response.json;
      final data = body['data'];
      if (body['success'] == true && data is Map<String, dynamic>) {
        return data['s3Key'] as String?;
      }
      _errorMessage.value = _apiErrorMessage(response) ?? 'Image upload failed.';
      return null;
    } catch (e) {
      log('Issue image upload error: $e');
      _errorMessage.value = 'Image upload failed. Please try again.';
      return null;
    }
  }

  /// Reports/updates the discrepancy issue for a product-request item.
  ///
  /// When [imagePaths] is non-empty each file is uploaded first and the
  /// resulting `s3Key`s are sent as `imageKeys`. When empty, only the message
  /// is sent.
  Future<bool> submitProductRequestItemIssue({
    required String itemId,
    required String message,
    List<String> imagePaths = const [],
  }) async {
    _errorMessage.value = null;
    try {
      final imageKeys = <String>[];
      for (final path in imagePaths) {
        final key = await uploadProductRequestIssueImage(path);
        if (key == null) {
          // uploadProductRequestIssueImage already set the API error message.
          _errorMessage.value ??= 'Image upload failed. Please try again.';
          return false;
        }
        imageKeys.add(key);
      }

      final body = <String, dynamic>{'message': message};
      if (imageKeys.isNotEmpty) {
        body['imageKeys'] = imageKeys;
      }

      final response = await _api.patch(
        '${EnvConfig.baseUrl}/api/v1/seller/product-requests/items/$itemId/issue',
        headers: AuthService.instance.authHeaders,
        body: body,
      );

      if (response.isSuccess) return true;

      _errorMessage.value = _apiErrorMessage(response) ??
          'Could not update report: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Submit product request issue error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    }
  }

  /// Sets the product's shipping tier (79 / 99 / 129 / 169 / 249 NOK) via
  /// `PUT /seller/products/{productId}/shipping`. The product must sit on a
  /// product request for one of the seller's own streams.
  ///
  /// On success every loaded request item for that product is patched in
  /// place, so reopening its quick view shows the saved tier without a refetch.
  Future<bool> updateProductShipping({
    required String productId,
    required num shippingPriceNok,
  }) async {
    _errorMessage.value = null;
    try {
      final response = await _api.put(
        '${EnvConfig.baseUrl}/api/v1/seller/products/$productId/shipping',
        headers: AuthService.instance.authHeaders,
        body: {'shippingPriceNok': shippingPriceNok},
      );

      if (!response.isSuccess) {
        _errorMessage.value = _apiErrorMessage(response) ??
            'Could not update shipping: ${response.statusCode}';
        return false;
      }

      for (var i = 0; i < _productRequestItems.length; i++) {
        final item = _productRequestItems[i];
        if (item.productId != productId || item.product == null) continue;
        _productRequestItems[i] = item.copyWith(
          product: item.product!.copyWith(shippingPriceNok: shippingPriceNok),
        );
      }
      return true;
    } catch (e) {
      log('Update product shipping error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    }
  }

  /// Adds a product that wasn't found in the catalog. Any selected images are
  /// uploaded first (reusing the issue-image upload) and their `s3Key`s are
  /// sent as `requestedImageUrls`.
  Future<bool> addUnknownProduct({
    required String name,
    List<String> imagePaths = const [],
    String? upc,
  }) async {
    final streamId = selectedStream.value?.id;
    final effectiveUpc = upc ?? _lastScannedUpc.value;
    if (streamId == null || effectiveUpc == null) {
      _errorMessage.value = 'Missing stream or scanned product.';
      return false;
    }
    if (_isProductUploading.value) return false;
    _isProductUploading.value = true;
    _errorMessage.value = null;

    try {
      final imageKeys = <String>[];
      for (final path in imagePaths) {
        final key = await uploadProductRequestIssueImage(path);
        if (key == null) {
          // uploadProductRequestIssueImage already set the API error message.
          _errorMessage.value ??= 'Image upload failed. Please try again.';
          return false;
        }
        imageKeys.add(key);
      }

      final body = <String, dynamic>{
        'upc': effectiveUpc,
        'requestedName': name,
      };
      if (imageKeys.isNotEmpty) {
        body['requestedImageUrls'] = imageKeys;
      }

      final response = await _api.post(
        '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/product-requests/scan/unknown',
        headers: AuthService.instance.authHeaders,
        body: body,
      );

      if (response.isSuccess && response.json['success'] == true) {
        _isProductNotFoundByScan.value = false;
        _lastScannedUpc.value = null;
        await fetchProductRequests(streamId);
        return true;
      }

      _errorMessage.value = _apiErrorMessage(response) ??
          'Could not add product: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Add unknown product error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isProductUploading.value = false;
    }
  }

  /// Removes a single assigned product from the selected stream via
  /// `DELETE /api/v1/seller/streams/:streamId/product-requests/items/:itemId`,
  /// then reloads the list so the UI matches the server.
  ///
  /// The row is dropped locally first so the card disappears on tap; the
  /// re-fetch is what makes it authoritative, and a failed call restores the
  /// list by re-fetching too.
  Future<bool> deleteProductRequestItem(String itemId) async {
    final streamId = selectedStream.value?.id;
    if (streamId == null) {
      _errorMessage.value = 'Select a stream first.';
      return false;
    }
    if (_deletingItemIds.contains(itemId)) return false;

    _deletingItemIds.add(itemId);
    _errorMessage.value = null;

    try {
      final response = await _api.delete(
        '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/product-requests/items/$itemId',
        headers: AuthService.instance.authHeaders,
      );

      if (response.isSuccess) {
        // A 204 has an empty body; only parse JSON when there's something to read.
        final ok = response.statusCode == 204 ||
            response.body.trim().isEmpty ||
            response.json['success'] == true;
        if (ok) {
          _productRequestItems.removeWhere((item) => item.id == itemId);
          _deletingItemIds.remove(itemId);
          await fetchProductRequests(streamId);
          return true;
        }
      }

      _errorMessage.value = _apiErrorMessage(response) ??
          'Could not delete product (${response.statusCode}).';
      return false;
    } catch (e) {
      log('Delete product request item error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _deletingItemIds.remove(itemId);
    }
  }

  Future<void> _fetchProductRequestDetail(
    String streamId,
    String requestId,
  ) async {
    final response = await _api.get(
      '${EnvConfig.baseUrl}/api/v1/seller/streams/$streamId/product-requests/$requestId',
      headers: AuthService.instance.authHeaders,
    );

    if (!response.isSuccess) {
      _errorMessage.value =
          'Could not load product request: ${response.statusCode}';
      return;
    }

    final body = response.json;
    final data = body['success'] == true && body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : null;
    final items = (data?['items'] as List?)
            ?.map((e) =>
                ProductRequestItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        <ProductRequestItem>[];

    _productRequestItems.assignAll(items);
  }
}
