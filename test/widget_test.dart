import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';

void main() {
  testWidgets('boots the shell and shows the dashboard', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const RmsApp());
    await tester.pumpAndSettle();

    expect(find.text('لوحة التحكم'), findsWidgets);
  });
}
