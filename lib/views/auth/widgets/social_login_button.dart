import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';

/// Visual variant for social-login buttons.
///
/// `apple` follows Apple's own button spec — black fill, white logo and
/// label — because Sign in with Apple has published design requirements.
enum SocialButtonStyle { vipps, google, apple }

class SocialLoginButton extends StatelessWidget {
  const SocialLoginButton({
    super.key,
    required this.style,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final SocialButtonStyle style;
  final String label;

  /// Null disables the button (another sign-in is running).
  final VoidCallback? onPressed;

  /// Swaps the provider logo for a spinner and drops taps while this
  /// provider's sign-in is in flight.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isVipps = style == SocialButtonStyle.vipps;
    final isApple = style == SocialButtonStyle.apple;
    final bg = isVipps
        ? AppColors.vipps
        : isApple
            ? _appleBlack
            : AppColors.card;
    final fg = (isVipps || isApple) ? Colors.white : AppColors.textPrimary;

    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Opacity(
        opacity: onPressed == null && !busy ? 0.55 : 1,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: (isVipps || isApple)
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
              if (busy)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                )
              else
                switch (style) {
                  SocialButtonStyle.vipps => const _VippsLogo(),
                  SocialButtonStyle.google => const _GoogleLogo(),
                  SocialButtonStyle.apple =>
                    const Icon(Icons.apple, size: 24, color: Colors.white),
                },
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
      ),
    );
  }
}

/// Apple's button black. Their guidelines specify pure black (or white), not
/// the app's navy.
const Color _appleBlack = Color(0xFF000000);

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
    canvas.drawArc(rect, -0.5, 1.6, false, stroke(const Color(0xFF4285F4)));
    canvas.drawArc(rect, 1.1, 1.55, false, stroke(const Color(0xFF34A853)));
    canvas.drawArc(rect, 2.65, 1.55, false, stroke(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 4.20, 1.55, false, stroke(const Color(0xFFEA4335)));

    // Horizontal bar of the "G".
    final bar = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(centre.dx, centre.dy - size.height * 0.06, radius * 0.85,
          size.height * 0.18),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
