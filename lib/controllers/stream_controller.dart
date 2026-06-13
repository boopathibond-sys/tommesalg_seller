import 'dart:developer';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../models/product_request_model.dart';
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

  final RxList<StreamModel> _streams = <StreamModel>[].obs;
  final RxList<StreamModel> _scheduledStreams = <StreamModel>[].obs;
  final selectedStream = Rxn<StreamModel>();
  List<StreamModel> get streams => _streams.toList();
  List<StreamModel> get scheduledStreams => _scheduledStreams.toList();

  final RxInt _page = 1.obs;
  final RxBool _hasMore = true.obs;
  bool get hasMore => _hasMore.value;

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

  /// The UPC of the last scan that wasn't found in the catalog. Used to
  /// pre-fill the "add unknown product" request.
  final RxnString _lastScannedUpc = RxnString();
  String? get lastScannedUpc => _lastScannedUpc.value;

  // ---------- Services ----------

  final _api = ApiClient.instance;

  // ---------- Intents ----------

  Future<bool> fetchStreams({bool refresh = false}) async {
    if (refresh) {
      _page.value = 1;
      _hasMore.value = true;
    }

    if (_isLoading.value) return false;

    _isLoading.value = true;
    _errorMessage.value = null;

    try {
      final response = await _api.get(
        '${EnvConfig.baseUrl}/api/v1/seller/streams?page=${_page.value}&pageSize=20',
        headers: AuthService.instance.authHeaders,
      );

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
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoading.value = false;
    }
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
  Future<bool> fetchStreamsByStatus({
    required String status,
    bool refresh = false,
  }) async {
    log("ksdjcksdjcd ${AuthService.instance.accessToken}");
    // Without [refresh] this is a one-shot load (skipped once we already have
    // streams). Pull-to-refresh passes refresh:true to force a reload.
    if (!refresh && _scheduledStreams.isNotEmpty) return false;
    if (_isLoading.value) return false;
    _isLoading.value = true;
    _errorMessage.value = null;

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
          return true;
        }
        _errorMessage.value = 'Unexpected response format.';
        return false;
      }

      _errorMessage.value = 'Could not load streams: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Stream fetch error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isLoading.value = false;
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
