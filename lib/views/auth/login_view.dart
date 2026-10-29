import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../core/services/social_auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import 'become_seller_view.dart';
import 'forgot_password_view.dart';
import 'post_login_gate.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/login_illustration.dart';
import 'widgets/primary_login_button.dart';
import 'widgets/social_login_button.dart';
import '../../core/localization/translation_keys.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key, this.runSellerGateOnOpen = false});

  /// A session already exists but hasn't passed the seller gate — an Android
  /// Google / Apple sign-in the splash finished after a cold start. Runs the
  /// gate as soon as the screen is up.
  final bool runSellerGateOnOpen;

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  /// Apple comes back from the backend callback as `auth_failed /
  /// code_exchange_failed` until the backend fix lands (sign-in guide §1-2),
  /// so its button stays hidden. Flip once Apple works end to end — App Store
  /// guideline 4.8 expects it alongside Google.
  static const bool _appleSignInEnabled = false;

  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();

  final _authCtrl = Get.put(AuthController());

  bool _passwordVisible = false;

  @override
  void initState() {
    super.initState();
    if (widget.runSellerGateOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) runSellerGate(context);
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loginWithPassword() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      showAuthError(context, TKeys.authEnterEmailPassword.tr);
      return;
    }

    final success = await _authCtrl.login(email: email, password: password);

    if (!mounted) return;

    if (!success) {
      showAuthError(context, _authCtrl.errorMessage ?? TKeys.authLoginFailed.tr);
      return;
    }

    await runSellerGate(context);
  }

  /// Google / Apple: browser sign-in, then the same seller gate as password
  /// login — a new federated identity is only a buyer, so the gate is what
  /// keeps it out. A cancel is silent.
  Future<void> _loginWithSocial(SocialProvider provider) async {
    final success = await _authCtrl.socialLogin(provider);
    if (!mounted) return;

    if (!success) {
      final message = _authCtrl.errorMessage;
      if (message != null) showAuthError(context, message);
      return;
    }

    await runSellerGate(context);
  }

  /// Straight to the application form — no sign-in, no session. The submit
  /// goes out unauthenticated and the form collects the identity fields the
  /// server would otherwise read off an account.
  void _openApplication() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const BecomeSellerView(anonymous: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // One scroll view for the whole page: the illustration scrolls away with
    // the form instead of staying pinned above a separately-scrolling card, so
    // short screens (and an open keyboard) can reach every field.
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            children: [
              const SizedBox(height: 8),
              const LoginIllustration(),
              _buildCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            TKeys.authLogIn.tr,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 6),
          CustomText(
            TKeys.authWelcomeBackStore.tr,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: AppColors.textSecondary,
          ),

          const SizedBox(height: 18),
          _ApplicantEntry(onApply: _openApplication),

          const SizedBox(height: 18),
          const _BusinessOnlyBadge(),

          const SizedBox(height: 22),

          CustomText(
            TKeys.emailCaps.tr,
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

          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CustomText(
                TKeys.passwordCaps.tr,
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
                child: CustomText(
                  TKeys.authForgotPassword.tr,
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
          const SizedBox(height: 22),

          Obx(() => PrimaryLoginButton(
                label: TKeys.authLogIn.tr,
                busy: _authCtrl.isLoading,
                onPressed: _authCtrl.isBusy ? null : _loginWithPassword,
              )),

          const SizedBox(height: 18),
          const _OrDivider(),
          const SizedBox(height: 18),
          Obx(() {
            final busy = _authCtrl.socialBusy;
            VoidCallback? start(SocialProvider p) =>
                _authCtrl.isBusy ? null : () => _loginWithSocial(p);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SocialLoginButton(
                  style: SocialButtonStyle.google,
                  label: TKeys.authContinueGoogle.tr,
                  busy: busy == SocialProvider.google,
                  onPressed: start(SocialProvider.google),
                ),
                if (_appleSignInEnabled) ...[
                  const SizedBox(height: 12),
                  SocialLoginButton(
                    style: SocialButtonStyle.apple,
                    label: TKeys.authContinueApple.tr,
                    busy: busy == SocialProvider.apple,
                    onPressed: start(SocialProvider.apple),
                  ),
                ],
              ],
            );
          }),

          const SizedBox(height: 14),
          const _StaySignedInNote(),

          const SizedBox(height: 22),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

/// "──── OR ────" between password login and the social buttons.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.borderGrey, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: CustomText(
            TKeys.authOrCaps.tr,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.textSecondary,
          ),
        ),
        const Expanded(child: Divider(color: AppColors.borderGrey, height: 1)),
      ],
    );
  }
}

/// Sets the expectation the session layer now delivers: sign in once and the
/// app restores the session on every later launch, until the seller signs out
/// (or the session is revoked server-side). Nothing about the password is
/// kept on the device — only the session tokens, in the Keychain / Keystore.
class _StaySignedInNote extends StatelessWidget {
  const _StaySignedInNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.lock_clock_outlined,
              size: 14, color: AppColors.textMuted),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: CustomText(
            TKeys.authStaySignedIn.tr,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Makes the B2B nature of the app explicit on the login screen: access is
/// limited to approved business sellers, not the general public or consumers.
class _BusinessOnlyBadge extends StatelessWidget {
  const _BusinessOnlyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.backgroundSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.brandNavy.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.business_center_outlined,
            size: 16,
            color: AppColors.brandNavy,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CustomText(
              TKeys.authBusinessOnly.tr,
              fontSize: 12,
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

/// The way in for someone who doesn't have a seller account yet: apply.
class _ApplicantEntry extends StatelessWidget {
  const _ApplicantEntry({required this.onApply});

  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.borderGrey, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CustomText(
                TKeys.authNotSellerYet.tr,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.textSecondary,
              ),
            ),
            const Expanded(child: Divider(color: AppColors.borderGrey, height: 1)),
          ],
        ),
        const SizedBox(height: 14),
        _EntryCard(
          icon: Icons.sell_outlined,
          title: TKeys.authBecomeSeller.tr,
          subtitle: TKeys.authBecomeSellerSub.tr,
          onTap: onApply,
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderGrey, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.brandYellow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: AppColors.brandNavy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    title,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                  const SizedBox(height: 2),
                  CustomText(
                    subtitle,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded,
                size: 18, color: AppColors.brandNavy),
          ],
        ),
      ),
    );
  }
}
