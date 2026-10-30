import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/services/pin_service.dart';

void main() {
  group('PinService Security & Lockout Tests (SEC-002)', () {
    setUp(() {
      PinService.resetLockoutForTesting();
    });

    tearDown(() {
      PinService.resetLockoutForTesting();
    });

    test('verify returns false when unconfigured and fails closed (no 1234 backdoor)', () async {
      final service = PinService();
      // Must not allow '1234' when Firestore settings/managerPin is unread or empty
      final result1234 = await service.verify('1234');
      expect(result1234, isFalse, reason: 'Must fail closed; 1234 fallback must be disallowed');

      final result9999 = await service.verify('9999');
      expect(result9999, isFalse);
    });

    test('triggers progressive lockout after repeated failed attempts', () async {
      final service = PinService();
      expect(PinService.isLocked, isFalse);

      // Attempt 1, 2
      await service.verify('0001');
      expect(PinService.isLocked, isFalse);
      await service.verify('0002');
      expect(PinService.isLocked, isFalse);

      // Attempt 3: triggers 30s lockout
      await service.verify('0003');
      expect(PinService.isLocked, isTrue);
      expect(PinService.remainingLockout, isNotNull);
      expect(PinService.remainingLockout!.inSeconds, greaterThan(0));

      // Attempt 4 while locked returns false immediately
      final lockedAttempt = await service.verify('1234');
      expect(lockedAttempt, isFalse);
    });

    test('resetLockoutForTesting clears active lockout', () async {
      final service = PinService();
      await service.verify('1111');
      await service.verify('2222');
      await service.verify('3333');
      expect(PinService.isLocked, isTrue);

      PinService.resetLockoutForTesting();
      expect(PinService.isLocked, isFalse);
      expect(PinService.remainingLockout, isNull);
    });

    test('generateDelegationCode creates random code and verifies single-use', () {
      final code = PinService.generateDelegationCode();
      expect(code, startsWith('DEL-'));
      expect(code.length, 8); // 'DEL-' + 4 digits

      // Verify digits-only match works
      final digits = code.replaceFirst('DEL-', '');
      expect(PinService.verifyDelegationCode(digits), isTrue);

      // Single-use: Second attempt must fail
      expect(PinService.verifyDelegationCode(digits), isFalse);
      expect(PinService.verifyDelegationCode(code), isFalse);
    });

    test('verifyDelegationCode rejects expired delegation code', () {
      final code = PinService.generateDelegationCode(ttl: const Duration(milliseconds: -1));
      expect(PinService.verifyDelegationCode(code), isFalse);
    });
  });
}
