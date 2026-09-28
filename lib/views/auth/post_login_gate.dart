import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/config/session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../../features/notifications/application/push_notification_service.dart';
import '../home/home_view.dart';
import '../../core/localization/translation_keys.dart';

/// Everything that has to happen *after* a session exists but *before* the
/// seller is allowed into the app.
///
/// Shared by both sign-in paths — password on `LoginView` and email code on
/// `VerifyCodeView` — so the role check can't be skipped by whichever screen
/// happens to authenticate.
Future<void> runSellerGate(BuildContext context) async {
  final authCtrl = getOrPut(() => AuthController());

  // Gate entry on `GET /api/v1/auth/me` — only sellers may enter. The
  // endpoint returns 200 for buyers too, so the role decides.
  final result = await authCtrl.fetchMe();

  if (!context.mounted) return;

  switch (result) {
    case AuthMeResult.seller:
      goHome(context);
      break;
    case AuthMeResult.notSeller:
      await showNoSellerAccessDialog(context);
      break;
    case AuthMeResult.error:
      showAuthError(
        context,
        authCtrl.errorMessage ?? TKeys.gateVerifyFailed.tr,
      );
      break;
  }
}

/// Navigates to Home, ensuring the seller profile is loaded first.
///
/// Signing out clears the per-account controllers, but a session can also end
/// without `logout()` running — an expired or revoked token, or a non-seller
/// bounced off the gate. Clearing again here means whoever just signed in
/// never inherits the previous account's controllers, whichever way the last
/// session ended. It's a no-op on a cold start.
void goHome(BuildContext context) {
  resetSessionControllers();
  getOrPut(() => ProfileController());

  // Post-login notification setup: asks for permission (a no-op prompt if the
  // splash already secured it) and registers this handset's FCM token against
  // the account that just signed in. Unawaited — push is an enhancement and
  // must never hold up navigation.
  unawaited(PushNotificationService.instance.onAuthenticated());

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const HomeView()),
    (route) => false,
  );
}

/// Shown when a non-seller (e.g. a buyer) signs in. They can't use the
/// Seller app, so we explain why and sign them out on OK so they land back
/// on a clean login screen (and aren't auto-routed to Home on next launch).
Future<void> showNoSellerAccessDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => Dialog(
      backgroundColor: AppColors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.brandYellow.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.storefront_outlined,
                size: 32,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 18),
            CustomText(
              TKeys.gateNoSellerAccess.tr,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              textAlign: TextAlign.center,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 10),
            CustomText(
              TKeys.gateNoSellerAccessBody.tr,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.5,
              textAlign: TextAlign.center,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => Navigator.of(dialogCtx).pop(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: AppColors.brandNavy,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const CustomText(
                  'OK',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // Clear the buyer's session so they stay on (and return to) login.
  await getOrPut(() => AuthController()).logout();
}

void showAuthError(BuildContext context, String message) =>
    showAuthSnack(context, message, Colors.red.shade700);

void showAuthInfo(BuildContext context, String message) =>
    showAuthSnack(context, message, AppColors.brandNavy);

void showAuthSnack(BuildContext context, String message, Color background) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
}
