import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/localization/translation_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/seller_product_detail.dart';

/// What the seller picked in [showShippingOptionsSheet].
///
/// Mirrors the two fields the products API actually takes — there is no third
/// state — so the caller can hand it straight to `PATCH .../products/{id}`.
class ShippingChoice {
  const ShippingChoice({required this.useDefault, this.priceNok});

  /// True → the platform's standard price; the override is cleared.
  final bool useDefault;

  /// The seller's own price, only meaningful when [useDefault] is false.
  final num? priceNok;
}

/// Lets the seller change a product's shipping without opening the full edit
/// form: standard platform price, or one of the fixed amounts the platform
/// allows.
///
/// Returns null when the sheet is dismissed or nothing actually changed. The
/// amounts offered are the platform's own `allowedShippingAmountsNok` — this
/// never invents a price, so a seller can't save a figure the backend would
/// reject.
Future<ShippingChoice?> showShippingOptionsSheet({
  required BuildContext context,
  required SellerProductDetail detail,
}) {
  return showModalBottomSheet<ShippingChoice>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ShippingOptionsSheet(detail: detail),
  );
}

class _ShippingOptionsSheet extends StatefulWidget {
  const _ShippingOptionsSheet({required this.detail});

  final SellerProductDetail detail;

  @override
  State<_ShippingOptionsSheet> createState() => _ShippingOptionsSheetState();
}

class _ShippingOptionsSheetState extends State<_ShippingOptionsSheet> {
  late bool _useDefault = !widget.detail.shippingOverrideEnabled;
  late num? _price = widget.detail.shippingPriceNok;

  PlatformShippingSettings? get _platform => widget.detail.platformShipping;

  /// Fixed amounts the platform allows, capped by its per-product maximum —
  /// an amount above the cap would only be bounced back by the API.
  List<num> get _amounts {
    final max = _platform?.maxShippingPerProductNok;
    final all = _platform?.allowedShippingAmountsNok ?? const <num>[];
    if (max == null) return all;
    return all.where((a) => a <= max).toList();
  }

  bool get _canOverride => _platform?.allowSellerOverride ?? false;

  /// Only enabled once the selection differs from what is already in force,
  /// and once a custom choice actually has an amount behind it.
  bool get _canSave {
    if (!_useDefault && _price == null) return false;
    final wasDefault = !widget.detail.shippingOverrideEnabled;
    if (_useDefault != wasDefault) return true;
    return !_useDefault && _price != widget.detail.shippingPriceNok;
  }

  void _submit() {
    if (!_canSave) return;
    Navigator.of(context).pop(
      ShippingChoice(useDefault: _useDefault, priceNok: _useDefault ? null : _price),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final amounts = _amounts;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
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
              CustomText(
                TKeys.shippingChooseOption.tr,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              const SizedBox(height: 14),

              _OptionRow(
                title: TKeys.shippingStandardOption.tr,
                subtitle: _nok(_platform?.defaultShippingPriceNok),
                selected: _useDefault,
                onTap: () => setState(() => _useDefault = true),
              ),
              const SizedBox(height: 10),
              _OptionRow(
                title: TKeys.shippingCustomOption.tr,
                subtitle: _useDefault || _price == null
                    ? TKeys.shippingPickAmount.tr
                    : _nok(_price),
                selected: !_useDefault,
                // The platform can forbid overrides per product; showing the
                // row greyed out says so, where hiding it would just look like
                // a missing feature.
                enabled: _canOverride && amounts.isNotEmpty,
                onTap: () => setState(() {
                  _useDefault = false;
                  _price ??= amounts.isEmpty ? null : amounts.first;
                }),
              ),

              if (!_canOverride) ...[
                const SizedBox(height: 10),
                _Note(TKeys.shippingOverrideLocked.tr),
              ] else if (amounts.isEmpty) ...[
                const SizedBox(height: 10),
                _Note(TKeys.shippingNoAmounts.tr),
              ] else if (!_useDefault) ...[
                const SizedBox(height: 16),
                CustomText(
                  TKeys.allowedAmountsCaps.tr,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final amount in amounts)
                      _AmountChip(
                        label: _nok(amount),
                        selected: amount == _price,
                        onTap: () => setState(() => _price = amount),
                      ),
                  ],
                ),
              ],

              if (_platform?.dailyFreeShippingCapNok != null) ...[
                const SizedBox(height: 14),
                _Note(
                  TKeys.freeShippingAt.trParams(
                    {'cap': _nok(_platform!.dailyFreeShippingCapNok)},
                  ),
                ),
              ],

              const SizedBox(height: 20),
              _SaveButton(
                label: TKeys.continueText.tr,
                enabled: _canSave,
                onTap: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _nok(num? value) {
    if (value == null) return '—';
    return '${value % 1 == 0 ? value.toInt() : value} NOK';
  }
}

/// One radio-style choice row.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = selected && enabled;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: active ? AppColors.brandYellow.withOpacity(0.14) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? AppColors.brandYellow : AppColors.borderGrey,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  active
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: active ? AppColors.brandNavy : AppColors.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomText(
                        title,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(height: 2),
                      CustomText(
                        subtitle,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ],
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

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandYellow : const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.brandNavy.withOpacity(0.25)
                  : AppColors.borderGrey,
            ),
          ),
          child: CustomText(
            label,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? AppColors.brandNavy : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return CustomText(
      text,
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      height: 1.45,
      color: AppColors.textMuted,
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: AppColors.brandNavy,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 52,
            child: Center(
              child: CustomText(
                label,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Collects the edit reason the products API requires on every PATCH.
///
/// A twin of the sheet the full edit form shows, kept here so a shipping change
/// made from the detail page is logged in the seller's edit history exactly
/// like one made from the form — the reason is not something this shorter path
/// gets to skip.
///
/// Returns null when dismissed.
Future<String?> showEditReasonSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _EditReasonSheet(),
  );
}

class _EditReasonSheet extends StatefulWidget {
  const _EditReasonSheet();

  @override
  State<_EditReasonSheet> createState() => _EditReasonSheetState();
}

class _EditReasonSheetState extends State<_EditReasonSheet> {
  // Owned by the sheet's own state so it is disposed after the pop animation,
  // not the moment the show future completes.
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      Get.snackbar(
        TKeys.reasonRequired.tr,
        TKeys.describeChange.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: media.size.height * 0.85 - media.viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
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
                CustomText(
                  TKeys.reasonForChange.tr,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 6),
                CustomText(
                  TKeys.reasonLoggedNote.tr,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 16),
                CustomText(
                  TKeys.whyChange.tr,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reason,
                  maxLines: 3,
                  maxLength: 2000,
                  autofocus: true,
                  cursorColor: AppColors.brandNavy,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: TKeys.whyChangeHint.tr,
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFFF5F6F8),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.borderGrey),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.borderGrey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.brandNavy, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SaveButton(
                  label: TKeys.saveChanges.tr,
                  enabled: true,
                  onTap: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
