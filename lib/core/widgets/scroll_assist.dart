import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Wraps a scroll view built on [controller] with:
///
/// * a draggable thumb on the right edge — press it and drag to reach any
///   point of a long page at once (works the same on Android and iOS);
/// * floating "jump to top" / "jump to bottom" buttons, shown only when there
///   is somewhere to jump to (more than [threshold] px away).
///
/// The [child] must be a scroll view that uses the same [controller].
class ScrollAssist extends StatelessWidget {
  const ScrollAssist({
    super.key,
    required this.controller,
    required this.child,
    this.threshold = 320,
    this.bottomPadding = 16,
  });

  final ScrollController controller;
  final Widget child;
  final double threshold;
  final double bottomPadding;

  void _jump(double target) {
    if (!controller.hasClients) return;
    final distance = (controller.offset - target).abs();
    // Longer trips take a little longer, but never drag on.
    final ms = (250 + distance / 8).clamp(250, 650).toInt();
    controller.animateTo(
      target,
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // Custom thumb rather than [Scrollbar]: on iOS the Material scrollbar
        // becomes a Cupertino one that only drags after a long-press, and its
        // thin thumb is hard to hit. This one follows a plain press-and-drag.
        Positioned.fill(child: _DragThumb(controller: controller)),
        Positioned(
          right: 26,
          bottom: bottomPadding,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              if (!controller.hasClients ||
                  !controller.position.hasContentDimensions) {
                return const SizedBox.shrink();
              }
              final pos = controller.position;
              final showTop = pos.pixels > threshold;
              final showBottom = pos.maxScrollExtent - pos.pixels > threshold;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _JumpButton(
                    visible: showTop,
                    icon: Icons.keyboard_double_arrow_up_rounded,
                    onTap: () => _jump(0),
                  ),
                  if (showTop && showBottom) const SizedBox(height: 8),
                  _JumpButton(
                    visible: showBottom,
                    icon: Icons.keyboard_double_arrow_down_rounded,
                    onTap: () => _jump(pos.maxScrollExtent),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Right-edge thumb sized to the visible fraction of the content. Pressing it
/// and dragging moves the page by the matching distance. Only the thumb takes
/// touches — the rest of the strip lets them through to the list.
class _DragThumb extends StatefulWidget {
  const _DragThumb({required this.controller});

  final ScrollController controller;

  @override
  State<_DragThumb> createState() => _DragThumbState();
}

class _DragThumbState extends State<_DragThumb> {
  static const double _hitWidth = 22;
  static const double _minThumb = 48;
  static const double _inset = 4;

  bool _dragging = false;

  ScrollController get _c => widget.controller;

  void _onDragUpdate(DragUpdateDetails d, double travel) {
    if (!_c.hasClients || travel <= 0) return;
    final pos = _c.position;
    final max = pos.maxScrollExtent;
    final next =
        (pos.pixels + d.delta.dy * max / travel).clamp(pos.minScrollExtent, max);
    _c.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          if (!_c.hasClients || !_c.position.hasContentDimensions) {
            return const SizedBox.shrink();
          }
          final pos = _c.position;
          final max = pos.maxScrollExtent;
          if (max <= 0) return const SizedBox.shrink();

          final track = constraints.maxHeight - _inset * 2;
          if (track <= _minThumb) return const SizedBox.shrink();
          final viewport = pos.viewportDimension;
          final thumb =
              (track * viewport / (viewport + max)).clamp(_minThumb, track);
          final travel = track - thumb;
          final fraction = (pos.pixels / max).clamp(0.0, 1.0);

          return Stack(
            children: [
              Positioned(
                top: _inset + travel * fraction,
                right: 0,
                width: _hitWidth,
                height: thumb,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) => setState(() => _dragging = true),
                  onVerticalDragUpdate: (d) => _onDragUpdate(d, travel),
                  onVerticalDragEnd: (_) => setState(() => _dragging = false),
                  onVerticalDragCancel: () =>
                      setState(() => _dragging = false),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _dragging ? 9 : 6,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: AppColors.brandNavy
                            .withOpacity(_dragging ? 0.75 : 0.45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({
    required this.visible,
    required this.icon,
    required this.onTap,
  });

  final bool visible;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.brandNavy,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: AppColors.buttonShadow,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 22, color: AppColors.brandYellow),
        ),
      ),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: visible ? button : const SizedBox.shrink(),
    );
  }
}
