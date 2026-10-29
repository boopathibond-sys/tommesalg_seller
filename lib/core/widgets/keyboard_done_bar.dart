import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../localization/translation_keys.dart';
import '../theme/app_colors.dart';
import 'custom_text.dart';

/// App-wide "Done" bar that rides on top of the iOS keyboard, so every text
/// field — numeric ones included, which have no return key on iOS — can be
/// dismissed. Mounted once in `GetMaterialApp.builder`; a no-op elsewhere.
///
/// The bar's height is added to the keyboard inset handed down to the app, so
/// scaffolds and bottom sheets that pad by `viewInsets` stay clear of it.
class KeyboardDoneBar extends StatelessWidget {
  const KeyboardDoneBar({super.key, required this.child});

  final Widget child;

  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return child;

    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    if (keyboard <= 0) return child;

    return Stack(
      children: [
        MediaQuery(
          data: media.copyWith(
            viewInsets: media.viewInsets.copyWith(bottom: keyboard + height),
          ),
          child: child,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: keyboard,
          height: height,
          child: Material(
            color: const Color(0xFFF1F2F4),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.inputBorder)),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  child: CustomText(
                    TKeys.doneAction.tr,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
