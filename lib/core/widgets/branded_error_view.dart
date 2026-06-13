import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../localization/translation_keys.dart';
import '../theme/app_colors.dart';
import 'custom_text.dart';

/// Centred error state in the brand palette — yellow squircle with a
/// navy alert glyph, the message in navy below, and a navy retry pill
/// at the bottom. Pairs with [BrandedLoadingView] so each API-bound
/// screen has one consistent loading / error pair to plug in.
///
/// ```dart
/// if (controller.errorMessage != null) {
///   return BrandedErrorView(
///     message : controller.errorMessage!,
///     onRetry : () => controller.fetchUserDetails(),
///   );
/// }
/// ```
class BrandedErrorView extends StatelessWidget {
  const BrandedErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  /// Human-readable message — the controllers already produce this via
  /// `_readableError` (Supabase / buyer API) so callers can pass the
  /// value straight through.
  final String message;

  /// Optional retry callback. The retry button only renders when set.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final onRetry = this.onRetry;

    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.brandYellow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  size: 26,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 18),
              CustomText(
                message,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: AppColors.brandNavy,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRetry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.brandNavy,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color: AppColors.brandYellow,
                        ),
                        const SizedBox(width: 8),
                        CustomText(
                          TKeys.retry.tr.toUpperCase(),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          color: AppColors.brandYellow,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
