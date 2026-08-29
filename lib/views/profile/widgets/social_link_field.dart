import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/social_links.dart';
import '../../../core/widgets/custom_text.dart';
import '../../auth/widgets/auth_text_field.dart';
import '../../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

/// A social link on the Edit Profile screen, in one of three states:
///
///  * **empty** — just the platform name and an "Add" button;
///  * **filled** — the value shown as a tappable link (opens in the browser)
///    with an "Edit" button beside it;
///  * **editing** — the familiar [AuthTextField], with Done / Remove.
///
/// The value lives in [controller] the whole time, so the parent screen still
/// saves everything in one go with its own Save button — this widget only
/// controls whether the field is editable.
class SocialLinkField extends StatefulWidget {
  const SocialLinkField({
    super.key,
    required this.platform,
    required this.controller,
    required this.icon,
    required this.hint,
    this.keyboardType,
  });

  /// Label used for display *and* for URL resolution — must match the keys in
  /// `SocialLinks.activeLinks` ('Website', 'Instagram', …).
  final String platform;
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final TextInputType? keyboardType;

  @override
  State<SocialLinkField> createState() => _SocialLinkFieldState();
}

class _SocialLinkFieldState extends State<SocialLinkField> {
  bool _editing = false;

  String get _value => widget.controller.text.trim();

  void _startEditing() => setState(() => _editing = true);

  void _finishEditing() {
    FocusScope.of(context).unfocus();
    setState(() => _editing = false);
  }

  void _remove() {
    widget.controller.clear();
    _finishEditing();
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) return _editor();
    return _value.isEmpty ? _empty() : _filled();
  }

  // ── States ────────────────────────────────────────────────────────────────

  /// Nothing saved yet — offer to add it.
  Widget _empty() {
    return _Shell(
      icon: widget.icon,
      child: Row(
        children: [
          Expanded(
            child: CustomText(
              widget.platform,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          _TextAction(
            label: TKeys.addAction.tr,
            icon: Icons.add_rounded,
            color: AppColors.primaryBlue,
            onTap: _startEditing,
          ),
        ],
      ),
    );
  }

  /// Saved value — tap the link to open it, or Edit to change it.
  Widget _filled() {
    final openable = isOpenableSocialLink(widget.platform, _value);
    return _Shell(
      icon: widget.icon,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomText(
                  widget.platform,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: openable
                      ? () => openSocialLink(widget.platform, _value)
                      : null,
                  child: CustomText(
                    _value,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: openable
                        ? AppColors.primaryBlue
                        : AppColors.textPrimary,
                    decoration:
                        openable ? TextDecoration.underline : TextDecoration.none,
                    decorationColor: AppColors.primaryBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TextAction(
            label: TKeys.edit.tr,
            icon: Icons.edit_outlined,
            color: AppColors.textSecondary,
            onTap: _startEditing,
          ),
        ],
      ),
    );
  }

  /// The editable field, plus Done / Remove.
  Widget _editor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AuthTextField(
          controller: widget.controller,
          icon: widget.icon,
          hint: widget.hint,
          keyboardType: widget.keyboardType,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_value.isNotEmpty)
              _TextAction(
                label: TKeys.removeAction.tr,
                icon: Icons.delete_outline_rounded,
                color: AppColors.vipps,
                onTap: _remove,
              ),
            const SizedBox(width: 12),
            _TextAction(
              label: TKeys.doneAction.tr,
              icon: Icons.check_rounded,
              color: AppColors.primaryBlue,
              onTap: _finishEditing,
            ),
          ],
        ),
      ],
    );
  }
}

/// The input-shaped container the non-editing states sit in, so a link row
/// lines up with the real [AuthTextField] above and below it.
class _Shell extends StatelessWidget {
  const _Shell({required this.icon, required this.child});
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Small icon + label button used for Add / Edit / Done / Remove.
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String       label;
  final IconData     icon;
  final Color        color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            CustomText(
              label,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
