import 'package:flutter/material.dart';

import 'branded_logo_loader.dart';

/// Drop-in replacement for the Material [RefreshIndicator] that shows the
/// animated brand loader ([BrandedLogoLoader]) instead of the stock spinner.
///
/// It listens to scroll overscroll at the top of any scrollable
/// (`ListView` / `SingleChildScrollView` / `CustomScrollView`), reveals the
/// loader as the user pulls, and fires [onRefresh] once the pull passes the
/// threshold. No third-party packages required — works with the
/// `BouncingScrollPhysics` already used across the app.
///
/// Usage mirrors the old widget:
/// ```dart
/// BrandedRefreshIndicator(
///   onRefresh: () => controller.fetch(),
///   child: ListView(...),
/// )
/// ```
class BrandedRefreshIndicator extends StatefulWidget {
  const BrandedRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.topOffset = 14,
  });

  /// Called when the user pulls past the trigger threshold. The loader stays
  /// on screen until the returned future completes.
  final Future<void> Function() onRefresh;

  /// The scrollable to wrap.
  final Widget child;

  /// Distance from the top of the viewport at which the loader floats.
  final double topOffset;

  @override
  State<BrandedRefreshIndicator> createState() =>
      _BrandedRefreshIndicatorState();
}

class _BrandedRefreshIndicatorState extends State<BrandedRefreshIndicator> {
  /// Pull distance (px) needed to arm a refresh.
  static const double _threshold = 88;

  /// Hard cap so a long fling doesn't drag the loader off into space.
  static const double _maxPull = 130;

  double _pull = 0;
  bool _armed = false;
  bool _refreshing = false;

  /// True while the finger is on the screen. The decision to refresh is taken
  /// the moment it leaves — see [_handle].
  bool _dragging = false;

  bool _handle(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (_refreshing) return false;

    if (n is ScrollUpdateNotification || n is OverscrollNotification) {
      final dragDetails = n is ScrollUpdateNotification
          ? n.dragDetails
          : (n as OverscrollNotification).dragDetails;

      // Notifications carrying drag details come from the finger; the ones
      // without come from the bounce-back simulation that runs after it lifts.
      if (dragDetails == null) {
        if (_dragging) _endDrag();
        return false;
      }

      _dragging = true;
      // Positive once the content is dragged below its resting top.
      final overscroll = n.metrics.minScrollExtent - n.metrics.pixels;
      final next = overscroll > 0 ? overscroll.clamp(0.0, _maxPull) : 0.0;
      if (next != _pull) {
        setState(() {
          _pull = next;
          _armed = next >= _threshold;
        });
      }
    } else if (n is ScrollEndNotification) {
      // A drag that stops without any ballistic phase ends here instead.
      if (_dragging) _endDrag();
    }
    return false;
  }

  /// Finger lifted: fire the refresh if the pull passed the threshold,
  /// otherwise drop the loader.
  ///
  /// This runs on the first notification that is *not* a drag — Flutter only
  /// reports `ScrollDirection.idle` once the spring-back animation has settled,
  /// which is far too late: its own scroll updates would have reset [_pull]
  /// back to 0 and disarmed the pull before it was ever read.
  void _endDrag() {
    _dragging = false;
    if (_armed && _pull >= _threshold) {
      _startRefresh();
    } else if (_pull != 0) {
      setState(() {
        _pull = 0;
        _armed = false;
      });
    }
  }

  Future<void> _startRefresh() async {
    setState(() {
      _refreshing = true;
      _armed = false;
      _pull = _threshold;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _pull = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_pull / _threshold).clamp(0.0, 1.0);
    final visible = _refreshing || _pull > 0;

    return NotificationListener<ScrollNotification>(
      onNotification: _handle,
      child: Stack(
        children: [
          widget.child,
          if (visible)
            Positioned(
              top: widget.topOffset + progress * 6,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    scale: _refreshing ? 1.0 : (0.55 + 0.45 * progress),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: _refreshing ? 1.0 : progress,
                      child: const BrandedLogoLoader(size: 52),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
