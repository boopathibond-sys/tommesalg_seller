import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/live_chat_message.dart';

/// Live auction chat as a bottom-left overlay on the camera stage, ported from
/// the buyer app so both sides of the room look identical.
///
/// It replaced a full Chat tab: the seller had to leave the camera to read what
/// buyers were saying, which is the one thing they need while a lot is running.
/// Floating it over the video costs no tab and no screen.
///
/// UI only — hand it the message list and a send callback. The sizes here were
/// measured off the buyer build and are meant to match it exactly.

/// Soft shadow so white chat text stays readable over a bright video frame.
const List<Shadow> kChatTextShadow = [
  Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
];

const Color _kSellerRed = Color(0xFFE5233A);

/// Drops the primary focus *and* tells the engine to retract the text input —
/// on iOS a scope-level `unfocus()` alone can leave the keyboard on screen.
void hideChatKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

/// Bottom-left column over the video: the fading chat list above the
/// "Say something…" field.
class LiveChatOverlay extends StatelessWidget {
  const LiveChatOverlay({
    super.key,
    required this.messages,
    required this.displayNames,
    required this.onSend,
    this.canSend = true,
    required this.hint,
    this.showInput = true,
    this.onLongPressMessage,
    this.onOpenQueue,
    this.queueCount = 0,
  });

  final List<LiveChatMessage> messages;

  /// senderId → resolved display name (batched lookup, may be missing).
  final Map<String, String> displayNames;

  final ValueChanged<String> onSend;

  /// False greys out the field: chat off for the room, stream ended, or RTM
  /// not subscribed yet.
  final bool canSend;

  /// Reason shown in the field when blocked, otherwise the normal placeholder.
  final String hint;

  /// A SCHEDULED stream has nothing to post into yet — hide the field.
  final bool showInput;

  /// Long-press on another viewer's line (delete / mute / report).
  final void Function(LiveChatMessage message)? onLongPressMessage;

  /// Opens the lot queue. The room has no bottom nav any more, so the queue is
  /// reached from the round button that leads this row — beside the field the
  /// seller's thumb is already on, rather than buried in the ⋮ menu. Null hides
  /// the button.
  final VoidCallback? onOpenQueue;

  /// Lots waiting in the queue. The badge that drew it is commented out — the
  /// queue page's title carries the count instead — so this is currently unused
  /// by the button, and kept only so turning the badge back on needs no
  /// plumbing.
  final int queueCount;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tapping the list drops the keyboard; the scrollable only claims the
        // gesture arena on a drag, so this tap still wins.
        GestureDetector(
          onTap: hideChatKeyboard,
          behavior: HitTestBehavior.translucent,
          child: SizedBox(
            height: screen.height * 0.30,
            // Width comes from the parent, not from a fraction of the screen:
            // the broadcast rail sits beside this column and takes its own
            // space out of the row, so chat gets exactly what is left.
            child: _ChatList(
              messages: messages,
              displayNames: displayNames,
              onLongPressMessage: onLongPressMessage,
            ),
          ),
        ),
        if (showInput || onOpenQueue != null)
          Padding(
            // No side inset of its own: the column already sits 12 in from the
            // screen edge, and stacking another 10 on top of that pushed the
            // field in far enough to leave a strip of dead space on the right.
            padding: const EdgeInsets.only(bottom: 4, top: 8),
            child: Row(
              // Bottom-aligned so the round button stays level with the last
              // line of a field that has grown to three.
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (onOpenQueue != null) ...[
                  QueueCircleButton(count: queueCount, onTap: onOpenQueue!),
                  const SizedBox(width: 8),
                ],
                if (showInput)
                  Expanded(
                    child:
                        SayField(onSend: onSend, canSend: canSend, hint: hint),
                  )
                else
                  const Spacer(),
              ],
            ),
          )
        else
          const SizedBox(height: 12),
      ],
    );
  }
}

/// The round, hairline-bordered queue button that leads the say-field row.
///
/// Sized and bordered to match [SayField] so the two read as one control strip
/// over the camera. It carries no count: the number of lots waiting is shown
/// in the title of the page it opens.
class QueueCircleButton extends StatelessWidget {
  const QueueCircleButton({super.key, required this.onTap, this.count = 0});

  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              // Same glass fill and hairline as the field beside it.
              color: Colors.black.withOpacity(0.28),
              shape: BoxShape.circle,
              border:
                  Border.all(color: Colors.white.withOpacity(0.7), width: 1.2),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.inventory_2_outlined,
                size: 19, color: Colors.white),
          ),
          // The badge is off: the count now rides in the queue page's own
          // title ("Product Queue (N)"), which is where the seller reads it
          // anyway, and a number stuck on a 38px circle over live video was
          // never legible mid-sale. Kept rather than deleted so it can be put
          // back without rebuilding the stack.
          // if (count > 0)
          //   Positioned(
          //     top: -3,
          //     right: -3,
          //     child: Container(
          //       padding: const EdgeInsets.symmetric(horizontal: 4),
          //       constraints: const BoxConstraints(minWidth: 16),
          //       height: 16,
          //       alignment: Alignment.center,
          //       decoration: BoxDecoration(
          //         color: AppColors.vipps,
          //         borderRadius: BorderRadius.circular(8),
          //         border: Border.all(color: Colors.white, width: 1.2),
          //       ),
          //       child: Text(
          //         count > 99 ? '99+' : '$count',
          //         style: const TextStyle(
          //           fontSize: 9,
          //           fontWeight: FontWeight.w800,
          //           color: Colors.white,
          //         ),
          //       ),
          //     ),
          //   ),
        ],
      ),
    );
  }
}

/// The floating message list: newest at the bottom, fading out at the top.
class _ChatList extends StatelessWidget {
  const _ChatList({
    required this.messages,
    required this.displayNames,
    this.onLongPressMessage,
  });

  final List<LiveChatMessage> messages;
  final Map<String, String> displayNames;
  final void Function(LiveChatMessage message)? onLongPressMessage;

  String _labelFor(LiveChatMessage m) {
    final resolved = displayNames[m.senderId] ?? m.senderName;
    if (resolved != null && resolved.isNotEmpty) return resolved;
    final id = m.senderId;
    return id.length > 12 ? id.substring(0, 12) : id;
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
          // Hairline inset only — enough to keep an avatar off the edge, not
          // the 12 a full-width list needed when chat had its own screen.
          padding: const EdgeInsets.only(left: 2, right: 4),
          reverse: true,
          // Dragging the list retracts the keyboard, as in WhatsApp/Messages.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: messages.length,
          itemBuilder: (_, i) {
            // reverse: true → render newest at the bottom.
            final msg = messages[messages.length - 1 - i];
            return _ChatRow(
              message: msg,
              name: _labelFor(msg),
              onLongPress: (msg.isMine || onLongPressMessage == null)
                  ? null
                  : () => onLongPressMessage!(msg),
            );
          },
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.message,
    required this.name,
    required this.onLongPress,
  });

  final LiveChatMessage message;
  final String name;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    // In the seller's own room every line they send is the host's.
    final isSeller = message.isMine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress,
        child: Container(
          // Only the host is boxed — the box is a label that belongs to the
          // seller's lines, not a highlight that follows the newest message
          // around.
          padding: isSeller
              ? const EdgeInsets.fromLTRB(8, 6, 10, 8)
              : EdgeInsets.zero,
          decoration: isSeller
              ? BoxDecoration(
                  color: Colors.black.withOpacity(0.30),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
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
                  color: isSeller ? AppColors.brandYellow : AppColors.brandNavy,
                ),
                alignment: Alignment.center,
                child: Text(
                  name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSeller ? AppColors.brandNavy : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name is light grey and regular weight so the message
                    // under it carries the line; the seller is called out by
                    // the badge, not by recolouring.
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
                              color: Colors.white.withOpacity(0.72),
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
                      message.text,
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
  }
}

/// Rounded "Say something…" input. Greys out with a reason hint when
/// [canSend] is false (chat off, stream ended, RTM not ready).
///
/// 38px tall rather than the buyer app's 36: the seller's field sits directly
/// above the auction controls, where the extra two pixels keep it from reading
/// as part of the card under it.
class SayField extends StatefulWidget {
  const SayField({
    super.key,
    required this.onSend,
    required this.hint,
    this.canSend = true,
  });

  final ValueChanged<String> onSend;
  final bool canSend;
  final String hint;

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
  }

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
      hideChatKeyboard();
      return;
    }
    widget.onSend(text);
    _controller.clear();
    // Close the keyboard after every send so the video is unobstructed again.
    _focusNode.unfocus();
    hideChatKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = widget.canSend;
    final Color line = canSend ? Colors.white70 : Colors.white24;

    return Container(
      // Grows with the text instead of scrolling it sideways: a long message
      // wraps and the pill gets taller, up to the three lines below. Min height
      // keeps an empty field the same size it has always been.
      constraints: const BoxConstraints(minHeight: 38),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        // Subtle glass fill so the field + hint stay legible over bright frames.
        color: Colors.black.withOpacity(0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.7), width: 1.2),
      ),
      child: Row(
        // Bottom-aligned so the send icon stays on the last line as the field
        // grows, rather than floating in the middle of a three-line message.
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: canSend,
              minLines: 1,
              maxLines: 3,
              // Explicitly text, not the multiline default `maxLines > 1`
              // implies: multiline turns the return key into a newline, and the
              // Done key is what sends here.
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              // Overriding onEditingComplete (instead of using onSubmitted)
              // means the framework's finalize path never runs, so there is
              // exactly one send per key press and its default "just unfocus"
              // can't swallow the message.
              onEditingComplete: _send,
              onSubmitted: (_) {},
              cursorColor: AppColors.brandYellow,
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
          // isn't allowed. Driven off the controller so only this icon rebuilds
          // as the field changes — no setState per keystroke.
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
                  child: Icon(Icons.send_rounded,
                      color: AppColors.brandYellow, size: 20),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
