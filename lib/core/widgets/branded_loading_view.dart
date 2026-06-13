import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../localization/translation_keys.dart';
import '../theme/app_colors.dart';
import 'custom_text.dart';

/// Centred loading state in the brand palette — yellow ring on the cream
/// scaffold background, with an optional caption underneath. Matches the
/// splash screen's spinner so the app feels like one continuous surface
/// from cold start through any in-app fetch.
///
/// Designed to drop straight into a `body:` slot or wherever an
/// in-progress API call needs to take over the viewport (profile fetch,
/// auction stream, listing details, …):
///
/// ```dart
/// if (controller.isLoading) return const BrandedLoadingView();
/// ```
class BrandedLoadingView extends StatelessWidget {
  const BrandedLoadingView({
    super.key,
    this.label,
    this.size = 32,
  });

  /// Optional caption shown below the spinner. Defaults to the shared
  /// `loading` translation when omitted.
  final String? label;

  /// Overall ring size — bump it on a full-screen loader, leave the
  /// default for inline placements.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.accent.withOpacity(0.85),
                ),
                backgroundColor:
                    AppColors.brandNavy.withOpacity(0.08),
              ),
            ),
            const SizedBox(height: 14),
            CustomText(
              label ?? TKeys.loading.tr,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.brandNavy.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }
}
