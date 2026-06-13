import 'package:flutter/material.dart';

/// App-wide replacement for Flutter's [Text] widget.
///
/// Pass the values you care about; the rest fall through to sensible
/// defaults. Mirrors the flat-parameter pattern used across our other
/// projects so call sites stay tight and uniform.
class CustomText extends StatelessWidget {
  final String? title;
  final Color? color;
  final FontWeight? fontWeight;
  final String? fontFamily;
  final double? fontSize;
  final TextAlign? textAlign;
  final double? height;
  final FontStyle? fontStyle;
  final TextOverflow? overflow;
  final int? maxLines;
  final TextDecoration? decoration;
  final double? letterSpacing;
  final Color? decorationColor;
  final TextDecorationStyle? decorationStyle;

  const CustomText(
    this.title, {
    super.key,
    this.color,
    this.fontWeight,
    this.fontFamily,
    this.fontSize,
    this.textAlign,
    this.height,
    this.fontStyle,
    this.maxLines,
    this.overflow,
    this.decoration = TextDecoration.none,
    this.letterSpacing,
    this.decorationColor,
    this.decorationStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      title ?? "",
      textAlign: textAlign,
      maxLines: maxLines,
      softWrap: true,
      style: TextStyle(
        color: color ?? Colors.black,
        fontFamily: fontFamily,
        fontWeight: fontWeight ?? FontWeight.w400,
        fontSize: fontSize ?? 14,
        height: height,
        fontStyle: fontStyle,
        overflow: overflow,
        decoration: decoration,
        letterSpacing: letterSpacing,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        decorationThickness: 2,
      ),
    );
  }
}
