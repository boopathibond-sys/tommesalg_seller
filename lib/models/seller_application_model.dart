/// Types behind the become-a-seller flow.
///
/// The endpoints live on the **buyer** backend (`EnvConfig.buyerBaseUrl`,
/// `/api/v1/buyer/seller-application`) and are bearer-authenticated, so this
/// flow always runs against an *applicant* session — never a seller one.
///
/// The guest lane goes to the mirror routes under `/api/v1/public/…`, which
/// take no bearer token and carry the identity fields in the body instead.
/// See `SellerApplicationController` for the calls and
/// `lib/views/auth/become_seller_view.dart` for the screen.
library;

import 'package:get/get.dart';

import '../core/localization/translation_keys.dart';

/// Typed representation of `GET /api/v1/buyer/seller-application`.
///
/// The endpoint wraps the payload in `{ success, data, meta }`; the controller
/// unwraps `data` before constructing this, so callers only deal with the
/// user-facing fields.
///
/// This is the gate the whole flow hangs off: [isApplyAllowed] decides whether
/// the form opens at all, and [state] picks which result screen shows instead.
class SellerApplicationStatus {
  const SellerApplicationStatus({
    this.status,
    this.applicationId,
    this.applicationType,
    this.canApply,
    this.rejectionReason,
    this.rejectedAt,
    this.reapplyAllowedAt,
    this.daysLeftToReapply,
  });

  /// `none` | `pending` | `approved` | `rejected`, kept as the raw string so an
  /// unrecognised value the backend grows later can still be logged. Read it
  /// through [state] for the parsed form.
  final String? status;
  final String? applicationId;

  /// Always `managed` today — the self-serve track isn't exposed to the app.
  final String? applicationType;

  /// Whether `POST` is currently allowed. Authoritative: it already folds in
  /// the pending check *and* the 30-day re-apply cooldown, so the UI never
  /// date-compares [reapplyAllowedAt] itself.
  final bool? canApply;

  final String? rejectionReason;
  final String? rejectedAt;
  final String? reapplyAllowedAt;
  final int? daysLeftToReapply;

  factory SellerApplicationStatus.fromJson(Map<String, dynamic> json) {
    return SellerApplicationStatus(
      status: json['status'] as String?,
      applicationId: json['applicationId'] as String?,
      applicationType: json['applicationType'] as String?,
      canApply: json['canApply'] as bool?,
      rejectionReason: json['rejectionReason'] as String?,
      rejectedAt: json['rejectedAt'] as String?,
      reapplyAllowedAt: json['reapplyAllowedAt'] as String?,
      daysLeftToReapply: (json['daysLeftToReapply'] as num?)?.toInt(),
    );
  }

  /// [status] parsed into the enum the screen switches on. Anything we don't
  /// recognise falls back to [SellerApplicationState.none], so a backend
  /// addition shows the apply path rather than dead-ending the applicant.
  SellerApplicationState get state {
    switch (status) {
      case 'pending':
        return SellerApplicationState.pending;
      case 'approved':
        return SellerApplicationState.approved;
      case 'rejected':
        return SellerApplicationState.rejected;
      default:
        return SellerApplicationState.none;
    }
  }

  /// True when the form should open. Trusts the server's [canApply] when it
  /// sent one; otherwise infers from [state] so a partial payload still
  /// behaves (only `none` / `rejected` can apply).
  bool get isApplyAllowed =>
      canApply ??
      (state == SellerApplicationState.none ||
          state == SellerApplicationState.rejected);
}

enum SellerApplicationState { none, pending, approved, rejected }

/// The account fields the submit endpoint reads server-side — shown read-only
/// on the form so the applicant can see what will be sent on their behalf.
/// From `GET /api/v1/buyer/profile`.
class ApplicantAccount {
  const ApplicantAccount({this.displayName, this.email, this.birthDate});

  final String? displayName;
  final String? email;

  /// ISO date as the profile stores it; the form renders it `dd.MM.yyyy`.
  final String? birthDate;

  factory ApplicantAccount.fromJson(Map<String, dynamic> json) =>
      ApplicantAccount(
        displayName: json['displayName'] as String?,
        email: json['email'] as String?,
        birthDate: json['birthDate'] as String?,
      );

  /// The submit endpoint 400s without a name, an e-mail and a date of birth on
  /// the account, so the form blocks up front rather than after the applicant
  /// has filled everything in.
  bool get isComplete =>
      (displayName ?? '').trim().isNotEmpty &&
      (email ?? '').trim().isNotEmpty &&
      (birthDate ?? '').trim().isNotEmpty;

  /// `1990-04-23T00:00:00Z` → `23.04.1990`. Falls back to the raw string when
  /// it isn't parseable, so a surprising format still shows *something*.
  String get formattedBirthDate {
    final raw = (birthDate ?? '').trim();
    if (raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final d = parsed.day.toString().padLeft(2, '0');
    final m = parsed.month.toString().padLeft(2, '0');
    return '$d.$m.${parsed.year}';
  }
}

/// The four "how comfortable are you on camera" answers, in the order the form
/// lists them. [api] is the exact enum string the submit endpoint accepts —
/// never send the label.
enum LiveComfort {
  veryComfortable('very-comfortable', TKeys.bsComfortVery),
  comfortable('comfortable', TKeys.bsComfortComfortable),
  somewhatComfortable('somewhat-comfortable', TKeys.bsComfortSomewhat),
  willingToLearn('willing-to-learn', TKeys.bsComfortWilling);

  const LiveComfort(this.api, this.labelKey);
  final String api;
  final String labelKey;

  /// Resolved at read time, not construction: enum values are `const`, and the
  /// catalogue isn't loaded yet when they're created.
  String get label => labelKey.tr;
}

/// Weekly time commitment — preparation plus the broadcast itself.
enum HoursPerWeek {
  oneToThree('1-3', TKeys.bsHours1To3),
  threeToSix('3-6', TKeys.bsHours3To6),
  sixToTen('6-10', TKeys.bsHours6To10),
  tenPlus('10-plus', TKeys.bsHours10Plus);

  const HoursPerWeek(this.api, this.labelKey);
  final String api;
  final String labelKey;

  String get label => labelKey.tr;
}

/// Multi-select background. [SellerExperience.other] unlocks the free-text
/// field the submit endpoint requires alongside it (`experienceOther`).
enum SellerExperience {
  liveSales('live-sales', TKeys.bsExpLiveSales),
  onlineRetail('online-retail', TKeys.bsExpOnlineRetail),
  salesCertificate('sales-certificate', TKeys.bsExpSalesCertificate),
  saleInStore('sale-in-store', TKeys.bsExpSaleInStore),
  other('other', TKeys.bsExpOther);

  const SellerExperience(this.api, this.labelKey);
  final String api;
  final String labelKey;

  String get label => labelKey.tr;
}
