import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Hand-drawn header illustration for the login screen.
///
/// Composed entirely of Flutter primitives + a small `CustomPainter` for the
/// mascot's smile, so the screen renders identically with no asset pipeline.
class LoginIllustration extends StatelessWidget {
  const LoginIllustration({super.key, this.height = 104});

  /// Rendered height. The artwork is authored at [_designSize] and scaled
  /// down to fit, so shrinking the header never re-flows the composition.
  final double height;

  /// The box the drawing below is laid out against.
  static const Size _designSize = Size(320, 172);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _designSize.width,
          height: _designSize.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Soft cloud blobs sitting in the background.
              const Positioned(top: 24,  left: 36,  child: _Cloud(size: 22)),
              const Positioned(top: 60,  right: 28, child: _Cloud(size: 14)),
              const Positioned(top: 12,  right: 90, child: _Cloud(size: 10)),

              // The little storefront — slightly left of centre.
              Positioned(
                top: 36,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(-22, 0),
                    child: const _Storefront(),
                  ),
                ),
              ),

              // The plant peeking out beside the door.
              Positioned(
                top: 118,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(34, 0),
                    child: const _PottedPlant(),
                  ),
                ),
              ),

              // Floating yellow mascot.
              Positioned(
                top: 70,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(58, 0),
                    child: const _Mascot(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Cloud
// ──────────────────────────────────────────────────────────────────────────────
class _Cloud extends StatelessWidget {
  const _Cloud({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 2.4,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(size),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Storefront
// ──────────────────────────────────────────────────────────────────────────────
class _Storefront extends StatelessWidget {
  const _Storefront();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 130,
      child: Stack(
        children: [
          // Rear shadow chimney detail.
          Positioned(
            top: 0,
            right: 18,
            child: Container(
              width: 14,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.shopShadow,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Building body.
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.shopWall,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shopShadow.withOpacity(0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
          ),
          // Striped awning.
          Positioned(
            top: 28,
            left: 4,
            right: 4,
            child: ClipPath(
              clipper: _AwningClipper(),
              child: SizedBox(
                height: 22,
                child: Row(
                  children: List.generate(7, (i) {
                    final isYellow = i.isEven;
                    return Expanded(
                      child: Container(
                        color: isYellow
                            ? AppColors.awningLight
                            : AppColors.shopWall,
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          // Awning top-bar (the wooden header).
          Positioned(
            top: 22,
            left: 4,
            right: 4,
            child: Container(
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.awningDark,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
            ),
          ),
          // Door.
          Positioned(
            bottom: 0,
            left: 28,
            child: Container(
              width: 28,
              height: 52,
              decoration: const BoxDecoration(
                color: AppColors.door,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Align(
                alignment: const Alignment(0.4, 0.1),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          // Window.
          Positioned(
            bottom: 12,
            right: 18,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.toggleTrack,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.shopShadow, width: 1),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 1, height: 26, color: AppColors.shopShadow,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 26, height: 1, color: AppColors.shopShadow,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AwningClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - 4);

    // Scalloped bottom edge.
    const scallops = 6;
    final w = size.width / scallops;
    for (int i = scallops - 1; i >= 0; i--) {
      p.quadraticBezierTo(
        i * w + w * 0.5, size.height + 2,
        i * w, size.height - 4,
      );
    }
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ──────────────────────────────────────────────────────────────────────────────
// Potted plant
// ──────────────────────────────────────────────────────────────────────────────
class _PottedPlant extends StatelessWidget {
  const _PottedPlant();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 50,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Leaves.
          Positioned(
            top: 0,
            child: Transform.rotate(
              angle: -0.2,
              child: const _Leaf(color: AppColors.leaf,     w: 14, h: 22),
            ),
          ),
          Positioned(
            top: 4, left: 6,
            child: Transform.rotate(
              angle: -0.6,
              child: const _Leaf(color: AppColors.leafDark, w: 10, h: 18),
            ),
          ),
          Positioned(
            top: 4, right: 4,
            child: Transform.rotate(
              angle: 0.5,
              child: const _Leaf(color: AppColors.leafDark, w: 10, h: 18),
            ),
          ),
          // Pot.
          Container(
            width: 26,
            height: 18,
            decoration: const BoxDecoration(
              color: AppColors.pot,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(6),
                topLeft: Radius.circular(2),
                topRight: Radius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Leaf extends StatelessWidget {
  const _Leaf({required this.color, required this.w, required this.h});
  final Color color;
  final double w, h;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft:     Radius.circular(w),
          topRight:    Radius.circular(w / 4),
          bottomLeft:  Radius.circular(w / 4),
          bottomRight: Radius.circular(w),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Mascot — yellow squircle with a friendly face
// ──────────────────────────────────────────────────────────────────────────────
class _Mascot extends StatelessWidget {
  const _Mascot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.awningLight, AppColors.mascot, AppColors.mascotShadow],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.mascotShadow.withOpacity(0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: CustomPaint(painter: _MascotFacePainter()),
    );
  }
}

class _MascotFacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final eye = Paint()..color = const Color(0xFF1B1B1B);
    final eyeR = size.width * 0.04;
    final eyeY = size.height * 0.42;
    canvas.drawCircle(Offset(size.width * 0.34, eyeY), eyeR, eye);
    canvas.drawCircle(Offset(size.width * 0.66, eyeY), eyeR, eye);

    // Smile arc.
    final smile = Paint()
      ..color = const Color(0xFF1B1B1B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.58),
      width:  size.width * 0.42,
      height: size.height * 0.32,
    );
    canvas.drawArc(rect, 0.15, math.pi - 0.3, false, smile);

    // Two soft blush spots.
    final blush = Paint()..color = const Color(0x30E25A2A);
    canvas.drawCircle(Offset(size.width * 0.22, size.height * 0.6), 4, blush);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.6), 4, blush);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
