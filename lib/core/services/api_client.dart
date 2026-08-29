import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// Invoked when the API responds with 401 + `error.code == "AUTH_EXPIRED"`.
  /// Wire this up once at app start to clear the session and bounce to login.
  void Function()? onSessionExpired;

  /// Invoked when any API responds with `error.code == "AUTH_ROLE_REQUIRED"`
  /// (the signed-in account is not a seller). Wire this up once at app start to
  /// clear the session and bounce to login.
  ///
  /// Only meaningful for endpoints that *should* accept a seller. A call to an
  /// endpoint gated to another role answers the same way, and signing the
  /// seller out over that would be wrong — such calls pass
  /// `suppressAuthHandlers: true`.
  void Function()? onRoleRequired;

  Future<ApiResponse> get(
    String url, {
    Map<String, String>? headers,
    bool suppressAuthHandlers = false,
  }) async {
    return _request('GET', url,
        headers: headers, suppressAuthHandlers: suppressAuthHandlers);
  }

  Future<ApiResponse> post(
    String url, {
    Map<String, String>? headers,
    Object? body,
    bool suppressAuthHandlers = false,
  }) async {
    return _request('POST', url,
        headers: headers,
        body: body,
        suppressAuthHandlers: suppressAuthHandlers);
  }

  Future<ApiResponse> put(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _request('PUT', url, headers: headers, body: body);
  }

  Future<ApiResponse> patch(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _request('PATCH', url, headers: headers, body: body);
  }

  Future<ApiResponse> delete(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _request('DELETE', url, headers: headers, body: body);
  }

  /// Uploads a single file as `multipart/form-data`.
  ///
  /// [fieldName] is the form-data key (e.g. `file`) and [filePath] points to a
  /// local image. [fields] carries any text parts that go alongside the file
  /// (endpoints like random-product create take the whole record as one
  /// multipart body). The `Content-Type` header is intentionally dropped so the
  /// multipart boundary header is used instead.
  Future<ApiResponse> uploadFile(
    String url, {
    required String fieldName,
    required String filePath,
    Map<String, String>? headers,
    Map<String, String>? fields,
    bool suppressAuthHandlers = false,
  }) async {
    final uri = Uri.parse(url);
    final stopwatch = Stopwatch()..start();

    _logRequest('POST (multipart)', url, headers,
        'file: $filePath${fields == null ? '' : ' fields: $fields'}');

    try {
      final request = http.MultipartRequest('POST', uri);
      headers?.forEach((key, value) {
        // Let MultipartRequest set its own multipart Content-Type/boundary.
        if (key.toLowerCase() == 'content-type') return;
        request.headers[key] = value;
      });
      if (fields != null) request.fields.addAll(fields);
      request.files.add(
        await http.MultipartFile.fromPath(
          fieldName,
          filePath,
          contentType: _mediaTypeForPath(filePath),
        ),
      );

      final streamed = await request.send();
      final responseBody = await streamed.stream.bytesToString();
      stopwatch.stop();

      _logResponse(
        'POST',
        url,
        streamed.statusCode,
        responseBody,
        stopwatch.elapsedMilliseconds,
      );

      if (!suppressAuthHandlers) {
        if (streamed.statusCode == 401 && _isAuthExpired(responseBody)) {
          onSessionExpired?.call();
        }
        if (_isRoleRequired(responseBody)) {
          onRoleRequired?.call();
        }
      }

      return ApiResponse(
        statusCode: streamed.statusCode,
        body: responseBody,
      );
    } catch (e, stack) {
      stopwatch.stop();
      _logError('POST', url, e, stack, stopwatch.elapsedMilliseconds);
      rethrow;
    }
  }

  /// Resolves the multipart `Content-Type` for an upload from its file
  /// extension. `http`'s [http.MultipartFile.fromPath] otherwise defaults to
  /// `application/octet-stream`, which servers reject as an invalid file type.
  MediaType? _mediaTypeForPath(String filePath) {
    final name = filePath.toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot < 0) return null;
    switch (name.substring(dot + 1)) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      // Documents — the seller-application CV upload rejects anything typed
      // as octet-stream, so these three have to be stamped explicitly too.
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'doc':
        return MediaType('application', 'msword');
      case 'docx':
        return MediaType('application',
            'vnd.openxmlformats-officedocument.wordprocessingml.document');
      default:
        return null;
    }
  }

  Future<ApiResponse> _request(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
    bool suppressAuthHandlers = false,
  }) async {
    final uri = Uri.parse(url);
    final encodedBody = body != null ? jsonEncode(body) : null;
    final stopwatch = Stopwatch()..start();

    _logRequest(method, url, headers, encodedBody);

    final client = HttpClient();
    try {
      late HttpClientRequest request;
      switch (method) {
        case 'GET':
          request = await client.getUrl(uri);
          break;
        case 'POST':
          request = await client.postUrl(uri);
          break;
        case 'PUT':
          request = await client.putUrl(uri);
          break;
        case 'PATCH':
          request = await client.patchUrl(uri);
          break;
        case 'DELETE':
          request = await client.deleteUrl(uri);
          break;
        default:
          request = await client.getUrl(uri);
      }

      headers?.forEach((key, value) {
        request.headers.set(key, value);
      });

      if (encodedBody != null) {
        request.add(utf8.encode(encodedBody));
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      stopwatch.stop();

      _logResponse(method, url, response.statusCode, responseBody, stopwatch.elapsedMilliseconds);

      if (!suppressAuthHandlers) {
        if (response.statusCode == 401 && _isAuthExpired(responseBody)) {
          onSessionExpired?.call();
        }
        if (_isRoleRequired(responseBody)) {
          onRoleRequired?.call();
        }
      }

      return ApiResponse(
        statusCode: response.statusCode,
        body: responseBody,
      );
    } catch (e, stack) {
      stopwatch.stop();
      _logError(method, url, e, stack, stopwatch.elapsedMilliseconds);
      rethrow;
    } finally {
      client.close();
    }
  }

  void _logRequest(String method, String url, Map<String, String>? headers, String? body) {
    if (!kDebugMode) return;
    debugPrint('');
    debugPrint('┌──────────────────────────────────────────');
    debugPrint('│ ➡️  REQUEST');
    debugPrint('│ $method  $url');
    if (headers != null && headers.isNotEmpty) {
      debugPrint('│ Headers:');
      headers.forEach((k, v) {
        debugPrint('│   $k: $v');
      });
    }
    if (body != null) {
      debugPrint('│ Body:');
      _printPrettyJson(body, '│   ');
    }
    debugPrint('└──────────────────────────────────────────');
  }

  void _logResponse(String method, String url, int statusCode, String body, int ms) {
    if (!kDebugMode) return;
    final emoji = statusCode >= 200 && statusCode < 300 ? '✅' : '❌';
    debugPrint('');
    debugPrint('┌──────────────────────────────────────────');
    debugPrint('│ $emoji  RESPONSE  [$statusCode]  ${ms}ms');
    debugPrint('│ $method  $url');
    debugPrint('│ Body:');
    _printPrettyJson(body, '│   ');
    debugPrint('└──────────────────────────────────────────');
  }

  void _logError(String method, String url, Object error, StackTrace stack, int ms) {
    if (!kDebugMode) return;
    debugPrint('');
    debugPrint('┌──────────────────────────────────────────');
    debugPrint('│ 🔥  ERROR  ${ms}ms');
    debugPrint('│ $method  $url');
    debugPrint('│ $error');
    debugPrint('│ ${stack.toString().split('\n').take(5).join('\n│ ')}');
    debugPrint('└──────────────────────────────────────────');
  }

  bool _isAuthExpired(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        return (decoded['error'] as Map)['code'] == 'AUTH_EXPIRED';
      }
    } catch (_) {}
    return false;
  }

  bool _isRoleRequired(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        return (decoded['error'] as Map)['code'] == 'AUTH_ROLE_REQUIRED';
      }
    } catch (_) {}
    return false;
  }

  void _printPrettyJson(String raw, String prefix) {
    try {
      final decoded = jsonDecode(raw);
      final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
      for (final line in pretty.split('\n')) {
        debugPrint('$prefix$line');
      }
    } catch (_) {
      debugPrint('$prefix$raw');
    }
  }
}

class ApiResponse {
  final int statusCode;
  final String body;

  ApiResponse({required this.statusCode, required this.body});

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  Map<String, dynamic> get json =>
      jsonDecode(body) as Map<String, dynamic>;
}
