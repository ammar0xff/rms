import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';

void main() {
  testWidgets('boots the shell and shows the dashboard', (tester) async {
    await tester.pumpWidget(const RmsApp());
    expect(find.text('Dashboard'), findsWidgets);
  });
}
