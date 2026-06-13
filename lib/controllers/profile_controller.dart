import 'dart:developer';

import 'package:get/get.dart';

import '../core/config/env_config.dart';
import '../core/services/api_client.dart';
import '../core/services/auth_service.dart';
import '../models/seller_profile.dart';

/// The three uploadable profile images. Each maps to its own S3 upload
/// endpoint + multipart field name, and to the profile field that stores
/// the resulting S3 key.
enum ProfileImageKind {
  avatar(
    uploadPath: '/api/s3/upload-profile-picture',
    fieldName: 'file',
    profileField: 'avatarUrl',
  ),
  banner(
    uploadPath: '/api/s3/upload-profile-banner',
    fieldName: 'file',
    profileField: 'bannerUrl',
  ),
  cardThumbnail(
    uploadPath: '/api/s3/upload-profile-card-thumbnail',
    fieldName: 'thumbnail',
    profileField: 'profileCardThumbnailUrl',
  );

  const ProfileImageKind({
    required this.uploadPath,
    required this.fieldName,
    required this.profileField,
  });

  final String uploadPath;
  final String fieldName;
  final String profileField;
}

class ProfileController extends GetxController {
  // ---------- Reactive state ----------

  final RxBool _isLoading = false.obs;
  bool get isLoading => _isLoading.value;

  final RxnString _errorMessage = RxnString();
  String? get errorMessage => _errorMessage.value;

  final RxBool _isSaving = false.obs;
  bool get isSaving => _isSaving.value;

  /// Which profile image is currently uploading (`null` when idle). The UI
  /// reads this to show a per-image spinner.
  final Rxn<ProfileImageKind> _uploadingImage = Rxn<ProfileImageKind>();
  ProfileImageKind? get uploadingImage => _uploadingImage.value;
  bool isUploading(ProfileImageKind kind) => _uploadingImage.value == kind;

  final Rxn<SellerProfile> _profile = Rxn<SellerProfile>();
  SellerProfile? get profile => _profile.value;

  // ---------- Services ----------

  final _api = ApiClient.instance;

  // ---------- Lifecycle ----------

  @override
  void onInit() {
    super.onInit();
    fetchProfile();
  }

  // ---------- Intents ----------

  /// Loads the seller profile.
  ///
  /// Right after login the backend can briefly reject the freshly-minted
  /// Supabase token (validation lag / cold connection), which previously
  /// surfaced the error card on the first launch of the Home screen. To
  /// avoid that, the request is retried a few times with a shot backoff
  /// before any error is shown to the user.
  /// Loads the seller profile. Pass [silent] = true for pull-to-refresh: the
  /// request runs in the background without flipping [isLoading] (so the
  /// existing content stays on screen under the refresh indicator instead of
  /// collapsing to a full-screen spinner), and a failure won't replace
  /// already-loaded content with the error card.
  Future<bool> fetchProfile({int maxAttempts = 3, bool silent = false}) async {
    //seller1@tommesalg.no
    //TestSeller#321
    if (!silent) _isLoading.value = true;
    _errorMessage.value = null;

    String? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _api.get(
          '${EnvConfig.baseUrl}/api/v1/seller/profile',
          headers: AuthService.instance.authHeaders,
        );

        if (response.isSuccess) {
          final body = response.json;
          if (body['success'] == true && body['data'] is Map) {
            _profile.value = SellerProfile.fromJson(
              body['data'] as Map<String, dynamic>,
            );
            _errorMessage.value = null;
            if (!silent) _isLoading.value = false;
            return true;
          }
          lastError = 'Unexpected response format.';
        } else {
          lastError = 'Failed to load profile: ${response.statusCode}';
        }
      } catch (e) {
        log('Profile fetch error (attempt $attempt/$maxAttempts): $e');
        lastError = 'Network error. Please try again.';
      }

      // Back off before retrying, unless this was the final attempt.
      if (attempt < maxAttempts) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    // On a silent refresh, keep the content already on screen rather than
    // swapping it for the error card; only surface the error if we have
    // nothing to show.
    if (!silent || _profile.value == null) {
      _errorMessage.value = lastError ?? 'Network error. Please try again.';
    }
    if (!silent) _isLoading.value = false;
    return false;
  }

  /// Pushes edited profile fields to `PATCH /api/v1/seller/profile`.
  ///
  /// On success the freshly returned profile (if any) replaces the local
  /// copy so the Profile tab reflects the change immediately. Returns
  /// `true` when the server accepts the update.
  Future<bool> updateProfile({
    required String displayName,
    required String businessName,
    String? bio,
    String? publicProfileSlug,
    required ProfileSections sections,
    required SocialLinks socialLinks,
  }) async {
    _isSaving.value = true;
    _errorMessage.value = null;

    String? orNull(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();

    try {
      final response = await _api.patch(
        '${EnvConfig.baseUrl}/api/v1/seller/profile',
        headers: AuthService.instance.authHeaders,
        body: {
          'displayName': displayName.trim(),
          'businessName': businessName.trim(),
          'bio': orNull(bio),
          'publicProfileSlug': orNull(publicProfileSlug),
          'sections': sections.toJson(),
          'socialLinksInput': socialLinks.toInputJson(),
        },
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true) {
          if (body['data'] is Map) {
            _profile.value = SellerProfile.fromJson(
              body['data'] as Map<String, dynamic>,
            );
          } else {
            // Endpoint returned no body — re-fetch to stay in sync.
            await fetchProfile();
          }
          return true;
        }
        _errorMessage.value = 'Unexpected response format.';
        return false;
      }

      _errorMessage.value = 'Failed to update profile: ${response.statusCode}';
      return false;
    } catch (e) {
      log('Profile update error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _isSaving.value = false;
    }
  }

  /// Uploads [filePath] to the S3 endpoint for [kind] (step 1), then PATCHes
  /// the returned `s3Key` onto the matching profile field (step 2). On
  /// success the local profile is refreshed from the PATCH response so the
  /// resolved HTTPS URL renders immediately. Returns `true` on success.
  Future<bool> uploadProfileImage({
    required ProfileImageKind kind,
    required String filePath,
  }) async {
    _uploadingImage.value = kind;
    _errorMessage.value = null;

    try {
      // Step 1 — multipart upload to S3.
      final upload = await _api.uploadFile(
        '${EnvConfig.baseUrl}${kind.uploadPath}',
        fieldName: kind.fieldName,
        filePath: filePath,
        headers: AuthService.instance.authHeaders,
      );

      if (!upload.isSuccess) {
        _errorMessage.value = 'Upload failed: ${upload.statusCode}';
        return false;
      }

      final uploadBody = upload.json;
      final s3Key = uploadBody['s3Key'] as String?;
      if (uploadBody['success'] != true || s3Key == null || s3Key.isEmpty) {
        _errorMessage.value = 'Upload did not return an image key.';
        return false;
      }

      // Step 2 — save the key to the public profile.
      final patch = await _api.patch(
        '${EnvConfig.baseUrl}/api/v1/seller/profile',
        headers: AuthService.instance.authHeaders,
        body: {kind.profileField: s3Key},
      );

      if (patch.isSuccess) {
        final body = patch.json;
        if (body['success'] == true) {
          if (body['data'] is Map) {
            _profile.value = SellerProfile.fromJson(
              body['data'] as Map<String, dynamic>,
            );
          } else {
            await fetchProfile();
          }
          return true;
        }
        _errorMessage.value = 'Unexpected response format.';
        return false;
      }

      _errorMessage.value = 'Failed to save image: ${patch.statusCode}';
      return false;
    } catch (e) {
      log('Profile image upload error: $e');
      _errorMessage.value = 'Network error. Please try again.';
      return false;
    } finally {
      _uploadingImage.value = null;
    }
  }
}
