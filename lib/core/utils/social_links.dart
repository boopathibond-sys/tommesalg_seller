/// Helpers for turning the loosely-typed social values on the seller profile
/// into openable URLs.
///
/// Sellers type these fields freehand — `@myshop`, `myshop`,
/// `instagram.com/myshop` and `https://instagram.com/myshop` all show up in
/// practice — so we normalise before launching instead of assuming a full URL.
library;

import 'dart:developer';

import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../localization/translation_keys.dart';

/// Base profile URL per platform, keyed by the labels [SocialLinks.activeLinks]
/// emits ('Website', 'Instagram', …).
const _handleBase = <String, String>{
  'Instagram': 'https://instagram.com/',
  'Facebook': 'https://facebook.com/',
  'YouTube': 'https://youtube.com/@',
  'LinkedIn': 'https://linkedin.com/in/',
  'TikTok': 'https://tiktok.com/@',
};

/// Resolves [raw] to a full URL for [platform], or null when there's nothing
/// sensible to open (empty value, or a bare word typed into "Website").
Uri? socialLinkUri(String platform, String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;

  // Already a URL, or close enough to one.
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return Uri.tryParse(value);
  }
  if (value.startsWith('www.')) return Uri.tryParse('https://$value');

  // "instagram.com/myshop" — a domain typed without the scheme.
  final looksLikeDomain = value.contains('.') && !value.startsWith('@');
  if (looksLikeDomain) return Uri.tryParse('https://$value');

  // A bare handle. Website has no handle form, so there's nothing to open.
  final base = _handleBase[platform];
  if (base == null) return null;
  return Uri.tryParse('$base${value.replaceFirst(RegExp(r'^@+'), '')}');
}

/// True when [raw] resolves to something we can open — drives whether the UI
/// renders a value as a tappable link.
bool isOpenableSocialLink(String platform, String? raw) =>
    socialLinkUri(platform, raw) != null;

/// Opens [raw] for [platform] in the system browser (or the platform's own app,
/// when it claims the link). Reports failures rather than doing nothing.
Future<void> openSocialLink(String platform, String? raw) async {
  final uri = socialLinkUri(platform, raw);
  if (uri == null) {
    Get.snackbar(TKeys.slInvalidLink.tr,
        TKeys.slInvalidLinkBody.trParams({'platform': platform}));
    return;
  }
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      Get.snackbar(TKeys.slCouldNotOpen.tr,
          TKeys.slNoAppForUri.trParams({'uri': '$uri'}));
    }
  } catch (e) {
    log('openSocialLink error: $e');
    Get.snackbar(TKeys.slCouldNotOpen.tr, TKeys.slOpenFailed.tr);
  }
}
