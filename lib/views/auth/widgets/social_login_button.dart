import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';

/// Visual variant for social-login buttons.
enum SocialButtonStyle { vipps, google }

class SocialLoginButton extends StatelessWidget {
  const SocialLoginButton({
    super.key,
    required this.style,
    required this.label,
    required this.onPressed,
  });

  final SocialButtonStyle style;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isVipps = style == SocialButtonStyle.vipps;
    final bg = isVipps ? AppColors.vipps : AppColors.card;
    final fg = isVipps ? Colors.white : AppColors.textPrimary;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: isVipps
              ? null
              : Border.all(color: AppColors.inputBorder, width: 1),
          boxShadow: isVipps
              ? [
                  BoxShadow(
                    color: AppColors.vipps.withOpacity(0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            isVipps ? const _VippsLogo() : const _GoogleLogo(),
            const SizedBox(width: 12),
            CustomText(
              label,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              color: fg,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Vipps: a small white smile bubble inside the button ──────────────────────
class _VippsLogo extends StatelessWidget {
  const _VippsLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: CustomPaint(painter: _VippsSmilePainter()),
    );
  }
}

class _VippsSmilePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.vipps
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.55),
      width: size.width * 0.55,
      height: size.height * 0.45,
    );
    canvas.drawArc(rect, 0.2, 3.14 - 0.4, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Google: tri-coloured "G" ────────────────────────────────────────────────
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleGlyphPainter()),
    );
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final centre = Offset(size.width / 2, size.height / 2);

    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.butt;

    final rect = Rect.fromCircle(center: centre, radius: radius * 0.78);

    // Each quadrant in Google's brand colours.
    canvas.drawArc(rect, -0.5, 1.6,           false, stroke(const Color(0xFF4285F4)));
    canvas.drawArc(rect, 1.1,  1.55,          false, stroke(const Color(0xFF34A853)));
    canvas.drawArc(rect, 2.65, 1.55,          false, stroke(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 4.20, 1.55,          false, stroke(const Color(0xFFEA4335)));

    // Horizontal bar of the "G".
    final bar = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(centre.dx, centre.dy - size.height * 0.06,
          radius * 0.85, size.height * 0.18),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
