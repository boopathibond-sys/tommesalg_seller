import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Owns the auction-room WebSocket connection: connect, `resume`, sequence
/// tracking, auth-expiry recovery, clock-sync pings, and reconnect.
///
/// Transport-only: every decoded server message that isn't an auth-control
/// event or a pong is forwarded to [onMessage]; the controller decodes it and
/// applies snapshots. Connection transitions surface through [onConnected] /
/// [onConnectionLost], pongs through [onPong].
///
/// The token rides the upgrade's `Authorization` header. The server does not
/// read an `access_token` query param at all: with a valid token there it
/// answers `WS_AUTH_REQUIRED` and closes 4401 (verified on production
/// 2026-10-10, MOBILE_BUYER_AUCTION_ROOM §2.2). That is why the seller room
/// used to load its REST snapshot and then never see a single live bid or
/// lot close.
class AuctionWebSocketService {
  AuctionWebSocketService({
    required this.wsBaseUrl,
    required this.getAccessToken,
    required this.refreshSession,
    required this.onMessage,
    required this.onConnected,
    required this.onConnectionLost,
    this.onPong,
    this.wsPath = '/ws/auction',
  });

  final String wsBaseUrl; // e.g. wss://tommesalg.no
  final String wsPath;
  final Future<String?> Function() getAccessToken;
  final Future<void> Function() refreshSession;
  final void Function(Map<String, dynamic> message) onMessage;
  final void Function(bool connected) onConnected;

  /// Fired once the fast reconnect ladder is spent. The service keeps trying
  /// on a slow cadence after this — the room shows a banner meanwhile.
  final void Function() onConnectionLost;

  /// One clock sample per pong: our send time (echoed `clientTs`), our
  /// receive time, and the server's `timestamp`.
  final void Function(int clientSentMs, int clientReceivedMs, int serverMs)?
      onPong;

  static const _tag = 'AuctionWs';
  static const _maxReconnectAttempts = 5;

  /// Once the fast ladder is spent, keep trying at this pace rather than
  /// leaving a live room deaf until the seller notices the banner.
  static const _slowRetry = Duration(seconds: 20);

  /// Steady heartbeat, plus an opening burst for the clock (§3.5).
  static const _pingInterval = Duration(seconds: 25);
  static const _burstCount = 5;
  static const _burstGap = Duration(milliseconds: 200);

  /// Nothing at all back within this long after a ping → the socket is dead
  /// even if the OS hasn't said so (Wi-Fi → cellular). Reconnect.
  static const _pongTimeout = Duration(seconds: 10);
  static const _handshakeTimeout = Duration(seconds: 10);
  static const _rateLimitedBackoff = Duration(seconds: 15);

  /// Auth recoveries allowed per window, so a token the server keeps refusing
  /// can't spin a refresh/reconnect loop.
  static const _maxAuthRecoveries = 2;
  static const _authWindow = Duration(seconds: 30);

  static const _uuid = Uuid();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  Timer? _burstTimer;
  Timer? _pongWatchdog;
  Timer? _reconnectTimer;

  String? _streamId;
  int _lastSequence = 0;
  int _reconnectAttempt = 0;
  bool _shouldReconnect = true;
  bool _connecting = false;
  bool _disposed = false;
  bool _rateLimited = false;
  int? _lastPingSentAt;
  final List<DateTime> _authRecoveries = [];

  /// The attempt counter is reset only once a socket has delivered something:
  /// a server that accepts the upgrade and drops us straight away must still
  /// walk the backoff ladder instead of retrying at 1 s forever.
  bool _receivedSinceOpen = false;

  bool get isConnected => _channel != null;

  Future<void> connect(String streamId) async {
    if (_disposed || _connecting) return;
    if (_channel != null && _streamId == streamId) return;
    _connecting = true;
    _streamId = streamId;
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) {
        _connecting = false;
        _scheduleReconnect();
        return;
      }

      final uri = Uri.parse(
        '$wsBaseUrl$wsPath?streamId=${Uri.encodeComponent(streamId)}',
      );
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      _channel = channel;
      await channel.ready.timeout(_handshakeTimeout);
      if (_disposed) {
        await channel.sink.close();
        return;
      }

      _receivedSinceOpen = false;
      onConnected(true);
      _subscription = channel.stream.listen(
        _handleRawMessage,
        onDone: _handleDone,
        onError: (Object e, StackTrace st) {
          dev.log('socket error: $e', name: _tag);
          _handleDone();
        },
        cancelOnError: true,
      );

      _send({
        'type': 'resume',
        'requestId': _uuid.v4(),
        'lastSequence': _lastSequence,
      });
      _startPing();
      dev.log('connected (lastSequence=$_lastSequence)', name: _tag);
    } catch (e) {
      dev.log('connect failed: $e', name: _tag);
      // A failed handshake must not leave the channel set, or the room
      // reports itself connected to a socket that never opened.
      final failed = _channel;
      _channel = null;
      if (failed != null) unawaited(failed.sink.close().catchError((_) {}));
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

    // Anything at all proves the socket is alive.
    _pongWatchdog?.cancel();
    _pongWatchdog = null;
    if (!_receivedSinceOpen) {
      _receivedSinceOpen = true;
      _reconnectAttempt = 0;
    }

    final type = msg['type'];
    if (type == 'pong') {
      _handlePong(msg);
      return;
    }

    final seq = msg['sequence'];
    if (seq is num && seq.toInt() > _lastSequence) _lastSequence = seq.toInt();

    if (type == 'AUTH_EXPIRED') {
      _handleAuthExpired();
      return;
    }
    if (type == 'WS_ERROR') {
      final payload = msg['payload'];
      final code = payload is Map ? payload['code'] as String? : null;
      dev.log('WS_ERROR $code', name: _tag);
      if (_handleWsError(code)) return;
    }

    onMessage(msg);
  }

  void _handlePong(Map<String, dynamic> msg) {
    final received = DateTime.now().millisecondsSinceEpoch;
    final payload = msg['payload'];
    final sent = (payload is Map ? payload['clientTs'] as num? : null)?.toInt() ??
        _lastPingSentAt;
    final server = DateTime.tryParse(msg['timestamp'] as String? ?? '');
    if (sent == null || server == null) return;
    onPong?.call(sent, received, server.millisecondsSinceEpoch);
  }

  /// `WS_ERROR` per the contract's code table. True when handled here.
  bool _handleWsError(String? code) {
    switch (code) {
      case 'WS_AUTH_EXPIRED':
      case 'WS_AUTH_INVALID':
      case 'WS_AUTH_REQUIRED':
      case 'WS_SESSION_REVOKED':
        _handleAuthExpired();
        return true;
      case 'WS_RECONNECT_RATE_LIMITED':
        _rateLimited = true;
        return true;
      case 'WS_STALE_CONNECTION':
        _forceReconnect('server reported stale connection');
        return true;
      default:
        return false;
    }
  }

  Future<void> _handleAuthExpired() async {
    final now = DateTime.now();
    _authRecoveries.removeWhere((t) => now.difference(t) > _authWindow);
    final id = _streamId;
    // Close first: the server usually drops the socket right after, and an
    // onDone landing mid-refresh would schedule a second, competing reconnect.
    await _closeSocket();
    onConnected(false);
    if (_disposed || !_shouldReconnect || id == null) return;
    if (_authRecoveries.length >= _maxAuthRecoveries) {
      dev.log('auth refused repeatedly → normal backoff', name: _tag);
      _scheduleReconnect();
      return;
    }
    _authRecoveries.add(now);
    dev.log('auth expired → refresh + reconnect', name: _tag);
    await refreshSession();
    if (!_disposed && _shouldReconnect) await connect(id);
  }

  void _forceReconnect(String reason) {
    if (_disposed || !_shouldReconnect) return;
    dev.log('forcing reconnect: $reason', name: _tag);
    _closeSocket().then((_) {
      onConnected(false);
      _scheduleReconnect();
    });
  }

  void _handleDone() {
    if (_channel == null && _subscription == null) return;
    final code = _channel?.closeCode;
    if (code != null) dev.log('socket closed ($code)', name: _tag);
    _stopPing();
    _subscription = null;
    _channel = null;
    onConnected(false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final id = _streamId;
    if (_disposed || !_shouldReconnect || id == null) return;
    if (_reconnectTimer?.isActive ?? false) return;

    Duration delay;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      if (_reconnectAttempt == _maxReconnectAttempts) {
        dev.log('fast reconnect gave up → retrying every '
            '${_slowRetry.inSeconds}s', name: _tag);
        onConnectionLost();
        _reconnectAttempt++;
      }
      delay = _slowRetry;
    } else {
      _reconnectAttempt++;
      delay = Duration(
        milliseconds: min(1000 * pow(2, _reconnectAttempt - 1).toInt(), 10000),
      );
    }
    if (_rateLimited) {
      _rateLimited = false;
      if (delay < _rateLimitedBackoff) delay = _rateLimitedBackoff;
    }
    dev.log('reconnect #$_reconnectAttempt in ${delay.inMilliseconds}ms',
        name: _tag);
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_disposed || !_shouldReconnect || _streamId == null) return;
      await _closeSocket();
      await connect(_streamId!);
    });
  }

  /// Back from the background, or a tap on the "connection lost" banner:
  /// probe a live socket, or reconnect a dead one straight away with a fresh
  /// backoff budget.
  void reconnectNow() {
    final id = _streamId;
    if (_disposed || !_shouldReconnect || id == null) return;
    if (_channel != null) {
      // Alive → the burst re-measures the clock; dead → no pong, and the
      // watchdog reconnects within [_pongTimeout].
      _pingBurst();
      return;
    }
    if (_connecting) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    connect(id);
  }

  void _startPing() {
    _stopPing();
    _pingBurst();
    _pingTimer = Timer.periodic(_pingInterval, (_) => _ping());
  }

  void _pingBurst() {
    _burstTimer?.cancel();
    var sent = 1;
    _ping();
    _burstTimer = Timer.periodic(_burstGap, (t) {
      if (sent >= _burstCount || _channel == null) {
        t.cancel();
        return;
      }
      _ping();
      sent++;
    });
  }

  void _ping() {
    if (_channel == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastPingSentAt = now;
    _send({'type': 'ping', 'clientTs': now});
    _pongWatchdog ??= Timer(_pongTimeout, () {
      _pongWatchdog = null;
      _forceReconnect('no reply to ping in ${_pongTimeout.inSeconds}s');
    });
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _burstTimer?.cancel();
    _burstTimer = null;
    _pongWatchdog?.cancel();
    _pongWatchdog = null;
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

  /// The stream is over: keep the socket for the terminal SNAPSHOT, but don't
  /// come back if the server closes it.
  void markTerminal() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
    if (!kReleaseMode) dev.log('disposed', name: _tag);
  }
}
