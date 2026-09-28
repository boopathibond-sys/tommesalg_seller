import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/notification_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/branded_error_view.dart';
import '../../core/widgets/branded_loading_view.dart';
import '../../core/widgets/custom_text.dart';
import '../../features/notifications/application/notification_router.dart';
import '../../features/notifications/application/push_destination.dart';
import '../../models/notification_model.dart';
import '../../core/localization/translation_keys.dart';

/// Notification inbox — opens from the bell on the home top bar.
///
/// Lists `GET /api/notifications` with the three slices the API exposes (all /
/// unread / archived), cursor pagination, pull-to-refresh, per-row read /
/// unread / archive / unarchive, and the bulk actions: read-all, archive-all
/// and unarchive-all.
///
/// Long-pressing a row enters selection mode — tick several rows and archive or
/// unarchive them in one `POST /bulk` call (100 ids max, which is the API's own
/// ceiling).
///
/// Tapping a row marks it read and routes it exactly where its original push
/// would have — see [NotificationRouter].
class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  late final NotificationController _ctrl =
      getOrPut(() => NotificationController(), permanent: true);
  final ScrollController _scrollCtrl = ScrollController();

  /// `POST /bulk` accepts at most 100 ids, so the selection is capped at the
  /// same number rather than letting the seller build a batch the API rejects.
  static const int _selectionLimit = 100;

  /// Ids ticked in selection mode. Non-empty implies selection mode is on.
  final Set<String> _selected = <String>{};
  bool _selectionMode = false;

  bool get _inArchive => _ctrl.filter == NotificationFilter.archived;

  @override
  void initState() {
    super.initState();
    _ctrl.fetchNotifications();
    _ctrl.fetchUnreadCount();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  // Next cursor page once the user is within 400px of the bottom.
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _ctrl.loadMore();
    }
  }

  Future<void> _refresh() async {
    await _ctrl.fetchNotifications();
    await _ctrl.fetchUnreadCount();
  }

  // ── Selection mode ────────────────────────────────────────────────────

  /// Long-press on a row turns selection on and ticks that row.
  void _startSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selected
        ..clear()
        ..add(id);
    });
  }

  /// Tap while selecting ticks / unticks. Emptying the selection leaves the
  /// mode — otherwise the seller is stuck in a bar with nothing to act on.
  void _toggleSelected(String id) {
    setState(() {
      if (_selected.remove(id)) {
        if (_selected.isEmpty) _selectionMode = false;
        return;
      }
      if (_selected.length >= _selectionLimit) {
        _toast(TKeys.ntSelectLimit.tr);
        return;
      }
      _selected.add(id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  /// Ticks every row currently loaded, up to the API's 100-id ceiling. Rows
  /// still behind the cursor are not selected — say so rather than silently
  /// acting on a subset.
  void _selectAllLoaded() {
    final ids = _ctrl.notifications.map((n) => n.id).toList();
    final capped = ids.length > _selectionLimit;
    setState(() {
      _selected
        ..clear()
        ..addAll(capped ? ids.take(_selectionLimit) : ids);
      _selectionMode = _selected.isNotEmpty;
    });
    if (capped) _toast(TKeys.ntSelectLimit.tr);
  }

  /// Runs `POST /bulk` over the ticked ids. [action] is `archive` or
  /// `restore`; the controller reloads the slice and re-syncs the badge.
  Future<void> _applyToSelection(String action) async {
    if (_selected.isEmpty) {
      _toast(TKeys.ntNothingSelected.tr);
      return;
    }
    final ids = _selected.toList();
    final ok = await _ctrl.bulk(ids: ids, action: action);
    if (!mounted) return;
    _exitSelection();
    _toast(ok
        ? (action == 'restore'
                ? TKeys.ntSelectionMoved
                : TKeys.ntSelectionArchived)
            .trParams({'count': '${ids.length}'})
        : (_ctrl.errorMessage ?? TKeys.authSomethingWrong.tr));
  }

  /// Row tap: mark read first (so the list settles before we leave), then
  /// route. Rows whose payload points nowhere just stay put with a hint.
  Future<void> _openRow(NotificationModel row) async {
    if (row.isUnread) {
      await _ctrl.markRead(row.id);
    }
    if (!mounted) return;

    final destination = PushDestination.parse(row.routingData);
    if (destination == null) {
      _toast(TKeys.ntNothingToOpen.tr);
      return;
    }
    final opened = await NotificationRouter.open(context, destination);
    if (!opened && mounted) {
      _toast(TKeys.ntNothingToOpen.tr);
    }
  }

  Future<void> _markAllRead() async {
    final ok = await _ctrl.markAllRead();
    if (!mounted) return;
    _toast(ok
        ? TKeys.ntAllMarkedRead.tr
        : (_ctrl.errorMessage ?? TKeys.authSomethingWrong.tr));
  }

  Future<void> _archiveAll() async {
    final confirmed = await _confirmArchiveAll();
    if (!confirmed) return;
    final ok = await _ctrl.markAllArchived();
    if (!mounted) return;
    _toast(ok
        ? TKeys.ntAllArchived.tr
        : (_ctrl.errorMessage ?? TKeys.authSomethingWrong.tr));
  }

  Future<void> _unarchiveRow(NotificationModel row) async {
    final ok = await _ctrl.unarchive(row.id);
    if (!mounted) return;
    _toast(ok
        ? TKeys.ntMovedToInbox.tr
        : (_ctrl.errorMessage ?? TKeys.authSomethingWrong.tr));
  }

  /// "Move all to inbox" — the archive has no `restore-all` route, so the
  /// controller walks it a page at a time. Confirmed first, like archive-all.
  Future<void> _unarchiveAll() async {
    final confirmed = await _confirmBulk(
      title: TKeys.ntUnarchiveAll.tr,
      body: TKeys.ntUnarchiveAllBody.tr,
      confirmLabel: TKeys.ntUnarchive.tr,
      confirmColor: AppColors.brandNavy,
    );
    if (!confirmed) return;
    final ok = await _ctrl.unarchiveAll();
    if (!mounted) return;
    _toast(ok
        ? TKeys.ntAllUnarchived.tr
        : (_ctrl.errorMessage ?? TKeys.authSomethingWrong.tr));
  }

  Future<bool> _confirmArchiveAll() => _confirmBulk(
        title: TKeys.ntArchiveAll.tr,
        body: TKeys.ntArchiveAllBody.tr,
        confirmLabel: TKeys.ntArchive.tr,
        confirmColor: AppColors.vipps,
      );

  Future<bool> _confirmBulk({
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: CustomText(
          title,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.brandNavy,
        ),
        content: CustomText(
          body,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: AppColors.textSecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: CustomText(
              TKeys.cancelAction.tr,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: CustomText(
              confirmLabel,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: confirmColor,
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.brandNavy,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: CustomText(
            message,
            color: AppColors.brandYellow,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // The selection bar replaces the whole header while rows are
            // ticked: the filter bar goes with it, so a slice can't change
            // underneath a selection that was made in another one.
            if (_selectionMode)
              Obx(() => _SelectionBar(
                    count: _selected.length,
                    busy: _ctrl.isMutating,
                    inArchive: _inArchive,
                    onClose: _exitSelection,
                    onSelectAll: _selectAllLoaded,
                    onArchive: () => _applyToSelection('archive'),
                    onUnarchive: () => _applyToSelection('restore'),
                  ))
            else ...[
              _TopBar(
                onBack: () => Navigator.of(context).maybePop(),
                controller: _ctrl,
                onMarkAllRead: _markAllRead,
                onArchiveAll: _archiveAll,
                onUnarchiveAll: _unarchiveAll,
              ),
              _FilterBar(controller: _ctrl),
            ],
            Expanded(
              child: Obx(() {
                final rows    = _ctrl.notifications;
                final loading = _ctrl.isLoading;
                final error   = _ctrl.errorMessage;

                if (_ctrl.featureDisabled) {
                  return const _FeatureDisabledState();
                }
                if (rows.isEmpty && loading) {
                  return const BrandedLoadingView();
                }
                if (rows.isEmpty && error != null && error.isNotEmpty) {
                  return BrandedErrorView(
                    message: error,
                    onRetry: () => _ctrl.fetchNotifications(),
                  );
                }
                if (rows.isEmpty) {
                  return _EmptyState(
                    filter: _ctrl.filter,
                    category: _ctrl.category,
                  );
                }

                return RefreshIndicator(
                  color          : AppColors.brandNavy,
                  backgroundColor: AppColors.white,
                  onRefresh      : _refresh,
                  child: ListView.separated(
                    controller      : _scrollCtrl,
                    physics         : const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding         : const EdgeInsets.fromLTRB(14, 4, 14, 32),
                    itemCount       : rows.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder     : (_, i) {
                      if (i == rows.length) {
                        return _ListFooter(
                          loadingMore: _ctrl.isLoadingMore,
                          hasMore    : _ctrl.hasMore,
                          count      : rows.length,
                        );
                      }
                      final row = rows[i];
                      // A row counts as archived when it carries the flag *or*
                      // when the archive slice is on screen — the list endpoint
                      // doesn't always echo `archivedAt` back.
                      final archived = row.isArchived || _ctrl.filter ==
                          NotificationFilter.archived;
                      return _NotificationCard(
                        row       : row,
                        selectionMode: _selectionMode,
                        selected  : _selected.contains(row.id),
                        onLongPress: () => _startSelection(row.id),
                        onTap     : _selectionMode
                            ? () => _toggleSelected(row.id)
                            : () => _openRow(row),
                        onToggleRead: () => row.isRead
                            ? _ctrl.markUnread(row.id)
                            : _ctrl.markRead(row.id),
                        onArchive : archived
                            ? null
                            : () => _ctrl.archive(row.id),
                        onUnarchive: archived
                            ? () => _unarchiveRow(row)
                            : null,
                      );
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar — back chip, title, unread chip, bulk-action menu.
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onBack,
    required this.controller,
    required this.onMarkAllRead,
    required this.onArchiveAll,
    required this.onUnarchiveAll,
  });

  final VoidCallback onBack;
  final NotificationController controller;
  final VoidCallback onMarkAllRead;
  final VoidCallback onArchiveAll;
  final VoidCallback onUnarchiveAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          _BackChip(onTap: onBack),
          const SizedBox(width: 14),
          Expanded(
            child: CustomText(
              TKeys.ntNotifications.tr,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.brandNavy,
            ),
          ),
          Obx(() {
            final unread = controller.unreadCount;
            if (unread <= 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _CountChip(count: unread),
            );
          }),
          Obx(() {
            final inArchive =
                controller.filter == NotificationFilter.archived;
            return _BulkMenu(
              busy           : controller.isMutating,
              canReadAll     : controller.unreadCount > 0,
              // Archive-all empties the inbox, so it is meaningless inside the
              // archive — and unarchive-all is meaningless outside it. Exactly
              // one of the two is ever live.
              canArchiveAll  : !inArchive,
              canUnarchiveAll: inArchive,
              onMarkAllRead  : onMarkAllRead,
              onArchiveAll   : onArchiveAll,
              onUnarchiveAll : onUnarchiveAll,
            );
          }),
        ],
      ),
    );
  }
}

class _BackChip extends StatelessWidget {
  const _BackChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.inputBorder, width: 1),
          boxShadow: const [
            BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.arrow_back_rounded,
          size: 20,
          color: AppColors.brandNavy,
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.brandYellow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.brandNavy, width: 1.2),
      ),
      child: CustomText(
        count > 99 ? '99+' : '$count',
        fontSize: 11.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
        color: AppColors.brandNavy,
      ),
    );
  }
}

/// Overflow menu carrying the bulk actions. Shows a spinner in place of the
/// icon while one is in flight so a second tap can't stack calls.
class _BulkMenu extends StatelessWidget {
  const _BulkMenu({
    required this.busy,
    required this.canReadAll,
    required this.canArchiveAll,
    required this.canUnarchiveAll,
    required this.onMarkAllRead,
    required this.onArchiveAll,
    required this.onUnarchiveAll,
  });

  final bool busy;
  final bool canReadAll;
  final bool canArchiveAll;
  final bool canUnarchiveAll;
  final VoidCallback onMarkAllRead;
  final VoidCallback onArchiveAll;
  final VoidCallback onUnarchiveAll;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 42,
        height: 42,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.brandNavy,
            ),
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      color: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      icon: const Icon(
        Icons.more_horiz_rounded,
        size: 22,
        color: AppColors.brandNavy,
      ),
      onSelected: (value) {
        if (value == 'read-all') onMarkAllRead();
        if (value == 'archive-all') onArchiveAll();
        if (value == 'unarchive-all') onUnarchiveAll();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'read-all',
          enabled: canReadAll,
          child: _MenuRow(
            icon: Icons.done_all_rounded,
            label: TKeys.ntMarkAllRead.tr,
            muted: !canReadAll,
          ),
        ),
        if (canUnarchiveAll)
          PopupMenuItem(
            value: 'unarchive-all',
            child: _MenuRow(
              icon: Icons.unarchive_outlined,
              label: TKeys.ntUnarchiveAll.tr,
            ),
          )
        else
          PopupMenuItem(
            value: 'archive-all',
            enabled: canArchiveAll,
            child: _MenuRow(
              icon: Icons.archive_outlined,
              label: TKeys.ntArchiveAll.tr,
              muted: !canArchiveAll,
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selection bar — replaces the header while rows are ticked.
//
// Navy so the screen reads as being in a different mode, with the count in the
// middle and exactly one destructive-ish action on the right: unarchive inside
// the archive, archive everywhere else.
// ─────────────────────────────────────────────────────────────────────────────
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.inArchive,
    required this.onClose,
    required this.onSelectAll,
    required this.onArchive,
    required this.onUnarchive,
  });

  final int count;
  final bool busy;
  final bool inArchive;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onArchive;
  final VoidCallback onUnarchive;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.brandNavy,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: busy ? null : onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              size: 20,
              color: AppColors.brandYellow,
            ),
          ),
          Expanded(
            child: CustomText(
              TKeys.ntSelectedCount.trParams({'count': '$count'}),
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: AppColors.white,
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.brandYellow,
                ),
              ),
            )
          else ...[
            TextButton(
              onPressed: onSelectAll,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: CustomText(
                TKeys.ntSelectAll.tr,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.brandYellow,
              ),
            ),
            _SelectionAction(
              icon: inArchive
                  ? Icons.unarchive_rounded
                  : Icons.archive_rounded,
              label: inArchive ? TKeys.ntUnarchive.tr : TKeys.ntArchive.tr,
              onTap: inArchive ? onUnarchive : onArchive,
            ),
          ],
        ],
      ),
    );
  }
}

/// The filled yellow pill carrying the selection's one action.
class _SelectionAction extends StatelessWidget {
  const _SelectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.brandYellow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.brandNavy),
            const SizedBox(width: 6),
            CustomText(
              label,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: AppColors.brandNavy,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? AppColors.textMuted : AppColors.brandNavy;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        CustomText(
          label,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter bar — the three server-side slices.
// ─────────────────────────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});
  final NotificationController controller;

  // Getter, not a stored field: `.tr` must re-resolve when the seller
  // switches language, and a field initialiser only ever runs once.
  static Map<NotificationFilter, String> get _options =>
      <NotificationFilter, String>{
        NotificationFilter.all: TKeys.filterAll.tr,
        NotificationFilter.unread: TKeys.ntUnread.tr,
        NotificationFilter.archived: TKeys.ntArchived.tr,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          // The three slices scroll; the topic dropdown stays pinned on the
          // right so it never scrolls out of reach.
          Expanded(
            child: Obx(() {
              final active = controller.filter;
              return ListView.separated(
                scrollDirection : Axis.horizontal,
                padding         : const EdgeInsets.fromLTRB(14, 0, 8, 8),
                itemCount       : _options.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder     : (_, i) {
                  final entry = _options.entries.elementAt(i);
                  return _FilterChip(
                    label   : entry.value,
                    selected: entry.key == active,
                    onTap   : () => controller.setFilter(entry.key),
                  );
                },
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 14, 8),
            child: _CategoryMenu(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String       label;
  final bool         selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandNavy : AppColors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.brandNavy
                : AppColors.brandNavy.withValues(alpha: 0.14),
            width: 1.2,
          ),
        ),
        child: CustomText(
          label,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: selected ? AppColors.brandYellow : AppColors.brandNavy,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category menu — the second, independent filter axis (`?category=…`).
//
// A dropdown rather than another chip strip: there are 13 options against the
// status row's 3, so chips would out-shout the rows they filter and still need
// horizontal scrolling to reach the last of them.
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryOption {
  const _CategoryOption(this.value, this.label);

  /// Sent verbatim as `?category=`; `null` = every category.
  final String? value;
  final String label;
}

// Getter, not a stored list: `.tr` must re-resolve on a language switch.
List<_CategoryOption> get _categoryOptions => <_CategoryOption>[
  _CategoryOption(null, TKeys.filterAll.tr),
  _CategoryOption('auction', TKeys.ntTopicAuction.tr),
  _CategoryOption('order', TKeys.ntTopicOrder.tr),
  _CategoryOption('offer', TKeys.ntTopicOffer.tr),
  _CategoryOption('payment', TKeys.ntTopicPayment.tr),
  _CategoryOption('shipping', TKeys.ntTopicShipping.tr),
  _CategoryOption('stream', TKeys.ntTopicStream.tr),
  _CategoryOption('social', TKeys.ntTopicSocial.tr),
  _CategoryOption('seller', TKeys.ntTopicSeller.tr),
  _CategoryOption('buyer', TKeys.ntTopicBuyer.tr),
  _CategoryOption('admin', TKeys.ntTopicAdmin.tr),
  _CategoryOption('security', TKeys.ntTopicSecurity.tr),
  _CategoryOption('marketing', TKeys.ntTopicMarketing.tr),
];

class _CategoryMenu extends StatelessWidget {
  const _CategoryMenu({required this.controller});
  final NotificationController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final active = controller.category;
      final index  = _categoryOptions.indexWhere((o) => o.value == active);
      // An unknown category (server added one we don't list) still shows as
      // filtered rather than silently reading "All".
      final option = index < 0 ? null : _categoryOptions[index];
      final filtered = active != null && active.isNotEmpty;

      return PopupMenuButton<int>(
        color: AppColors.white,
        elevation: 6,
        offset: const Offset(0, 44),
        constraints: const BoxConstraints(minWidth: 210, maxHeight: 380),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: AppColors.brandNavy.withValues(alpha: 0.10),
          ),
        ),
        // Values are indices, not category strings: PopupMenuButton treats a
        // null selection as a dismissal, which would make "All" unselectable.
        onSelected: (i) => controller.setCategory(_categoryOptions[i].value),
        itemBuilder: (_) => [
          for (var i = 0; i < _categoryOptions.length; i++)
            PopupMenuItem<int>(
              value: i,
              height: 42,
              child: _CategoryMenuRow(
                option  : _categoryOptions[i],
                selected: _categoryOptions[i].value == active,
              ),
            ),
        ],
        // Unfiltered reads "All" — the same word as the menu's first row, so
        // the pill always names the option that is actually selected.
        child: _CategoryTrigger(
          label: filtered ? (option?.label ?? _humanise(active)) : TKeys.filterAll.tr,
          icon: filtered
              ? _paletteForCategory(active).icon
              : Icons.apps_rounded,
          filtered: filtered,
        ),
      );
    });
  }
}

/// The pill the menu hangs off. Neutral until a category is picked, then
/// brand-yellow so the list being filtered is obvious at a glance.
class _CategoryTrigger extends StatelessWidget {
  const _CategoryTrigger({
    required this.label,
    required this.icon,
    required this.filtered,
  });

  final String   label;
  final IconData icon;
  final bool     filtered;

  @override
  Widget build(BuildContext context) {
    final foreground =
        filtered ? AppColors.brandNavy : AppColors.textSecondary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 34,
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: filtered ? AppColors.brandYellow : AppColors.inputFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filtered
              ? AppColors.brandNavy
              : AppColors.brandNavy.withValues(alpha: 0.10),
          width: filtered ? 1.2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: CustomText(
              label,
              fontSize: 12,
              fontWeight: filtered ? FontWeight.w900 : FontWeight.w700,
              letterSpacing: 0.1,
              color: foreground,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.expand_more_rounded, size: 16, color: foreground),
        ],
      ),
    );
  }
}

class _CategoryMenuRow extends StatelessWidget {
  const _CategoryMenuRow({required this.option, required this.selected});

  final _CategoryOption option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = option.value == null
        ? Icons.apps_rounded
        : _paletteForCategory(option.value!).icon;
    final color = selected ? AppColors.brandNavy : AppColors.textSecondary;

    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 11),
        Expanded(
          child: CustomText(
            option.label,
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            color: color,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (selected)
          const Icon(Icons.check_rounded, size: 16, color: AppColors.brandNavy),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row — category icon, title + body, relative time, unread marker.
//
//   ┃┌─────────────────────────────────────────────┐
//   ┃│ (icon)  Your stream was approved       ● ⋮  │  ← rail + dot = unread
//   ┃│         You can go live at 18:00            │
//   ┃└─────────────────────────────────────────────┘
//    ↑ yellow rail
//
// Unread is carried by the left rail, a bolder title and the dot — not by a
// wash over the card. An earlier version tinted the whole card brand-yellow,
// which flattened the category badge (auction rows are themselves pale yellow)
// and made the body text sit on a muddy ground. Read rows keep the same
// geometry and simply lose the rail and drop a weight, so a half-read list
// still scans as one column.
//
// Swipe left archives, or — inside the archive slice — moves the row back to
// the inbox; the ⋮ menu carries the same action plus read / unread. While
// selection mode is on the swipe is off and the menu becomes a tick.
// ─────────────────────────────────────────────────────────────────────────────
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.row,
    required this.onTap,
    required this.onToggleRead,
    required this.onLongPress,
    this.onArchive,
    this.onUnarchive,
    this.selectionMode = false,
    this.selected = false,
  });

  final NotificationModel row;
  final VoidCallback onTap;
  final VoidCallback onToggleRead;

  /// Long-press turns on selection mode with this row ticked.
  final VoidCallback onLongPress;

  /// Archive this row. Null once it is already archived — [onUnarchive] is
  /// set instead, and the two are never both live.
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;

  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final card = _buildCard(context);

    // Swiping while selecting would fight the tick, so the gesture is off in
    // selection mode.
    final swipeAction = selectionMode ? null : (onArchive ?? onUnarchive);
    if (swipeAction == null) return card;

    final restoring = onArchive == null;
    return Dismissible(
      key: ValueKey('notification-${row.id}'),
      direction: DismissDirection.endToStart,
      background: _SwipeBackground(restoring: restoring),
      // The controller removes the row itself (and puts it back if the call
      // fails), so the widget is never dismissed by the framework — that keeps
      // the list and the model from disagreeing about what exists.
      confirmDismiss: (_) async {
        swipeAction.call();
        return false;
      },
      child: card,
    );
  }

  Widget _buildCard(BuildContext context) {
    final unread  = row.isUnread;
    final palette = _paletteFor(row);

    // Read rows step back rather than being repainted: the same navy at a
    // lower opacity, so the column keeps one text colour instead of two.
    final titleColor = unread
        ? AppColors.brandNavy
        : AppColors.brandNavy.withValues(alpha: 0.72);

    return Container(
      decoration: BoxDecoration(
        color: selected
            ? AppColors.brandYellow.withValues(alpha: 0.16)
            : AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? AppColors.brandNavy
              : unread
                  ? AppColors.brandNavy.withValues(alpha: 0.16)
                  : AppColors.brandNavy.withValues(alpha: 0.09),
          width: selected ? 1.6 : 1.1,
        ),
        boxShadow: [
          // Unread rows sit a little higher off the page.
          BoxShadow(
            color: unread
                ? AppColors.brandNavy.withValues(alpha: 0.10)
                : AppColors.cardShadow,
            blurRadius: unread ? 16 : 10,
            offset: Offset(0, unread ? 6 : 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: selectionMode ? null : onLongPress,
            splashColor: AppColors.brandNavy.withValues(alpha: 0.06),
            highlightColor: AppColors.brandNavy.withValues(alpha: 0.03),
            // Stack, not a Row with a stretched first child: inside a ListView
            // the row's height is only known once the content has laid out, so
            // the rail is positioned to fill whatever that turns out to be.
            child: Stack(
              children: [
                Padding(
                  // Left padding is the same read or unread, so badges stay on
                  // one vertical line as rows are read.
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CategoryBadge(palette: palette),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: CustomText(
                                    row.title ?? _humanise(row.type),
                                    fontSize: 14,
                                    fontWeight: unread
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                    letterSpacing: -0.2,
                                    height: 1.2,
                                    color: titleColor,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (unread)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      // Same orange as the home bell badge, so
                                      // "there is something new" is one colour
                                      // across the app.
                                      color: AppColors.vipps,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.vipps
                                              .withValues(alpha: 0.35),
                                          blurRadius: 6,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            if ((row.body ?? '').isNotEmpty) ...[
                              const SizedBox(height: 4),
                              CustomText(
                                row.body,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                                color: unread
                                    ? AppColors.textSecondary
                                    : AppColors.textMuted,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 12,
                                  color: unread
                                      ? AppColors.brandNavy
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(width: 4),
                                CustomText(
                                  _relativeTime(row.createdAt),
                                  fontSize: 11,
                                  fontWeight:
                                      unread ? FontWeight.w800 : FontWeight.w700,
                                  color: unread
                                      ? AppColors.brandNavy
                                      : AppColors.textMuted,
                                ),
                                if ((row.category ?? '').isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  _CategoryPill(
                                    label: _humanise(row.category),
                                    palette: palette,
                                  ),
                                ],
                                if (row.isArchived) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.archive_rounded,
                                    size: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (selectionMode)
                        _SelectionTick(selected: selected)
                      else
                        _RowMenu(
                          isRead: row.isRead,
                          onToggleRead: onToggleRead,
                          onArchive: onArchive,
                          onUnarchive: onUnarchive,
                        ),
                    ],
                  ),
                ),
                if (unread)
                  const Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 4,
                    child: ColoredBox(color: AppColors.brandYellow),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({
    required this.isRead,
    required this.onToggleRead,
    this.onArchive,
    this.onUnarchive,
  });

  final bool isRead;
  final VoidCallback onToggleRead;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: AppColors.white,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      icon: const Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: AppColors.textMuted,
      ),
      onSelected: (value) {
        if (value == 'read') onToggleRead();
        if (value == 'archive') onArchive?.call();
        if (value == 'unarchive') onUnarchive?.call();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'read',
          child: _MenuRow(
            icon: isRead
                ? Icons.mark_email_unread_outlined
                : Icons.mark_email_read_outlined,
            label: isRead ? TKeys.ntMarkAsUnread.tr : TKeys.ntMarkAsRead.tr,
          ),
        ),
        if (onArchive != null)
          PopupMenuItem(
            value: 'archive',
            child: _MenuRow(
              icon: Icons.archive_outlined,
              label: TKeys.ntArchive.tr,
            ),
          ),
        if (onUnarchive != null)
          PopupMenuItem(
            value: 'unarchive',
            child: _MenuRow(
              icon: Icons.unarchive_outlined,
              label: TKeys.ntUnarchive.tr,
            ),
          ),
      ],
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({this.restoring = false});

  /// True in the archive, where the same swipe moves the row back to the inbox
  /// instead of archiving it.
  final bool restoring;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        color: AppColors.brandNavy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            restoring ? Icons.unarchive_rounded : Icons.archive_rounded,
            size: 18,
            color: AppColors.brandYellow,
          ),
          const SizedBox(width: 8),
          CustomText(
            restoring ? TKeys.ntUnarchive.tr : TKeys.ntArchive.tr,
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
            color: AppColors.brandYellow,
          ),
        ],
      ),
    );
  }
}

/// The tick that replaces the row's ⋮ menu while selecting.
class _SelectionTick extends StatelessWidget {
  const _SelectionTick({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12, top: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: selected ? AppColors.brandNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected
                ? AppColors.brandNavy
                : AppColors.brandNavy.withValues(alpha: 0.30),
            width: 1.6,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded,
                size: 15, color: AppColors.brandYellow)
            : null,
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.palette});
  final _CategoryPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.border, width: 1),
      ),
      alignment: Alignment.center,
      child: Icon(palette.icon, size: 19, color: palette.foreground),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label, required this.palette});
  final String label;
  final _CategoryPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: CustomText(
        label.toUpperCase(),
        fontSize: 8.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
        color: palette.foreground,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Footer / empty / disabled states.
// ─────────────────────────────────────────────────────────────────────────────
class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.loadingMore,
    required this.hasMore,
    required this.count,
  });

  final bool loadingMore;
  final bool hasMore;
  final int  count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Center(
        child: loadingMore
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.brandNavy,
                ),
              )
            : CustomText(
                hasMore ? '' : '$count notifications',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.textMuted,
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, this.category});
  final NotificationFilter filter;
  final String? category;

  @override
  Widget build(BuildContext context) {
    // A category filter narrows the result set, so "you have no notifications"
    // would be a lie — point at the filter instead.
    if (category != null && category!.isNotEmpty) {
      return _CenteredMessage(
        icon : Icons.filter_alt_off_rounded,
        title: TKeys.ntNothingInTopic.tr,
        body : TKeys.ntNothingInTopicBody.tr,
      );
    }

    final (icon, title, body) = switch (filter) {
      NotificationFilter.unread => (
          Icons.mark_email_read_outlined,
          TKeys.ntAllCaughtUp.tr,
          TKeys.ntAllCaughtUpBody.tr,
        ),
      NotificationFilter.archived => (
          Icons.archive_outlined,
          TKeys.ntNothingArchived.tr,
          TKeys.ntNothingArchivedBody.tr,
        ),
      NotificationFilter.all => (
          Icons.notifications_none_rounded,
          TKeys.ntNoNotificationsYet.tr,
          TKeys.ntNoNotificationsBody.tr,
        ),
    };

    return _CenteredMessage(icon: icon, title: title, body: body);
  }
}

class _FeatureDisabledState extends StatelessWidget {
  const _FeatureDisabledState();

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(
      icon : Icons.notifications_off_outlined,
      title: TKeys.ntUnavailable.tr,
      body : TKeys.ntUnavailableBody.tr,
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.brandYellow.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 30, color: AppColors.brandNavy),
            ),
            const SizedBox(height: 18),
            CustomText(
              title,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            CustomText(
              body,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category mapping + formatting helpers.
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryPalette {
  const _CategoryPalette({
    required this.icon,
    required this.background,
    required this.border,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color border;
  final Color foreground;
}

/// Icon + tint for a row, falling back to the template id when it carries no
/// category (older notifications).
_CategoryPalette _paletteFor(NotificationModel row) {
  final key = (row.category ?? '').toLowerCase().isNotEmpty
      ? row.category!.toLowerCase()
      : _categoryFromType(row.type);
  return _paletteForCategory(key);
}

/// Icon + tint per server category. A brand-new category the app doesn't know
/// about still renders, as a neutral bell.
_CategoryPalette _paletteForCategory(String category) {
  switch (category.toLowerCase()) {
    case 'auction':
    case 'stream':
      return const _CategoryPalette(
        icon      : Icons.gavel_rounded,
        background: Color(0xFFFFF4D6),
        border    : Color(0xFFE8C766),
        foreground: Color(0xFF8A5A00),
      );
    case 'order':
    case 'shipping':
      return const _CategoryPalette(
        icon      : Icons.local_shipping_rounded,
        background: Color(0xFFE7EEFB),
        border    : Color(0xFFBBD0F2),
        foreground: Color(0xFF1E4FB0),
      );
    case 'offer':
      return const _CategoryPalette(
        icon      : Icons.local_offer_rounded,
        background: Color(0xFFF1E9FB),
        border    : Color(0xFFD3BFF0),
        foreground: Color(0xFF5B2E9E),
      );
    case 'payment':
      return const _CategoryPalette(
        icon      : Icons.credit_card_rounded,
        background: Color(0xFFE7F6EC),
        border    : Color(0xFFB8E0C2),
        foreground: Color(0xFF1F6B40),
      );
    case 'security':
      return const _CategoryPalette(
        icon      : Icons.shield_outlined,
        background: Color(0xFFFDECEC),
        border    : Color(0xFFF1C0C0),
        foreground: Color(0xFF9A2A1E),
      );
    case 'social':
    case 'seller':
      return const _CategoryPalette(
        icon      : Icons.storefront_rounded,
        background: Color(0xFFE9F4F3),
        border    : Color(0xFFB5DAD5),
        foreground: Color(0xFF1D6A62),
      );
    case 'marketing':
      return const _CategoryPalette(
        icon      : Icons.campaign_rounded,
        background: Color(0xFFFDEFE7),
        border    : Color(0xFFF3C9AE),
        foreground: Color(0xFF9C4A16),
      );
    default:
      return _CategoryPalette(
        icon      : Icons.notifications_rounded,
        background: AppColors.inputFill,
        border    : AppColors.brandNavy.withValues(alpha: 0.12),
        foreground: AppColors.textSecondary,
      );
  }
}

/// Best-effort category for rows that only carry a template id
/// (`AUCTION_WON` → `auction`, `OFFER_ACCEPTED` → `offer`, …).
String _categoryFromType(String? type) {
  final t = (type ?? '').toLowerCase();
  if (t.isEmpty) return '';
  if (t.startsWith('auction') || t.contains('bid')) return 'auction';
  if (t.startsWith('offer')) return 'offer';
  if (t.startsWith('order')) return 'order';
  if (t.contains('payment')) return 'payment';
  if (t.contains('ship') || t.contains('deliver')) return 'shipping';
  if (t.contains('live') || t.contains('stream')) return 'stream';
  if (t.contains('follow') || t.contains('seller')) return 'social';
  return '';
}

/// `STREAM_APPROVED` → `Stream approved`; used as a title fallback and for the
/// category pill.
String _humanise(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final spaced = raw.replaceAll('_', ' ').trim().toLowerCase();
  if (spaced.isEmpty) return '—';
  return spaced[0].toUpperCase() + spaced.substring(1);
}

List<String> get _months => [
      TKeys.monthJanShort.tr, TKeys.monthFebShort.tr, TKeys.monthMarShort.tr,
      TKeys.monthAprShort.tr, TKeys.monthMayShort.tr, TKeys.monthJunShort.tr,
      TKeys.monthJulShort.tr, TKeys.monthAugShort.tr, TKeys.monthSepShort.tr,
      TKeys.monthOctShort.tr, TKeys.monthNovShort.tr, TKeys.monthDecShort.tr,
    ];

/// `now` / `5m` / `3h` / `2d`, then an absolute `30 Jun` past a week — the
/// usual inbox cadence.
String _relativeTime(DateTime? when) {
  if (when == null) return '—';
  final local = when.toLocal();
  final diff  = DateTime.now().difference(local);

  if (diff.isNegative) return TKeys.timeNow.tr;
  if (diff.inMinutes < 1) return TKeys.timeNow.tr;
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}${TKeys.timeMinutesShort.tr}';
  }
  if (diff.inHours < 24) return '${diff.inHours}${TKeys.timeHoursShort.tr}';
  if (diff.inDays < 7) return '${diff.inDays}${TKeys.timeDaysShort.tr}';
  return '${local.day} ${_months[local.month - 1]}';
}
