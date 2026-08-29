import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

/// Login method this screen supports. Lives next to the toggle so the auth
/// UI compiles without a view-model layer.
enum LoginMethod { password, emailCode }

/// Two-way segmented control swapping between password login and email-code
/// login.
///
/// A pure-white pill rides under the active half, lifted by a soft
/// orange-tinted shadow so it appears to float above the recessed track.
/// Icons scale and labels cross-fade as selection changes — the same
/// "premium picker" feel you get from iOS-grade apps.
class AuthMethodToggle extends StatelessWidget {
  const AuthMethodToggle({
    super.key,
    required this.method,
    required this.onChanged,
  });

  final LoginMethod method;
  final ValueChanged<LoginMethod> onChanged;

  // ── Geometry ───────────────────────────────────────────────────────────────
  static const double _height       = 56;
  static const double _innerPadding = 5;
  static const double _trackRadius  = 16;
  static const double _pillRadius   = 12;

  // ── Motion ─────────────────────────────────────────────────────────────────
  static const Duration _slideDuration = Duration(milliseconds: 320);
  static const Curve    _slideCurve    = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _height,
      padding: const EdgeInsets.all(_innerPadding),
      decoration: BoxDecoration(
        color: AppColors.toggleTrack,
        borderRadius: BorderRadius.circular(_trackRadius),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segWidth   = (constraints.maxWidth - _innerPadding * 2) / 2;
          final isPassword = method == LoginMethod.password;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Floating pill ───────────────────────────────────────────────
              AnimatedPositioned(
                duration: _slideDuration,
                curve: _slideCurve,
                left: isPassword ? 0 : segWidth,
                top: 0,
                bottom: 0,
                width: segWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(_pillRadius),
                    boxShadow: [
                      // Warm tinted glow — picks up the brand accent.
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                      // Tight contact shadow for crispness.
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Tappable segments ────────────────────────────────────────────
              // Positioned.fill makes the Row span the Stack's full height
              // (46px after the Container's 5px inset). crossAxisAlignment.stretch
              // then forces each Expanded segment to that full height, so the
              // icon + label centre inside the pill AND the tap zone is the
              // entire segment, not just the text.
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Segment(
                      icon: Icons.lock_rounded,
                      label: TKeys.authPassword.tr,
                      selected: isPassword,
                      onTap: () => onChanged(LoginMethod.password),
                    ),
                    _Segment(
                      icon: Icons.mail_rounded,
                      label: TKeys.authEmailCode.tr,
                      selected: !isPassword,
                      onTap: () => onChanged(LoginMethod.emailCode),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Segment
// ─────────────────────────────────────────────────────────────────────────────
class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData      icon;
  final String        label;
  final bool          selected;
  final VoidCallback  onTap;

  static const Duration _stateDuration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    const activeIcon   = AppColors.accent;
    const inactiveIcon = AppColors.textMuted;
    const activeText   = AppColors.textPrimary;
    const inactiveText = AppColors.textSecondary;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon: tweens both colour and scale on state change.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: selected ? 1 : 0, end: selected ? 1 : 0),
              duration: _stateDuration,
              curve: Curves.easeOut,
              builder: (_, t, __) {
                final color = Color.lerp(inactiveIcon, activeIcon, t)!;
                final scale = 0.92 + (0.08 * t);
                return Transform.scale(
                  scale: scale,
                  child: Icon(icon, size: 18, color: color),
                );
              },
            ),
            const SizedBox(width: 8),
            // Label: colour cross-fades; weight switches at the boundary.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: selected ? 1 : 0, end: selected ? 1 : 0),
              duration: _stateDuration,
              curve: Curves.easeOut,
              builder: (_, t, __) {
                final textColor = Color.lerp(inactiveText, activeText, t)!;
                return CustomText(
                  label,
                  fontSize: 13.5,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.1,
                  color: textColor,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
