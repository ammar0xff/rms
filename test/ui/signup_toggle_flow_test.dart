import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/core/theme/pie_theme.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/facility_settings.dart';
import 'package:rms/src/features/auth/sign_in_screen.dart';
import 'package:rms/src/features/system/diagnostics_screen.dart';
import 'package:rms/src/features/system/settings_screen.dart';

import '../helpers/test_bootstrap.dart';

void main() {
  group('Developer Signup Control & SignInScreen Gating Flow', () {
    testWidgets('SignInScreen shows sign up tab when allowSignUp is true',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );
      await services.facility!.save(const FacilitySettings(allowSignUp: true));

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: PieTheme.themeFor(AppRole.cashier),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: SignInScreen(),
            ),
          ),
        ),
      );
      await tester.pumpFewFrames();

      expect(find.text('تسجيل الدخول'), findsWidgets);
      expect(find.text('إنشاء حساب موظف'), findsOneWidget);
      expect(find.text('التسجيل مغلق'), findsNothing);
    });

    testWidgets('SignInScreen hides sign up tab and shows locked pill when allowSignUp is false',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );
      await services.facility!.save(const FacilitySettings(allowSignUp: false));

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: PieTheme.themeFor(AppRole.cashier),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: SignInScreen(),
            ),
          ),
        ),
      );
      await tester.pumpFewFrames();

      expect(find.text('تسجيل الدخول للمحطة'), findsOneWidget);
      expect(find.text('التسجيل مغلق'), findsOneWidget);
      expect(find.text('إنشاء حساب موظف'), findsNothing);
    });

    testWidgets('DiagnosticsScreen displays signup toggle and switches state on tap',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.developer,
      );
      await services.facility!.save(const FacilitySettings(allowSignUp: true));

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: const MaterialApp(
            home: Scaffold(body: DiagnosticsScreen()),
          ),
        ),
      );
      await tester.pumpFewFrames();

      // Initially enabled
      expect(find.text('تسجيل الموظفين: مفعّل'), findsOneWidget);

      // Tap to toggle
      await tester.tap(find.text('تسجيل الموظفين: مفعّل'));
      await tester.pumpFewFrames();

      // Now disabled
      expect(find.text('تسجيل الموظفين: مغلق'), findsOneWidget);
      final updated = await services.facility!.load();
      expect(updated.allowSignUp, isFalse);
    });

    testWidgets('SettingsScreen has developer signup control card',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.developer,
      );
      await services.facility!.save(const FacilitySettings(allowSignUp: true));

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: const MaterialApp(
            home: Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpFewFrames();

      // Scroll to access control section
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -700));
      await tester.pumpFewFrames();

      expect(find.text('صلاحيات الوصول وتسجيل الموظفين (تحكم المطور والمدير)'), findsOneWidget);
      expect(find.text('السماح بتسجيل موظفين جدد (Sign Up)'), findsOneWidget);
    });
  });
}
