class SellerProfile {
  final String id;
  final String displayName;
  final String businessName;
  final String email;
  final String phone;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? profileCardThumbnailUrl;
  final String? bio;
  final String? publicProfileSlug;
  final String sellerType;
  final bool verified;
  final String approvalStatus;
  final ProfileSections sections;
  final SocialLinks socialLinks;

  SellerProfile({
    required this.id,
    required this.displayName,
    required this.businessName,
    required this.email,
    required this.phone,
    this.avatarUrl,
    this.bannerUrl,
    this.profileCardThumbnailUrl,
    this.bio,
    this.publicProfileSlug,
    required this.sellerType,
    required this.verified,
    required this.approvalStatus,
    required this.sections,
    required this.socialLinks,
  });

  factory SellerProfile.fromJson(Map<String, dynamic> json) {
    return SellerProfile(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? '',
      businessName: json['businessName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      bannerUrl: json['bannerUrl'] as String?,
      profileCardThumbnailUrl: json['profileCardThumbnailUrl'] as String?,
      bio: json['bio'] as String?,
      publicProfileSlug: json['publicProfileSlug'] as String?,
      sellerType: json['sellerType'] as String? ?? '',
      verified: json['verified'] as bool? ?? false,
      approvalStatus: json['approvalStatus'] as String? ?? '',
      sections: ProfileSections.fromJson(
        json['sections'] as Map<String, dynamic>? ?? {},
      ),
      socialLinks: SocialLinks.fromJson(
        json['socialLinks'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

/// Toggle flags controlling which blocks render on the seller's public
/// profile page. Defaults to everything visible (except stats) so a profile
/// that predates the feature still looks sensible.
class ProfileSections {
  final bool header;
  final bool stats;
  final bool products;
  final bool streams;
  final bool businessInfo;
  final bool accountInfo;
  final bool socialLinks;

  ProfileSections({
    this.header = true,
    this.stats = false,
    this.products = true,
    this.streams = true,
    this.businessInfo = true,
    this.accountInfo = true,
    this.socialLinks = true,
  });

  factory ProfileSections.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) => json[key] as bool? ?? fallback;
    return ProfileSections(
      header: flag('header', true),
      stats: flag('stats', false),
      products: flag('products', true),
      streams: flag('streams', true),
      businessInfo: flag('businessInfo', true),
      accountInfo: flag('accountInfo', true),
      socialLinks: flag('socialLinks', true),
    );
  }

  Map<String, dynamic> toJson() => {
        'header': header,
        'stats': stats,
        'products': products,
        'streams': streams,
        'businessInfo': businessInfo,
        'accountInfo': accountInfo,
        'socialLinks': socialLinks,
      };

  ProfileSections copyWith({
    bool? header,
    bool? stats,
    bool? products,
    bool? streams,
    bool? businessInfo,
    bool? accountInfo,
    bool? socialLinks,
  }) {
    return ProfileSections(
      header: header ?? this.header,
      stats: stats ?? this.stats,
      products: products ?? this.products,
      streams: streams ?? this.streams,
      businessInfo: businessInfo ?? this.businessInfo,
      accountInfo: accountInfo ?? this.accountInfo,
      socialLinks: socialLinks ?? this.socialLinks,
    );
  }
}

class SocialLinks {
  final String? website;
  final String? instagram;
  final String? facebook;
  final String? youtube;
  final String? linkedin;
  final String? tiktok;

  SocialLinks({
    this.website,
    this.instagram,
    this.facebook,
    this.youtube,
    this.linkedin,
    this.tiktok,
  });

  factory SocialLinks.fromJson(Map<String, dynamic> json) {
    return SocialLinks(
      website: json['website'] as String?,
      instagram: json['instagram'] as String?,
      facebook: json['facebook'] as String?,
      youtube: json['youtube'] as String?,
      linkedin: json['linkedin'] as String?,
      tiktok: json['tiktok'] as String?,
    );
  }

  /// Shape expected by the `socialLinksInput` field of the profile PATCH
  /// endpoint. Empty values are sent as `null` so the server clears them.
  Map<String, dynamic> toInputJson() => {
        'website': _orNull(website),
        'instagram': _orNull(instagram),
        'facebook': _orNull(facebook),
        'youtube': _orNull(youtube),
        'linkedin': _orNull(linkedin),
        'tiktok': _orNull(tiktok),
      };

  static String? _orNull(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();

  List<MapEntry<String, String>> get activeLinks {
    final all = <MapEntry<String, String>>[
      if (website != null) MapEntry('Website', website!),
      if (instagram != null) MapEntry('Instagram', instagram!),
      if (facebook != null) MapEntry('Facebook', facebook!),
      if (youtube != null) MapEntry('YouTube', youtube!),
      if (linkedin != null) MapEntry('LinkedIn', linkedin!),
      if (tiktok != null) MapEntry('TikTok', tiktok!),
    ];
    return all;
  }
}
