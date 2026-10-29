import 'dart:developer';
import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Shrinks photos before they are uploaded.
///
/// Re-encodes to JPEG, scaled so the short edge is about [_maxSide] px, so phone
/// shots (often 4–12 MB) land well under the API's 5 MB limit and upload
/// fast. Falls back to the original path if compression fails, so an upload
/// is never blocked by this step.
class ImageCompressor {
  ImageCompressor._();

  static const int _maxSide = 1280;
  static const int _quality = 65;

  /// Returns the path of a compressed JPEG copy of [sourcePath], or
  /// [sourcePath] itself when compression is not possible.
  static Future<String> compress(String sourcePath) async {
    try {
      final dir = Directory.systemTemp;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final target = '${dir.path}/upload_$stamp.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        target,
        minWidth: _maxSide,
        minHeight: _maxSide,
        quality: _quality,
        format: CompressFormat.jpeg,
      );
      if (result == null) return sourcePath;

      final before = await File(sourcePath).length();
      final after = await result.length();
      log('[image-compress] $before → $after bytes');

      // Keep the original if re-encoding somehow made it bigger.
      return after < before ? result.path : sourcePath;
    } catch (e) {
      log('[image-compress] failed, uploading original: $e');
      return sourcePath;
    }
  }
}
