import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import 'login_view.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/primary_login_button.dart';
import '../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

/// Step 2 of the password reset. Reached only via the recovery deep link, so
/// the recovery session is already installed by [AuthService.setRecoverySession]
/// before this screen mounts.
///
/// After updating the password we deliberately [AuthService.logout] so the
/// recovery session is NOT carried into a real session — the user must sign in
/// fresh with the new password.
class ResetPasswordView extends StatefulWidget {
  const ResetPasswordView({super.key});

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<ResetPasswordView> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (password.length < 8) {
      setState(() => _error = TKeys.authPasswordTooShort.tr);
      return;
    }
    if (password != confirm) {
      setState(() => _error = TKeys.authPasswordsDoNotMatch.tr);
      return;
    }

    // Capture before awaits.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await AuthService.instance.updatePassword(password);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = TKeys.authPasswordUpdateFailed.tr;
      });
      return;
    }

    // Don't carry the recovery session into a real session.
    await AuthService.instance.logout();

    if (!mounted) return;
    setState(() => _busy = false);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          TKeys.authPasswordUpdated.tr,
        ),
        backgroundColor: AppColors.brandNavy,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginView()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        // Arrived from an email link — no screen to go back to.
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomText(
                TKeys.authSetNewPassword.tr,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -0.5,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 6),
              CustomText(
                TKeys.authSetNewPasswordBody.tr,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 22),

              CustomText(
                TKeys.authNewPasswordCaps.tr,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 8),
              AuthTextField(
                controller: _passwordCtrl,
                icon: Icons.lock_outline_rounded,
                hint: '••••••••',
                obscure: !_passwordVisible,
                autofillHints: const [AutofillHints.newPassword],
                suffix: _VisibilityToggle(
                  visible: _passwordVisible,
                  onTap: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                ),
              ),
              const SizedBox(height: 18),

              CustomText(
                TKeys.authConfirmPasswordCaps.tr,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 8),
              AuthTextField(
                controller: _confirmCtrl,
                icon: Icons.lock_outline_rounded,
                hint: '••••••••',
                obscure: !_confirmVisible,
                autofillHints: const [AutofillHints.newPassword],
                suffix: _VisibilityToggle(
                  visible: _confirmVisible,
                  onTap: () =>
                      setState(() => _confirmVisible = !_confirmVisible),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 16, color: AppColors.vipps),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CustomText(
                        _error!,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: AppColors.vipps,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 22),

              PrimaryLoginButton(
                label: TKeys.authUpdatePassword.tr,
                busy: _busy,
                onPressed: _busy ? null : _onSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        size: 18,
        color: AppColors.textSecondary,
      ),
    );
  }
}
