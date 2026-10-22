import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/repositories/auth_repository.dart';
import 'package:rms/src/data/repositories/firebase_auth_repository.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/app_user.dart';

/// A backend that records what it was asked and answers as told.
class _Backend implements AuthBackend {
  _Backend({this.signedIn, this.failure});

  AppUser? signedIn;
  String? failure;
  final List<String> calls = [];
  final controller = StreamController<AppUser?>.broadcast();

  @override
  AppUser? get currentUser => signedIn;

  @override
  Stream<AppUser?> authStateChanges() => controller.stream;

  @override
  Future<AppUser?> signIn({
    required String email,
    required String password,
  }) async {
    calls.add('signIn:$email:$password');
    final code = failure;
    if (code != null) throw AuthBackendFailure(code);
    return signedIn;
  }

  @override
  Future<AppUser?> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    calls.add('signUp:$email:$password');
    final code = failure;
    if (code != null) throw AuthBackendFailure(code);
    return signedIn;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    signedIn = null;
    controller.add(null);
  }
}

const _user = AppUser(uid: 'u-1', email: 'am@example.com');

void main() {
  group('authFailureMessage', () {
    // Every code the repository can be handed, and the guarantee that an
    // unrecognised one is never silently swallowed into a generic message —
    // the code has to stay visible or the backend's behaviour is undebuggable.
    test('maps every known code to an operator-facing message', () {
      const expected = {
        'invalid-email': 'صيغة البريد الإلكتروني غير صحيحة.',
        'user-disabled': 'تم تعطيل هذا الحساب.',
        'user-not-found': 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
        'wrong-password': 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
        'invalid-credential': 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
        'too-many-requests': 'محاولات كثيرة. حاول لاحقًا.',
        'network-request-failed': 'تعذّر الاتصال. تحقق من الشبكة.',
        'weak-password': 'كلمة المرور ضعيفة. استخدم 6 أحرف على الأقل.',
        'email-already-in-use': 'هذا البريد مسجّل بالفعل. سجّل الدخول.',
        'operation-not-allowed': 'تسجيل الدخول بالبريد غير مفعّل. راجع الإعدادات.',
        'requires-recent-login': 'سجّل الدخول مجددًا لإتمام هذا الإجراء.',
      };
      expected.forEach((code, message) {
        expect(authFailureMessage(code), message, reason: code);
      });
    });

    // Distinguishing these two would let the form be used to enumerate accounts.
    test('does not reveal whether an account exists', () {
      expect(
        authFailureMessage('user-not-found'),
        authFailureMessage('wrong-password'),
      );
      expect(
        authFailureMessage('user-not-found'),
        authFailureMessage('invalid-credential'),
      );
    });

    test('reports an unrecognised code rather than hiding it', () {
      expect(authFailureMessage('some-new-code'), contains('some-new-code'));
    });
  });

  group('FirebaseAuthRepository', () {
    test('returns the signed-in user', () async {
      final backend = _Backend(signedIn: _user);
      final repo = FirebaseAuthRepository(backend: backend);

      expect(repo.currentUser?.uid, 'u-1');
    });

    test('reports signed out when there is no user', () {
      expect(FirebaseAuthRepository(backend: _Backend()).currentUser, isNull);
    });

    test('signs in and returns the mapped user', () async {
      final backend = _Backend(signedIn: _user);
      final repo = FirebaseAuthRepository(backend: backend);

      final user = await repo.signInWithEmail(
        email: 'am@example.com',
        password: 'hunter2',
      );

      expect(user.uid, 'u-1');
      expect(user.email, 'am@example.com');
    });

    // Whitespace survives a copy-paste from an email client often enough to be
    // worth trimming before it reaches the backend, which rejects it outright.
    test('trims the email before sending it', () async {
      final backend = _Backend(signedIn: _user);
      final repo = FirebaseAuthRepository(backend: backend);

      await repo.signInWithEmail(email: '  am@example.com  ', password: 'pw');

      expect(backend.calls, ['signIn:am@example.com:pw']);
    });

    // The password is never trimmed: leading and trailing spaces are part of
    // it, and silently altering it would turn a typo into a wrong password.
    test('does not alter the password', () async {
      final backend = _Backend(signedIn: _user);
      final repo = FirebaseAuthRepository(backend: backend);

      await repo.signInWithEmail(email: 'a@b.c', password: '  pw  ');

      expect(backend.calls.single, 'signIn:a@b.c:  pw  ');
    });

    test('translates a backend failure into a readable message', () async {
      final backend = _Backend(failure: 'network-request-failed');
      final repo = FirebaseAuthRepository(backend: backend);

      await expectLater(
        repo.signInWithEmail(email: 'a@b.c', password: 'pw'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'تعذّر الاتصال. تحقق من الشبكة.',
          ),
        ),
      );
    });

    test('never leaks the backend code on a known failure', () async {
      for (final code in const [
        'invalid-email',
        'user-disabled',
        'user-not-found',
        'wrong-password',
        'invalid-credential',
        'too-many-requests',
        'network-request-failed',
        'weak-password',
        'email-already-in-use',
        'operation-not-allowed',
        'requires-recent-login',
      ]) {
        final repo = FirebaseAuthRepository(backend: _Backend(failure: code));
        try {
          await repo.signInWithEmail(email: 'a@b.c', password: 'pw');
          fail('expected $code to throw');
        } on AuthException catch (e) {
          expect(e.message, isNot(contains(code)), reason: code);
        }
      }
    });

    // The backend accepted the call but handed back no session. That is not a
    // credential problem and must not be presented as one.
    test('fails when the backend returns no user', () async {
      final repo = FirebaseAuthRepository(backend: _Backend());

      await expectLater(
        repo.signInWithEmail(email: 'a@b.c', password: 'pw'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.message, 'message', 'تعذّر إنشاء الجلسة.'),
        ),
      );
    });

    test('signs out and clears the user', () async {
      final backend = _Backend(signedIn: _user);
      final repo = FirebaseAuthRepository(backend: backend);

      await repo.signOut();

      expect(repo.currentUser, isNull);
      expect(backend.calls, contains('signOut'));
    });

    test('forwards auth state changes', () async {
      final backend = _Backend(signedIn: _user);
      final repo = FirebaseAuthRepository(backend: backend);

      final next = repo.authStateChanges().first;
      backend.controller.add(_user);

      expect((await next)?.uid, 'u-1');
    });

    test('propagates a signed-out event as null', () async {
      final backend = _Backend();
      final repo = FirebaseAuthRepository(backend: backend);

      final next = repo.authStateChanges().first;
      backend.controller.add(null);

      expect(await next, isNull);
    });

    test('infers role from email convention', () {
      expect(inferRoleFromEmail('driver@pie.eg'), AppRole.driver);
      expect(inferRoleFromEmail('driver.ahmed@pie.eg'), AppRole.driver);
      expect(inferRoleFromEmail('manager@pie.eg'), AppRole.manager);
      expect(inferRoleFromEmail('dev@pie.eg'), AppRole.developer);
      expect(inferRoleFromEmail('developer@pie.eg'), AppRole.developer);
      expect(inferRoleFromEmail('cashier@pie.eg'), AppRole.cashier);
      expect(inferRoleFromEmail('unknown@pie.eg'), AppRole.cashier);
    });

    test('resolves role upon sign-in with email', () async {
      const driverUser = AppUser(uid: 'u-driver', email: 'driver@pie.eg');
      final backend = _Backend(signedIn: driverUser);
      final repo = FirebaseAuthRepository(backend: backend);

      final signedIn = await repo.signInWithEmail(
        email: 'driver@pie.eg',
        password: 'password',
      );

      expect(signedIn.role, AppRole.driver);
      expect(signedIn.email, 'driver@pie.eg');
    });

    test('authStateChanges propagates resolved role for user', () async {
      const managerUser = AppUser(uid: 'u-mgr', email: 'manager@pie.eg');
      final backend = _Backend(signedIn: managerUser);
      final repo = FirebaseAuthRepository(backend: backend);

      final next = repo.authStateChanges().first;
      backend.controller.add(managerUser);

      final user = await next;
      expect(user?.role, AppRole.manager);
    });
  });
}
