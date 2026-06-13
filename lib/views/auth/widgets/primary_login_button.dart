import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// The big yellow→orange "Logg inn" CTA. By default it carries a circular
/// dark badge on the right that hosts a forward arrow (or a spinner while
/// busy). Pass `showArrow: false` for a bare button — the label centres on
/// its own and the busy state renders an inline spinner in the middle.
class PrimaryLoginButton extends StatelessWidget {
  const PrimaryLoginButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.showArrow = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: GestureDetector(
        onTap: busy ? null : onPressed,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [AppColors.primaryYellow, AppColors.primaryOrange],
            ),
            boxShadow: const [
              BoxShadow(
                color: AppColors.buttonShadow,
                blurRadius: 22,
                offset: Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // 44px spacer mirrors the trailing badge so the label stays
              // visually centred. Without an arrow there's nothing to
              // balance, so we drop both.
              if (showArrow) const SizedBox(width: 44),
              Expanded(
                child: Center(
                  child: !showArrow && busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor:
                                AlwaysStoppedAnimation(Color(0xFF181818)),
                          ),
                        )
                      : Text(label, style: AppTextStyles.button),
                ),
              ),
              if (showArrow) _ArrowBadge(busy: busy),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrowBadge extends StatelessWidget {
  const _ArrowBadge({required this.busy});
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          : const Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
              size: 20,
            ),
    );
  }
}
