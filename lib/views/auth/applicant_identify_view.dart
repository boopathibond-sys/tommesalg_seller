import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/seller_application_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import 'become_seller_view.dart';
import 'post_login_gate.dart';
import 'verify_code_view.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/primary_login_button.dart';
import '../../core/localization/translation_keys.dart';

/// Identifies an existing applicant so their application status can be read.
///
/// Applying itself is anonymous — the login screen's "Become a seller" card
/// opens [BecomeSellerView] directly. Checking a *status* can't be: the
/// endpoint answers for whichever account the bearer token belongs to, and
/// there is no lookup-by-e-mail equivalent. So this screen bridges the gap:
/// e-mail → 6-digit code → a session [BecomeSellerView] can read the gate
/// with.
///
/// The session it creates is an **applicant** session, not a seller one, so it
/// deliberately never calls `runSellerGate` — that would either drop the
/// applicant into `HomeView` or bounce them through the "no seller access"
/// dialog. [BecomeSellerView] signs it out on the way back.
class ApplicantIdentifyView extends StatefulWidget {
  const ApplicantIdentifyView({super.key});

  @override
  State<ApplicantIdentifyView> createState() => _ApplicantIdentifyViewState();
}

class _ApplicantIdentifyViewState extends State<ApplicantIdentifyView> {
  final _emailCtrl = TextEditingController();
  final _authCtrl = getOrPut(() => AuthController());

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      showAuthError(context, TKeys.authEnterEmail.tr);
      return;
    }

    final sent = await _authCtrl.sendLoginCode(email: email);
    if (!mounted) return;

    if (!sent) {
      showAuthError(
        context,
        _authCtrl.errorMessage ?? TKeys.applicantCodeSendFailed.tr,
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerifyCodeView(
          email: email,
          title: TKeys.applicantConfirmEmail.tr,
          subtitle: TKeys.applicantConfirmBody.trParams({'email': email}),
          // Deliberately not runSellerGate — see the class doc.
          onVerified: _openApplication,
        ),
      ),
    );
  }

  /// Verified. Hand over to the application screen, replacing *this* route so
  /// backing out of it returns to the login screen rather than to a stale
  /// "enter your code" step.
  Future<void> _openApplication(BuildContext context) async {
    // Fresh controller state per applicant — a previous applicant's status or
    // cached CV key on this handset must not leak into this one.
    getOrPut(() => SellerApplicationController()).clearSession();
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const BecomeSellerView()),
      // Keep only the login screen underneath.
      (route) => route.isFirst,
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
                TKeys.applicantCheckTitle.tr,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -0.5,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 8),
              CustomText(
                TKeys.applicantCheckBody.tr,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              const _NeedsAccountNote(),
              const SizedBox(height: 24),
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
                hint: TKeys.emailHintExample.tr,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 24),
              Obx(() => PrimaryLoginButton(
                    label: TKeys.applicantSendCode.tr,
                    busy: _authCtrl.isLoading,
                    showArrow: false,
                    onPressed: _authCtrl.isLoading ? null : _sendCode,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Supabase's OTP endpoint answers an unknown address with an error rather
/// than creating an account, so an applicant with no Tommesalg account at all
/// would otherwise hit "No account found" with nowhere to go. Say where to
/// start instead of dead-ending them.
class _NeedsAccountNote extends StatelessWidget {
  const _NeedsAccountNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.brandYellow.withOpacity(0.28),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded,
                size: 16, color: AppColors.brandNavy),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CustomText(
              TKeys.applicantUseAppliedEmail.tr,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: AppColors.brandNavy,
            ),
          ),
        ],
      ),
    );
  }
}
