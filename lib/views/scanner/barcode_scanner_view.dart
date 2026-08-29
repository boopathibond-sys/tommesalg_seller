import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../../core/localization/translation_keys.dart';
import 'package:get/get.dart';

/// Full-screen barcode scanner. Drives a live camera feed via mobile_scanner,
/// stops on the first valid detection, and slides the result up from the
/// bottom as a card. The user can rescan or dismiss back to home.
class BarcodeScannerView extends StatefulWidget {
  const BarcodeScannerView({super.key});

  @override
  State<BarcodeScannerView> createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<BarcodeScannerView> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  Barcode? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_result != null) return;
    final codes = capture.barcodes;
    if (codes.isEmpty) return;
    final first = codes.first;
    final rawValue = first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    Barcode resultToStore = first;

    // If scanned code is Code 128, remove the first three letters.
    if (first.format == BarcodeFormat.code128 && rawValue.length >= 3) {
      resultToStore = Barcode(
        format: first.format,
        rawValue: rawValue.substring(3),
        rawDecodedBytes: first.rawDecodedBytes,
        displayValue: first.displayValue,
      );
    }

    setState(() => _result = resultToStore);
    _controller.stop();
  }

  Future<void> _rescan() async {
    setState(() => _result = null);
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          const _ScannerOverlay(),
          _TopBar(controller: _controller),
          if (_result != null)
            _ResultCard(
              barcode: _result!,
              onRescan: _rescan,
              // Pop with the (possibly edited) code so the caller (Products tab)
              // can append it to its list.
              onConfirm: (code) => Navigator.of(context).pop(
                Barcode(
                  format: _result!.format,
                  rawValue: code,
                  rawDecodedBytes: _result!.rawDecodedBytes,
                  displayValue: _result!.displayValue,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar — close button on the left, torch toggle on the right. Sits over
// the camera with a soft scrim so the controls stay legible.
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});
  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          12,
          MediaQuery.of(context).padding.top + 8,
          12,
          12,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
            colors: [Color(0xCC000000), Color(0x00000000)],
          ),
        ),
        child: Row(
          children: [
            _CircleButton(
              icon: Icons.close_rounded,
              onTap: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            CustomText(
              TKeys.scScanBarcode.tr,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            const Spacer(),
            _CircleButton(
              icon: Icons.flash_on_rounded,
              onTap: () => controller.toggleTorch(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData      icon;
  final VoidCallback  onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Aim reticle — a square cut-out with rounded corners drawn over a translucent
// black scrim so the centre of the camera reads as the "scan area".
// ─────────────────────────────────────────────────────────────────────────────
class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final side = c.maxWidth * 0.72;
          return Stack(
            children: [
              CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _ScrimPainter(holeSide: side),
              ),
              Center(
                child: Container(
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.accent, width: 3),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: c.maxHeight / 2 - side / 2 - 44,
                child: Center(
                  child: CustomText(
                    TKeys.scHoldInFrame.tr,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.holeSide});
  final double holeSide;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withOpacity(0.55);
    final outer = Path()..addRect(Offset.zero & size);
    final hole = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width:  holeSide,
        height: holeSide,
      ),
      const Radius.circular(20),
    );
    final cutout = Path()..addRRect(hole);
    final ring = Path.combine(PathOperation.difference, outer, cutout);
    canvas.drawPath(ring, scrim);
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) => old.holeSide != holeSide;
}

// ─────────────────────────────────────────────────────────────────────────────
// Result card — slides up from the bottom once a barcode is detected. Shows
// the raw value + the format (EAN-13, QR, etc.) and lets the user either
// scan another one or finish.
// ─────────────────────────────────────────────────────────────────────────────
class _ResultCard extends StatefulWidget {
  const _ResultCard({
    required this.barcode,
    required this.onRescan,
    required this.onConfirm,
  });

  final Barcode             barcode;
  final VoidCallback        onRescan;
  final ValueChanged<String> onConfirm;

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  late final TextEditingController _codeCtrl;

  @override
  void initState() {
    super.initState();
    // Pre-fill with the scanned code; the user can edit it (digits only).
    _codeCtrl = TextEditingController(text: widget.barcode.rawValue ?? '');
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.only(
            topLeft:  Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.buttonShadow,
              blurRadius: 24,
              offset: Offset(0, -8),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          18,
          24,
          // Lift above the keyboard when the field is focused.
          MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).padding.bottom +
              18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.inputBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppColors.brandNavy,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomText(
                        TKeys.scBarcodeFound.tr,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(height: 2),
                      CustomText(
                        _formatLabel(widget.barcode.format),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            CustomText(
              TKeys.scCodeCaps.tr,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              // Only digits — the user can add or remove numbers.
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: TKeys.scEnterCode.tr,
                filled: true,
                fillColor: AppColors.inputFill,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.inputBorder, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.inputBorder, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.brandNavy, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onRescan,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.brandNavy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: CustomText(
                      TKeys.scScanAgain.tr,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandNavy,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _codeCtrl.text.trim().isEmpty
                        ? null
                        : () => widget.onConfirm(_codeCtrl.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.brandNavy,
                      disabledBackgroundColor: AppColors.accent.withOpacity(0.4),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: CustomText(
                      TKeys.scDone.tr,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandNavy,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatLabel(BarcodeFormat f) {
    switch (f) {
      case BarcodeFormat.qrCode:    return TKeys.scQrCode.tr;
      case BarcodeFormat.ean13:     return 'EAN-13';
      case BarcodeFormat.ean8:      return 'EAN-8';
      case BarcodeFormat.upcA:      return 'UPC-A';
      case BarcodeFormat.upcE:      return 'UPC-E';
      case BarcodeFormat.code128:   return 'Code 128';
      case BarcodeFormat.code39:    return 'Code 39';
      case BarcodeFormat.code93:    return 'Code 93';
      case BarcodeFormat.codabar:   return 'Codabar';
      case BarcodeFormat.itf14:     return 'ITF';
      case BarcodeFormat.dataMatrix: return 'Data Matrix';
      case BarcodeFormat.aztec:     return 'Aztec';
      case BarcodeFormat.pdf417:    return 'PDF417';
      default:                      return TKeys.scBarcode.tr;
    }
  }
}
