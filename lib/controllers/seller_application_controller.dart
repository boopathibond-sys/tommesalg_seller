import 'dart:developer';
import 'dart:io';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/localization/translation_keys.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../models/seller_application_model.dart';

/// Drives the become-a-seller flow end to end:
///
///   1. [fetchAccount] — `GET /buyer/profile`, the name / e-mail / date of
///      birth the submit endpoint reads off the account.
///   2. [fetchStatus]  — `GET /buyer/seller-application`, the gate that decides
///      whether the form opens or a result state shows instead.
///   3. [uploadCv]     — `POST …/cv`, multipart, answers an S3 key.
///   4. [submitApplication] — `POST /buyer/seller-application` with that key
///      plus the form body.
///
/// [submit] chains 3 → 4 and is what the screen actually calls. The S3 key is
/// cached in [cvS3Key] between them, so a submit that fails validation retries
/// with the already-uploaded file instead of pushing the same 2 MB up again.
///
/// **Everything here talks to the buyer host** ([EnvConfig.buyerBaseUrl]), not
/// the seller API, and every call passes `suppressAuthHandlers: true`: these
/// paths are gated to the `buyer` role, and letting an `AUTH_ROLE_REQUIRED`
/// answer reach [ApiClient.onRoleRequired] would sign out a real seller who
/// happened to open the status screen.
///
/// Two lanes, on two different sets of routes:
///
///  * **Guest apply** (`authenticated: false`) — the form opens straight from
///    the login screen with no session at all, so the calls go to the public
///    mirror routes (`/api/v1/public/seller-application[/cv]`), carry no
///    `Authorization` header, and put the identity fields the server would
///    otherwise read off the account ([fullName] / [email] / [dateOfBirth]) in
///    the body instead. There is no status endpoint on this lane — the submit
///    returning 201 *is* the confirmation.
///  * **Authenticated** (`authenticated: true`, the default) — the buyer
///    routes (`/api/v1/buyer/…`), reached after an e-mail-code identify, and
///    the only lane that can read [fetchStatus] / [fetchAccount], both of
///    which are bearer-only.
///
/// The two are never mixed: a signed-in buyer sent down the public route would
/// have their application stored with `user_id = null`, detached from the
/// account that made it.
///
/// Follows the app's controller convention: every intent returns a `bool` (or a
/// nullable value) and writes a readable sentence to [errorMessage] rather than
/// throwing, so views bind one observable to an inline banner.
class SellerApplicationController extends GetxController {
  // ---------- Reactive state ----------

  final Rx<SellerApplicationStatus?> _status =
      Rx<SellerApplicationStatus?>(null);
  SellerApplicationStatus? get status => _status.value;

  final Rx<ApplicantAccount?> _account = Rx<ApplicantAccount?>(null);
  ApplicantAccount? get account => _account.value;

  /// First status read, or a refresh of it.
  final RxBool _isLoadingStatus = false.obs;
  bool get isLoadingStatus => _isLoadingStatus.value;

  /// True from the moment [submit] starts until it resolves — covers both the
  /// upload and the submit leg, so the CTA stays busy across the pair rather
  /// than flickering between them.
  final RxBool _isSubmitting = false.obs;
  bool get isSubmitting => _isSubmitting.value;

  /// Narrower than [isSubmitting] — lets the CV tile show its own progress
  /// while the button reads "busy".
  final RxBool _isUploadingCv = false.obs;
  bool get isUploadingCv => _isUploadingCv.value;

  final RxnString _errorMessage = RxnString();
  String? get errorMessage => _errorMessage.value;

  /// S3 key of the uploaded CV. Survives a failed submit so the retry can skip
  /// the upload; cleared by [resetDraft] and whenever a different file is
  /// picked.
  final RxnString _cvS3Key = RxnString();
  String? get cvS3Key => _cvS3Key.value;

  final RxnString _applicationId = RxnString();
  String? get applicationId => _applicationId.value;

  /// Clears the banner without touching anything else — called when a field is
  /// edited after a failed submit, so a stale server message doesn't sit under
  /// a form that's already been corrected.
  void clearError() => _errorMessage.value = null;

  // ---------- CV constraints ----------

  /// Extensions handed to the platform file picker.
  static const List<String> cvAllowedExtensions = ['pdf', 'doc', 'docx'];

  /// Server-side ceiling — 2 MB. Checked locally so an oversized CV fails with
  /// a sentence the applicant can act on instead of a 413.
  static const int cvMaxBytes = 2 * 1024 * 1024;

  // ---------- Endpoints ----------

  /// `BUYER_BASE_URL` is blank in some `.env` checkouts, and a relative URL
  /// fails at the transport rather than with a readable message. Falls back to
  /// `BASE_URL` exactly as `AuthService.sendPasswordResetEmail` does — the two
  /// hosts are the same deployment in every environment where the buyer host
  /// isn't split out.
  String get _host => EnvConfig.buyerBaseUrl.isNotEmpty
      ? EnvConfig.buyerBaseUrl
      : EnvConfig.baseUrl;

  String get _profileUrl => '$_host/api/v1/buyer/profile';

  /// Bearer lane — the row is attached to the signed-in account.
  String get _buyerApplicationUrl => '$_host/api/v1/buyer/seller-application';

  /// Guest lane — no session at all, so a separate route: this one stores
  /// `user_id = null` and matches a returning applicant by e-mail instead.
  String get _publicApplicationUrl => '$_host/api/v1/public/seller-application';

  String _applicationUrl({required bool authenticated}) =>
      authenticated ? _buyerApplicationUrl : _publicApplicationUrl;

  String _cvUrl({required bool authenticated}) =>
      '${_applicationUrl(authenticated: authenticated)}/cv';

  /// Bearer headers for the authenticated lane, none for the anonymous one.
  /// Returns null when a token was required but couldn't be produced, so
  /// callers can fail with a readable message instead of a bare 401.
  Future<Map<String, String>?> _headers({required bool authenticated}) async {
    // The public routes take no token — but they still need the JSON headers
    // spelled out, because those normally ride along with the bearer ones from
    // [AuthService.authHeaders]. Without a `Content-Type` the transport sends
    // the encoded body as `text/plain` and the server rejects it. The
    // multipart upload drops `Content-Type` again so it can set its own
    // boundary; `Accept` survives, which is what the CV route wants.
    if (!authenticated) {
      return const <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
    }
    final headers = await AuthService.instance.ensuredAuthHeaders();
    return headers.containsKey('Authorization') ? headers : null;
  }

  // ---------- Intents ----------

  /// Reads the account fields the submit endpoint will use. Failure leaves
  /// [account] as it was and is reported through [errorMessage]; the form
  /// treats a null account as an incomplete profile and blocks submit.
  Future<bool> fetchAccount() async {
    final headers = await AuthService.instance.ensuredAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      _errorMessage.value = TKeys.bsSessionExpired.tr;
      return false;
    }

    log('[seller-application] ➡️  GET $_profileUrl');
    try {
      final response = await ApiClient.instance.get(
        _profileUrl,
        headers: headers,
        suppressAuthHandlers: true,
      );
      if (response.isSuccess) {
        final body = response.json;
        if (body['data'] is Map) {
          _account.value = ApplicantAccount.fromJson(
            Map<String, dynamic>.from(body['data'] as Map),
          );
          return true;
        }
      }
      _errorMessage.value = _failureMessage(
        response.statusCode,
        _safeJson(response),
        TKeys.bsAccountReadFailed.tr,
      );
      return false;
    } catch (e) {
      log('[seller-application] 🔥 profile error: $e');
      _errorMessage.value = TKeys.bsNetworkError.tr;
      return false;
    }
  }

  /// Reads the current application status.
  ///
  /// On failure the previous [status] is left in place — a transient blip must
  /// not drop a `pending` applicant back onto an empty form.
  Future<bool> fetchStatus() async {
    final headers = await AuthService.instance.ensuredAuthHeaders();
    if (!headers.containsKey('Authorization')) {
      _errorMessage.value = TKeys.bsSessionExpired.tr;
      return false;
    }

    _isLoadingStatus.value = true;
    _errorMessage.value = null;

    log('[seller-application] ➡️  GET $_buyerApplicationUrl');
    try {
      final response = await ApiClient.instance.get(
        _buyerApplicationUrl,
        headers: headers,
        suppressAuthHandlers: true,
      );
      final body = _safeJson(response);
      if (response.isSuccess &&
          body != null &&
          body['success'] == true &&
          body['data'] is Map) {
        _status.value = SellerApplicationStatus.fromJson(
          Map<String, dynamic>.from(body['data'] as Map),
        );
        log('[seller-application] status=${_status.value?.status} '
            'canApply=${_status.value?.canApply}');
        return true;
      }
      _errorMessage.value = _failureMessage(
        response.statusCode,
        body,
        TKeys.bsStatusLoadFailed.tr,
      );
      return false;
    } catch (e) {
      log('[seller-application] 🔥 status error: $e');
      _errorMessage.value = TKeys.bsNetworkError.tr;
      return false;
    } finally {
      _isLoadingStatus.value = false;
    }
  }

  /// Uploads [filePath] as the application's CV and returns the S3 key the
  /// submit call needs, or null on failure (with [errorMessage] set).
  ///
  /// Validates the extension and the 2 MB ceiling locally first, so an
  /// obviously-wrong file is rejected before it leaves the handset.
  Future<String?> uploadCv(String filePath, {bool authenticated = true}) async {
    final extension = filePath.split('.').last.toLowerCase();
    if (!cvAllowedExtensions.contains(extension)) {
      _errorMessage.value = TKeys.bsPickDocType.tr;
      return null;
    }

    try {
      if (await File(filePath).length() > cvMaxBytes) {
        _errorMessage.value = TKeys.bsFileTooLarge.tr;
        return null;
      }
    } catch (_) {
      _errorMessage.value = TKeys.bsFileReadFailed.tr;
      return null;
    }

    final headers = await _headers(authenticated: authenticated);
    if (headers == null) {
      _errorMessage.value = TKeys.bsSessionExpired.tr;
      return null;
    }

    _isUploadingCv.value = true;
    _errorMessage.value = null;

    final url = _cvUrl(authenticated: authenticated);
    log('[seller-application] ➡️  POST $url');
    try {
      final response = await ApiClient.instance.uploadFile(
        url,
        // The field name MUST be `cv` — the endpoint looks for exactly this.
        fieldName: 'cv',
        filePath: filePath,
        headers: headers,
        suppressAuthHandlers: true,
      );
      final body = _safeJson(response);
      if (response.isSuccess && body != null && body['data'] is Map) {
        final key = (body['data'] as Map)['s3Key']?.toString();
        if (key != null && key.isNotEmpty) {
          _cvS3Key.value = key;
          log('[seller-application] CV uploaded ($key)');
          return key;
        }
      }
      _errorMessage.value = _failureMessage(
        response.statusCode,
        body,
        TKeys.bsCvUploadFailed.tr,
      );
      return null;
    } catch (e) {
      log('[seller-application] 🔥 cv error: $e');
      _errorMessage.value = TKeys.bsNetworkError.tr;
      return null;
    } finally {
      _isUploadingCv.value = false;
    }
  }

  /// Submits the application with an already-uploaded [cvS3Key].
  ///
  /// Name, e-mail and date of birth are deliberately absent — the server reads
  /// them off the account, which is why the form shows them read-only.
  Future<bool> submitApplication({
    required String phoneNumber,
    required String line1,
    required String postalCode,
    required String city,
    required String country,
    required LiveComfort liveComfort,
    required HoursPerWeek hoursPerWeek,
    required Set<SellerExperience> experience,
    required String cvS3Key,
    String? line2,
    String? state,
    String? experienceOther,
    bool authenticated = true,
    String? fullName,
    String? email,
    String? dateOfBirth,
  }) async {
    final headers = await _headers(authenticated: authenticated);
    if (headers == null) {
      _errorMessage.value = TKeys.bsSessionExpired.tr;
      return false;
    }

    final trimmedOther = experienceOther?.trim();
    final body = <String, dynamic>{
      // Only on the anonymous lane. With a bearer token the server reads these
      // off the account and sending them is the wrong contract, so they're
      // omitted unless the form actually collected them.
      if (fullName != null && fullName.trim().isNotEmpty)
        'fullName': fullName.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (dateOfBirth != null && dateOfBirth.trim().isNotEmpty)
        'dateOfBirth': dateOfBirth.trim(),
      'phoneNumber': phoneNumber,
      'address': <String, dynamic>{
        'line1': line1,
        // Optional strings are omitted rather than sent empty — the validator
        // treats `""` as present-but-invalid.
        if (line2 != null && line2.trim().isNotEmpty) 'line2': line2.trim(),
        'postalCode': postalCode,
        'city': city,
        'country': country,
        if (state != null && state.trim().isNotEmpty) 'state': state.trim(),
      },
      'liveComfort': liveComfort.api,
      'hoursPerWeek': hoursPerWeek.api,
      'experience': experience.map((e) => e.api).toList(),
      // Required by the server only when `other` is among the choices.
      if (experience.contains(SellerExperience.other) &&
          trimmedOther != null &&
          trimmedOther.isNotEmpty)
        'experienceOther': trimmedOther,
      'cvS3Key': cvS3Key,
    };

    _isSubmitting.value = true;
    _errorMessage.value = null;

    final url = _applicationUrl(authenticated: authenticated);
    log('[seller-application] ➡️  POST $url');
    try {
      final response = await ApiClient.instance.post(
        url,
        headers: headers,
        body: body,
        suppressAuthHandlers: true,
      );
      final json = _safeJson(response);

      if (response.isSuccess && json?['success'] != false) {
        if (json?['data'] is Map) {
          _applicationId.value =
              (json!['data'] as Map)['applicationId']?.toString();
        }
        log('[seller-application] submitted (${_applicationId.value})');
        // Re-read the gate so the screen flips itself to "pending" without the
        // caller orchestrating it. Bearer-only, so the anonymous lane skips it
        // and shows its own confirmation instead.
        if (authenticated) await fetchStatus();
        return true;
      }

      // 409 is a documented outcome: an application already exists, or the
      // cooldown is still running. Either way the local gate is stale, so
      // refresh it and let the screen swap to the right result state instead of
      // leaving a dead form.
      if (response.statusCode == 409) {
        _errorMessage.value =
            _serverMessage(json) ?? TKeys.bsAlreadyApplied.tr;
        if (authenticated) await fetchStatus();
        return false;
      }

      _errorMessage.value = _failureMessage(
        response.statusCode,
        json,
        TKeys.bsSubmitFailed.tr,
      );
      return false;
    } catch (e) {
      log('[seller-application] 🔥 submit error: $e');
      _errorMessage.value = TKeys.bsNetworkError.tr;
      return false;
    } finally {
      _isSubmitting.value = false;
    }
  }

  /// The two-step flow the screen calls: upload [cvFilePath] (unless the key
  /// from a previous attempt is still good), then submit.
  ///
  /// Reusing the cached key matters — a 400 on the submit leg is the likeliest
  /// failure, and re-uploading the same file on every retry would be a needless
  /// 2 MB round trip each time.
  Future<bool> submit({
    required String cvFilePath,
    required String phoneNumber,
    required String line1,
    required String postalCode,
    required String city,
    required String country,
    required LiveComfort liveComfort,
    required HoursPerWeek hoursPerWeek,
    required Set<SellerExperience> experience,
    String? line2,
    String? state,
    String? experienceOther,
    bool authenticated = true,
    String? fullName,
    String? email,
    String? dateOfBirth,
  }) async {
    // Everything the server validates that we can check first. The guest lane
    // has no profile behind it, so a typo'd e-mail or a 3-digit postal code
    // would otherwise cost a 2 MB CV upload before coming back as a 400.
    final localError = validationError(
      postalCode: postalCode,
      experience: experience,
      experienceOther: experienceOther,
      fullName: fullName,
      email: email,
      dateOfBirth: dateOfBirth,
      authenticated: authenticated,
    );
    if (localError != null) {
      _errorMessage.value = localError;
      return false;
    }

    _isSubmitting.value = true;
    try {
      var key = _cvS3Key.value;
      if (key == null || key.isEmpty) {
        key = await uploadCv(cvFilePath, authenticated: authenticated);
        if (key == null) return false; // uploadCv already set the message
      }
      return await submitApplication(
        phoneNumber: phoneNumber,
        line1: line1,
        line2: line2,
        postalCode: postalCode,
        city: city,
        country: country,
        state: state,
        liveComfort: liveComfort,
        hoursPerWeek: hoursPerWeek,
        experience: experience,
        experienceOther: experienceOther,
        cvS3Key: key,
        authenticated: authenticated,
        fullName: fullName,
        email: email,
        dateOfBirth: dateOfBirth,
      );
    } finally {
      _isSubmitting.value = false;
    }
  }

  /// Forgets the uploaded CV. Called when a different file is picked, so the
  /// next submit uploads that one instead of re-sending the old key.
  void resetDraft() {
    _cvS3Key.value = null;
    _errorMessage.value = null;
  }

  /// Wipes everything — called when the applicant session is signed out.
  void clearSession() {
    _status.value = null;
    _account.value = null;
    _cvS3Key.value = null;
    _applicationId.value = null;
    _errorMessage.value = null;
  }

  // ---------- Validation ----------

  /// Minimum age the server enforces — on the guest lane's `dateOfBirth`, and
  /// on the profile's `birthDate` for a signed-in applicant.
  static const int minimumAgeYears = 15;

  /// `experienceOther` is trimmed and capped server-side.
  static const int experienceOtherMaxLength = 150;

  /// Norway is the only country in the product, and its postal codes are
  /// exactly four digits.
  static bool isValidPostalCode(String value) =>
      RegExp(r'^\d{4}$').hasMatch(value.trim());

  /// Deliberately loose — the server (and the confirmation mail) is the real
  /// check. This only catches the obvious typo before a 2 MB upload.
  static bool isValidEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

  /// `yyyy-MM-dd`, in the past, and at least [minimumAgeYears] ago.
  static bool isEligibleBirthDate(String iso) {
    final parsed = DateTime.tryParse(iso.trim());
    if (parsed == null) return false;
    final now = DateTime.now();
    final earliestAllowed = DateTime(now.year - minimumAgeYears, now.month, now.day);
    return !parsed.isAfter(earliestAllowed);
  }

  /// The first thing wrong with the form, as a sentence to show, or null when
  /// the request is well-formed. Mirrors the server's `VALIDATION_ERROR`
  /// checks so the applicant is corrected in place instead of by a 400.
  static String? validationError({
    required String postalCode,
    required Set<SellerExperience> experience,
    String? experienceOther,
    String? fullName,
    String? email,
    String? dateOfBirth,
    bool authenticated = true,
  }) {
    if (!isValidPostalCode(postalCode)) return TKeys.bsInvalidPostal.tr;

    if (experience.contains(SellerExperience.other)) {
      final other = experienceOther?.trim() ?? '';
      if (other.isEmpty) return TKeys.bsExperienceOtherRequired.tr;
      if (other.length > experienceOtherMaxLength) {
        return TKeys.bsExperienceOtherTooLong.tr;
      }
    }

    // Identity only travels on the guest lane; with a token the server reads
    // it off the account and the form shows it read-only.
    if (!authenticated) {
      if ((fullName ?? '').trim().isEmpty) return TKeys.bsNameRequired.tr;
      if (!isValidEmail(email ?? '')) return TKeys.bsInvalidEmail.tr;
      final dob = (dateOfBirth ?? '').trim();
      if (dob.isEmpty) return TKeys.bsSelectDob.tr;
      if (!isEligibleBirthDate(dob)) return TKeys.bsMinimumAge.tr;
    }

    return null;
  }

  // ---------- Helpers ----------

  /// The sentence to show for a failed call: the server's own message when it
  /// sent one, the rate-limit line for a 429 (which often answers with an
  /// empty body), otherwise [fallback] with the status code appended so a
  /// support ticket still carries it.
  String _failureMessage(
    int statusCode,
    Map<String, dynamic>? body,
    String fallback,
  ) {
    if (statusCode == 429) {
      return _serverMessage(body) ?? TKeys.bsTooManyRequests.tr;
    }
    return _serverMessage(body) ?? '$fallback ($statusCode)';
  }

  /// [ApiResponse.json] throws on a non-JSON body (an HTML error page from a
  /// proxy, say), which would surface as a raw `FormatException`.
  Map<String, dynamic>? _safeJson(ApiResponse response) {
    try {
      return response.json;
    } catch (_) {
      return null;
    }
  }

  /// `error.message` → `message`, in that order. Never a raw transport error.
  String? _serverMessage(Map<String, dynamic>? body) {
    if (body == null) return null;
    final error = body['error'];
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    final message = body['message'];
    return (message is String && message.isNotEmpty) ? message : null;
  }

  /// Normalises what the applicant typed into exactly one `+47` prefix.
  /// Strips a pasted `+47` / `0047` / bare `47` on an over-long string, and a
  /// Norwegian trunk `0`.
  static String normaliseNorwegianPhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+47')) {
      digits = digits.substring(3);
    } else if (digits.startsWith('0047')) {
      digits = digits.substring(4);
    } else if (digits.startsWith('47') && digits.length > 8) {
      digits = digits.substring(2);
    }
    digits = digits.replaceAll('+', '');
    if (digits.length > 8 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '+47$digits';
  }
}
