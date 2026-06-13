import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../home/home_view.dart';
import 'forgot_password_view.dart';
import 'widgets/auth_method_toggle.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/login_illustration.dart';
import 'widgets/primary_login_button.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _otpCtrl      = TextEditingController();

  final _authCtrl = Get.put(AuthController());

  LoginMethod _method        = LoginMethod.password;
  bool        _emailCodeSent = false;
  bool        _passwordVisible = false;

  bool get _otpStage => _method == LoginMethod.emailCode && _emailCodeSent;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _onPrimaryCta() async {
    if (_method == LoginMethod.emailCode && !_emailCodeSent) {
      setState(() => _emailCodeSent = true);
      return;
    }

    if (_method == LoginMethod.password) {
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text.trim();

      if (email.isEmpty || password.isEmpty) {
        _showError('Please enter email and password.');
        return;
      }

      final success = await _authCtrl.login(email: email, password: password);

      if (!mounted) return;

      if (!success) {
        _showError(_authCtrl.errorMessage ?? 'Login failed.');
        return;
      }

      // Gate entry on `GET /api/v1/auth/me` — only sellers may enter. The
      // endpoint returns 200 for buyers too, so the role decides.
      final result = await _authCtrl.fetchMe();

      if (!mounted) return;

      switch (result) {
        case AuthMeResult.seller:
          _goHome();
          break;
        case AuthMeResult.notSeller:
          await _showNoSellerAccessDialog();
          break;
        case AuthMeResult.error:
          _showError(
              _authCtrl.errorMessage ?? 'Could not verify your account.');
          break;
      }
      return;
    }

    // OTP verify — placeholder for now
    _goHome();
  }

  /// Navigates to Home, ensuring the seller profile is loaded first. The
  /// profile API is called here on login: if the controller already exists
  /// (e.g. after a previous logout), it's refreshed; otherwise creating it
  /// triggers its initial fetch.
  void _goHome() {
    if (Get.isRegistered<ProfileController>()) {
      Get.find<ProfileController>().fetchProfile();
    } else {
      getOrPut(() => ProfileController());
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeView()),
      (route) => false,
    );
  }

  /// Shown when a non-seller (e.g. a buyer) signs in. They can't use the
  /// Seller app, so we explain why and sign them out on OK so they land back
  /// on a clean login screen (and aren't auto-routed to Home on next launch).
  Future<void> _showNoSellerAccessDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AppColors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
              const CustomText(
                'No seller access',
                fontSize: 19,
                fontWeight: FontWeight.w800,
                textAlign: TextAlign.center,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 10),
              const CustomText(
                'This is the Tommesalg Seller app, but your account is '
                'registered as a buyer. To start selling, please complete the '
                'seller registration form on our website first. Once approved, '
                'you can sign in here.',
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
    await _authCtrl.logout();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String get _ctaLabel {
    if (_otpStage) return 'Verify code';
    return _method == LoginMethod.password
        ? 'Log in'
        : 'Send login code';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            const LoginIllustration(),
            Expanded(child: _buildCard(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            _otpStage ? 'Verify code' : 'Log in',
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 6),
          CustomText(
            _otpStage
                ? 'We sent a 6-digit code to ${_emailCtrl.text.trim()}.'
                : 'Welcome back to your store.',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 22),

          if (!_otpStage) ...[
            AuthMethodToggle(
              method: _method,
              onChanged: (m) => setState(() => _method = m),
            ),
            const SizedBox(height: 22),
          ],

          if (_method == LoginMethod.emailCode && !_otpStage) ...[
            const _EmailCodeNotice(),
            const SizedBox(height: 18),
          ],

          const CustomText(
            'EMAIL',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 8),
          AbsorbPointer(
            absorbing: _otpStage,
            child: Opacity(
              opacity: _otpStage ? 0.7 : 1,
              child: AuthTextField(
                controller: _emailCtrl,
                icon: Icons.mail_outline_rounded,
                hint: 'navn@tommesalg.no',
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
            ),
          ),

          if (_method == LoginMethod.password) ...[
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const CustomText(
                  'PASSWORD',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.textSecondary,
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ForgotPasswordView(),
                    ),
                  ),
                  child: const CustomText(
                    'Forgot password?',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AuthTextField(
              controller: _passwordCtrl,
              icon: Icons.lock_outline_rounded,
              hint: '••••••••',
              obscure: !_passwordVisible,
              autofillHints: const [AutofillHints.password],
              suffix: GestureDetector(
                onTap: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                child: Icon(
                  _passwordVisible
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ] else if (_otpStage) ...[
            const SizedBox(height: 18),
            const CustomText(
              'LOGIN CODE',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            AuthTextField(
              controller: _otpCtrl,
              icon: Icons.pin_rounded,
              hint: '6-digit code',
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                GestureDetector(
                  onTap: () {},
                  child: const CustomText(
                    'Resend',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: () {
                    _otpCtrl.clear();
                    setState(() => _emailCodeSent = false);
                  },
                  child: const CustomText(
                    'Change email',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppColors.textMuted,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: CustomText(
                    'Vi sender deg en 6-digit code på e-post',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),

          Obx(() => PrimaryLoginButton(
                label: _ctaLabel,
                busy: _authCtrl.isLoading,
                onPressed: _authCtrl.isLoading ? null : _onPrimaryCta,
              )),

          const SizedBox(height: 22),

          // Center(
          //   child: Row(
          //     mainAxisSize: MainAxisSize.min,
          //     children: [
          //       const CustomText(
          //         "Don't have an account?  ",
          //         fontSize: 13,
          //         fontWeight: FontWeight.w500,
          //         color: AppColors.textSecondary,
          //       ),
          //       GestureDetector(
          //         onTap: () {},
          //         child: const CustomText(
          //           'Sign up now',
          //           fontSize: 13,
          //           fontWeight: FontWeight.w700,
          //           color: AppColors.accent,
          //         ),
          //       ),
          //     ],
          //   ),
          // ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _EmailCodeNotice extends StatelessWidget {
  const _EmailCodeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.backgroundSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accent.withOpacity(0.22),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
         const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 CustomText(
                  'Email code is only for existing members.',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: AppColors.textPrimary,
                ),
                 SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
