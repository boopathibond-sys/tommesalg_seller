import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../data/models/auction_room_snapshot.dart';
import '../../data/services/auction_room_api.dart';
import '../../../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

/// Bottom sheet to configure and start an auction for the queue head.
/// Returns [StartAuctionParams] on confirm, or null on cancel.
class StartAuctionSheet extends StatefulWidget {
  const StartAuctionSheet({super.key, this.nextProduct});
  final AuctionProduct? nextProduct;

  @override
  State<StartAuctionSheet> createState() => _StartAuctionSheetState();
}

class _StartAuctionSheetState extends State<StartAuctionSheet> {
  late String _type = widget.nextProduct?.auctionType ?? 'NORMAL';
  double _duration = 60;
  final _startingPrice = TextEditingController();
  final _bidIncrement = TextEditingController();

  /// Fixed shipping tiers offered by the platform, in NOK.
  static const _shippingTiers = <num>[79, 99, 129, 169, 249];
  static const _defaultShipping = 99;

  /// The tiers plus, if the lot already carries an off-tier price, that price —
  /// so opening the sheet never silently rewrites what the seller configured.
  late final List<num> _shippingOptions;
  late num _shipping;

  @override
  void initState() {
    super.initState();
    final p = widget.nextProduct;
    if (p?.startingPrice != null) _startingPrice.text = '${p!.startingPrice}';
    if (p?.bidIncrement != null) _bidIncrement.text = '${p!.bidIncrement}';
    // Zero (and anything negative) means "no shipping price configured", not a
    // free lot: the API sends 0 for a product the seller never priced, and
    // showing that as the selection would start the auction on a price nobody
    // chose. Treated as absent, so the sheet falls back to the 99 kr tier.
    final raw = p?.shippingPriceNok;
    final shipping = raw != null && raw > 0 ? raw : null;
    _shippingOptions = shipping == null || _shippingTiers.contains(shipping)
        ? _shippingTiers
        : (<num>[..._shippingTiers, shipping]..sort());
    _shipping = shipping ?? _defaultShipping;
  }

  @override
  void dispose() {
    _startingPrice.dispose();
    _bidIncrement.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(context).pop(StartAuctionParams(
      auctionType: _type,
      durationSec: _duration.round(),
      startingPrice: num.tryParse(_startingPrice.text.trim()),
      bidIncrement: num.tryParse(_bidIncrement.text.trim()),
      shippingPriceNok: _shipping,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 20),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderGrey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            CustomText(TKeys.sasStartAuction.tr, fontSize: 20,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            if (widget.nextProduct != null) ...[
              const SizedBox(height: 12),
              _ProductDetailsCard(product: widget.nextProduct!),
            ],
            const SizedBox(height: 18),
            _FieldBox(
              label: TKeys.sasAuctionType.tr,
              child: Row(
                children: [
                  _TypeChip(
                    // Backend type stays 'NORMAL'; sellers see it as "Regular".
                    label: TKeys.sasRegular.tr,
                    selected: _type == 'NORMAL',
                    onTap: () => setState(() => _type = 'NORMAL'),
                  ),
                  const SizedBox(width: 8),
                  _TypeChip(
                    label: TKeys.sasDutch.tr,
                    selected: _type == 'DUTCH',
                    onTap: () => setState(() => _type = 'DUTCH'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FieldBox(
              label: TKeys.sasDuration.tr,
              // The seconds read as the field's value, so they sit on the
              // label line where every other box shows what it holds.
              trailing: CustomText('${_duration.round()}s',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                  inactiveTrackColor: AppColors.borderGrey,
                ),
                child: Slider(
                  value: _duration,
                  min: 10,
                  max: 60,
                  divisions: 50,
                  activeColor: AppColors.brandNavy,
                  label: '${_duration.round()}s',
                  onChanged: (v) => setState(() => _duration = v),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FieldBox(
              label: TKeys.sasStartingPriceOptional.tr,
              child: _Field(controller: _startingPrice, number: true),
            ),
            if (_type == 'NORMAL') ...[
              const SizedBox(height: 12),
              _FieldBox(
                label: TKeys.sasBidIncrementOptional.tr,
                child: _Field(controller: _bidIncrement, number: true),
              ),
            ],
            const SizedBox(height: 12),
            _FieldBox(
              label: TKeys.fieldShippingPrice.tr,
              child: _ShippingDropdown(
                value: _shipping,
                options: _shippingOptions,
                onChanged: (v) => setState(() => _shipping = v),
              ),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: _confirm,
              child: Container(
                width: double.infinity,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandNavy,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow_rounded,
                        color: AppColors.brandYellow),
                    const SizedBox(width: 8),
                    CustomText(TKeys.sasStartAuction.tr, fontSize: 15,
                        fontWeight: FontWeight.w800, color: AppColors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One form row: a white box with a hairline grey border, its label small and
/// muted along the top and the value under it.
///
/// Every control in the sheet wears this — text fields, the type chips, the
/// duration slider, the shipping picker — so the form reads as one column of
/// identical cards rather than a stack of differently-shaped widgets.
class _FieldBox extends StatelessWidget {
  const _FieldBox({required this.label, required this.child, this.trailing});
  final String label;
  final Widget child;

  /// Optional value shown on the label line, for controls whose value isn't
  /// text the seller types (the duration slider).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGrey, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: CustomText(label,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}

/// Highlighted, bordered summary of the lot about to be auctioned — its name
/// plus the starting / Dutch / original prices (whichever the queue provides).
class _ProductDetailsCard extends StatelessWidget {
  const _ProductDetailsCard({required this.product});
  final AuctionProduct product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGrey, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(TKeys.sasProduct.tr, fontSize: 11,
              fontWeight: FontWeight.w700, color: AppColors.textMuted),
          const SizedBox(height: 3),
          CustomText(p.title.isEmpty ? TKeys.ltCurrentLot.tr : p.title,
              fontSize: 15, fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          if (p.startingPrice != null || p.dutchPrice != null ||
              p.originalPrice != null) ...[
            const SizedBox(height: 10),
            if (p.startingPrice != null)
              _PriceRow(
                  label: TKeys.sasStartingPrice.tr,
                  value: _price(p.startingPrice!)),
            if (p.dutchPrice != null)
              _PriceRow(
                  label: TKeys.sasDutchPrice.tr, value: _price(p.dutchPrice!)),
            if (p.originalPrice != null)
              _PriceRow(
                label: TKeys.sasOriginalPrice.tr,
                value: _price(p.originalPrice!),
                muted: true,
                strikethrough: true,
              ),
          ],
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    this.muted = false,
    this.strikethrough = false,
  });
  final String label;
  final String value;
  final bool muted;
  final bool strikethrough;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CustomText(label, fontSize: 13, fontWeight: FontWeight.w600,
              color: AppColors.textSecondary),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: muted ? FontWeight.w600 : FontWeight.w800,
              color: muted ? AppColors.textMuted : AppColors.brandNavy,
              decoration:
                  strikethrough ? TextDecoration.lineThrough : TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// Norwegian price format: space thousands separator, comma decimals, `kr`
/// suffix — e.g. 2070 → "2 070,00 kr".
String _price(num v) {
  final fixed = v.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final intPart = fixed.substring(0, dot);
  final dec = fixed.substring(dot + 1);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(' ');
    buf.write(intPart[i]);
  }
  return '$buf,$dec kr';
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brandNavy : AppColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.brandNavy : AppColors.borderGrey,
              width: 1.2,
            ),
          ),
          child: CustomText(label, fontSize: 13.5, fontWeight: FontWeight.w700,
              color: selected ? AppColors.white : AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// Shipping price picker — the platform's fixed NOK tiers, styled to match
/// [_Field] so the sheet reads as one form.
class _ShippingDropdown extends StatelessWidget {
  const _ShippingDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final num value;
  final List<num> options;
  final ValueChanged<num> onChanged;

  @override
  Widget build(BuildContext context) {
    // Bare, like [_Field]: the [_FieldBox] around it owns the border.
    return DropdownButtonHideUnderline(
      child: DropdownButton<num>(
        value: value,
        isExpanded: true,
        isDense: true,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(12),
        icon: const Icon(Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary),
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        items: [
          for (final o in options)
            DropdownMenuItem<num>(value: o, child: Text(_nok(o))),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// Shipping tier label — "99 NOK", with decimals kept only when they exist.
String _nok(num v) => '${v % 1 == 0 ? v.toInt() : v} NOK';

class _Field extends StatelessWidget {
  const _Field({required this.controller, this.number = false});
  final TextEditingController controller;
  final bool number;

  @override
  Widget build(BuildContext context) {
    // No border, fill or padding of its own — the [_FieldBox] around it draws
    // the box, so the input is just the value line inside it.
    return TextField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      cursorColor: AppColors.brandNavy,
      style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      decoration: const InputDecoration(
        hintText: '0',
        hintStyle: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMuted),
        // NOK, always — the seller never types the unit.
        suffixText: 'kr',
        suffixStyle: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        isDense: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }
}
