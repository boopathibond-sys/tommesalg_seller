import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/stream_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../../models/stream_model.dart';

class StreamListView extends StatelessWidget {
  const StreamListView({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(StreamListController());

    return Obx(() {
      // First load
      if (ctrl.isLoading && ctrl.streams.isEmpty) {
        return const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
          ),
        );
      }

      // Error with no data
      if (ctrl.errorMessage != null && ctrl.streams.isEmpty) {
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
                const CustomText(
                  'Could not load streams',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 6),
                CustomText(
                  ctrl.errorMessage ?? '',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  textAlign: TextAlign.center,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => ctrl.fetchStreams(refresh: true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.brandNavy,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const CustomText(
                      'Try again',
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

      // Empty
      if (ctrl.streams.isEmpty) {
        return _EmptyState(onRefresh: () => ctrl.fetchStreams(refresh: true));
      }

      // Separate scheduled (upcoming) from ended
      final scheduled = ctrl.streams.where((s) => s.isScheduled || s.isLive).toList();
      final ended = ctrl.streams.where((s) => s.isEnded).toList();

      return RefreshIndicator(
        onRefresh: () => ctrl.fetchStreams(refresh: true),
        color: AppColors.brandNavy,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            // Header
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CustomText(
                      'My Streams',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(height: 4),
                    CustomText(
                      '${ctrl.streams.length} streams total',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),

            // Upcoming section
            if (scheduled.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
                sliver: SliverToBoxAdapter(
                  child: _SectionHeader(
                    icon: Icons.schedule_rounded,
                    label: 'Upcoming',
                    count: scheduled.length,
                    color: const Color(0xFF1565C0),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.separated(
                  itemCount: scheduled.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _StreamCard(stream: scheduled[i]),
                ),
              ),
            ],

            // Past section
            if (ended.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
                sliver: SliverToBoxAdapter(
                  child: _SectionHeader(
                    icon: Icons.history_rounded,
                    label: 'Past',
                    count: ended.length,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.separated(
                  itemCount: ended.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _StreamCard(stream: ended[i]),
                ),
              ),
            ],

            // Load more
            if (ctrl.hasMore)
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                sliver: SliverToBoxAdapter(
                  child: ctrl.isLoadingMore
                      ? const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
                            ),
                          ),
                        )
                      : Center(
                          child: GestureDetector(
                            onTap: () => ctrl.loadMore(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.inputFill,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const CustomText(
                                'Load more',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                ),
              ),

            // Bottom padding
            SliverPadding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16),
              sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        CustomText(
          label,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: CustomText(
            '$count',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StreamCard extends StatelessWidget {
  const _StreamCard({required this.stream});
  final StreamModel stream;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(
        children: [
          // Thumbnail / placeholder
          _Thumbnail(stream: stream),
          const SizedBox(width: 14),
          // Info
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
                _StatusBadge(status: stream.status),
                const SizedBox(height: 6),
                _MetaRow(stream: stream),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.textMuted.withOpacity(0.5),
          ),
        ],
      ),
    );
  }
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
        label = 'Live';
        icon = Icons.sensors_rounded;
        break;
      case 'SCHEDULED':
        color = const Color(0xFF1565C0);
        label = 'Scheduled';
        icon = Icons.schedule_rounded;
        break;
      default:
        color = AppColors.textMuted;
        label = 'Ended';
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
        Expanded(
          child: CustomText(
            dateStr,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (stream.openForProductRequests) ...[
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
          const Icon(Icons.shopping_bag_outlined, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 3),
          const CustomText(
            'Requests open',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ],
      ],
    );
  }

  String _formatDate(StreamModel s) {
    final dt = s.scheduledStartTime ?? s.createdAt;
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final day = dt.day;
    final month = months[dt.month];
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');

    if (s.isScheduled && s.scheduledStartTime != null) {
      return 'Scheduled $day $month at $hour:$min';
    }
    return '$day $month $hour:$min';
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
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
            const CustomText(
              'No streams yet',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 6),
            const CustomText(
              'Your live streams and scheduled broadcasts will appear here.',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
              textAlign: TextAlign.center,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onRefresh,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const CustomText(
                  'Refresh',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
