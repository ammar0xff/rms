import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/theme/app_colors.dart';
import 'package:rms/src/core/theme/app_text.dart';
import 'package:rms/src/domain/models/delivery.dart';
import 'package:rms/src/features/delivery/trip_phase_rail.dart';

void main() {
  group('trip phases derive from the stop state', () {
    test('every open state maps onto a phase', () {
      expect(TripPhaseX.of(DeliveryState.waiting), TripPhase.pickedUp);
      expect(TripPhaseX.of(DeliveryState.assigned), TripPhase.pickedUp);
      expect(TripPhaseX.of(DeliveryState.onRoute), TripPhase.atCustomer);
      expect(TripPhaseX.of(DeliveryState.delivered), TripPhase.handedOver);
    });

    test('a stop that left the happy path has no phase', () {
      // A failed stop is not "stuck on a phase" — the rail must disappear
      // rather than sit at 2 of 4 forever implying progress is still possible.
      expect(TripPhaseX.of(DeliveryState.failed), isNull);
      expect(TripPhaseX.of(DeliveryState.returned), isNull);
    });

    test('the four phases are labelled in the design\'s order', () {
      expect(
        TripPhase.values.map((p) => p.label),
        ['تم الاستلام', 'في الطريق', 'عند العميل', 'تسليم وكش'],
      );
    });
  });

  group('the rail renders', () {
    Future<void> pump(WidgetTester tester, DeliveryState state) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: AppColors.base,
            body: TripPhaseRail(state: state),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an en-route stop shows phase 3 of 4', (tester) async {
      await pump(tester, DeliveryState.onRoute);

      expect(find.text('حالة المشوار'), findsOneWidget);
      expect(find.text('مرحلة 3 من 4'), findsOneWidget);
      for (final phase in TripPhase.values) {
        expect(find.text(phase.label), findsOneWidget);
      }
    });

    testWidgets('a delivered stop shows the final phase', (tester) async {
      await pump(tester, DeliveryState.delivered);
      expect(find.text('مرحلة 4 من 4'), findsOneWidget);
    });

    testWidgets('a failed stop renders nothing', (tester) async {
      await pump(tester, DeliveryState.failed);
      expect(find.byType(TripPhaseRail), findsNothing);
      expect(find.text('حالة المشوار'), findsNothing);
    });

    testWidgets('the rail fits a narrow screen without overflowing',
        (tester) async {
      await pump(tester, DeliveryState.onRoute);
      // A row of four Arabic labels is the overflow risk; the labels wrap
      // inside their own third instead.
      expect(tester.takeException(), isNull);
      final labels = tester
          .widgetList<Text>(find.text('عند العميل'))
          .toList();
      expect(labels, hasLength(1));
      expect(labels.first.style?.fontSize, 10);
      expect(labels.first.style?.fontSize, lessThan(AppText.body.fontSize!));
    });
  });
}
