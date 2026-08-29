import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/localization/translation_keys.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../data/services/moderation_report_api.dart';

/// Bottom sheet for flagging user-generated content to the operators.
///
/// Pick a reason, optionally add a note, send. The sheet owns the network
/// call so every call site gets the same success/failure feedback; it pops
/// itself when the report lands.
///
/// Returns `true` when a report was accepted, `false`/`null` otherwise.
Future<bool?> showReportSheet({
  required BuildContext context,
  required String targetType,
  required String targetId,
  String? reportedUserId,
  String? contextId,
  String? contentPreview,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sctx) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
      reportedUserId: reportedUserId,
      contextId: contextId,
      contentPreview: contentPreview,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    this.reportedUserId,
    this.contextId,
    this.contentPreview,
  });

  final String targetType;
  final String targetId;
  final String? reportedUserId;
  final String? contextId;
  final String? contentPreview;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _api = ModerationReportApi();
  final _details = TextEditingController();

  ReportReason? _reason;
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _sending) return;

    setState(() => _sending = true);
    final ok = await _api.report(
      targetType: widget.targetType,
      targetId: widget.targetId,
      reason: reason,
      details: _details.text,
      reportedUserId: widget.reportedUserId,
      contextId: widget.contextId,
      contentPreview: widget.contentPreview,
    );
    if (!mounted) return;

    Navigator.of(context).pop(ok);
    Get.snackbar(
      TKeys.reportTitle.tr,
      ok ? TKeys.reportSent.tr : TKeys.reportFailed.tr,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Lift the sheet above the keyboard while the note field has focus.
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.inputBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                CustomText(
                  TKeys.reportTitle.tr,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 4),
                CustomText(
                  TKeys.reportBody.tr,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 14),

                for (final reason in ReportReason.values)
                  _ReasonRow(
                    label: reason.labelKey.tr,
                    selected: _reason == reason,
                    onTap: () => setState(() => _reason = reason),
                  ),

                const SizedBox(height: 12),
                TextField(
                  controller: _details,
                  maxLines: 3,
                  maxLength: 500,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: TKeys.reportNoteHint.tr,
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    filled: true,
                    fillColor: AppColors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.inputBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // Disabled until a reason is picked — the backend requires one,
                // and a greyed button explains that better than an error toast.
                ElevatedButton(
                  onPressed: (_reason == null || _sending) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.vipps,
                    disabledBackgroundColor: AppColors.inputBorder,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppColors.white),
                          ),
                        )
                      : CustomText(
                          TKeys.reportSubmit.tr,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.white,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tappable reason, check-marked when it is the current pick.
class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: CustomText(
                label,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? AppColors.vipps : AppColors.inputBorder,
            ),
          ],
        ),
      ),
    );
  }
}
