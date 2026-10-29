import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/localization/translation_keys.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import 'login_view.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/primary_login_button.dart';

/// Step 2 of the password reset: the numeric code emailed to [email] plus the
/// new password, sent to `POST /api/v1/auth/reset-password`.
///
/// Nothing is signed in here. On success the seller goes back to Login and
/// signs in fresh with the new password; older sessions are invalid.
class ResetPasswordView extends StatefulWidget {
  const ResetPasswordView({super.key, required this.email});

  /// The address the code was sent to — the only one the code is valid for.
  final String email;

  /// Same rule as the backend (contract §4.1): 6–128 characters with at least
  /// one lowercase letter, one uppercase letter, one digit and one symbol.
  static bool meetsPasswordPolicy(String password) =>
      password.length >= 6 &&
      password.length <= 128 &&
      RegExp(r'[a-z]').hasMatch(password) &&
      RegExp(r'[A-Z]').hasMatch(password) &&
      RegExp(r'[0-9]').hasMatch(password) &&
      RegExp(r'[^A-Za-z0-9]').hasMatch(password);

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<ResetPasswordView> {
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _authCtrl = getOrPut(() => AuthController());

  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final code = _codeCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (code.isEmpty) {
      setState(() => _error = TKeys.authEnterResetCode.tr);
      return;
    }
    if (!ResetPasswordView.meetsPasswordPolicy(password)) {
      setState(() => _error = TKeys.authPasswordPolicy.tr);
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

    final ok = await _authCtrl.resetPassword(
      email: widget.email,
      code: code,
      newPassword: password,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      setState(() => _error =
          _authCtrl.errorMessage ?? TKeys.authPasswordUpdateFailed.tr);
      return;
    }

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
                TKeys.authSetNewPasswordBody.trParams({'email': widget.email}),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 22),

              CustomText(
                TKeys.authResetCodeCaps.tr,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 8),
              AuthTextField(
                controller: _codeCtrl,
                icon: Icons.pin_outlined,
                hint: TKeys.authResetCodeHint.tr,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
              ),
              const SizedBox(height: 18),

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
