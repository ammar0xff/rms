import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/data/repositories/auth_repository.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/app_user.dart';

void main() {
  group('AppRole', () {
    test('parses every role by name and rejects the rest', () {
      for (final role in AppRole.values) {
        expect(AppRole.tryParse(role.name), role);
      }
      expect(AppRole.tryParse('owner'), isNull);
      expect(AppRole.tryParse(''), isNull);
      expect(AppRole.tryParse(null), isNull);
      expect(AppRole.tryParse(42), isNull);
    });

    test('only managers and developers are privileged', () {
      expect(AppRole.manager.isPrivileged, isTrue);
      expect(AppRole.developer.isPrivileged, isTrue);
      expect(AppRole.driver.isPrivileged, isFalse);
      expect(AppRole.cashier.isPrivileged, isFalse);
    });
  });

  group('DemoAuthRepository roles', () {
    Future<AppRole> roleFor(String email) async {
      final repo = DemoAuthRepository();
      final user = await repo.signInWithEmail(email: email, password: 'x');
      // The signed-in user already carries its role, and roleFor agrees.
      expect(user.role, await repo.roleFor(user));
      return user.role;
    }

    test('infers the role from the email convention', () async {
      expect(await roleFor('driver.ahmed@rms.dev'), AppRole.driver);
      expect(await roleFor('cashier.sara@rms.dev'), AppRole.cashier);
      expect(await roleFor('manager@rms.dev'), AppRole.manager);
      expect(await roleFor('dev@rms.dev'), AppRole.developer);
      expect(await roleFor('developer.ops@rms.dev'), AppRole.developer);
    });

    test('defaults to manager so demo stays fully explorable', () async {
      expect(await roleFor('ammar@rms.dev'), AppRole.manager);
    });

    test('matching is case-insensitive and prefix-scoped', () async {
      // 'drivers' is not the driver role; 'devops' is not dev.
      expect(await roleFor('DRIVER.A@rms.dev'), AppRole.driver);
      expect(await roleFor('drivers@rms.dev'), AppRole.manager);
      expect(await roleFor('devops@rms.dev'), AppRole.manager);
    });
  });

  group('role navigation', () {
    AppServices services() => AppServices(
          config: const FirebaseConfig.empty(),
          auth: DemoAuthRepository(),
          firebaseReady: false,
        );

    Future<void> signInAs(WidgetTester tester, String email) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(RmsApp(services: services()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), email);
      await tester.enterText(find.byType(TextField).at(1), 'secret');
      await tester.tap(find.text('ادخل'));
      await tester.pumpAndSettle();
    }

    testWidgets('a driver gets delivery and more, nothing else', (tester) async {
      await signInAs(tester, 'driver.ahmed@rms.dev');

      // Bottom bar: the delivery tab plus المزيد. No POS, no kitchen.
      expect(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('التوصيل'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('المزيد'),
        ),
        findsOneWidget,
      );
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(
        tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .items,
        hasLength(2),
      );
    });

    testWidgets('a cashier lands on the shift board', (tester) async {
      await signInAs(tester, 'cashier.sara@rms.dev');

      // Shift-first: the board is on screen, and the bar carries shift,
      // sale and more — not kitchen or delivery.
      expect(find.text('شيفت النهاردة'), findsOneWidget);
      expect(
        tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .items,
        hasLength(3),
      );
    });

    testWidgets('a developer lands on the system board', (tester) async {
      await signInAs(tester, 'dev@rms.dev');

      expect(find.text('حالة النظام'), findsOneWidget);
      expect(
        tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .items,
        hasLength(3),
      );
    });

    testWidgets('a manager keeps the full bar', (tester) async {
      await signInAs(tester, 'ammar@rms.dev');

      expect(
        tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .items,
        hasLength(4),
      );
    });

    testWidgets('a driver gets a driver-built home, not the ops tables',
        (tester) async {
      await signInAs(tester, 'driver.ahmed@rms.dev');

      // The driver branch renders its own empty state; the 8-column ops
      // table and the drivers panel never mount for this role.
      expect(find.text('مفيش مهمات مفتوحة. يوم موفق!'), findsOneWidget);
      expect(find.text('السائقون'), findsNothing);
      expect(find.text('قائمة تسوية التحصيلات المعلقة'), findsNothing);
    });

    testWidgets('only developers see the database tools', (tester) async {
      await signInAs(tester, 'dev@rms.dev');

      await tester.tap(find.text('المزيد'));
      await tester.pumpAndSettle();

      expect(find.text('قاعدة البيانات'), findsOneWidget);
    });

    testWidgets('managers do not see the database tools', (tester) async {
      await signInAs(tester, 'ammar@rms.dev');

      await tester.tap(find.text('المزيد'));
      await tester.pumpAndSettle();

      expect(find.text('قاعدة البيانات'), findsNothing);
      // But the team screen is shared with managers.
      expect(find.text('الفريق'), findsOneWidget);
    });

    testWidgets('sign-out returns to the sign-in screen', (tester) async {
      await signInAs(tester, 'driver.ahmed@rms.dev');

      await tester.tap(find.text('المزيد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اخرج'));
      await tester.pumpAndSettle();

      // Back where a signed-out operator belongs.
      expect(find.text('ادخل'), findsOneWidget);
    });
  });

  group('Firebase role fallback', () {
    test('an unreadable role resolves to cashier, never throws', () async {
      // No Firestore, no Firebase app: FirebaseFirestore.instance throws, and
      // the lookup degrades instead of taking auth down with it.
      final repo = FirebaseAuthRepositoryShim();
      expect(
        await repo.roleFor(const AppUser(uid: 'u-1')),
        AppRole.cashier,
      );
    });
  });
}

/// FirebaseAuthRepository without any backend: constructing the real one
/// touches FirebaseAuth.instance, which needs a configured app.
class FirebaseAuthRepositoryShim implements AuthRepository {
  @override
  AppUser? get currentUser => null;

  @override
  Stream<AppUser?> authStateChanges() => const Stream.empty();

  @override
  Future<AppUser> signInWithEmail(
          {required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<AppRole> roleFor(AppUser user) async => AppRole.cashier;
}
