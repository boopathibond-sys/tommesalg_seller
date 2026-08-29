import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import 'post_login_gate.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/primary_login_button.dart';
import '../../core/localization/translation_keys.dart';

/// Step 2 of email-code login: the seller types the 6-digit code Supabase
/// mailed to [email], we exchange it for a session, then the shared seller
/// gate decides whether they get into the app.
///
/// Pushed by `LoginView` once the code is confirmed sent, so backing out
/// returns to a login screen with the email still filled in. The pending code
/// stays valid on Supabase's side for its normal lifetime, so coming back and
/// re-sending is harmless.
class VerifyCodeView extends StatefulWidget {
  const VerifyCodeView({
    super.key,
    required this.email,
    this.title,
    this.subtitle,
    this.onVerified,
  });

  /// Address the code was actually mailed to — the login field is no longer
  /// in play, so this is the only value the verify call may use.
  final String email;

  /// Headline, so the applicant path can say what it's confirming rather than
  /// "Verify code".
  /// Null falls back to the translated default at paint time.
  final String? title;

  /// Replaces the default "…to log in." line when the session isn't a login.
  final String? subtitle;

  /// What to do once a session exists. Defaults to [runSellerGate] — the
  /// seller sign-in path. The become-a-seller flow passes its own handler:
  /// that session belongs to an *applicant*, so it must never be role-checked
  /// into `HomeView` or bounced by `showNoSellerAccessDialog`.
  final Future<void> Function(BuildContext context)? onVerified;

  @override
  State<VerifyCodeView> createState() => _VerifyCodeViewState();
}

class _VerifyCodeViewState extends State<VerifyCodeView> {
  /// Seconds before another code can be mailed. Supabase enforces its own
  /// per-address limit server-side; this just stops the button from firing
  /// requests that would come back as 429s.
  static const int _resendCooldownSeconds = 60;

  final _codeCtrl = TextEditingController();
  final _authCtrl = getOrPut(() => AuthController());

  Timer? _resendTimer;
  int    _resendIn = 0;

  @override
  void initState() {
    super.initState();
    // The code that got us here was just sent, so the clock starts full.
    _startResendCooldown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _onVerify() async {
    final code = _codeCtrl.text.trim();

    if (code.isEmpty) {
      showAuthError(context, TKeys.verifyEnterCode.tr);
      return;
    }

    final verified =
        await _authCtrl.verifyLoginCode(email: widget.email, code: code);

    if (!mounted) return;

    if (!verified) {
      showAuthError(
        context,
        _authCtrl.errorMessage ?? TKeys.verifyFailed.tr,
      );
      return;
    }

    await (widget.onVerified ?? runSellerGate)(context);
  }

  Future<void> _onResend() async {
    final sent = await _authCtrl.sendLoginCode(email: widget.email);

    if (!mounted) return;

    if (!sent) {
      showAuthError(
        context,
        _authCtrl.errorMessage ?? TKeys.verifyResendFailed.tr,
      );
      return;
    }

    _codeCtrl.clear();
    _startResendCooldown();
    showAuthInfo(context,
        TKeys.verifyNewCodeSent.trParams({'email': widget.email}));
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
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
                widget.title ?? TKeys.verifyCodeTitle.tr,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -0.5,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 6),
              CustomText(
                widget.subtitle ??
                    TKeys.verifySentTo.trParams({'email': widget.email}),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 22),

              CustomText(
                TKeys.verifyLoginCodeCaps.tr,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 8),
              AuthTextField(
                controller: _codeCtrl,
                icon: Icons.pin_rounded,
                hint: TKeys.verifySixDigitHint.tr,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  GestureDetector(
                    onTap: _resendIn > 0 ? null : _onResend,
                    child: CustomText(
                      _resendIn > 0
                          ? TKeys.verifyResendIn
                              .trParams({'seconds': '$_resendIn'})
                          : TKeys.verifyResendCode.tr,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          _resendIn > 0 ? AppColors.textMuted : AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 18),
                  GestureDetector(
                    // Back to login with the email field intact.
                    onTap: () => Navigator.of(context).maybePop(),
                    child: CustomText(
                      TKeys.verifyChangeEmail.tr,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              Obx(() => PrimaryLoginButton(
                    label: TKeys.verifyCodeTitle.tr,
                    busy: _authCtrl.isLoading,
                    onPressed: _authCtrl.isLoading ? null : _onVerify,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
