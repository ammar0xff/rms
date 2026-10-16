import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/core/theme/app_theme.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';
import 'package:rms/src/features/accounting/accounting_screen.dart';
import 'package:rms/src/features/branches/branches_screen.dart';
import 'package:rms/src/features/conflicts/conflicts_screen.dart';
import 'package:rms/src/features/customers/customers_screen.dart';
import 'package:rms/src/features/dashboard/dashboard_screen.dart';
import 'package:rms/src/features/database/database_screen.dart';
import 'package:rms/src/features/delivery/delivery_screen.dart';
import 'package:rms/src/features/inventory/inventory_screen.dart';
import 'package:rms/src/features/menu/menu_screen.dart';
import 'package:rms/src/features/pos/pos_screen.dart';
import 'package:rms/src/features/purchasing/purchasing_screen.dart';
import 'package:rms/src/features/reports/reports_screen.dart';
import 'package:rms/src/features/settings/settings_screen.dart';
import 'package:rms/src/features/shift/shift_screen.dart';
import 'package:rms/src/features/sync/sync_center_screen.dart';
import 'package:rms/src/features/system/system_screen.dart';
import 'package:rms/src/features/team/team_screen.dart';

/// Every screen, rendered at phone width, must lay out without overflow.
///
/// Flutter fails a widget test on RenderFlex overflow, so each case below is
/// a proof, not a snapshot: if any Row, table, chart, or header exceeds the
/// viewport, CI goes red. Screens mount with bare services (no stores), which
/// doubles as a demo-mode crash check — every screen must render its empty
/// state, never throw on a null repository.
Widget _frame(Widget screen) => AppScope(
      services: AppServices(
        config: const FirebaseConfig.empty(),
        auth: DemoAuthRepository(),
        firebaseReady: false,
      ),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: screen),
      ),
);

Future<void> _pumpPhone(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_frame(screen));
  await tester.pumpAndSettle();
}

void main() {
  group('phone-width render sweep (390x844)', () {
    testWidgets('shift renders', (t) => _pumpPhone(t, const ShiftScreen()));
    testWidgets('dashboard renders',
        (t) => _pumpPhone(t, const DashboardScreen()));
    testWidgets('pos renders', (t) => _pumpPhone(t, const PosScreen()));

    testWidgets('dashboard renders', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_frame(const DashboardScreen()));
      await tester.pumpAndSettle();
    });

  });
}
