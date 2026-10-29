import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/localization/translation_keys.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/custom_text.dart';
import 'edit_inputs.dart';

/// Collects the `editReason` the products API requires on every PATCH. Used by
/// the edit form and by the detail page's shipping shortcut, so every change
/// lands in the edit history the same way.
///
/// [fieldCount] labels the button ("Save 3 changes"); omit it for a single
/// shortcut edit. Returns null when dismissed.
Future<String?> showEditReasonSheet(BuildContext context, {int? fieldCount}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditReasonSheet(fieldCount: fieldCount),
  );
}

/// Owns its [TextEditingController] so it is disposed with the sheet's own
/// element — after the pop animation — rather than when the show future
/// completes, which used to throw "used after being disposed".
class _EditReasonSheet extends StatefulWidget {
  const _EditReasonSheet({this.fieldCount});

  final int? fieldCount;

  @override
  State<_EditReasonSheet> createState() => _EditReasonSheetState();
}

class _EditReasonSheetState extends State<_EditReasonSheet> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      AppSnackbar.show(TKeys.reasonRequired.tr, TKeys.describeChange.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final count = widget.fieldCount;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            // Scrolls inside the space the keyboard leaves, so a small screen
            // shrinks the sheet instead of overflowing it.
            constraints: BoxConstraints(
              maxHeight: media.size.height * 0.85 - media.viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderGrey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CustomText(TKeys.reasonForChange.tr,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                  const SizedBox(height: 6),
                  EditNote(TKeys.reasonLoggedNote.tr),
                  const SizedBox(height: 14),
                  EditTextField(
                    label: TKeys.whyChange.tr,
                    controller: _reason,
                    maxLines: 3,
                    maxLength: 2000,
                    autofocus: true,
                    hint: TKeys.whyChangeHint.tr,
                  ),
                  EditPrimaryButton(
                    label: count == null
                        ? TKeys.saveChanges.tr
                        : (count == 1
                                ? TKeys.saveChangeCount
                                : TKeys.saveChangesCount)
                            .trParams({'count': '$count'}),
                    onTap: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
