import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/seller_application_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/branded_loading_view.dart';
import '../../core/widgets/custom_text.dart';
import '../../models/seller_application_model.dart';
import 'post_login_gate.dart';
import 'widgets/auth_phone_field.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/primary_login_button.dart';
import '../../core/localization/translation_keys.dart';

/// The become-a-seller application, and the result state once one exists.
///
/// Opens in one of two modes:
///
///  * [anonymous] — straight off the login screen's "Become a seller" card,
///    with no session at all. Nothing is read from an account, so the form
///    collects name / date of birth / e-mail itself and the submit goes out
///    with no `Authorization` header. There is no status to gate on, so the
///    form shows immediately and a local confirmation replaces it on success.
///  * authenticated — reached through [ApplicantIdentifyView] after an
///    e-mail-code identify. The status gate and the account fields are both
///    bearer-only, so this is the only mode that can read them. The applicant
///    session is signed out on the way out (see [_leave]), so the next launch
///    lands on a clean login screen rather than auto-routing.
///
/// In the authenticated mode which face shows is decided by the server, not by
/// the card the applicant tapped: [SellerApplicationStatus.isApplyAllowed]
/// opens the form, anything else shows the matching result state.
class BecomeSellerView extends StatefulWidget {
  const BecomeSellerView({super.key, this.anonymous = false});

  /// No session, no bearer token, no status gate — see the class doc.
  final bool anonymous;

  @override
  State<BecomeSellerView> createState() => _BecomeSellerViewState();
}

class _BecomeSellerViewState extends State<BecomeSellerView> {
  /// The green on the "retrieved from your account" rows. Local to this
  /// screen — it isn't part of [AppColors].
  static const Color _confirmGreen = Color(0xFF2E9E5B);

  final _ctrl = getOrPut(() => SellerApplicationController());

  /// Anonymous lane only — with a token these come off the account instead.
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  DateTime? _birthDate;

  final _phoneCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _experienceOtherCtrl = TextEditingController();

  LiveComfort? _comfort;
  HoursPerWeek? _hours;
  final Set<SellerExperience> _experience = {};

  String? _cvPath;
  String? _cvName;
  int? _cvBytes;

  bool _confirmed = false;
  bool _loading = true;

  /// Anonymous lane only: the submit landed. There's no status endpoint to
  /// re-read without a token, so the confirmation is held here.
  bool _submitted = false;

  /// Guards the sign-out so the button path and the system-back path can't
  /// both fire it.
  bool _signedOut = false;

  /// Every text input on the form — they all feed the submit gate.
  List<TextEditingController> get _textFields => [
        _nameCtrl,
        _emailCtrl,
        _phoneCtrl,
        _streetCtrl,
        _postalCtrl,
        _cityCtrl,
        _experienceOtherCtrl,
      ];

  @override
  void initState() {
    super.initState();
    // Every text field feeds the submit gate, so the CTA has to re-evaluate as
    // they're typed in.
    for (final c in _textFields) {
      c.addListener(_onFieldChanged);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _textFields) {
      c.dispose();
    }
    // Safety net for the system back button / swipe-back, which don't go
    // through [_leave]. This screen never pushes anything on top of itself, so
    // being disposed always means the applicant left the flow.
    unawaited(_signOut());
    super.dispose();
  }

  /// Reads the gate and the account in parallel — neither depends on the other
  /// and both have to land before the screen can decide what to show.
  Future<void> _load() async {
    // Both reads are bearer-only, and the anonymous lane has no gate to
    // consult anyway — the form is the landing state.
    if (widget.anonymous) {
      setState(() => _loading = false);
      return;
    }
    if (!_loading) setState(() => _loading = true);
    await Future.wait([_ctrl.fetchStatus(), _ctrl.fetchAccount()]);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _onFieldChanged() {
    // A stale server message shouldn't sit under a form that's been corrected.
    if (_ctrl.errorMessage != null) _ctrl.clearError();
    setState(() {});
  }

  Future<void> _signOut() async {
    if (_signedOut) return;
    _signedOut = true;
    _ctrl.clearSession();
    // The anonymous lane never created a session — signing out here would
    // clobber whoever happened to be signed in on this handset.
    if (widget.anonymous) return;
    await getOrPut(() => AuthController()).logout();
  }

  /// Ends the applicant session and returns to a clean login screen.
  Future<void> _leave() async {
    await _signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ── CV ─────────────────────────────────────────────────────────────────

  Future<void> _pickCv() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: SellerApplicationController.cvAllowedExtensions,
      );
    } catch (_) {
      // A denied permission or a handset with no document provider throws
      // rather than returning null.
      if (!mounted) return;
      showAuthError(context, TKeys.bsFileOpenFailed.tr);
      return;
    }

    final path = picked?.path;
    if (path == null || !mounted) return;

    final extension = path.split('.').last.toLowerCase();
    if (!SellerApplicationController.cvAllowedExtensions.contains(extension)) {
      showAuthError(context, TKeys.bsPickDocType.tr);
      return;
    }

    int size;
    try {
      size = await File(path).length();
    } catch (_) {
      if (!mounted) return;
      showAuthError(context, TKeys.bsFileReadFailed.tr);
      return;
    }
    if (size > SellerApplicationController.cvMaxBytes) {
      if (!mounted) return;
      showAuthError(
          context, TKeys.bsFileTooLarge.tr);
      return;
    }

    if (!mounted) return;
    setState(() {
      _cvPath = path;
      _cvName = picked?.name ?? path.split(Platform.pathSeparator).last;
      _cvBytes = size;
    });
    // A different file invalidates any key from an earlier attempt.
    _ctrl.resetDraft();
  }

  void _removeCv() {
    setState(() {
      _cvPath = null;
      _cvName = null;
      _cvBytes = null;
    });
    _ctrl.resetDraft();
  }

  // ── Derived state ──────────────────────────────────────────────────────

  /// Only meaningful with a token — the anonymous lane types the same values
  /// into the form, so there's no account to be incomplete.
  bool get _profileIncomplete =>
      !widget.anonymous && !(_ctrl.account?.isComplete ?? false);

  /// The identity fields the server can't look up without a bearer token.
  bool get _identityFilled =>
      !widget.anonymous ||
      (_nameCtrl.text.trim().isNotEmpty &&
          SellerApplicationController.isValidEmail(_emailCtrl.text) &&
          _birthDate != null);

  bool get _needsExperienceOther =>
      _experience.contains(SellerExperience.other);

  /// Everything the submit endpoint requires, so the CTA is only tappable when
  /// the request would actually be well-formed. `experience` itself is
  /// optional — but picking "Other" makes its free-text twin mandatory.
  bool get _canSubmit =>
      !_profileIncomplete &&
      _identityFilled &&
      _phoneCtrl.text.trim().isNotEmpty &&
      _streetCtrl.text.trim().isNotEmpty &&
      SellerApplicationController.isValidPostalCode(_postalCtrl.text) &&
      _cityCtrl.text.trim().isNotEmpty &&
      _comfort != null &&
      _hours != null &&
      (!_needsExperienceOther || _experienceOtherCtrl.text.trim().isNotEmpty) &&
      _cvPath != null &&
      _confirmed;

  Future<void> _submit() async {
    final path = _cvPath;
    if (!_canSubmit || path == null) return;

    final ok = await _ctrl.submit(
      cvFilePath: path,
      phoneNumber: SellerApplicationController.normaliseNorwegianPhone(
          _phoneCtrl.text),
      line1: _streetCtrl.text.trim(),
      postalCode: _postalCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
      country: 'NO',
      liveComfort: _comfort!,
      hoursPerWeek: _hours!,
      experience: _experience,
      experienceOther:
          _needsExperienceOther ? _experienceOtherCtrl.text.trim() : null,
      authenticated: !widget.anonymous,
      fullName: widget.anonymous ? _nameCtrl.text.trim() : null,
      email: widget.anonymous ? _emailCtrl.text.trim() : null,
      dateOfBirth: widget.anonymous ? _isoBirthDate : null,
    );

    if (!mounted) return;
    // With a token the controller has re-read the gate, so the screen swaps
    // itself: to "pending" on success, to whichever state a 409 revealed.
    // Without one there's nothing to re-read, so the confirmation is local.
    setState(() => _submitted = _submitted || (ok && widget.anonymous));
    if (ok) showAuthInfo(context, TKeys.bsApplicationSubmitted.tr);
  }

  /// `yyyy-MM-dd` — what the submit body carries on the anonymous lane.
  String? get _isoBirthDate {
    final d = _birthDate;
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// `23.04.1990`, matching how the authenticated lane renders the account's
  /// date of birth.
  String get _birthDateLabel {
    final d = _birthDate;
    if (d == null) return TKeys.bsSelectDob.tr;
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      // The submit endpoint rejects anyone under
      // [SellerApplicationController.minimumAgeYears], so there's no point
      // offering a date that can only come back a 400.
      lastDate: DateTime(
        now.year - SellerApplicationController.minimumAgeYears,
        now.month,
        now.day,
      ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.brandNavy,
            onPrimary: AppColors.white,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _birthDate = picked);
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.brandNavy),
          onPressed: _leave,
        ),
        title: CustomText(
          TKeys.bsSellerApplication.tr,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        actions: [
          Obx(() {
            // Read the observable first, unconditionally: an Obx that returns
            // without touching one throws, and the error box GetX leaves in
            // its place is unbounded, which is what overflowed the toolbar.
            final status = _ctrl.status;
            final state = widget.anonymous ? null : status?.state;
            if (state == null || state == SellerApplicationState.none) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Align(
                alignment: Alignment.center,
                widthFactor: 1,
                child: _StatusPill(state: state),
              ),
            );
          }),
        ],
      ),
      body: Obx(() {
        // Same rule as the toolbar action: bind to the observable before any
        // early return, or the anonymous lane leaves the Obx with nothing to
        // watch and it throws instead of building.
        final status = _ctrl.status;

        // Anonymous: no gate to consult, so the form is the landing state and
        // the confirmation is held locally.
        if (widget.anonymous) {
          return _submitted ? _buildSubmitted() : _buildForm(null);
        }

        // Never a raw empty state while the first read is in flight.
        if (_loading && status == null) return const BrandedLoadingView();

        // A failed first read leaves nothing to decide on — offer a retry
        // rather than an empty form we can't validate against.
        if (status == null) {
          return _LoadFailed(
            message: _ctrl.errorMessage ?? TKeys.bsCouldNotLoad.tr,
            onRetry: _load,
          );
        }
        // Trust `canApply` — it already folds in the pending check and the
        // re-apply cooldown.
        return status.isApplyAllowed ? _buildForm(status) : _buildResult(status);
      }),
    );
  }

  // ── Result states ──────────────────────────────────────────────────────

  Widget _buildResult(SellerApplicationStatus status) {
    final (IconData icon, String title, String body) = switch (status.state) {
      SellerApplicationState.pending => (
          Icons.hourglass_top_rounded,
          TKeys.bsUnderReview.tr,
          TKeys.bsUnderReviewBody.tr,
        ),
      SellerApplicationState.approved => (
          Icons.verified_rounded,
          TKeys.bsApproved.tr,
          TKeys.bsApprovedBody.tr,
        ),
      SellerApplicationState.rejected => (
          Icons.info_outline_rounded,
          TKeys.bsNotApproved.tr,
          TKeys.bsNotApprovedBody.tr,
        ),
      // `none` never reaches here — isApplyAllowed would have opened the form.
      SellerApplicationState.none => (
          Icons.info_outline_rounded,
          TKeys.bsNoApplication.tr,
          TKeys.bsNoApplicationBody.tr,
        ),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.brandYellow,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(icon, size: 36, color: AppColors.brandNavy),
          ),
          const SizedBox(height: 22),
          CustomText(
            title,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            height: 1.2,
            textAlign: TextAlign.center,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 10),
          CustomText(
            body,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.5,
            textAlign: TextAlign.center,
            color: AppColors.textSecondary,
          ),
          if (status.state == SellerApplicationState.rejected) ...[
            const SizedBox(height: 22),
            _RejectionCard(status: status, showCooldown: true),
          ],
          const SizedBox(height: 28),
          PrimaryLoginButton(
            label: status.state == SellerApplicationState.approved
                ? TKeys.bsGoToLogin.tr
                : TKeys.doneAction.tr,
            showArrow: false,
            onPressed: _leave,
          ),
        ],
      ),
    );
  }

  /// Anonymous lane's end state. The authenticated lane gets this from the
  /// server as `pending`; without a token there's nothing to re-read, so it's
  /// rendered from the fact that the submit returned 2xx.
  Widget _buildSubmitted() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.brandYellow,
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Icon(Icons.hourglass_top_rounded,
                size: 36, color: AppColors.brandNavy),
          ),
          const SizedBox(height: 22),
          CustomText(
            TKeys.bsApplicationReceived.tr,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            height: 1.2,
            textAlign: TextAlign.center,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 10),
          CustomText(
            TKeys.bsUnderReviewBody.tr,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.5,
            textAlign: TextAlign.center,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 28),
          PrimaryLoginButton(
            label: TKeys.doneAction.tr,
            showArrow: false,
            onPressed: _leave,
          ),
        ],
      ),
    );
  }

  // ── The form ───────────────────────────────────────────────────────────

  Widget _buildForm(SellerApplicationStatus? status) {
    final account = _ctrl.account;
    final busy = _ctrl.isSubmitting;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A rejection whose cooldown has expired: the form is open again, so
          // the reason is pinned above it rather than replacing it.
          if (status != null &&
              status.state == SellerApplicationState.rejected) ...[
            _RejectionCard(status: status, showCooldown: false),
            const SizedBox(height: 18),
          ],
          if (_profileIncomplete) ...[
            const _ProfileGateCard(),
            const SizedBox(height: 18),
          ],

          // ── 01 · Personal information ──────────────────────────────────
          _SectionHeader(number: '01', title: TKeys.bsPersonalInfo.tr),
          const SizedBox(height: 16),
          if (widget.anonymous) ...[
            // No account to read from, so these are typed in and travel in the
            // submit body.
            _FieldLabel(TKeys.bsFullNameCaps.tr, required: true),
            const SizedBox(height: 8),
            AuthTextField(
              controller: _nameCtrl,
              icon: Icons.person_outline_rounded,
              hint: TKeys.bsFirstLastName.tr,
            ),
            const SizedBox(height: 14),
            _FieldLabel(TKeys.bsDobCaps.tr, required: true),
            const SizedBox(height: 8),
            _DatePlate(
              label: _birthDateLabel,
              chosen: _birthDate != null,
              onTap: _pickBirthDate,
            ),
            const SizedBox(height: 14),
            _FieldLabel(TKeys.emailCaps.tr, required: true),
            const SizedBox(height: 8),
            AuthTextField(
              controller: _emailCtrl,
              icon: Icons.mail_outline_rounded,
              hint: TKeys.emailHintExample.tr,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
          ] else ...[
            _ReadOnlyPlate(
              label: TKeys.bsFullNameCaps.tr,
              value: account?.displayName ?? '—',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 14),
            _ReadOnlyPlate(
              label: TKeys.bsDobCaps.tr,
              value: account?.formattedBirthDate ?? '—',
              icon: Icons.cake_outlined,
            ),
            const SizedBox(height: 14),
            _ReadOnlyPlate(
              label: TKeys.emailCaps.tr,
              value: account?.email ?? '—',
              icon: Icons.mail_outline_rounded,
            ),
          ],
          const SizedBox(height: 18),
          _FieldLabel(TKeys.bsPhoneCaps.tr, required: true),
          const SizedBox(height: 8),
          AuthPhoneField(
            controller: _phoneCtrl,
            dialCode: '+47',
            hint: '400 00 000',
            // Norway-only product — the chip is decoration, not a picker.
            onCountryTap: () {},
          ),

          const SizedBox(height: 26),
          CustomText(
            TKeys.bsSellerAddress.tr,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 6),
          CustomText(
            TKeys.bsSellerAddressBody.tr,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          _FieldLabel(TKeys.bsStreetCaps.tr, required: true),
          const SizedBox(height: 8),
          AuthTextField(
            controller: _streetCtrl,
            icon: Icons.home_outlined,
            hint: TKeys.bsStreetHint.tr,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(TKeys.bsPostalCaps.tr, required: true),
                    const SizedBox(height: 8),
                    AuthTextField(
                      controller: _postalCtrl,
                      icon: Icons.markunread_mailbox_outlined,
                      hint: '0123',
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 6),
                    CustomText(
                      TKeys.bsPostalHint.tr,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(TKeys.bsCityCaps.tr, required: true),
                    const SizedBox(height: 8),
                    AuthTextField(
                      controller: _cityCtrl,
                      icon: Icons.location_city_rounded,
                      hint: 'Oslo',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _FieldLabel(TKeys.bsCountryCaps.tr),
          const SizedBox(height: 8),
          _LockedPlate(value: TKeys.countryNorway.tr, icon: Icons.public_rounded),

          // ── 02 · Experience ────────────────────────────────────────────
          const SizedBox(height: 30),
          _SectionHeader(number: '02', title: TKeys.bsExperience.tr),
          const SizedBox(height: 16),
          _QuestionLabel(
            TKeys.bsComfortQuestion.tr,
            required: true,
          ),
          const SizedBox(height: 12),
          for (final option in LiveComfort.values) ...[
            _ChoiceCard(
              label: option.label,
              selected: _comfort == option,
              onTap: () => setState(() => _comfort = option),
            ),
            const SizedBox(height: 10),
          ],

          const SizedBox(height: 12),
          _QuestionLabel(
            TKeys.bsHoursQuestion.tr,
            required: true,
            help: TKeys.bsHoursNote.tr,
          ),
          const SizedBox(height: 12),
          for (final option in HoursPerWeek.values) ...[
            _ChoiceCard(
              label: option.label,
              selected: _hours == option,
              onTap: () => setState(() => _hours = option),
            ),
            const SizedBox(height: 10),
          ],

          const SizedBox(height: 12),
          _QuestionLabel(
            TKeys.bsTypesOfExperience.tr,
            help: TKeys.bsSelectAllApply.tr,
          ),
          const SizedBox(height: 12),
          _experienceGrid(),
          if (_needsExperienceOther) ...[
            const SizedBox(height: 14),
            _FieldLabel(TKeys.bsTellUsMoreCaps.tr, required: true),
            const SizedBox(height: 8),
            AuthTextField(
              controller: _experienceOtherCtrl,
              icon: Icons.edit_outlined,
              hint: TKeys.bsDescribeExperience.tr,
              maxLength:
                  SellerApplicationController.experienceOtherMaxLength,
            ),
          ],

          // ── 03 · Documentation ─────────────────────────────────────────
          const SizedBox(height: 30),
          _SectionHeader(number: '03', title: TKeys.bsDocumentation.tr),
          const SizedBox(height: 16),
          Obx(() => _CvTile(
                fileName: _cvName,
                bytes: _cvBytes,
                uploading: _ctrl.isUploadingCv,
                onPick: _pickCv,
                onRemove: _removeCv,
              )),

          // ── Footer ─────────────────────────────────────────────────────
          const SizedBox(height: 26),
          _ConfirmCheckbox(
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v),
          ),
          const SizedBox(height: 20),
          PrimaryLoginButton(
            label: TKeys.bsSubmitApplication.tr,
            busy: busy,
            showArrow: false,
            onPressed: busy || !_canSubmit ? null : _submit,
          ),
          if (_ctrl.errorMessage != null) ...[
            const SizedBox(height: 12),
            CustomText(
              _ctrl.errorMessage!,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: AppColors.vipps,
            ),
          ],
        ],
      ),
    );
  }

  /// Two-up when there's room for it, one column on a narrow handset.
  Widget _experienceGrid() {
    return LayoutBuilder(builder: (context, constraints) {
      final twoUp = constraints.maxWidth >= 320;
      final width =
          twoUp ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final option in SellerExperience.values)
            SizedBox(
              width: width,
              child: _ChoiceCard(
                label: option.label,
                selected: _experience.contains(option),
                multi: true,
                onTap: () => setState(() {
                  if (!_experience.remove(option)) _experience.add(option);
                }),
              ),
            ),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

/// Numbered badge + title + hairline, opening each of the three sections.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.number, required this.title});
  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brandYellow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: CustomText(
                number,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomText(
                title,
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppColors.brandNavy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(height: 1, color: AppColors.brandNavy.withOpacity(0.10)),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.required = false});
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CustomText(
          label,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: AppColors.textSecondary,
        ),
        if (required) ...[
          const SizedBox(width: 3),
          const CustomText('*',
              fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.vipps),
        ],
      ],
    );
  }
}

/// A full-sentence question above a group of choice cards.
class _QuestionLabel extends StatelessWidget {
  const _QuestionLabel(this.text, {this.required = false, this.help});
  final String text;
  final bool required;
  final String? help;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: CustomText(
                text,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                height: 1.35,
                color: AppColors.textPrimary,
              ),
            ),
            if (required) ...[
              const SizedBox(width: 3),
              const CustomText('*',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.vipps),
            ],
          ],
        ),
        if (help != null) ...[
          const SizedBox(height: 4),
          CustomText(
            help!,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ],
      ],
    );
  }
}

/// A value the submit endpoint reads off the account — shown so the applicant
/// can see what will be sent on their behalf, with a green confirmation row.
class _ReadOnlyPlate extends StatelessWidget {
  const _ReadOnlyPlate({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  static const Color _green = _BecomeSellerViewState._confirmGreen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        _LockedPlate(value: value, icon: icon),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.check_rounded, size: 14, color: _green),
            const SizedBox(width: 5),
            CustomText(
              TKeys.bsRetrievedFromAccount.tr,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: _green,
            ),
          ],
        ),
      ],
    );
  }
}

/// Grey, non-editable field plate with a trailing lock.
class _LockedPlate extends StatelessWidget {
  const _LockedPlate({required this.value, required this.icon});
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGrey, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: CustomText(
              value,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.lock_outline_rounded,
              size: 15, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

/// Tappable date field, shaped like [_LockedPlate] but with a calendar
/// affordance instead of a lock.
class _DatePlate extends StatelessWidget {
  const _DatePlate({
    required this.label,
    required this.chosen,
    required this.onTap,
  });
  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.inputBorder, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.cake_outlined,
                size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: CustomText(
                label,
                fontSize: 14.5,
                fontWeight: chosen ? FontWeight.w600 : FontWeight.w500,
                color: chosen ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
            const Icon(Icons.calendar_today_rounded,
                size: 15, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// One answer. [multi] swaps the radio for a checkbox stamp.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.label,
    required this.selected,
    required this.onTap,
    this.multi = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandNavy : AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.brandNavy
                : AppColors.brandNavy.withOpacity(0.12),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            if (multi)
              _CheckStamp(selected: selected)
            else
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? AppColors.brandYellow : AppColors.textMuted,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: CustomText(
                label,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
                color: selected ? AppColors.brandYellow : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckStamp extends StatelessWidget {
  const _CheckStamp({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: selected ? AppColors.brandYellow : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: selected
              ? AppColors.brandYellow
              : AppColors.brandNavy.withOpacity(0.25),
          width: 1.4,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 13, color: AppColors.brandNavy)
          : null,
    );
  }
}

/// CV upload — dashed drop zone when empty, a file card once picked.
class _CvTile extends StatelessWidget {
  const _CvTile({
    required this.fileName,
    required this.bytes,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
  });

  final String? fileName;
  final int? bytes;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  static String _formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    if (fileName == null) return _empty();
    return _picked();
  }

  Widget _empty() {
    return GestureDetector(
      onTap: onPick,
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: _DashedBorderPainter(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: AppColors.brandYellow.withOpacity(0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.description_outlined,
                    size: 28, color: AppColors.brandNavy),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CustomText(TKeys.bsUploadCv.tr,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                  const SizedBox(width: 3),
                  const CustomText('*',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.vipps),
                ],
              ),
              const SizedBox(height: 6),
              CustomText(
                TKeys.bsCvFormats.tr,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _picked() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderGrey, width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandYellow.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: uploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.brandNavy),
                        ),
                      )
                    : const Icon(Icons.description_rounded,
                        size: 22, color: AppColors.brandNavy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      fileName!,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    CustomText(
                      _formatSize(bytes),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.borderGrey),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: uploading ? null : onPick,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: CustomText(TKeys.bsReplace.tr,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandNavy),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: uploading ? null : onRemove,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: CustomText(TKeys.removeAction.tr,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.vipps),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Flutter has no dashed [Border], so the rounded rect is walked with
/// `computeMetrics()` and stroked in 7px-on / 5px-off segments.
class _DashedBorderPainter extends CustomPainter {
  static const double _dash = 7;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x330A1420)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(20),
      ));

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ConfirmCheckbox extends StatelessWidget {
  const _ConfirmCheckbox({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: value ? AppColors.brandNavy : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: value
                    ? AppColors.brandNavy
                    : AppColors.brandNavy.withOpacity(0.25),
                width: 1.4,
              ),
            ),
            child: value
                ? const Icon(Icons.check_rounded,
                    size: 16, color: AppColors.brandYellow)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: CustomText(
                    TKeys.bsConfirmInfo.tr,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 3),
                const CustomText('*',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.vipps),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Why the application was turned down. [showCooldown] adds the "you can apply
/// again in N days" line — dropped once the cooldown has expired and the form
/// is open again, where it would contradict the form sitting right below it.
class _RejectionCard extends StatelessWidget {
  const _RejectionCard({required this.status, required this.showCooldown});
  final SellerApplicationStatus status;
  final bool showCooldown;

  @override
  Widget build(BuildContext context) {
    final days = status.daysLeftToReapply;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.vipps.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.vipps.withOpacity(0.30), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            TKeys.bsReasonCaps.tr,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
            color: AppColors.vipps,
          ),
          const SizedBox(height: 8),
          CustomText(
            status.rejectionReason?.trim().isNotEmpty == true
                ? status.rejectionReason!
                : TKeys.bsNoReasonGiven.tr,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.45,
            color: AppColors.textPrimary,
          ),
          if (showCooldown) ...[
            const SizedBox(height: 12),
            CustomText(
              days != null
                  ? TKeys.bsApplyAgainInDays.trParams({'days': '$days'})
                  : TKeys.bsCannotApplyYet.tr,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// Blocks submission while the account is missing the name / date of birth the
/// endpoint reads server-side. The applicant can't edit a buyer profile from
/// the seller app, so this points at where they can.
class _ProfileGateCard extends StatelessWidget {
  const _ProfileGateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandYellow.withOpacity(0.28),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, size: 18, color: AppColors.brandNavy),
              const SizedBox(width: 8),
              Expanded(
                child: CustomText(
                  TKeys.bsCompleteProfileFirst.tr,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CustomText(
            TKeys.bsCompleteProfileBody.tr,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 1.45,
            color: AppColors.brandNavy,
          ),
        ],
      ),
    );
  }
}

/// PENDING / APPROVED / REJECTED, mirrored in the app-bar.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});
  final SellerApplicationState state;

  @override
  Widget build(BuildContext context) {
    final rejected = state == SellerApplicationState.rejected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: rejected ? AppColors.vipps : AppColors.brandNavy,
        borderRadius: BorderRadius.circular(999),
      ),
      child: CustomText(
        state.name.toUpperCase(),
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        color: rejected ? AppColors.white : AppColors.brandYellow,
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 34, color: AppColors.vipps),
            const SizedBox(height: 14),
            CustomText(
              message,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
              textAlign: TextAlign.center,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 20),
            PrimaryLoginButton(
              label: TKeys.tryAgain.tr,
              showArrow: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
