import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/stream_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/services/media_permission_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/branded_loading_view.dart';
import '../../core/widgets/branded_refresh_indicator.dart';
import '../../core/widgets/custom_text.dart';
import '../../features/live_auction/views/auction_room_view.dart';
import '../../models/stream_model.dart';
import 'create_stream_view.dart';
import 'stream_analytics_view.dart';
import '../../core/localization/translation_keys.dart';

enum _StreamTab { all, draft, scheduled, live, ended, cancelled }

extension _StreamTabX on _StreamTab {
  String get label {
    switch (this) {
      case _StreamTab.all:
        return TKeys.filterAll.tr;
      case _StreamTab.draft:
        return TKeys.statusDraft.tr;
      case _StreamTab.scheduled:
        return TKeys.statusScheduled.tr;
      case _StreamTab.live:
        return TKeys.statusLive.tr;
      case _StreamTab.ended:
        return TKeys.statusEnded.tr;
      case _StreamTab.cancelled:
        return TKeys.statusCancelled.tr;
    }
  }

  /// The `status` query value sent to `GET /api/v1/seller/streams`.
  /// `null` on the All tab — the param is then left off entirely.
  String? get status {
    switch (this) {
      case _StreamTab.all:
        return null;
      case _StreamTab.draft:
        return 'DRAFT';
      case _StreamTab.scheduled:
        return 'SCHEDULED';
      case _StreamTab.live:
        return 'LIVE';
      case _StreamTab.ended:
        return 'ENDED';
      case _StreamTab.cancelled:
        return 'CANCELLED';
    }
  }

  static _StreamTab fromStatus(String? status) {
    for (final t in _StreamTab.values) {
      if (t.status == status) return t;
    }
    return _StreamTab.all;
  }
}

class StreamListView extends StatefulWidget {
  const StreamListView({super.key});

  @override
  State<StreamListView> createState() => _StreamListViewState();
}

class _StreamListViewState extends State<StreamListView> {
  final StreamListController ctrl = getOrPut(() => StreamListController());

  /// Mirrors the controller's server-side filter, so a rebuilt view (or one
  /// returning to a screen it left on the "Live" tab) shows the chip that
  /// matches the data actually loaded.
  late _StreamTab _tab = _StreamTabX.fromStatus(ctrl.statusFilter);

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateStreamView()),
    );
    if (created == true) {
      // The new stream may not belong to the active tab's status, so drop back
      // to All rather than leaving the seller on a list it isn't in.
      _onTabSelected(_StreamTab.all);
    }
  }

  /// Selects a tab and re-queries the API with that tab's `status` — each tab
  /// is a server-side filter (`…/streams?page=1&pageSize=20&status=DRAFT`),
  /// not a client-side slice of one loaded page. No-op when re-tapping the
  /// active tab.
  void _onTabSelected(_StreamTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    ctrl.selectStatus(tab.status);
  }

  @override
  Widget build(BuildContext context) {
    // Draft is commented out of the row for now. The enum case stays so a
    // stream that still carries DRAFT resolves to a tab through
    // [_StreamTabX.fromStatus] instead of falling through — only the chip is
    // withheld. Put `_StreamTab.draft` back after `all` to restore it.
    const tabs = [
      _StreamTab.all,
      // _StreamTab.draft,
      _StreamTab.scheduled,
      _StreamTab.live,
      _StreamTab.ended,
      _StreamTab.cancelled,
    ];

    return Column(
      children: [
        _Header(onCreate: _openCreate),
        // Kept outside the Obx below so the chips stay put (and tappable)
        // while a tab's request is in flight.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final t = tabs[i];
                return _TabChip(
                  label: t.label,
                  selected: _tab == t,
                  onTap: () => _onTabSelected(t),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: Obx(() {
            // First load, and every tab switch (the list is cleared up front).
            if (ctrl.isLoading && ctrl.streams.isEmpty) {
              return const BrandedLoadingView();
            }

            // Error with no data
            if (ctrl.errorMessage != null && ctrl.streams.isEmpty) {
              return _ErrorState(
                message: ctrl.errorMessage ?? '',
                onRetry: () => ctrl.fetchStreams(refresh: true),
              );
            }

            return _StreamList(
              ctrl: ctrl,
              streams: ctrl.streams,
              tab: _tab,
            );
          }),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The pill is laid out at its intrinsic width, so on a narrow phone
          // (or with a large system font scale) it and the two title lines can
          // no longer share one row: the title would collapse to nothing and
          // the button would be pushed off the right edge. Below this width it
          // drops the label and becomes a square "+" instead.
          final scale = MediaQuery.textScalerOf(context).scale(13.5) / 13.5;
          final compact = constraints.maxWidth < 340 * scale;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      TKeys.myStreamsTitle.tr,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: AppColors.textPrimary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    CustomText(
                      TKeys.myStreamsSub.tr,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _CreateStreamButton(onTap: onCreate, compact: compact),
            ],
          );
        },
      ),
    );
  }
}

/// The header's create action. [compact] keeps only the "+" icon so the button
/// still fits — and stays tappable — on narrow screens.
class _CreateStreamButton extends StatelessWidget {
  const _CreateStreamButton({required this.onTap, required this.compact});
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: TKeys.newStream.tr,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: compact
              ? const EdgeInsets.all(11)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.brandNavy,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandNavy.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded,
                  size: 18, color: AppColors.brandYellow),
              if (!compact) ...[
                const SizedBox(width: 6),
                CustomText(
                  TKeys.newStream.tr,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white,
                  maxLines: 1,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A status filter chip. No count badge: each chip queries the API for its own
/// status, so the other tabs' totals aren't loaded and any number shown next to
/// them would be a guess.
class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandNavy : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.brandNavy : AppColors.inputBorder,
            width: 1,
          ),
        ),
        child: Center(
          child: CustomText(
            label,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StreamList extends StatelessWidget {
  const _StreamList({
    required this.ctrl,
    required this.streams,
    required this.tab,
  });
  final StreamListController ctrl;

  /// Already filtered by the server to the active tab's status.
  final List<StreamModel> streams;
  final _StreamTab tab;

  @override
  Widget build(BuildContext context) {
    if (streams.isEmpty) {
      return BrandedRefreshIndicator(
        onRefresh: () => ctrl.fetchStreams(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.12),
            _EmptyState(tab: tab),
          ],
        ),
      );
    }

    final bottom = MediaQuery.of(context).padding.bottom;
    // Pagination carries the active tab's status filter, so "Load more" pulls
    // the next page of *this* status.
    final showLoadMore = ctrl.hasMore;

    return BrandedRefreshIndicator(
      onRefresh: () => ctrl.fetchStreams(refresh: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 6, 16, bottom + 20),
        itemCount: streams.length + (showLoadMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i >= streams.length) {
            return _LoadMoreButton(ctrl: ctrl);
          }
          return _StreamCard(stream: streams[i], ctrl: ctrl);
        },
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.ctrl});
  final StreamListController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: ctrl.isLoadingMore
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
                  ),
                )
              : GestureDetector(
                  onTap: () => ctrl.loadMore(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.inputBorder, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.brandNavy),
                        const SizedBox(width: 6),
                        CustomText(
                          TKeys.loadMore.tr,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StreamCard extends StatelessWidget {
  const _StreamCard({required this.stream, required this.ctrl});
  final StreamModel stream;
  final StreamListController ctrl;

  /// Cards without an "Enter room" button — draft, ended, cancelled — as well
  /// as admin-rejected ones open the stream analysis page (details + orders +
  /// sales summary) on tap instead.
  bool get _isTerminal =>
      !(stream.isLive || stream.isScheduled) ||
      (stream.approvalStatus?.toUpperCase() == 'REJECTED');

  void _openDetails(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StreamAnalyticsView(
          streamId: stream.id,
          initial: stream,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Thumbnail(stream: stream),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      stream.title,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusBadge(status: stream.status),
                        if (stream.approvalStatus != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: _ApprovalBadge(status: stream.approvalStatus!),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    _MetaRow(stream: stream),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _StreamActionsMenu(stream: stream, ctrl: ctrl),
            ],
          ),
          if (stream.isLive || stream.isScheduled) ...[
            const SizedBox(height: 12),
            _EnterRoomButton(stream: stream, ctrl: ctrl),
          ],
        ],
      ),
    );

    if (!_isTerminal) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetails(context),
      child: card,
    );
  }
}

/// Opens the live auction room (Agora broadcast + queue + chat) for a live or
/// scheduled stream.
///
/// The card's status can be stale (the stream may have ended from another
/// device, or auto-ended on its timer while this list sat untouched), and the
/// room rejects a terminal stream with a bootstrap error. So the tap first
/// re-reads the stream: an ended one flips the card in place instead of
/// pushing a room that would only show an error. An unreadable status is
/// treated as "still open" — a network hiccup must not lock the seller out of
/// their own live room.
///
/// On the way back the list is refreshed (and the card marked ended right away
/// when the room says so), so the row never stays stuck on "Live".
class _EnterRoomButton extends StatefulWidget {
  const _EnterRoomButton({required this.stream, required this.ctrl});
  final StreamModel stream;
  final StreamListController ctrl;

  @override
  State<_EnterRoomButton> createState() => _EnterRoomButtonState();
}

class _EnterRoomButtonState extends State<_EnterRoomButton> {
  bool _checking = false;

  Future<void> _open() async {
    if (_checking) return;
    setState(() => _checking = true);
    final fresh = await widget.ctrl.resolveStreamStatus(widget.stream.id);
    if (!mounted) return;

    if (fresh != null && fresh.isEnded) {
      setState(() => _checking = false);
      // resolveStreamStatus already synced the status into the list, so the
      // card has flipped to "Ended" behind this snackbar.
      Get.snackbar(
        TKeys.streamAlreadyEnded.tr,
        TKeys.streamNoLongerLive.trParams({'title': widget.stream.title}),
      );
      return;
    }

    // Camera + mic are settled here, before the room is pushed. The room asks
    // for them too, but landing on its full-screen "permission needed" state is
    // a dead end on iOS, where the system alert is shown once per install and
    // only the Settings app can undo a refusal.
    final allowed = await ensureAuctionMediaAccess(context);
    if (!mounted) return;
    setState(() => _checking = false);
    if (!allowed) return;

    final ended = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AuctionRoomView(
          streamId: widget.stream.id,
          title: widget.stream.title,
        ),
      ),
    );
    if (!mounted) return;
    if (ended == true) widget.ctrl.markStreamEnded(widget.stream.id);
    unawaited(widget.ctrl.fetchStreams(refresh: true));
  }

  @override
  Widget build(BuildContext context) {
    final stream = widget.stream;
    return GestureDetector(
      onTap: _open,
      child: Container(
        width: double.infinity,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brandNavy,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandNavy.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: _checking
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(AppColors.brandYellow),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    stream.isLive
                        ? Icons.sensors_rounded
                        : Icons.videocam_rounded,
                    size: 18,
                    color: AppColors.brandYellow,
                  ),
                  const SizedBox(width: 8),
                  CustomText(
                   TKeys.enterRoom.tr,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ],
              ),
      ),
    );
  }
}

/// The per-stream "⋮" menu offering Edit — opens [CreateStreamView] in edit
/// mode, prefilled with this stream.
/// Delete is intentionally commented out for now — keep the wiring so it can
/// be switched back on without rebuilding it.
class _StreamActionsMenu extends StatelessWidget {
  const _StreamActionsMenu({required this.stream, required this.ctrl});
  final StreamModel stream;
  final StreamListController ctrl;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: AppColors.textMuted.withOpacity(0.7),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: AppColors.white,
      onSelected: (value) {
        if (value == 'edit') {
          _openEdit(context);
        }
        // } else if (value == 'delete') {
        //   _confirmDelete(context);
        // }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18, color: AppColors.brandNavy),
              const SizedBox(width: 10),
              CustomText(TKeys.edit.tr, fontSize: 14, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ],
          ),
        ),
        // PopupMenuItem<String>(
        //   value: 'delete',
        //   child: Row(
        //     children: [
        //       Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.vipps),
        //       SizedBox(width: 10),
        //       CustomText('Delete', fontSize: 14, fontWeight: FontWeight.w700,
        //           color: AppColors.vipps),
        //     ],
        //   ),
        // ),
      ],
    );
  }

  /// The edit form PATCHes and refreshes the list itself, so nothing else is
  /// needed on the way back.
  Future<void> _openEdit(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreateStreamView(stream: stream)),
    );
  }

  // Delete flow — disabled along with the menu entry above. Restore both
  // together (menu item + the 'delete' branch in onSelected) to re-enable.
  //
  // Future<void> _confirmDelete(BuildContext context) async {
  //   final confirmed = await showDialog<bool>(
  //     context: context,
  //     builder: (dctx) => AlertDialog(
  //       backgroundColor: AppColors.white,
  //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  //       title: const CustomText('Delete stream?', fontSize: 18,
  //           fontWeight: FontWeight.w800, color: AppColors.textPrimary),
  //       content: CustomText(
  //         'This will permanently delete "${stream.title}". This action cannot be undone.',
  //         fontSize: 14,
  //         fontWeight: FontWeight.w500,
  //         height: 1.4,
  //         color: AppColors.textSecondary,
  //       ),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.of(dctx).pop(false),
  //           child: const CustomText('Cancel', fontSize: 14,
  //               fontWeight: FontWeight.w700, color: AppColors.textSecondary),
  //         ),
  //         TextButton(
  //           onPressed: () => Navigator.of(dctx).pop(true),
  //           child: const CustomText('Delete', fontSize: 14,
  //               fontWeight: FontWeight.w800, color: AppColors.vipps),
  //         ),
  //       ],
  //     ),
  //   );
  //
  //   if (confirmed != true) return;
  //
  //   final ok = await ctrl.deleteStream(stream.id);
  //   if (ok) {
  //     Get.snackbar('Stream deleted', '"${stream.title}" has been deleted.');
  //   } else {
  //     Get.snackbar('Could not delete', ctrl.createError ?? 'Please try again.');
  //   }
  // }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.stream});
  final StreamModel stream;

  @override
  Widget build(BuildContext context) {
    final isUpcoming = stream.isScheduled || stream.isLive;
    final bgColor = isUpcoming
        ? AppColors.brandYellow.withOpacity(0.35)
        : AppColors.inputFill;
    final iconColor = isUpcoming ? AppColors.brandNavy : AppColors.textMuted;

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        image: stream.thumbnailUrl != null
            ? DecorationImage(
                image: NetworkImage(stream.thumbnailUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: stream.thumbnailUrl == null
          ? Icon(
              stream.isLive
                  ? Icons.sensors_rounded
                  : stream.isScheduled
                      ? Icons.videocam_rounded
                      : stream.isDraft
                          ? Icons.edit_note_rounded
                          : stream.isCancelled
                              ? Icons.cancel_outlined
                              : Icons.play_circle_outline_rounded,
              size: 24,
              color: iconColor,
            )
          : null,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'LIVE':
        color = AppColors.vipps;
        label = TKeys.statusLive.tr;
        icon = Icons.sensors_rounded;
        break;
      case 'SCHEDULED':
        color = const Color(0xFF1565C0);
        label = TKeys.statusScheduled.tr;
        icon = Icons.schedule_rounded;
        break;
      case 'DRAFT':
        color = const Color(0xFFB26A00);
        label = TKeys.statusDraft.tr;
        icon = Icons.edit_note_rounded;
        break;
      case 'CANCELLED':
        color = AppColors.vipps;
        label = TKeys.statusCancelled.tr;
        icon = Icons.cancel_outlined;
        break;
      default:
        color = AppColors.textMuted;
        label = TKeys.statusEnded.tr;
        icon = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.18), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'LIVE')
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(icon, size: 11, color: color),
            ),
          CustomText(
            label,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ],
      ),
    );
  }
}

/// Small pill showing the admin moderation decision for the stream
/// (APPROVED / PENDING / REJECTED). The shield icon signals this state is
/// set by an admin, not the seller.
class _ApprovalBadge extends StatelessWidget {
  const _ApprovalBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (status.toUpperCase()) {
      case 'APPROVED':
        color = const Color(0xFF2E7D32);
        label = TKeys.adminApproved.tr;
        icon = Icons.verified_user_rounded;
        break;
      case 'PENDING':
        color = const Color(0xFFB26A00);
        label = TKeys.awaitingAdmin.tr;
        icon = Icons.shield_moon_rounded;
        break;
      case 'REJECTED':
        color = AppColors.vipps;
        label = TKeys.adminRejected.tr;
        icon = Icons.gpp_bad_rounded;
        break;
      default:
        color = AppColors.textMuted;
        label = status;
        icon = Icons.shield_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.18), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(icon, size: 11, color: color),
          ),
          Flexible(
            child: CustomText(
              label,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.stream});
  final StreamModel stream;

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatDate(stream);
    return Row(
      children: [
        Icon(
          stream.isScheduled ? Icons.event_rounded : Icons.access_time_rounded,
          size: 12,
          color: AppColors.textMuted,
        ),
        const SizedBox(width: 4),
        // Not flexible on purpose: the date/time must stay fully readable on
        // narrow phones. The icon already says "scheduled", so the label
        // carries only the time — and "Requests open" below yields space
        // instead of the date being ellipsised away.
        CustomText(
          dateStr,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
          maxLines: 1,
        ),
        if (stream.openForProductRequests)
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 8),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.shopping_bag_outlined,
                    size: 12, color: AppColors.textMuted),
                const SizedBox(width: 3),
                Flexible(
                  child: CustomText(
                    TKeys.requestsOpen.tr,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _formatDate(StreamModel s) {
    final dt = s.scheduledStartTime ?? s.createdAt;
    final months = [
      '', TKeys.monthJanShort.tr, TKeys.monthFebShort.tr, TKeys.monthMarShort.tr,
      TKeys.monthAprShort.tr, TKeys.monthMayShort.tr, TKeys.monthJunShort.tr,
      TKeys.monthJulShort.tr, TKeys.monthAugShort.tr, TKeys.monthSepShort.tr,
      TKeys.monthOctShort.tr, TKeys.monthNovShort.tr, TKeys.monthDecShort.tr,
    ];
    final day = dt.day;
    final month = months[dt.month];
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$day $month, $hour:$min';
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tab});
  final _StreamTab tab;

  @override
  Widget build(BuildContext context) {
    final isAll = tab == _StreamTab.all;
    final label = isAll ? '' : ' ${tab.label.toLowerCase()}';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.brandYellow.withOpacity(0.3),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.live_tv_rounded,
                size: 32,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 16),
            CustomText(
              TKeys.noStreamsYetTab.trParams({'label': label}),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 6),
            CustomText(
              isAll
                  ? TKeys.tapNewStream.tr
                  : TKeys.nothingHereRightNow.tr,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
              textAlign: TextAlign.center,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.vipps.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.wifi_off_rounded, size: 28, color: AppColors.vipps),
            ),
            const SizedBox(height: 16),
            CustomText(
              TKeys.couldNotLoadStreams.tr,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 6),
            CustomText(
              message,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              textAlign: TextAlign.center,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.brandNavy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CustomText(
                  TKeys.tryAgain.tr,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
