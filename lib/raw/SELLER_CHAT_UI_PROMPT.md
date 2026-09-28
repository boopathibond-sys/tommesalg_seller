# Seller app — live auction chat UI (port of the buyer UI)

Paste everything below the line into a Claude Code session opened on the **seller** app.

---

## PROMPT

I want the live-stream chat in this seller app to look and behave exactly like the buyer app's
auction room chat: a transparent, bottom-left message list floating over the video, with a
rounded "Say something…" input field under it.

### Wire contract — must match the buyer app exactly (do not change it)

- Transport is **Agora RTM (Signaling 2.x)**, separate from the RTC video channel and from the
  auction WebSocket.
- **Chat channel name = `auction:{streamId}`** (the RTC video channel is the bare `streamId`).
  If the seller publishes to the bare `streamId`, buyers will never see the messages.
- Every payload is a JSON string:
  - chat line → `{"type":"CHAT","id":"<uuid>","text":"<body>","ts":<epochMillis>}`
  - delete one line → `{"type":"MODERATION_DELETE","messageId":"<id>"}`
  - wipe chat → `{"type":"MODERATION_CLEAR"}`
  - any other `type` must be ignored, and a non-JSON payload is treated as a bare chat line.
- `id` is what moderation targets, so it must survive the round trip: mint a uuid locally for
  our own lines and use the payload `id` for received ones (fall back to `"$senderId:$ts"`).
- `senderId` is the RTM `event.publisher` (the Supabase user id).
- Display names are resolved in batches via `GET /api/v1/users/display-names?ids=a,b,c`
  (debounce ~250 ms, cache per session, fall back to the first 12 chars of the id).

### Controller behaviour to mirror

1. Optimistically append our own sent line, and skip the RTM echo where `senderId == myUserId`.
2. Drop duplicates of the same `senderId:text` seen within a 2 s window.
3. Cap the in-memory buffer at 200 messages (keep the newest).
4. Chat is best-effort: if RTM login/subscribe fails, log it and keep the video running —
   the field just stays disabled.
5. `chatReady` flips true only after `subscribe()` succeeds; the send button is gated on it.

### Visual spec (measured off the buyer build — keep these numbers)

- Column sits bottom-left over the video: list height `screenHeight * 0.30`, width
  `screenWidth * 0.72`, input field padded `bottom 12, top 8, left 10, right 30`.
- List is `reverse: true` (newest at the bottom), horizontal padding 12, 10 px gap between rows,
  `keyboardDismissBehavior: onDrag`, and masked by a top-to-bottom `ShaderMask`
  (transparent → white, stops 0.0 / 0.25) so old lines fade out at the top.
- Wrap the `ShaderMask` in a `RepaintBoundary` (outside it, not inside) — chat is the fastest
  changing layer over a video painting at frame rate.
- Row = 28 px circle avatar with the initial, 10 px gap, then name over message.
  - name: 12.5 px, w500, white at 72 % opacity, 1 line, ellipsis
  - message: 13.5 px, w700, white, line height 1.25
  - both carry `Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1))`
- The **host/seller's own lines** are the highlighted ones: yellow avatar (`0xFFFFD844`) with
  navy initial (`0xFF0A1420`), a red `SELLER` badge (`0xFFE5233A`, 8.5 px, w800, radius 4)
  beside the name, and the whole row boxed in `black @ 30 %`, radius 14, 1 px `white @ 10 %`
  border, padding `(8, 6, 10, 8)`. Everyone else renders unboxed with a navy avatar.
- Input field: 36 px tall, radius 30, fill `black @ 28 %`, 1.2 px `white @ 70 %` border,
  horizontal padding 14. Text 14 px w500 white, yellow cursor, `isCollapsed`, no border.
  `textInputAction: TextInputAction.done` wired through `onEditingComplete` (not `onSubmitted`)
  so exactly one send fires per key press.
- Send icon only appears once there is non-empty text (yellow `Icons.send_rounded`, 20 px), and
  becomes `Icons.do_not_disturb_on_outlined` in `white24` when sending is blocked. It rebuilds
  off a `ValueListenableBuilder` on the `TextEditingController` — never `setState` on keystroke.
- After every send: clear the field, unfocus, and hide the keyboard with
  `SystemChannels.textInput.invokeMethod('TextInput.hide')` (iOS needs the channel call as well
  as `unfocus()`). Pressing Done on an empty field just dismisses the keyboard.
- Tapping the message list also dismisses the keyboard (`HitTestBehavior.translucent` —
  the scrollable only claims the arena on a drag, so the tap still wins).

### Seller-side differences from the buyer app

- The seller **is** the host, so their own lines get the `SELLER` badge and the box. Pass
  `sellerId == currentUserId`.
- Long-press on someone else's line should open the seller's **moderation** actions
  (delete message / mute user), not the buyer's report-and-block sheet. Wire
  `onLongPressMessage` to whatever moderation the seller app already has; deleting must publish
  `MODERATION_DELETE` with that message's `id` so buyers drop it too.
- The field must also be disabled (with a reason hint) when the seller has turned chat off for
  the room or the stream has ended, same gating as the buyer.

### What to build

Use the widget code below as-is — it is UI-only and prop-driven, with no Riverpod/GetX
dependency, so it drops into whatever state management this app uses. Wire it to the seller's
existing live-stream controller/state and add the RTM pieces if this app does not have them yet.

```dart
// lib/features/live_stream/presentation/widgets/live_chat_overlay.dart
//
// Live auction chat, ported from the buyer app so both sides look identical.
// UI only: hand it the message list and a send callback.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single chat message exchanged over Agora RTM during a live auction.
///
/// Wire envelope: `{ "type": "CHAT", "id": <uuid>, "text": <body>, "ts": <ms> }`.
/// [id] is what moderation targets, so it must survive the round trip.
class LiveChatMessage {
  const LiveChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.timestamp,
  });

  final String id;
  final String senderId;
  final String text;
  final int? timestamp;
}

// Brand colours — swap for this app's AppColors if it has them.
const Color _kYellow = Color(0xFFFFD844);
const Color _kNavy = Color(0xFF0A1420);
const Color _kSellerRed = Color(0xFFE5233A);

/// Soft shadow so white chat text stays readable over a bright video frame.
const List<Shadow> kChatTextShadow = [
  Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
];

/// Drops the primary focus *and* tells the engine to retract the text input —
/// on iOS a scope-level `unfocus()` alone can leave the keyboard on screen.
void hideKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

/// Bottom-left column over the video: the fading chat list above the
/// "Say something…" field. Drop this into the player's overlay Stack, aligned
/// bottom-left.
class LiveChatOverlay extends StatelessWidget {
  const LiveChatOverlay({
    super.key,
    required this.messages,
    required this.currentUserId,
    required this.sellerId,
    required this.displayNames,
    required this.onSend,
    this.canSend = true,
    this.hint = 'Say something...',
    this.showInput = true,
    this.onLongPressMessage,
  });

  final List<LiveChatMessage> messages;

  /// The signed-in user (the seller, in this app).
  final String currentUserId;

  /// The host of the room — their lines get the badge and the box.
  final String? sellerId;

  /// senderId → resolved display name (batched lookup, may be missing).
  final Map<String, String> displayNames;

  final ValueChanged<String> onSend;

  /// False greys out the field: chat off for the room, muted, stream ended,
  /// or RTM not subscribed yet.
  final bool canSend;

  /// Reason shown in the field when blocked, otherwise the normal placeholder.
  final String hint;

  /// A SCHEDULED stream has nothing to post into yet — hide the field.
  final bool showInput;

  /// Long-press on another user's line (seller moderation: delete / mute).
  final void Function(LiveChatMessage message, String senderName)?
      onLongPressMessage;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tapping the list drops the keyboard; the scrollable only claims the
        // gesture arena on a drag, so this tap still wins.
        GestureDetector(
          onTap: hideKeyboard,
          behavior: HitTestBehavior.translucent,
          child: SizedBox(
            height: screen.height * 0.30,
            width: screen.width * 0.72,
            child: RepaintBoundary(
              child: LiveChatList(
                messages: messages,
                currentUserId: currentUserId,
                sellerId: sellerId,
                displayNames: displayNames,
                onLongPressMessage: onLongPressMessage,
              ),
            ),
          ),
        ),
        if (showInput)
          Padding(
            // Trimmed on the right only, so the left edge stays flush with the
            // chat list above it.
            padding:
                const EdgeInsets.only(bottom: 12, top: 8, left: 10, right: 30),
            child: SayField(
              onSend: onSend,
              canSend: canSend,
              hint: hint,
            ),
          )
        else
          const SizedBox(height: 12),
      ],
    );
  }
}

/// The floating message list: newest at the bottom, fading out at the top.
class LiveChatList extends StatelessWidget {
  const LiveChatList({
    super.key,
    required this.messages,
    required this.currentUserId,
    required this.sellerId,
    required this.displayNames,
    this.onLongPressMessage,
  });

  final List<LiveChatMessage> messages;
  final String currentUserId;
  final String? sellerId;
  final Map<String, String> displayNames;
  final void Function(LiveChatMessage message, String senderName)?
      onLongPressMessage;

  String _labelFor(String senderId) {
    if (senderId == currentUserId) return 'You';
    final name = displayNames[senderId];
    if (name != null && name.isNotEmpty) return name;
    return senderId.length > 12 ? senderId.substring(0, 12) : senderId;
  }

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();

    // RepaintBoundary belongs *around* the ShaderMask, not inside it: the mask
    // renders its child to an offscreen layer (one saveLayer per paint), and
    // chat is the most frequently-changing thing on the screen.
    return RepaintBoundary(
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white],
          stops: [0.0, 0.25],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          reverse: true,
          // Dragging the list retracts the keyboard, as in WhatsApp/Messages.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: messages.length,
          itemBuilder: (_, i) {
            // reverse: true → render newest at the bottom.
            final msg = messages[messages.length - 1 - i];
            final name = _labelFor(msg.senderId);
            final isSeller = sellerId != null &&
                sellerId!.isNotEmpty &&
                msg.senderId == sellerId;
            final isMine = msg.senderId == currentUserId;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: (isMine || onLongPressMessage == null)
                    ? null
                    : () => onLongPressMessage!(msg, name),
                child: Container(
                  // Only the host is boxed — the box is a label that belongs to
                  // the seller's lines, not a highlight that follows the newest
                  // message around.
                  padding: isSeller
                      ? const EdgeInsets.fromLTRB(8, 6, 10, 8)
                      : EdgeInsets.zero,
                  decoration: isSeller
                      ? BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        )
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSeller ? _kYellow : _kNavy,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          name.isEmpty
                              ? '?'
                              : name.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isSeller ? _kNavy : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name is light grey and regular weight so the
                            // message under it carries the line; the seller is
                            // called out by the badge, not by recolouring.
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          Colors.white.withValues(alpha: 0.72),
                                      shadows: kChatTextShadow,
                                    ),
                                  ),
                                ),
                                if (isSeller) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: _kSellerRed,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'SELLER',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 1),
                            Text(
                              msg.text,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.25,
                                shadows: kChatTextShadow,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Rounded "Say something…" input. Greys out with a reason hint when
/// [canSend] is false (chat off, muted, stream ended, RTM not ready).
class SayField extends StatefulWidget {
  const SayField({
    super.key,
    required this.onSend,
    this.canSend = true,
    this.hint = 'Say something...',
    this.onFocusChanged,
  });

  final ValueChanged<String> onSend;
  final bool canSend;
  final String hint;

  /// Mirrors focus out so the overlay can hide its action rail / widen the
  /// field while the keyboard is up.
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<SayField> createState() => _SayFieldState();
}

class _SayFieldState extends State<SayField> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// True once the keyboard has actually raised the bottom inset. Guards the
  /// retract check below so the opening frames (focus set, inset still 0)
  /// don't immediately blur the field and snap the keyboard shut.
  bool _keyboardWasOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() => widget.onFocusChanged?.call(_focusNode.hasFocus);

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final bottomInset = View.of(context).viewInsets.bottom;
    if (bottomInset > 0) {
      _keyboardWasOpen = true;
      return;
    }
    // Keyboard fully retracted (after having been open) but the field kept
    // focus — e.g. dismissed with the keyboard's own button — so blur it.
    if (_keyboardWasOpen && _focusNode.hasFocus) _focusNode.unfocus();
    _keyboardWasOpen = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Sends what is typed and closes the keyboard. Also the handler for the
  /// keyboard's **Done** key, which is why an empty field still dismisses.
  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _focusNode.unfocus();
      hideKeyboard();
      return;
    }
    widget.onSend(text);
    _controller.clear();
    // Close the keyboard after every send so the video is unobstructed again.
    _focusNode.unfocus();
    hideKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = widget.canSend;
    final Color line = canSend ? Colors.white70 : Colors.white24;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        // Subtle glass fill so the field + hint stay legible over bright frames.
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.7),
          width: 1.2,
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: canSend,
              textInputAction: TextInputAction.done,
              // Overriding onEditingComplete (instead of using onSubmitted)
              // means the framework's finalize path never runs, so there is
              // exactly one send per key press and its default "just unfocus"
              // can't swallow the message.
              onEditingComplete: _send,
              onSubmitted: (_) {},
              cursorColor: _kYellow,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: line,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // Send icon: hidden until something is typed, blocked icon when chat
          // isn't allowed. Driven off the controller so only this icon
          // rebuilds as the field changes — no setState per keystroke.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, __) {
              if (!canSend) {
                return Icon(Icons.do_not_disturb_on_outlined,
                    color: line, size: 20);
              }
              if (value.text.trim().isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                onTap: _send,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.send_rounded, color: _kYellow, size: 20),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
```

### Wiring example

```dart
Align(
  alignment: Alignment.bottomLeft,
  child: LiveChatOverlay(
    messages: state.messages,
    currentUserId: myUserId,
    sellerId: myUserId,            // the seller is the host of their own room
    displayNames: state.displayNames,
    canSend: state.chatReady && state.chatEnabled && !state.isEnded,
    hint: state.chatEnabled ? 'Say something...' : 'Chat is turned off',
    showInput: !state.isScheduled,
    onSend: controller.sendMessage,
    onLongPressMessage: (msg, name) =>
        showSellerModerationSheet(context, messageId: msg.id, userId: msg.senderId),
  ),
)
```

Notes:
- `Color.withValues(alpha:)` needs Flutter 3.27+. On an older SDK swap in `withOpacity(...)`.
- If this app already has a shared text widget and colour tokens, replace the local
  `Text` / `_kYellow` / `_kNavy` with them — the sizes and weights above must stay.
