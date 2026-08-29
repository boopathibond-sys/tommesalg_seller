import 'dart:developer';

import '../../../../core/config/env_config.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/services/auth_service.dart';

/// Why something is being flagged. [wire] is the literal the backend expects;
/// [labelKey] is the translation key for the row the seller taps.
///
/// Kept identical to the buyer app's `ReportReason` — both roles post to the
/// same `/api/v1/moderation/reports` endpoint, so the vocabularies must not
/// drift or the operator queue ends up with two spellings of one reason.
enum ReportReason {
  sexualContent('SEXUAL_CONTENT', 'report_reason_sexual'),
  violence('VIOLENCE', 'report_reason_violence'),
  harassment('HARASSMENT', 'report_reason_harassment'),
  hateSpeech('HATE_SPEECH', 'report_reason_hate'),
  spamOrScam('SPAM_OR_SCAM', 'report_reason_spam'),
  illegalItem('ILLEGAL_ITEM', 'report_reason_illegal'),
  other('OTHER', 'report_reason_other');

  const ReportReason(this.wire, this.labelKey);

  final String wire;
  final String labelKey;
}

/// Flags user-generated content to the operators.
///
/// App Review guideline 1.2: an app carrying user-generated content has to
/// give the people looking at it a way to flag what they see, and the
/// developer has to actually receive it. The seller's mute/delete controls are
/// about their *own* room; this is the channel that reaches a human at
/// Tommesalg.
///
/// Served from [EnvConfig.buyerBaseUrl]. The route is account-scoped
/// (`/api/v1/moderation/…`, not `/api/v1/buyer/…`) and derives the reporter
/// from the bearer token, so the same endpoint serves buyers and sellers.
class ModerationReportApi {
  final _api = ApiClient.instance;

  /// Posts one report. Returns `true` when the backend accepted it.
  ///
  /// [targetType] is `CHAT_MESSAGE` | `LIVE_STREAM` | `LISTING` | `USER`.
  /// [contentPreview] gives the reviewer the offending text without having to
  /// go dig the message out of the stream log — worth sending whenever the
  /// content is short enough to quote.
  Future<bool> report({
    required String targetType,
    required String targetId,
    required ReportReason reason,
    String? details,
    String? reportedUserId,
    String? contextId,
    String? contentPreview,
  }) async {
    try {
      final response = await _api.post(
        '${EnvConfig.buyerBaseUrl}/api/v1/moderation/reports',
        headers: await AuthService.instance.ensuredAuthHeaders(),
        body: {
          'targetType': targetType,
          'targetId': targetId,
          'reason': reason.wire,
          if (details != null && details.trim().isNotEmpty)
            'details': details.trim(),
          if (reportedUserId != null && reportedUserId.isNotEmpty)
            'reportedUserId': reportedUserId,
          if (contextId != null && contextId.isNotEmpty) 'contextId': contextId,
          if (contentPreview != null && contentPreview.isNotEmpty)
            'contentPreview': contentPreview,
        },
        // Account-scoped rather than seller-scoped: a role-shaped error from
        // it must not tear the seller's session down mid-broadcast.
        suppressAuthHandlers: true,
      );

      if (response.isSuccess) {
        final body = response.json;
        if (body['success'] == true) return true;
      }
      log('Moderation report rejected: ${response.statusCode} ${response.body}');
      return false;
    } catch (e) {
      log('Moderation report error: $e');
      return false;
    }
  }
}
