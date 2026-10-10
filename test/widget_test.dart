import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';

void main() {
  testWidgets('shows the POS screen on launch', (tester) async {
    await tester.pumpWidget(const RmsApp());
    expect(find.text('POS'), findsWidgets);
  });
}
