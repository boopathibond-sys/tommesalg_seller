/// The S3 key behind [value] — the (percent-decoded) path of a signed URL, or
/// the string itself when it already is a key.
///
/// Endpoints hand back saved images as signed URLs but take bare keys on
/// save, so anything already on the server is converted with this before it
/// is sent back.
///
/// Image-proxy URLs (`https://…/images/v/card/assets/…/x.jpg.webp`) are
/// unwrapped too: the key is the path from `assets/` on, without the `.webp`
/// the proxy appends to a key that already has an image extension.
String s3KeyOf(String value) {
  if (!value.startsWith('http')) return value;
  final segments = Uri.tryParse(value)?.pathSegments;
  if (segments == null || segments.isEmpty) return value;
  var key = segments.join('/');

  final assets = key.indexOf('assets/');
  if (assets > 0) {
    key = key.substring(assets);
    final proxied = RegExp(r'\.(jpe?g|png|webp)\.webp$', caseSensitive: false);
    if (proxied.hasMatch(key)) {
      key = key.substring(0, key.length - '.webp'.length);
    }
  }
  return key;
}
