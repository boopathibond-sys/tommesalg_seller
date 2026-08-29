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
    final shipping = p?.shippingPriceNok;
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
                  color: AppColors.inputBorder,
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
            _Label(TKeys.sasAuctionType.tr),
            const SizedBox(height: 8),
            Row(
              children: [
                _TypeChip(
                  // Backend type stays 'NORMAL'; sellers see it as "Regular".
                  label: TKeys.sasRegular.tr,
                  selected: _type == 'NORMAL',
                  onTap: () => setState(() => _type = 'NORMAL'),
                ),
                const SizedBox(width: 10),
                _TypeChip(
                  label: TKeys.sasDutch.tr,
                  selected: _type == 'DUTCH',
                  onTap: () => setState(() => _type = 'DUTCH'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Label(TKeys.sasDuration.tr),
                CustomText('${_duration.round()}s', fontSize: 14,
                    fontWeight: FontWeight.w800, color: AppColors.brandNavy),
              ],
            ),
            Slider(
              value: _duration,
              min: 10, max: 60, divisions: 50,
              activeColor: AppColors.brandNavy,
              label: '${_duration.round()}s',
              onChanged: (v) => setState(() => _duration = v),
            ),
            const SizedBox(height: 6),
            _Label(TKeys.sasStartingPriceOptional.tr),
            const SizedBox(height: 6),
            _Field(controller: _startingPrice, hint: 'kr', number: true),
            const SizedBox(height: 14),
            if (_type == 'NORMAL') ...[
              const _Label('Bid increment (optional)'),
              const SizedBox(height: 6),
              _Field(controller: _bidIncrement, hint: 'kr', number: true),
              const SizedBox(height: 14),
            ],
            const _Label('Shipping price'),
            const SizedBox(height: 6),
            _ShippingDropdown(
              value: _shipping,
              options: _shippingOptions,
              onChanged: (v) => setState(() => _shipping = v),
            ),
            const SizedBox(height: 20),
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
                    const Icon(Icons.play_arrow_rounded, color: AppColors.brandYellow),
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
        color: AppColors.brandNavy.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brandNavy, width: 1.3),
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

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => CustomText(text,
      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brandNavy : AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brandNavy : AppColors.inputBorder,
              width: 1.2,
            ),
          ),
          child: CustomText(label, fontSize: 14, fontWeight: FontWeight.w700,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey.withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<num>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
          items: [
            for (final o in options)
              DropdownMenuItem<num>(value: o, child: Text(_nok(o))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Shipping tier label — "99 NOK", with decimals kept only when they exist.
String _nok(num v) => '${v % 1 == 0 ? v.toInt() : v} NOK';

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.number = false,
  });
  final TextEditingController controller;
  final String hint;
  final bool number;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      cursorColor: AppColors.brandNavy,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
          color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF6F7F9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.grey.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.grey.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brandNavy, width: 1.4),
        ),
      ),
    );
  }
}
