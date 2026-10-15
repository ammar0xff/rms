import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';

AppServices _demoServices() => AppServices(
      config: const FirebaseConfig.empty(),
      auth: DemoAuthRepository(),
      firebaseReady: false,
    );

void main() {
  testWidgets('boots to sign-in, authenticates, then shows the dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(RmsApp(services: _demoServices()));
    await tester.pumpAndSettle();

    expect(find.text('أهلاً بيك'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'ammar@rms.dev');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.text('ادخل'));
    await tester.pumpAndSettle();

    expect(find.text('لوحة التحكم'), findsWidgets);
  });
}
