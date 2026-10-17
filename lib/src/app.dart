import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/di/app_services.dart';
import 'core/theme/pie_colors.dart';
import 'core/theme/pie_theme.dart';
import 'core/widgets/pie_scaffold.dart';
import 'domain/models/app_role.dart';
import 'domain/models/app_user.dart';
import 'features/accounting/invoices_screen.dart';
import 'features/accounting/z_report_screen.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/delivery/active_trip_screen.dart';
import 'features/delivery/custody_settlement_screen.dart';
import 'features/delivery/fleet_screen.dart';
import 'features/delivery/trip_log_screen.dart';
import 'features/manager/approvals_screen.dart';
import 'features/manager/branches_screen.dart';
import 'features/manager/dashboard_screen.dart';
import 'features/manager/inventory_screen.dart';
import 'features/manager/team_screen.dart';
import 'features/manager/triage_screen.dart';
import 'features/pos/pos_screen.dart';
import 'features/shift/shift_screen.dart';
import 'features/system/conflicts_screen.dart';
import 'features/system/diagnostics_screen.dart';
import 'features/system/settings_screen.dart';
import 'features/system/updates_screen.dart';
import 'features/tables/tables_screen.dart';

/// The root application widget for PIE Operations.
class RmsApp extends StatelessWidget {
  const RmsApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  AppRole? _selectedRoleOverride;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return StreamBuilder<AppUser?>(
      stream: services.auth.authStateChanges(),
      initialData: services.auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          return MaterialApp(
            title: 'PIE Operations',
            debugShowCheckedModeBanner: false,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: PieTheme.themeFor(AppRole.cashier),
            home: const SignInScreen(),
          );
        }

        // The role comes from the signed-in user's server-side document.
        // It may only be overridden in demo mode, where the repository infers
        // the role from the email and switching is the intended way to walk
        // the apps. In a real session, letting a client pick its own role
        // would let any operator grant themselves manager — approving their
        // own refunds, reading the team roster, opening diagnostics.
        final demo = services.isDemo;
        final activeRole = demo ? (_selectedRoleOverride ?? user.role) : user.role;

        return MaterialApp(
          title: 'PIE Operations',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: PieTheme.themeFor(activeRole),
          home: _RoleShell(
            user: user,
            activeRole: activeRole,
            // Null outside demo mode: the scaffold then renders no switcher
            // at all, so there is no control to tap.
            onRoleSwitch: demo
                ? (newRole) {
                    setState(() {
                      _selectedRoleOverride = newRole;
                    });
                  }
                : null,
          ),
        );
      },
    );
  }
}

class _RoleShell extends StatefulWidget {
  const _RoleShell({
    required this.user,
    required this.activeRole,
    required this.onRoleSwitch,
  });

  final AppUser user;
  final AppRole activeRole;
  /// Null outside demo mode, which is what removes the switcher.
  final ValueChanged<AppRole>? onRoleSwitch;

  @override
  State<_RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<_RoleShell> {
  int _currentIndex = 0;

  @override
  void didUpdateWidget(covariant _RoleShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeRole != widget.activeRole) {
      _currentIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final (items, screens) = _buildDestinations(widget.activeRole);

    final safeIndex = _currentIndex < screens.length ? _currentIndex : 0;

    return PieScaffold(
      role: widget.activeRole,
      items: items,
      currentIndex: safeIndex,
      onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
      onRoleSwitch: widget.onRoleSwitch,
      actions: [
        IconButton(
          tooltip: 'تسجيل الخروج',
          icon: const Icon(Icons.logout_rounded, color: PieColors.inkSecondary),
          onPressed: () => services.auth.signOut(),
        ),
        const SizedBox(width: 8),
      ],
      body: IndexedStack(
        index: safeIndex,
        children: screens,
      ),
    );
  }

  (List<PieNavItem>, List<Widget>) _buildDestinations(AppRole role) {
    switch (role) {
      case AppRole.cashier:
        return (
          const [
            PieNavItem(
              label: 'نقطة البيع',
              icon: Icons.point_of_sale_outlined,
              selectedIcon: Icons.point_of_sale,
            ),
            PieNavItem(
              label: 'طاولات الصالة',
              icon: Icons.table_restaurant_outlined,
              selectedIcon: Icons.table_restaurant,
            ),
            PieNavItem(
              label: 'الوردية والخزينة',
              icon: Icons.schedule_outlined,
              selectedIcon: Icons.schedule,
            ),
            PieNavItem(
              label: 'سجل الفواتير',
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long,
            ),
            PieNavItem(
              label: 'تقفيل Z',
              icon: Icons.summarize_outlined,
              selectedIcon: Icons.summarize,
            ),
          ],
          const [
            PosScreen(),
            TablesScreen(),
            ShiftScreen(),
            InvoicesScreen(),
            ZReportScreen(),
          ],
        );

      case AppRole.driver:
        return (
          const [
            PieNavItem(
              label: 'الرحلة الحالية',
              icon: Icons.navigation_outlined,
              selectedIcon: Icons.navigation,
            ),
            PieNavItem(
              label: 'تسوية العهدة',
              icon: Icons.account_balance_wallet_outlined,
              selectedIcon: Icons.account_balance_wallet,
            ),
            PieNavItem(
              label: 'سجل المشاوير',
              icon: Icons.history_outlined,
              selectedIcon: Icons.history,
            ),
            PieNavItem(
              label: 'فريق التوصيل',
              icon: Icons.two_wheeler_outlined,
              selectedIcon: Icons.two_wheeler,
            ),
          ],
          const [
            ActiveTripScreen(),
            CustodySettlementScreen(),
            TripLogScreen(),
            FleetScreen(),
          ],
        );

      case AppRole.manager:
        return (
          const [
            PieNavItem(
              label: 'المؤشرات',
              icon: Icons.dashboard_outlined,
              selectedIcon: Icons.dashboard,
            ),
            PieNavItem(
              label: 'الموافقات',
              icon: Icons.approval_outlined,
              selectedIcon: Icons.approval,
            ),
            PieNavItem(
              label: 'المخزون',
              icon: Icons.inventory_2_outlined,
              selectedIcon: Icons.inventory_2,
            ),
            PieNavItem(
              label: 'فريق العمل',
              icon: Icons.people_outline,
              selectedIcon: Icons.people,
            ),
            PieNavItem(
              label: 'الفروع والتحويلات',
              icon: Icons.store_mall_directory_outlined,
              selectedIcon: Icons.store_mall_directory,
            ),
            PieNavItem(
              label: 'طوارئ الفروع',
              icon: Icons.crisis_alert_outlined,
              selectedIcon: Icons.crisis_alert,
            ),
          ],
          const [
            DashboardScreen(),
            ApprovalsScreen(),
            InventoryScreen(),
            TeamScreen(),
            BranchesScreen(),
            TriageScreen(),
          ],
        );

      case AppRole.developer:
        return (
          const [
            PieNavItem(
              label: 'التشخيص والمزامنة',
              icon: Icons.monitor_heart_outlined,
              selectedIcon: Icons.monitor_heart,
            ),
            PieNavItem(
              label: 'التعارضات',
              icon: Icons.merge_type_outlined,
              selectedIcon: Icons.merge_type,
            ),
            PieNavItem(
              label: 'التحديثات',
              icon: Icons.system_update_alt_outlined,
              selectedIcon: Icons.system_update_alt,
            ),
            PieNavItem(
              label: 'إعدادات المنشأة',
              icon: Icons.tune_outlined,
              selectedIcon: Icons.tune,
            ),
          ],
          const [
            DiagnosticsScreen(),
            ConflictsScreen(),
            UpdatesScreen(),
            SettingsScreen(),
          ],
        );
    }
  }
}
