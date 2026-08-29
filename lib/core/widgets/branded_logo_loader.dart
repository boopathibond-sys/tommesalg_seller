import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Animated brand loader — the app's yellow T-mark sitting in a softly
/// "breathing" navy badge with a navy arc orbiting around it.
///
/// Navy is used for the badge + ring on purpose: the mark itself is yellow,
/// and the page background is brand yellow, so a bare logo would melt into
/// the page. The navy chip gives the yellow mark something to sit on and the
/// orbiting arc reads clearly on both the yellow page and white cards.
///
/// Drop it anywhere a spinner is wanted — full-screen loads
/// ([BrandedLoadingView]) and the pull-to-refresh indicator both use it, so
/// every loading surface in the app feels like the same object.
class BrandedLogoLoader extends StatefulWidget {
  const BrandedLogoLoader({super.key, this.size = 56});

  /// Overall diameter of the loader (ring included).
  final double size;

  @override
  State<BrandedLogoLoader> createState() => _BrandedLogoLoaderState();
}

class _BrandedLogoLoaderState extends State<BrandedLogoLoader>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final badge = s * 0.72;

    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Orbiting arc.
          RotationTransition(
            turns: _spin,
            child: CustomPaint(
              size: Size(s, s),
              painter: _RingPainter(),
            ),
          ),
          // Breathing badge with the brand mark.
          ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1.0).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
            child: Container(
              width: badge,
              height: badge,
              padding: EdgeInsets.all(badge * 0.16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandNavy,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandNavy.withOpacity(0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/logo/app_loading.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = size.width * 0.075;
    final radius = (size.width - stroke) / 2;

    // Faint full track so the orbit reads even at the arc's tail.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.brandNavy.withOpacity(0.12);
    canvas.drawCircle(center, radius, track);

    // Sweep arc that fades from transparent into solid navy — gives the
    // rotation a clear "head" and a soft trailing tail.
    final rect = Rect.fromCircle(center: center, radius: radius);
    final shader = SweepGradient(
      colors: [
        AppColors.brandNavy.withOpacity(0.0),
        AppColors.brandNavy.withOpacity(0.85),
        AppColors.brandNavy,
      ],
      stops: const [0.0, 0.72, 1.0],
    ).createShader(rect);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = shader;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 1.65, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => false;
}
