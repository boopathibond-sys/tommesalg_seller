import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Owns the auction-room WebSocket connection: connect, `resume`, sequence
/// tracking, auth-expiry recovery, and exponential-backoff reconnect.
///
/// Transport-only: every decoded server message that isn't an auth-control
/// event is forwarded to [onMessage]; the controller decodes it and applies
/// snapshots. Connection transitions surface through [onConnected] /
/// [onConnectionLost].
class AuctionWebSocketService {
  AuctionWebSocketService({
    required this.wsBaseUrl,
    required this.getAccessToken,
    required this.refreshSession,
    required this.onMessage,
    required this.onConnected,
    required this.onConnectionLost,
    this.wsPath = '/ws/auction',
    this.accessTokenParam = 'access_token',
  });

  final String wsBaseUrl; // e.g. wss://tommesalg.no
  final String wsPath;
  final String accessTokenParam;
  final Future<String?> Function() getAccessToken;
  final Future<void> Function() refreshSession;
  final void Function(Map<String, dynamic> message) onMessage;
  final void Function(bool connected) onConnected;
  final void Function() onConnectionLost;

  static const _tag = 'AuctionWs';
  static const _maxReconnectAttempts = 5;
  static const _pingInterval = Duration(seconds: 25);
  static const _uuid = Uuid();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  String? _streamId;
  int _lastSequence = 0;
  int _reconnectAttempt = 0;
  bool _shouldReconnect = true;
  bool _connecting = false;
  bool _disposed = false;

  bool get isConnected => _channel != null;

  Future<void> connect(String streamId) async {
    if (_disposed || _connecting) return;
    _connecting = true;
    _streamId = streamId;
    _shouldReconnect = true;
    _reconnectTimer?.cancel();

    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) {
        _connecting = false;
        _scheduleReconnect();
        return;
      }

      final uri = Uri.parse(
        '$wsBaseUrl$wsPath'
        '?streamId=${Uri.encodeComponent(streamId)}'
        '&$accessTokenParam=${Uri.encodeComponent(token)}',
      );

      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;
      if (_disposed) {
        await channel.sink.close();
        return;
      }

      _subscription = channel.stream.listen(
        _handleRawMessage,
        onDone: _handleDone,
        onError: (Object e, StackTrace st) {
          dev.log('socket error: $e', name: _tag);
          _scheduleReconnect();
        },
        cancelOnError: true,
      );

      _send({
        'type': 'resume',
        'requestId': _uuid.v4(),
        'lastSequence': _lastSequence,
      });

      _reconnectAttempt = 0;
      _startPing();
      onConnected(true);
      dev.log('connected (lastSequence=$_lastSequence)', name: _tag);
    } catch (e) {
      dev.log('connect failed: $e', name: _tag);
      onConnected(false);
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleRawMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map) return;
      msg = Map<String, dynamic>.from(decoded);
    } catch (e) {
      dev.log('bad message dropped: $e', name: _tag);
      return;
    }

    final seq = msg['sequence'];
    if (seq is int && seq > _lastSequence) _lastSequence = seq;

    final type = msg['type'];
    if (type == 'AUTH_EXPIRED') {
      _handleAuthExpired();
      return;
    }
    if (type == 'WS_ERROR') {
      final payload = msg['payload'];
      final code = payload is Map ? payload['code'] : null;
      if (code == 'WS_AUTH_EXPIRED' || code == 'WS_AUTH_INVALID') {
        _handleAuthExpired();
        return;
      }
    }
    if (type == 'pong') return;

    onMessage(msg);
  }

  Future<void> _handleAuthExpired() async {
    dev.log('auth expired → refresh + reconnect', name: _tag);
    await refreshSession();
    final id = _streamId;
    await _closeSocket();
    if (!_disposed && id != null) await connect(id);
  }

  void _handleDone() {
    _stopPing();
    onConnected(false);
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final id = _streamId;
    if (_disposed || !_shouldReconnect || id == null) return;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      dev.log('reconnect gave up after $_reconnectAttempt attempts', name: _tag);
      onConnectionLost();
      return;
    }
    _reconnectAttempt++;
    final delayMs = min(1000 * pow(2, _reconnectAttempt - 1).toInt(), 10000);
    dev.log('reconnect #$_reconnectAttempt in ${delayMs}ms', name: _tag);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (_disposed || !_shouldReconnect || _streamId == null) return;
      await _closeSocket();
      await connect(_streamId!);
    });
  }

  void _startPing() {
    _stopPing();
    _pingTimer = Timer.periodic(_pingInterval, (_) => _send({'type': 'ping'}));
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _send(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (e) {
      dev.log('send failed: $e', name: _tag);
    }
  }

  Future<void> _closeSocket() async {
    _stopPing();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  /// Permanent teardown — call on screen dispose / explicit leave.
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeSocket();
    onConnected(false);
  }

  void dispose() {
    _disposed = true;
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stopPing();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
