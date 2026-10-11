import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/repositories/auth_repository.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';

void main() {
  group('DemoAuthRepository', () {
    test('starts signed out', () async {
      final repo = DemoAuthRepository();
      expect(repo.currentUser, isNull);
      expect(await repo.authStateChanges().first, isNull);
    });

    test('rejects empty credentials', () {
      final repo = DemoAuthRepository();
      expect(
        () => repo.signInWithEmail(email: '  ', password: 'x'),
        throwsA(isA<AuthException>()),
      );
    });

    test('signs in and emits a demo user', () async {
      final repo = DemoAuthRepository();
      final emitted = <Object?>[];
      final sub = repo.authStateChanges().listen(emitted.add);

      final user = await repo.signInWithEmail(
        email: 'ammar@rms.dev',
        password: 'secret',
      );

      expect(user.isDemo, isTrue);
      expect(user.email, 'ammar@rms.dev');
      expect(repo.currentUser, user);

      await Future<void>.delayed(Duration.zero);
      expect(emitted, contains(user));
      await sub.cancel();
    });

    test('signOut clears the session', () async {
      final repo = DemoAuthRepository();
      await repo.signInWithEmail(email: 'a@b.com', password: 'x');
      await repo.signOut();
      expect(repo.currentUser, isNull);
    });
  });
}
