import 'package:flutter_test/flutter_test.dart';
import 'package:saydali_pro/utils/security_helper.dart';

void main() {
  group('SecurityHelper.hashPin + verifyPin', () {
    test('correct PIN verifies', () {
      final hash = SecurityHelper.hashPin('1234');
      expect(SecurityHelper.verifyPin('1234', hash), true);
    });

    test('wrong PIN fails', () {
      final hash = SecurityHelper.hashPin('1234');
      expect(SecurityHelper.verifyPin('5678', hash), false);
    });

    test('empty PIN', () {
      final hash = SecurityHelper.hashPin('');
      expect(SecurityHelper.verifyPin('', hash), true);
      expect(SecurityHelper.verifyPin('1', hash), false);
    });

    test('legacy plaintext compatibility', () {
      expect(SecurityHelper.verifyPin('1234', '1234'), true);
      expect(SecurityHelper.verifyPin('1234', '5678'), false);
    });

    test('different hashes for same PIN (random salt)', () {
      final hash1 = SecurityHelper.hashPin('1234');
      final hash2 = SecurityHelper.hashPin('1234');
      // Both should verify, but hashes should differ (different salts)
      expect(SecurityHelper.verifyPin('1234', hash1), true);
      expect(SecurityHelper.verifyPin('1234', hash2), true);
      expect(hash1, isNot(equals(hash2)));
    });
  });

  group('SecurityHelper.signValue + verifyValue', () {
    test('valid signature', () async {
      final sig = await SecurityHelper.signValue('key', 'value');
      expect(await SecurityHelper.verifyValue('key', 'value', sig), true);
    });

    test('tampered value fails', () async {
      final sig = await SecurityHelper.signValue('key', 'value');
      expect(await SecurityHelper.verifyValue('key', 'tampered', sig), false);
    });

    test('wrong key fails', () async {
      final sig = await SecurityHelper.signValue('key', 'value');
      expect(await SecurityHelper.verifyValue('other', 'value', sig), false);
    });

    test('different calls produce same signature', () async {
      final sig1 = await SecurityHelper.signValue('key', 'value');
      final sig2 = await SecurityHelper.signValue('key', 'value');
      expect(sig1, equals(sig2));
    });
  });
}
