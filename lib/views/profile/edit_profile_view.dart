import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/profile_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../../models/seller_profile.dart';
import '../auth/widgets/auth_text_field.dart';
import '../auth/widgets/primary_login_button.dart';
import 'widgets/social_link_field.dart';
import '../../core/localization/translation_keys.dart';

/// Edit screen for the seller's public profile. Pre-fills from the current
/// [SellerProfile] and PATCHes the changes through [ProfileController].
class EditProfileView extends StatefulWidget {
  const EditProfileView({super.key, required this.profile});

  final SellerProfile profile;

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  final _profileCtrl = getOrPut(() => ProfileController());

  late final TextEditingController _displayName;
  late final TextEditingController _businessName;
  late final TextEditingController _bio;
  late final TextEditingController _slug;

  late final TextEditingController _website;
  late final TextEditingController _instagram;
  late final TextEditingController _facebook;
  late final TextEditingController _youtube;
  late final TextEditingController _linkedin;
  late final TextEditingController _tiktok;

  late ProfileSections _sections;

  /// Every text field, keyed — so the opening snapshot and the dirty check
  /// can't drift apart when a field is added to the form.
  late final Map<String, TextEditingController> _fields = {
    'displayName': _displayName,
    'businessName': _businessName,
    'bio': _bio,
    'slug': _slug,
    'website': _website,
    'instagram': _instagram,
    'facebook': _facebook,
    'youtube': _youtube,
    'linkedin': _linkedin,
    'tiktok': _tiktok,
  };

  /// What the form opened with. "Save changes" stays disabled until something
  /// differs from this, so opening the screen and backing out can't PATCH a
  /// no-op.
  late final Map<String, String> _initialText;
  late final Map<String, dynamic> _initialSections;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _displayName = TextEditingController(text: p.displayName);
    _businessName = TextEditingController(text: p.businessName);
    _bio = TextEditingController(text: p.bio ?? '');
    _slug = TextEditingController(text: p.publicProfileSlug ?? '');

    _website = TextEditingController(text: p.socialLinks.website ?? '');
    _instagram = TextEditingController(text: p.socialLinks.instagram ?? '');
    _facebook = TextEditingController(text: p.socialLinks.facebook ?? '');
    _youtube = TextEditingController(text: p.socialLinks.youtube ?? '');
    _linkedin = TextEditingController(text: p.socialLinks.linkedin ?? '');
    _tiktok = TextEditingController(text: p.socialLinks.tiktok ?? '');

    _sections = p.sections;

    _initialText = {for (final e in _fields.entries) e.key: e.value.text};
    _initialSections = _sections.toJson();
    for (final c in _fields.values) {
      c.addListener(_recomputeDirty);
    }
  }

  /// Runs on every keystroke, but only rebuilds when the answer actually
  /// flips — typing in a field doesn't rebuild the form on each character.
  void _recomputeDirty() {
    final dirty =
        _fields.entries.any((e) => e.value.text != _initialText[e.key]) ||
            !mapEquals(_sections.toJson(), _initialSections);
    if (dirty == _dirty) return;
    setState(() => _dirty = dirty);
  }

  @override
  void dispose() {
    _displayName.dispose();
    _businessName.dispose();
    _bio.dispose();
    _slug.dispose();
    _website.dispose();
    _instagram.dispose();
    _facebook.dispose();
    _youtube.dispose();
    _linkedin.dispose();
    _tiktok.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_displayName.text.trim().isEmpty) {
      Get.snackbar(TKeys.epRequired.tr, TKeys.epDisplayNameEmpty.tr);
      return;
    }
    if (_businessName.text.trim().isEmpty) {
      Get.snackbar(TKeys.epRequired.tr, TKeys.epBusinessNameEmpty.tr);
      return;
    }

    final ok = await _profileCtrl.updateProfile(
      displayName: _displayName.text,
      businessName: _businessName.text,
      bio: _bio.text,
      publicProfileSlug: _slug.text,
      sections: _sections,
      socialLinks: SocialLinks(
        website: _website.text,
        instagram: _instagram.text,
        facebook: _facebook.text,
        youtube: _youtube.text,
        linkedin: _linkedin.text,
        tiktok: _tiktok.text,
      ),
    );

    if (!mounted) return;

    if (ok) {
      Get.snackbar(TKeys.savedTitle.tr, TKeys.epProfileUpdated.tr);
      Navigator.of(context).pop(true);
    } else {
      Get.snackbar(
        TKeys.errorTitle.tr,
        _profileCtrl.errorMessage ?? TKeys.epCouldNotUpdate.tr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        surfaceTintColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.brandNavy),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: CustomText(
          TKeys.epEditProfile.tr,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(TKeys.epBasicInformation.tr),
              const SizedBox(height: 12),
              AuthTextField(
                controller: _displayName,
                icon: Icons.person_outline_rounded,
                hint: TKeys.epDisplayName.tr,
              ),
              const SizedBox(height: 12),
              AuthTextField(
                controller: _businessName,
                icon: Icons.storefront_outlined,
                hint: TKeys.epBusinessName.tr,
              ),
              const SizedBox(height: 12),
              AuthTextField(
                controller: _slug,
                icon: Icons.link_rounded,
                hint: TKeys.epPublicSlug.tr,
              ),
              const SizedBox(height: 12),
              _BioField(controller: _bio),

              const SizedBox(height: 28),
              _label(TKeys.epPublicSections.tr),
              const SizedBox(height: 8),
              CustomText(
                TKeys.epPublicSectionsBody.tr,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
                height: 1.4,
              ),
              const SizedBox(height: 8),
              _sectionToggle(TKeys.epHeader.tr, _sections.header,
                  (v) => _sections = _sections.copyWith(header: v)),
              _sectionToggle(TKeys.epStats.tr, _sections.stats,
                  (v) => _sections = _sections.copyWith(stats: v)),
              _sectionToggle(TKeys.productsLabel.tr, _sections.products,
                  (v) => _sections = _sections.copyWith(products: v)),
              _sectionToggle(TKeys.navStreams.tr, _sections.streams,
                  (v) => _sections = _sections.copyWith(streams: v)),
              _sectionToggle(TKeys.epBusinessInfo.tr, _sections.businessInfo,
                  (v) => _sections = _sections.copyWith(businessInfo: v)),
              _sectionToggle(TKeys.epAccountInfo.tr, _sections.accountInfo,
                  (v) => _sections = _sections.copyWith(accountInfo: v)),
              _sectionToggle(TKeys.socialLinksLabel.tr, _sections.socialLinks,
                  (v) => _sections = _sections.copyWith(socialLinks: v)),

              const SizedBox(height: 28),
              _label(TKeys.epSocialLinksTitle.tr),
              const SizedBox(height: 8),
              CustomText(
                TKeys.epSocialLinksBody.tr,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
                height: 1.4,
              ),
              const SizedBox(height: 12),
              SocialLinkField(
                platform: 'Website',
                controller: _website,
                icon: Icons.language_rounded,
                hint: TKeys.epWebsiteHint.tr,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              SocialLinkField(
                platform: 'Instagram',
                controller: _instagram,
                icon: Icons.camera_alt_outlined,
                hint: TKeys.epInstagramHint.tr,
              ),
              const SizedBox(height: 12),
              SocialLinkField(
                platform: 'Facebook',
                controller: _facebook,
                icon: Icons.facebook_rounded,
                hint: 'Facebook',
              ),
              const SizedBox(height: 12),
              SocialLinkField(
                platform: 'YouTube',
                controller: _youtube,
                icon: Icons.play_circle_outline_rounded,
                hint: 'YouTube',
              ),
              const SizedBox(height: 12),
              SocialLinkField(
                platform: 'LinkedIn',
                controller: _linkedin,
                icon: Icons.work_outline_rounded,
                hint: 'LinkedIn',
              ),
              const SizedBox(height: 12),
              SocialLinkField(
                platform: 'TikTok',
                controller: _tiktok,
                icon: Icons.music_note_rounded,
                hint: 'TikTok',
              ),

              const SizedBox(height: 32),
              Obx(() {
                final busy = _profileCtrl.isSaving;
                return PrimaryLoginButton(
                  label: TKeys.saveChanges.tr,
                  busy: busy,
                  showArrow: false,
                  // Null keeps the button dimmed and inert — nothing to save
                  // until the form differs from what it opened with.
                  onPressed: busy || !_dirty ? null : _save,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return CustomText(
      text,
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
      color: AppColors.textPrimary,
    );
  }

  Widget _sectionToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: CustomText(
              label,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          Switch.adaptive(
            value: value,
            // activeThumbColor: AppColors.brandNavy,
            activeTrackColor: AppColors.brandYellow,
            onChanged: (v) {
              setState(() => onChanged(v));
              _recomputeDirty();
            },
          ),
        ],
      ),
    );
  }
}

/// Multi-line bio input styled to match [AuthTextField].
class _BioField extends StatelessWidget {
  const _BioField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Icon(Icons.info_outline_rounded,
                size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 5,
              minLines: 3,
              cursorColor: AppColors.accent,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: TKeys.epAboutStoreHint.tr,
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
