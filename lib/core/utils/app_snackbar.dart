import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// The app's one pop-up message. Every warning / success / error slides up
/// from the bottom (with a little breathing room above the edge), stays a
/// moment, then slides back down.
///
/// Mirrors [Get.snackbar]'s arguments so call sites read the same. Any
/// [snackPosition] passed is ignored — the whole app shows these at the
/// bottom.
class AppSnackbar {
  AppSnackbar._();

  static SnackbarController show(
    String title,
    String message, {
    Color? backgroundColor,
    Color? colorText,
    Duration? duration,
    SnackPosition? snackPosition,
  }) {
    // One at a time — a new message replaces the current one instead of
    // queueing behind it.
    Get.closeAllSnackbars();

    return Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: backgroundColor ?? const Color(0xE6323232),
      colorText: colorText ?? Colors.white,
      duration: duration ?? const Duration(seconds: 3),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      borderRadius: 12,
      animationDuration: const Duration(milliseconds: 350),
      forwardAnimationCurve: Curves.easeOutCubic,
      reverseAnimationCurve: Curves.easeInCubic,
      isDismissible: true,
      dismissDirection: DismissDirection.down,
    );
  }
}
