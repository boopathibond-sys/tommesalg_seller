import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../controllers/auction_room_controller.dart';
import '../../data/models/live_chat_message.dart';
import '../../../../core/localization/translation_keys.dart';
import '../widgets/report_sheet.dart';

/// The Chat tab: live auction chat over Agora RTM with server-authoritative
/// moderation (enable/disable chat, delete message, mute/unmute a viewer,
/// clear). The seller can long-press any viewer message to moderate it.
class ChatTab extends StatefulWidget {
  const ChatTab({super.key, required this.ctrl});
  final AuctionRoomController ctrl;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Drops focus *and* asks the engine to hide the soft keyboard. Unfocusing
  /// alone isn't enough: when the field is already unfocused (the framework
  /// drops focus itself on the keyboard's send action) the platform text-input
  /// connection can stay open on both iOS and Android, leaving the keyboard up
  /// over the chat.
  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    widget.ctrl.sendChat(text);
    _input.clear();
    _dismissKeyboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: CustomText(TKeys.ctLiveChat.tr, fontSize: 14,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              Obx(() => _HeaderAction(
                    icon: ctrl.chatDisabled
                        ? Icons.chat_bubble_outline_rounded
                        : Icons.do_not_disturb_on_outlined,
                    label: ctrl.chatDisabled ? TKeys.ctEnable.tr : TKeys.ctDisable.tr,
                    onTap: ctrl.toggleChatEnabled,
                  )),
              _HeaderAction(
                icon: Icons.clear_all_rounded,
                label: TKeys.ctClear.tr,
                onTap: () => _confirmClear(context, ctrl),
              ),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
            final msgs = ctrl.messages;
            if (msgs.isEmpty) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: Center(
                  child: CustomText(TKeys.ctNoMessages.tr,
                      fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textMuted),
                ),
              );
            }
            // Read here, not inside itemBuilder — Obx only tracks observables
            // touched while its own builder runs, so a read from a lazily-built
            // list item would never trigger a rebuild. This is what makes a
            // fresh mute — or a name that just finished resolving — repaint the
            // chat.
            final muted = ctrl.mutedUserIds;
            // Copied, not referenced: reading the field alone registers
            // nothing with Obx, and the per-bubble lookups happen inside
            // `itemBuilder`, which runs outside this builder. Iterating the
            // RxMap here is the read that makes a freshly resolved name
            // repaint the chat.
            final names = Map<String, String>.of(ctrl.displayNames);
            return ListView.builder(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              itemCount: msgs.length,
              itemBuilder: (_, i) {
                final m = msgs[i];
                return _ChatBubble(
                  message: m,
                  // Resolved profile name first, then whatever the RTM payload
                  // carried; the bubble falls back to a short id while a new
                  // sender's lookup is still in flight.
                  senderName: names[m.senderId] ?? m.senderName,
                  muted: muted.contains(m.senderId),
                  onModerate: m.isMine ? null : () => _moderate(context, ctrl, m),
                );
              },
            );
          }),
        ),
        Obx(() {
          final err = ctrl.chatError.value;
          if (ctrl.chatReady.value || err == null) return const SizedBox.shrink();
          return _ChatConnectionBanner(message: err, onRetry: ctrl.retryChat);
        }),
        Obx(() => ctrl.chatDisabled
            ? const _DisabledBanner()
            : const SizedBox.shrink()),
        _Composer(controller: _input, onSend: _send),
      ],
    );
  }

  Future<void> _moderate(
    BuildContext context,
    AuctionRoomController ctrl,
    LiveChatMessage m,
  ) async {
    final muted = ctrl.isMuted(m.senderId);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.inputBorder,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 6),
            _SheetTile(
              icon: Icons.delete_outline_rounded,
              label: TKeys.ctDeleteMessage.tr,
              color: AppColors.vipps,
              onTap: () {
                Navigator.of(sctx).pop();
                ctrl.deleteChatMessage(m.id);
              },
            ),
            _SheetTile(
              icon: muted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              label: muted ? TKeys.ctUnmuteViewer.tr : TKeys.ctMuteViewer.tr,
              onTap: () {
                Navigator.of(sctx).pop();
                if (muted) {
                  ctrl.unmuteUser(m.senderId);
                } else {
                  ctrl.muteUser(m.senderId);
                }
              },
            ),
            // Delete and mute only clean up this room; reporting is what
            // reaches a human at Tommesalg, which App Review guideline 1.2
            // requires of an app carrying user-generated content.
            _SheetTile(
              icon: Icons.flag_outlined,
              label: TKeys.ctReportMessage.tr,
              onTap: () {
                Navigator.of(sctx).pop();
                showReportSheet(
                  context: context,
                  targetType: 'CHAT_MESSAGE',
                  targetId: m.id,
                  reportedUserId: m.senderId,
                  contextId: ctrl.streamId,
                  // Quote the line so the reviewer does not have to dig it out
                  // of the stream log — it may be deleted by then.
                  contentPreview: m.text,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmClear(BuildContext context, AuctionRoomController ctrl) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: CustomText(TKeys.ctClearChatTitle.tr, fontSize: 18,
          fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      content: CustomText(TKeys.ctClearChatBody.tr,
          fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: CustomText(TKeys.cancelAction.tr, fontSize: 14,
              fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(true),
          child: CustomText(TKeys.ctClear.tr, fontSize: 14,
              fontWeight: FontWeight.w800, color: AppColors.vipps),
        ),
      ],
    ),
  );
  if (ok == true) await ctrl.clearChat();
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
      icon: Icon(icon, size: 16, color: AppColors.textSecondary),
      label: CustomText(label, fontSize: 12.5,
          fontWeight: FontWeight.w700, color: AppColors.textSecondary),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.muted,
    this.senderName,
    this.onModerate,
  });
  final LiveChatMessage message;
  final String? senderName;
  final bool muted;
  final VoidCallback? onModerate;

  @override
  Widget build(BuildContext context) {
    // The seller's own lines are highlighted — navy bubble, yellow "You · Host"
    // label and a yellow rim — so the host's voice stands out from viewer
    // chatter at a glance (matching how buyers see seller messages).
    final mine = message.isMine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onModerate,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: mine ? AppColors.brandNavy : AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: mine ? AppColors.brandYellow : AppColors.inputBorder,
              width: mine ? 1.4 : 1,
            ),
            boxShadow: mine
                ? [
                    BoxShadow(
                      color: AppColors.brandYellow.withOpacity(0.3),
                      blurRadius: 10, offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mine) ...[
                    const Icon(Icons.storefront_rounded,
                        size: 11, color: AppColors.brandYellow),
                    const SizedBox(width: 4),
                  ],
                  CustomText(
                    mine ? TKeys.ctYouHost.tr : (senderName ?? _short(message.senderId)),
                    fontSize: 10.5, fontWeight: mine ? FontWeight.w800 : FontWeight.w700,
                    color: mine ? AppColors.brandYellow : AppColors.textMuted,
                  ),
                  if (!mine && muted) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.volume_off_rounded, size: 11, color: AppColors.vipps),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              CustomText(message.text, fontSize: 13.5, fontWeight: FontWeight.w500,
                  color: mine ? AppColors.white : AppColors.textPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder label while a sender's real name is still being resolved.
String _short(String id) => id.length > 6 ? TKeys.ctUserPrefix.trParams({'id': id.substring(0, 6)}) : id;

class _ChatConnectionBanner extends StatelessWidget {
  const _ChatConnectionBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        width: double.infinity,
        color: AppColors.vipps.withOpacity(0.08),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 14, color: AppColors.vipps),
            const SizedBox(width: 8),
            Flexible(
              child: CustomText(message,
                  fontSize: 11.5, fontWeight: FontWeight.w700,
                  textAlign: TextAlign.center, color: AppColors.vipps),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.refresh_rounded, size: 14, color: AppColors.vipps),
          ],
        ),
      ),
    );
  }
}

class _DisabledBanner extends StatelessWidget {
  const _DisabledBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.vipps.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: CustomText(TKeys.ctChatDisabled.tr,
          fontSize: 11.5, fontWeight: FontWeight.w700,
          textAlign: TextAlign.center, color: AppColors.vipps),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.textPrimary,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: CustomText(label, fontSize: 15, fontWeight: FontWeight.w700, color: color),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.inputBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              cursorColor: AppColors.brandNavy,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: TKeys.ctMessageHint.tr,
                isDense: true,
                filled: true,
                fillColor: AppColors.inputFill,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(
                color: AppColors.brandNavy, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, size: 20, color: AppColors.brandYellow),
            ),
          ),
        ],
      ),
    );
  }
}
