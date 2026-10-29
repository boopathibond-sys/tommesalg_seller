/// Norwegian currency format used for every price in the app:
/// `1485` → `1 485,00 kr`, `-20.5` → `-20,50 kr`.
///
/// Thousands are grouped with a non-breaking space (and one sits before `kr`)
/// so a price never wraps across lines.
String formatNok(num value) {
  final fixed = value.abs().toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final whole = fixed.substring(0, dot);
  final decimals = fixed.substring(dot + 1);

  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(' ');
    grouped.write(whole[i]);
  }
  final sign = value < 0 && fixed != '0.00' ? '-' : '';
  return '$sign$grouped,$decimals kr';
}

/// [formatNok], or `—` when there is no price.
String formatNokOrDash(num? value) =>
    value == null ? '—' : formatNok(value);
