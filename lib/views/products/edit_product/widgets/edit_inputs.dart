import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../core/localization/translation_keys.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';

/// Building blocks shared by every section of the product edit screen, so the
/// sections themselves only describe *which* fields go where.

/// Light canvas the section cards sit on.
const Color editCanvas = Color(0xFFF6F7F9);

/// A titled white card grouping related fields ("Prices", "Sizing", …).
class EditGroup extends StatelessWidget {
  const EditGroup({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.brandNavy),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: CustomText(title,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            EditNote(subtitle!),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// Two fields side by side.
class EditRow extends StatelessWidget {
  const EditRow(this.left, this.right, {super.key});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

class EditFieldLabel extends StatelessWidget {
  const EditFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => CustomText(text,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary);
}

class EditNote extends StatelessWidget {
  const EditNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => CustomText(text,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.4,
      color: AppColors.textMuted);
}

enum EditBannerTone { info, warning, locked }

/// Full-width notice: the "edits are logged" note, the locked state, etc.
class EditBanner extends StatelessWidget {
  const EditBanner(
    this.text, {
    super.key,
    this.title,
    this.tone = EditBannerTone.info,
  });

  final String text;
  final String? title;
  final EditBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (tone) {
      EditBannerTone.info => (AppColors.primaryBlue, Icons.info_outline_rounded),
      EditBannerTone.warning => (AppColors.textPrimary, Icons.warning_amber_rounded),
      EditBannerTone.locked => (AppColors.vipps, Icons.lock_outline_rounded),
    };
    final fill = tone == EditBannerTone.warning
        ? AppColors.brandYellow.withOpacity(0.2)
        : color.withOpacity(0.07);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  CustomText(title!,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: color),
                  const SizedBox(height: 3),
                ],
                CustomText(text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                    color: color),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Labelled input styled like the rest of the app's forms.
class EditTextField extends StatelessWidget {
  const EditTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.maxLines = 1,
    this.numeric = false,
    this.integer = false,
    this.maxLength,
    this.autofocus = false,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final int maxLines;
  final bool numeric;
  final bool integer;
  final int? maxLength;
  final bool autofocus;

  /// Unit shown inside the field's end (`kr`, `kg`).
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditFieldLabel(label),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: maxLines > 1 ? 2 : 1,
            maxLength: maxLength,
            autofocus: autofocus,
            cursorColor: AppColors.brandNavy,
            keyboardType: numeric
                ? TextInputType.numberWithOptions(decimal: !integer)
                : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
            inputFormatters:
                integer ? [FilteringTextInputFormatter.digitsOnly] : null,
            textCapitalization: numeric
                ? TextCapitalization.none
                : TextCapitalization.sentences,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: editInputDecoration(hint: hint, suffix: suffix),
          ),
          if (helper != null) ...[
            const SizedBox(height: 5),
            EditNote(helper!),
          ],
        ],
      ),
    );
  }
}

/// Decoration shared by every text input on the edit screen.
InputDecoration editInputDecoration({String? hint, String? suffix}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AppColors.textMuted,
    ),
    suffixText: suffix,
    suffixStyle: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppColors.textMuted,
    ),
    counterText: '',
    isDense: true,
    filled: true,
    fillColor: AppColors.inputFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: border(AppColors.borderGrey),
    enabledBorder: border(AppColors.borderGrey),
    focusedBorder: border(AppColors.brandNavy, 1.4),
  );
}

/// A read-only label/value line, for reference values the API won't take.
class EditReadOnlyValue extends StatelessWidget {
  const EditReadOnlyValue({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: EditFieldLabel(label)),
          CustomText(value,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ],
      ),
    );
  }
}

/// Free-text chip list — type a value, tap Add, get a chip.
class EditChipInput extends StatefulWidget {
  const EditChipInput({
    super.key,
    required this.label,
    required this.values,
    required this.onAdd,
    required this.onRemove,
    this.hint,
  });

  final String label;
  final List<String> values;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final String? hint;

  @override
  State<EditChipInput> createState() => _EditChipInputState();
}

class _EditChipInputState extends State<EditChipInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    widget.onAdd(value);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditFieldLabel(widget.label),
          const SizedBox(height: 8),
          if (widget.values.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in widget.values)
                  _Chip(label: value, onRemove: () => widget.onRemove(value)),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  cursorColor: AppColors.brandNavy,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  decoration: editInputDecoration(hint: widget.hint),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandNavy,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: CustomText(TKeys.addAction.tr,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.brandNavy,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomText(label,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.white),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  size: 13, color: AppColors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable pill — used for the fixed shipping amounts.
class EditChoicePill extends StatelessWidget {
  const EditChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandNavy : AppColors.inputFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.brandNavy : AppColors.borderGrey,
          ),
        ),
        child: CustomText(label,
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: selected ? AppColors.white : AppColors.textPrimary),
      ),
    );
  }
}

/// Navy action button — full width by default, hug-content in the save bar.
class EditPrimaryButton extends StatelessWidget {
  const EditPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
    this.expand = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool loading;
  final bool enabled;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final off = !enabled || loading;
    return Opacity(
      opacity: off ? 0.5 : 1,
      child: GestureDetector(
        onTap: off ? null : onTap,
        child: Container(
          width: expand ? double.infinity : null,
          height: 48,
          padding: expand ? null : const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.brandNavy,
            borderRadius: BorderRadius.circular(14),
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(AppColors.white),
                  ),
                )
              : CustomText(label,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white),
        ),
      ),
    );
  }
}
