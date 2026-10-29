import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  // ── Session recovery hooks (wired to AuthService in `main()`) ──
  //
  // They apply only to requests that carry a `Bearer` header and aren't auth
  // routes themselves, so a refresh or ensure-profile call can never recurse.

  /// Returns a bearer that is valid for at least another minute (refreshing
  /// first when needed). Consulted before every bearer request, so a call never
  /// leaves with a token that is about to expire.
  Future<String?> Function()? freshAccessToken;

  /// Forces one refresh after `401 AUTH_EXPIRED` and returns the new token for
  /// a single retry, or null when none could be minted.
  Future<String?> Function()? refreshAccessToken;

  /// Provisions the app profile after `401 AUTH_USER_NOT_FOUND`. Returns
  /// whether it now exists, in which case the request is retried once.
  Future<bool> Function()? ensureProfile;

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
    return _withRecovery(
      url,
      headers,
      (h) => _sendMultipart(url,
          fieldName: fieldName, filePath: filePath, headers: h, fields: fields),
      suppressAuthHandlers: suppressAuthHandlers,
    );
  }

  Future<ApiResponse> _sendMultipart(
    String url, {
    required String fieldName,
    required String filePath,
    Map<String, String>? headers,
    Map<String, String>? fields,
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
  }) {
    return _withRecovery(
      url,
      headers,
      (h) => _send(method, url, headers: h, body: body),
      suppressAuthHandlers: suppressAuthHandlers,
    );
  }

  /// Runs [send] with a fresh bearer, then recovers once from the two 401s
  /// that aren't the seller's fault (contract §7.1, §8.2):
  ///
  ///  * `AUTH_EXPIRED` → refresh, retry once with the new token;
  ///  * `AUTH_USER_NOT_FOUND` → ensure-profile, retry once. Not a token
  ///    problem, so no refresh and no logout.
  ///
  /// [suppressAuthHandlers] only silences [onRoleRequired]; recovery still
  /// runs, because a refreshed token is never the wrong answer.
  Future<ApiResponse> _withRecovery(
    String url,
    Map<String, String>? headers,
    Future<ApiResponse> Function(Map<String, String>? headers) send, {
    required bool suppressAuthHandlers,
  }) async {
    final recover = _bearerKey(headers) != null && !_isAuthRoute(url);

    var sent = recover
        ? _withBearer(headers!, await freshAccessToken?.call())
        : headers;
    var response = await send(sent);

    if (recover && response.statusCode == 401) {
      switch (_errorCode(response.body)) {
        case 'AUTH_EXPIRED':
          final token = await refreshAccessToken?.call();
          if (token != null) {
            sent = _withBearer(headers!, token);
            response = await send(sent);
          }
          break;
        case 'AUTH_USER_NOT_FOUND':
          if (await ensureProfile?.call() ?? false) {
            response = await send(sent);
          }
          break;
      }
    }

    if (!suppressAuthHandlers &&
        _errorCode(response.body) == 'AUTH_ROLE_REQUIRED') {
      onRoleRequired?.call();
    }
    return response;
  }

  /// The header key holding `Authorization: Bearer …`, whatever its casing.
  String? _bearerKey(Map<String, String>? headers) {
    if (headers == null) return null;
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'authorization' &&
          e.value.startsWith('Bearer ')) {
        return e.key;
      }
    }
    return null;
  }

  Map<String, String> _withBearer(Map<String, String> headers, String? token) {
    if (token == null) return headers;
    return {...headers, _bearerKey(headers)!: 'Bearer $token'};
  }

  /// Auth endpoints manage the session themselves; recovering inside them
  /// would recurse (a refresh that refreshes, an ensure-profile that ensures).
  bool _isAuthRoute(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    return _authRoutes.contains(path) || path.startsWith('/api/v1/buyer/auth/');
  }

  static const Set<String> _authRoutes = {
    '/api/v1/auth/login',
    '/api/v1/auth/refresh',
    '/api/v1/auth/logout',
    '/api/v1/auth/ensure-profile',
    '/api/v1/auth/reset-password',
  };

  Future<ApiResponse> _send(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
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
        final shown = k.toLowerCase() == 'authorization' ? 'Bearer ***' : v;
        debugPrint('│   $k: $shown');
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

  /// `error.code` of a V1 error envelope, or null.
  String? _errorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        return (decoded['error'] as Map)['code'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Body fields that must never reach a log, even a debug one: credentials,
  /// tokens and one-time codes (contract §14).
  static const Set<String> _secretKeys = {
    'password',
    'newPassword',
    'accessToken',
    'refreshToken',
    'idToken',
    'access_token',
    'refresh_token',
    'id_token',
    'code',
    'otp',
  };

  Object? _redact(Object? value) {
    if (value is Map) {
      return {
        for (final e in value.entries)
          e.key: _secretKeys.contains(e.key) && e.value is String
              ? '***'
              : _redact(e.value),
      };
    }
    if (value is List) return value.map(_redact).toList();
    return value;
  }

  void _printPrettyJson(String raw, String prefix) {
    try {
      final decoded = _redact(jsonDecode(raw));
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
