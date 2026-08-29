import 'dart:convert';
import 'dart:developer' as dev;

import 'package:agora_rtm/agora_rtm.dart';

import '../models/live_chat_message.dart';

/// Wraps the Agora RTM 2.x (Signaling) client for the live auction chat.
///
/// The seller logs in with their user id + RTM token and subscribes to the
/// chat channel (`auction:{streamId}`). Both directions speak the JSON envelope
/// `{ type, id, text, ts }`:
///
///  * `type: "CHAT"` → a chat line, surfaced via [onMessage].
///  * `type: "MODERATION_DELETE"` → delete one message, via [onModerationDelete].
///  * `type: "MODERATION_CLEAR"` → wipe the chat, via [onModerationClear].
///
/// Non-JSON payloads are treated as a bare chat line for backward compat.
class AgoraRtmService {
  RtmClient? _client;
  String? _channelName;
  bool _loggedIn = false;

  static const String _tag = 'AgoraRtmService';

  bool get isLoggedIn => _loggedIn;

  Future<void> initAndLogin({
    required String appId,
    required String userId,
    required String token,
    required void Function(LiveChatMessage message) onMessage,
    required void Function(String messageId) onModerationDelete,
    required void Function() onModerationClear,
    required Future<void> Function() onTokenWillExpire,
    void Function(String message)? onError,
  }) async {
    if (_loggedIn) return;

    final (createStatus, client) = await RTM(appId, userId);
    if (createStatus.error) {
      throw StateError('RTM create failed: ${createStatus.reason}');
    }
    _client = client;

    client.addListener(
      message: (MessageEvent event) => _handleMessage(
        event,
        onMessage: onMessage,
        onModerationDelete: onModerationDelete,
        onModerationClear: onModerationClear,
      ),
      token: (TokenEvent event) {
        dev.log('rtm token will expire — renewing', name: _tag);
        onTokenWillExpire();
      },
      linkState: (LinkStateEvent event) {
        dev.log('rtm link state: ${event.currentState}', name: _tag);
      },
    );

    final (loginStatus, _) = await client.login(token);
    if (loginStatus.error) {
      onError?.call('RTM login failed: ${loginStatus.reason}');
      throw StateError('RTM login failed: ${loginStatus.reason}');
    }
    _loggedIn = true;
    dev.log('rtm logged in as $userId', name: _tag);
  }

  /// Subscribes to the chat [channelName] (`auction:{streamId}`).
  Future<void> subscribe(String channelName) async {
    final client = _client;
    if (client == null || !_loggedIn) return;
    _channelName = channelName;
    final (status, _) = await client.subscribe(
      channelName,
      withMessage: true,
      withPresence: true,
    );
    if (status.error) {
      throw StateError('RTM subscribe failed: ${status.reason}');
    }
    dev.log('rtm subscribed to $channelName', name: _tag);
  }

  /// Publishes a chat message as `{ type: "CHAT", id, text, ts }`.
  Future<void> sendMessage({
    required String id,
    required String text,
    required int ts,
  }) async {
    final client = _client;
    final channel = _channelName;
    final trimmed = text.trim();
    if (client == null || channel == null || trimmed.isEmpty) return;
    final payload = jsonEncode({
      'type': 'CHAT',
      'id': id,
      'text': trimmed,
      'ts': ts,
    });
    final (status, _) = await client.publish(channel, payload);
    if (status.error) {
      throw StateError('RTM publish failed: ${status.reason}');
    }
  }

  /// Broadcasts a moderation action (`MODERATION_DELETE` / `MODERATION_CLEAR`)
  /// to every subscriber of the channel.
  Future<void> sendModeration({
    required String type,
    String? messageId,
  }) async {
    final client = _client;
    final channel = _channelName;
    if (client == null || channel == null) return;
    final payload = jsonEncode({
      'type': type,
      if (messageId != null) 'messageId': messageId,
    });
    await client.publish(channel, payload);
  }

  Future<void> renewToken(String token) async {
    final client = _client;
    if (client == null) return;
    await client.renewToken(token);
  }

  Future<void> dispose() async {
    final client = _client;
    if (client == null) return;
    try {
      final channel = _channelName;
      if (channel != null) await client.unsubscribe(channel);
      if (_loggedIn) await client.logout();
      await client.release();
    } catch (e) {
      dev.log('rtm dispose error: $e', name: _tag);
    } finally {
      _client = null;
      _channelName = null;
      _loggedIn = false;
    }
  }

  void _handleMessage(
    MessageEvent event, {
    required void Function(LiveChatMessage message) onMessage,
    required void Function(String messageId) onModerationDelete,
    required void Function() onModerationClear,
  }) {
    final raw = _decode(event);
    if (raw == null) return;
    final senderId = event.publisher ?? 'unknown';

    // Everything the wire gives us about who sent this. RTM carries no profile
    // data, so this is the full set of identity fields available for a buyer
    // message — useful while working out where a real name should come from.
    dev.log(
      'RX message | publisher=$senderId | customType=${event.customType} '
      '| channel=${event.channelName} | topic=${event.channelTopic} '
      '| ts=${event.timestamp} | payload=$raw',
      name: _tag,
    );

    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) payload = decoded;
    } catch (_) {
      // Not JSON — handled below as a plain chat line.
    }

    if (payload == null) {
      onMessage(LiveChatMessage(
        id: '$senderId:${event.timestamp ?? ''}',
        senderId: senderId,
        text: raw,
        timestamp: event.timestamp,
      ));
      return;
    }

    switch (payload['type']) {
      case 'CHAT':
        final text = (payload['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) return;
        final ts = (payload['ts'] as num?)?.toInt() ?? event.timestamp;
        final id = (payload['id'] as String?)?.trim();
        // Senders don't include a name today (the room resolves it from the
        // user id), but honour one if a client starts sending it.
        final name =
            ((payload['name'] ?? payload['senderName']) as String?)?.trim();
        onMessage(LiveChatMessage(
          id: (id != null && id.isNotEmpty) ? id : '$senderId:${ts ?? ''}',
          senderId: senderId,
          text: text,
          timestamp: ts,
          senderName: (name == null || name.isEmpty) ? null : name,
        ));
        break;
      case 'MODERATION_DELETE':
        final mid = (payload['messageId'] as String?)?.trim();
        if (mid != null && mid.isNotEmpty) onModerationDelete(mid);
        break;
      case 'MODERATION_CLEAR':
        onModerationClear();
        break;
      default:
        break;
    }
  }

  String? _decode(MessageEvent event) {
    final bytes = event.message;
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }
}
