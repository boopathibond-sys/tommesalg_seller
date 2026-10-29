import 'package:flutter_test/flutter_test.dart';
import 'package:tommesalg_seller_app/views/auth/reset_password_view.dart';

/// The client check must match the backend's rule (MOBILE_LOGIN_API_FLOW §4.1):
/// 6–128 chars with a lowercase, an uppercase, a digit and a symbol.
void main() {
  bool ok(String p) => ResetPasswordView.meetsPasswordPolicy(p);

  test('accepts a password with every character class', () {
    expect(ok('Abc12!'), isTrue);
    expect(ok('SecurePass1!'), isTrue);
  });

  test('rejects a missing character class', () {
    expect(ok('abcde1!'), isFalse, reason: 'no uppercase');
    expect(ok('ABCDE1!'), isFalse, reason: 'no lowercase');
    expect(ok('Abcdef!'), isFalse, reason: 'no digit');
    expect(ok('Abcde12'), isFalse, reason: 'no symbol');
  });

  test('enforces the 6–128 length bounds', () {
    expect(ok('Ab1!x'), isFalse);
    expect(ok('Ab1!${'x' * 124}'), isTrue);
    expect(ok('Ab1!${'x' * 125}'), isFalse);
  });
}
