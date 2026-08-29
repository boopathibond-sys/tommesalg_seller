import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/primary_login_button.dart';
import '../../core/localization/translation_keys.dart';

/// Step 1 of the password reset: collect the email and ask the buyer backend
/// to send the recovery link.
///
/// Anti-enumeration: whatever the backend returns, a successful request shows
/// the same generic "if an account exists…" message — we never reveal whether
/// the email is registered.
class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final _emailCtrl = TextEditingController();
  final _authCtrl = getOrPut(() => AuthController());

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSendLink() async {
    final email = _emailCtrl.text.trim();

    // Capture before the await so we don't touch a stale BuildContext after.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final accepted = await _authCtrl.requestPasswordReset(email: email);

    if (!mounted) return;

    if (!accepted) {
      messenger.showSnackBar(
        _snack(
          _authCtrl.errorMessage ?? TKeys.authSomethingWrong.tr,
          AppColors.vipps,
        ),
      );
      return;
    }

    // Generic, account-agnostic confirmation, then back to login.
    messenger.showSnackBar(
      _snack(
        TKeys.authResetLinkSent.trParams({'email': email}),
        AppColors.brandNavy,
      ),
    );
    navigator.maybePop();
  }

  SnackBar _snack(String message, Color background) => SnackBar(
        content: Text(message),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomText(
                TKeys.authForgotPasswordTitle.tr,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -0.5,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 6),
              CustomText(
                TKeys.authForgotPasswordBody.tr,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 22),

              const CustomText(
                'EMAIL',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 8),
              AuthTextField(
                controller: _emailCtrl,
                icon: Icons.mail_outline_rounded,
                hint: TKeys.emailHintTommesalg.tr,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),

              // Inline error banner mirrors the snackbar for non-2xx replies.
              Obx(() {
                final error = _authCtrl.errorMessage;
                if (error == null || error.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _ErrorBanner(message: error),
                );
              }),

              const SizedBox(height: 22),

              Obx(() => PrimaryLoginButton(
                    label: TKeys.authSendResetLink.tr,
                    busy: _authCtrl.isLoading,
                    onPressed: _authCtrl.isLoading ? null : _onSendLink,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.vipps.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.vipps.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.vipps),
          const SizedBox(width: 8),
          Expanded(
            child: CustomText(
              message,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
