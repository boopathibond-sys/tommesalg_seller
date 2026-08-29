/// A single line in the live auction chat, decoded from an Agora RTM envelope
/// on the `auction:{streamId}` channel.
class LiveChatMessage {
  const LiveChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.timestamp,
    this.senderName,
    this.isMine = false,
  });

  final String id;
  final String senderId;
  final String text;
  final int? timestamp;
  final String? senderName;

  /// True when this device authored the message (used for right-aligned
  /// bubbles). Set locally on send / when the sender id matches ours.
  final bool isMine;

  LiveChatMessage copyWith({String? senderName, bool? isMine}) => LiveChatMessage(
        id: id,
        senderId: senderId,
        text: text,
        timestamp: timestamp,
        senderName: senderName ?? this.senderName,
        isMine: isMine ?? this.isMine,
      );
}
