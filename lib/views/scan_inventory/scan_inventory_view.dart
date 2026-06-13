import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../scanner/barcode_scanner_view.dart';

/// A scanned line item: the detected [barcode] plus how many times that same
/// code has been scanned. Quantity starts at 1 and bumps each time the same
/// raw value is scanned again.
class _ScannedItem {
  _ScannedItem({required this.barcode, this.quantity = 1});

  final Barcode barcode;
  int quantity;

  String get code => barcode.rawValue ?? '—';
}

/// Inventory builder driven by the barcode scanner. Opens [BarcodeScannerView],
/// collects each scan into a list, merges duplicates by bumping their quantity,
/// and renders the running list below. Swiping a row left asks to confirm
/// before removing it.
class ScanInventoryView extends StatefulWidget {
  const ScanInventoryView({super.key});

  @override
  State<ScanInventoryView> createState() => _ScanInventoryViewState();
}

class _ScanInventoryViewState extends State<ScanInventoryView> {
  final List<_ScannedItem> _items = [];

  @override
  void initState() {
    super.initState();
    // TODO: remove — dummy rows for testing the delete / swipe flow.
    _items.addAll([
      _ScannedItem(
        barcode: const Barcode(
          format: BarcodeFormat.ean13,
          rawValue: '7039610000019',
          displayValue: '7039610000019',
        ),
        quantity: 3,
      ),
      _ScannedItem(
        barcode: const Barcode(
          format: BarcodeFormat.code128,
          rawValue: 'ABC123456',
          displayValue: 'ABC123456',
        ),
      ),
      _ScannedItem(
        barcode: const Barcode(
          format: BarcodeFormat.qrCode,
          rawValue: 'https://example.com/product/42',
          displayValue: 'https://example.com/product/42',
        ),
        quantity: 2,
      ),
    ]);
  }

  int get _totalUnits =>
      _items.fold(0, (sum, item) => sum + item.quantity);

  Future<void> _openScanner() async {
    final result = await Navigator.of(context).push<Barcode>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerView()),
    );
    if (!mounted || result == null) return;
    _addScan(result);
  }

  /// Adds a freshly scanned [barcode] to the list. If the same raw value is
  /// already present its quantity is incremented instead of adding a dupe.
  void _addScan(Barcode barcode) {
    final raw = barcode.rawValue;
    final existing = raw == null
        ? -1
        : _items.indexWhere((item) => item.barcode.rawValue == raw);

    setState(() {
      if (existing >= 0) {
        _items[existing].quantity++;
      } else {
        _items.insert(0, _ScannedItem(barcode: barcode));
      }
    });
  }

  Future<bool> _confirmDelete(_ScannedItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const CustomText(
          'Delete item?',
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        content: CustomText(
          'Do you want to delete "${item.code}" from the list?',
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const CustomText(
              'Cancel',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const CustomText(
              'Delete',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.vipps,
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _removeItem(_ScannedItem item) {
    setState(() => _items.remove(item));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.brandNavy,
        title: const CustomText(
          'Scan inventory',
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      body: Column(
        children: [
          if (_items.isNotEmpty) _SummaryBar(
            lines: _items.length,
            units: _totalUnits,
          ),
          Expanded(
            child: _items.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      return Dismissible(
                        key: ValueKey(item.code + i.toString()),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmDelete(item),
                        onDismissed: (_) => _removeItem(item),
                        background: const _DeleteBackground(),
                        child: _ScannedRow(item: item),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScanner,
        backgroundColor: AppColors.brandNavy,
        foregroundColor: AppColors.white,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const CustomText(
          'Scan barcode',
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.white,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary bar — quick count of distinct items and total scanned units.
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.lines, required this.units});
  final int lines;
  final int units;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.brandYellow.withOpacity(0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brandYellow.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_rounded,
              size: 18, color: AppColors.brandNavy),
          const SizedBox(width: 10),
          CustomText(
            '$lines item${lines == 1 ? '' : 's'}  •  $units unit${units == 1 ? '' : 's'}',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.brandNavy,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scanned row — code + format on the left, quantity badge on the right.
// ─────────────────────────────────────────────────────────────────────────────
class _ScannedRow extends StatelessWidget {
  const _ScannedRow({required this.item});
  final _ScannedItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inputBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.qr_code_2_rounded,
                size: 22, color: AppColors.brandNavy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  item.code,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                CustomText(
                  _formatLabel(item.barcode.format),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _QtyBadge(quantity: item.quantity),
        ],
      ),
    );
  }
}

class _QtyBadge extends StatelessWidget {
  const _QtyBadge({required this.quantity});
  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brandNavy,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CustomText(
            'x',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
          const SizedBox(width: 2),
          CustomText(
            '$quantity',
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.white,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Swipe-left delete background.
// ─────────────────────────────────────────────────────────────────────────────
class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        color: AppColors.vipps.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, color: AppColors.vipps, size: 22),
          SizedBox(width: 6),
          CustomText(
            'Delete',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.vipps,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state shown before the first scan.
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.brandYellow.withOpacity(0.3),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.qr_code_scanner_rounded,
                  size: 32, color: AppColors.brandNavy),
            ),
            const SizedBox(height: 16),
            const CustomText(
              'No items scanned yet',
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 6),
            const CustomText(
              'Tap "Scan barcode" to start building your list. '
              'Scanning the same code again adds to its quantity.',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              textAlign: TextAlign.center,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatLabel(BarcodeFormat f) {
  switch (f) {
    case BarcodeFormat.qrCode:     return 'QR-kode';
    case BarcodeFormat.ean13:      return 'EAN-13';
    case BarcodeFormat.ean8:       return 'EAN-8';
    case BarcodeFormat.upcA:       return 'UPC-A';
    case BarcodeFormat.upcE:       return 'UPC-E';
    case BarcodeFormat.code128:    return 'Code 128';
    case BarcodeFormat.code39:     return 'Code 39';
    case BarcodeFormat.code93:     return 'Code 93';
    case BarcodeFormat.codabar:    return 'Codabar';
    case BarcodeFormat.itf:        return 'ITF';
    case BarcodeFormat.dataMatrix: return 'Data Matrix';
    case BarcodeFormat.aztec:      return 'Aztec';
    case BarcodeFormat.pdf417:     return 'PDF417';
    default:                       return 'Strekkode';
  }
}
