import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/di/app_services.dart';
import 'core/sound/pie_sound_service.dart';
import 'core/theme/pie_colors.dart';
import 'core/theme/pie_theme.dart';
import 'core/theme/pie_typography.dart';
import 'core/widgets/pie_button.dart';
import 'core/widgets/pie_scaffold.dart';
import 'data/repositories/cash_session_repository.dart';
import 'domain/models/app_role.dart';
import 'domain/models/app_user.dart';
import 'domain/models/cash_session.dart';
import 'features/accounting/invoices_screen.dart';
import 'features/accounting/z_report_screen.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/cashier/cashier_customers_screen.dart';
import 'features/cashier/cashier_settings_screen.dart';
import 'features/delivery/active_trip_screen.dart';
import 'features/delivery/custody_settlement_screen.dart';
import 'features/delivery/driver_profile_screen.dart';
import 'features/delivery/driver_settings_screen.dart';
import 'features/delivery/fleet_screen.dart';
import 'features/delivery/trip_log_screen.dart';
import 'features/manager/approvals_screen.dart';
import 'features/manager/branches_screen.dart';
import 'features/manager/dashboard_screen.dart';
import 'features/manager/inventory_screen.dart';
import 'features/manager/team_screen.dart';
import 'features/manager/triage_screen.dart';
import 'features/pos/pos_screen.dart';
import 'features/shift/open_shift_dialog.dart';
import 'features/shift/shift_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/system/conflicts_screen.dart';
import 'features/system/diagnostics_screen.dart';
import 'features/system/settings_screen.dart';
import 'features/system/updates_screen.dart';

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
  String? _lastUserUid;
  bool _splashCompleted = false;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    // In production without an active session, render the animated splash screen on startup
    if (!services.isDemo && !_splashCompleted && services.auth.currentUser == null) {
      return MaterialApp(
        key: const ValueKey('splash_screen_app'),
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
        home: SplashScreen(
          onLoaded: () {
            if (mounted) setState(() => _splashCompleted = true);
          },
        ),
      );
    }

    return StreamBuilder<AppUser?>(
      stream: services.auth.authStateChanges(),
      initialData: services.auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          _lastUserUid = null;
          _selectedRoleOverride = null;
          return MaterialApp(
            key: const ValueKey('signed_out_app'),
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

        if (_lastUserUid != user.uid) {
          _lastUserUid = user.uid;
          _selectedRoleOverride = null;
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
          key: ValueKey('app_${user.uid}_${activeRole.name}'),
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
            key: ValueKey('shell_${user.uid}_${activeRole.name}'),
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
    super.key,
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
  bool _isLocked = false;

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
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    return Stack(
      children: [
        PieScaffold(
          role: widget.activeRole,
          items: items,
          currentIndex: safeIndex,
          title: items[safeIndex].label,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          onRoleSwitch: widget.onRoleSwitch,
          actions: [
            if (services.cashSessions != null &&
                (widget.activeRole == AppRole.cashier || widget.activeRole == AppRole.manager))
              _TopBarShiftControls(
                services: services,
                isCloseShiftTab: safeIndex == 5 && widget.activeRole == AppRole.cashier,
                onNavigateToCloseShift: () {
                  PieSoundService.instance.click();
                  if (widget.activeRole == AppRole.cashier) {
                    setState(() => _currentIndex = 5);
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ZReportScreen()),
                    );
                  }
                },
                onNavigateToShiftDetails: () {
                  PieSoundService.instance.click();
                  if (widget.activeRole == AppRole.cashier) {
                    setState(() => _currentIndex = 3);
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ShiftScreen()),
                    );
                  }
                },
              ),
            if (isMobile)
              PopupMenuButton<String>(
                tooltip: 'خيارات إضافية',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.more_vert_rounded, color: PieColors.inkSecondary, size: 20),
                color: PieColors.surfaceOverlay,
                onSelected: (val) {
                  if (val == 'lock') {
                    setState(() => _isLocked = true);
                  } else if (val == 'logout') {
                    _confirmSignOut(context, services);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'lock',
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 18, color: PieColors.inkSecondary),
                        SizedBox(width: 8),
                        Text('قفل الشاشة السريع', style: PieTypography.body),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, size: 18, color: PieColors.stateError),
                        SizedBox(width: 8),
                        Text('تسجيل الخروج', style: TextStyle(color: PieColors.stateError)),
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'قفل الشاشة السريع',
                icon: const Icon(Icons.lock_outline_rounded, color: PieColors.inkSecondary, size: 20),
                onPressed: () => setState(() => _isLocked = true),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'تسجيل الخروج',
                icon: const Icon(Icons.logout_rounded, color: PieColors.inkSecondary, size: 20),
                onPressed: () => _confirmSignOut(context, services),
              ),
            ],
            const SizedBox(width: 4),
          ],
          body: IndexedStack(
            index: safeIndex,
            children: screens,
          ),
        ),
        if (_isLocked)
          _buildLockOverlay(context, services),
      ],
    );
  }

  Widget _buildLockOverlay(BuildContext context, AppServices services) {
    final String displayName = (widget.user.displayName != null && widget.user.displayName!.isNotEmpty)
        ? widget.user.displayName!
        : (widget.user.email ?? 'المستخدم');
    final accentColor = PieColors.accentFor(widget.activeRole);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: PieColors.canvas.withValues(alpha: 0.96),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: PieColors.surfaceOverlay,
                borderRadius: PieRadius.borderLg,
                border: Border.all(color: PieColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 32,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      color: accentColor,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'الشاشة مقفلة مؤقتاً',
                    style: PieTypography.heading,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'تم قفل الشاشة لحماية الدرج النقدي والعمليات أثناء مغادرة الجهاز.',
                    style: PieTypography.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: PieColors.surface2,
                      borderRadius: PieRadius.borderMd,
                      border: Border.all(color: PieColors.border),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: accentColor.withValues(alpha: 0.2),
                          child: Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : '؟',
                            style: PieTypography.body.copyWith(
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: PieTypography.body.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                widget.activeRole.name,
                                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PieButton.primary(
                      onPressed: () => setState(() => _isLocked = false),
                      label: 'فتح القفل ومتابعة العمل',
                      icon: Icons.lock_open_rounded,
                      height: 44,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _isLocked = false);
                      _confirmSignOut(context, services);
                    },
                    icon: const Icon(Icons.logout_rounded, size: 16, color: PieColors.inkSecondary),
                    label: Text(
                      'تسجيل الخروج والتبديل لمستخدم آخر',
                      style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, AppServices services) async {
    CashSession? openSession;
    if (services.cashSessions != null) {
      try {
        openSession = await services.cashSessions!.currentSession();
      } catch (_) {}
    }
    final hasOpenSession = openSession != null && openSession.isOpen;

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          shape: const RoundedRectangleBorder(
            borderRadius: PieRadius.borderLg,
            side: BorderSide(color: PieColors.border),
          ),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: PieColors.stateError, size: 22),
              SizedBox(width: 10),
              Text('تسجيل الخروج', style: PieTypography.heading),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل أنت متأكد من تسجيل خروج ${(widget.user.displayName != null && widget.user.displayName!.isNotEmpty) ? widget.user.displayName! : (widget.user.email ?? 'المستخدم')}؟',
                style: PieTypography.body,
              ),
              if (openSession != null && openSession.isOpen) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PieColors.cashierSurface,
                    borderRadius: PieRadius.borderMd,
                    border: Border.all(color: PieColors.cashierAccent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: PieColors.cashierAccent, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'تنبيه: توجد وردية نقدية مفتوحة!',
                            style: TextStyle(
                              color: PieColors.cashierAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'الوردية الحالية مفتوحة برأس مال ${openSession.openingFloat.toStringAsFixed(2)} ج.م'
                        '${openSession.cashierName != null ? ' (المسؤول: ${openSession.cashierName})' : ''}. '
                        'يُفضّل تقفيل الوردية وجرد الدرج (Z-Report) قبل الخروج لضمان عدم تداخل العهد النقدية.',
                        style: PieTypography.caption.copyWith(color: PieColors.ink),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.of(dialogCtx).pop(false);
                            if (widget.activeRole == AppRole.cashier) {
                              setState(() => _currentIndex = 5);
                            } else {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const ZReportScreen()),
                              );
                            }
                          },
                          icon: const Icon(Icons.summarize_rounded, size: 16, color: PieColors.cashierAccent),
                          label: Text(
                            'الانتقال لتقفيل Z الآن',
                            style: PieTypography.caption.copyWith(
                              color: PieColors.cashierAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (widget.activeRole == AppRole.cashier) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PieColors.cashierSurface,
                    borderRadius: PieRadius.borderMd,
                    border: Border.all(color: PieColors.cashierAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: PieColors.cashierAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تأكد من تسوية الخزينة وإغلاق الوردية قبل الخروج إذا انتهت فترة عملك.',
                          style: PieTypography.caption.copyWith(color: PieColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(
                'إلغاء',
                style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
              ),
            ),
            PieButton.destructive(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              label: hasOpenSession ? 'متابعة الخروج مع بقاء الوردية' : 'تأكيد الخروج',
              height: 40,
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await services.auth.signOut();
    }
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
              label: 'طيارين الفرع',
              icon: Icons.two_wheeler_outlined,
              selectedIcon: Icons.two_wheeler,
            ),
            PieNavItem(
              label: 'سجل العملاء',
              icon: Icons.people_alt_outlined,
              selectedIcon: Icons.people_alt,
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
            PieNavItem(
              label: 'إعدادات الكاشير',
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
            ),
          ],
          const [
            PosScreen(),
            FleetScreen(),
            CashierCustomersScreen(),
            ShiftScreen(),
            InvoicesScreen(),
            ZReportScreen(),
            CashierSettingsScreen(),
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
              label: 'ملفي وحالتي',
              icon: Icons.badge_outlined,
              selectedIcon: Icons.badge,
            ),
            PieNavItem(
              label: 'إعدادات الكابتن',
              icon: Icons.tune_rounded,
              selectedIcon: Icons.settings,
            ),
          ],
          const [
            ActiveTripScreen(),
            CustodySettlementScreen(),
            TripLogScreen(),
            DriverProfileScreen(),
            DriverSettingsScreen(),
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
              label: 'الفروع',
              icon: Icons.store_mall_directory_outlined,
              selectedIcon: Icons.store_mall_directory,
            ),
            PieNavItem(
              label: 'الطوارئ',
              icon: Icons.crisis_alert_outlined,
              selectedIcon: Icons.crisis_alert,
            ),
            PieNavItem(
              label: 'الإعدادات',
              icon: Icons.tune_outlined,
              selectedIcon: Icons.tune,
            ),
          ],
          const [
            DashboardScreen(),
            ApprovalsScreen(),
            InventoryScreen(),
            TeamScreen(),
            BranchesScreen(),
            TriageScreen(),
            SettingsScreen(),
          ],
        );

      case AppRole.developer:
        return (
          const [
            PieNavItem(
              label: 'التشخيص',
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
              label: 'الإعدادات',
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

class _TopBarShiftControls extends StatefulWidget {
  const _TopBarShiftControls({
    required this.services,
    required this.onNavigateToCloseShift,
    required this.onNavigateToShiftDetails,
    required this.isCloseShiftTab,
  });

  final AppServices services;
  final VoidCallback onNavigateToCloseShift;
  final VoidCallback onNavigateToShiftDetails;
  final bool isCloseShiftTab;

  @override
  State<_TopBarShiftControls> createState() => _TopBarShiftControlsState();
}

class _TopBarShiftControlsState extends State<_TopBarShiftControls> {
  StreamSubscription<CashSession?>? _sessionSubscription;
  Timer? _refreshTimer;
  CashSession? _session;
  double _expectedCash = 0.0;
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _TopBarShiftControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services != widget.services) {
      _sessionSubscription?.cancel();
      _refreshTimer?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    final services = widget.services;
    final repo = services.cashSessions;
    if (repo == null) {
      _isInitialLoading = false;
      return;
    }

    _sessionSubscription?.cancel();
    _sessionSubscription = repo.watchCurrentSession().listen((session) {
      if (!mounted) return;
      setState(() {
        _session = session;
        if (session != null) {
          _isInitialLoading = false;
        }
        if (session == null || !session.isOpen) {
          _expectedCash = 0.0;
        }
      });
      if (session != null && session.isOpen) {
        _updateExpectedCash(session);
      }
    });

    _resolveInitialSession(services, repo);

    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && _session != null && _session!.isOpen) {
        _updateExpectedCash(_session!);
      }
    });
  }

  Future<void> _resolveInitialSession(
    AppServices services,
    CashSessionRepository repo,
  ) async {
    try {
      final session = await repo.currentSession();
      if (session != null) {
        if (mounted) {
          setState(() {
            _session = session;
            _isInitialLoading = false;
          });
          _updateExpectedCash(session);
        }
        return;
      }
    } catch (_) {}

    if (services.firebaseReady && services.inboundSync != null) {
      try {
        await services.inboundSync!.waitForInitialCollection(
          'cashSessions',
          timeout: const Duration(milliseconds: 1800),
        );
        final synced = await repo.currentSession();
        if (mounted) {
          setState(() {
            _session = synced;
            _isInitialLoading = false;
          });
          if (synced != null) _updateExpectedCash(synced);
          return;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isInitialLoading = false;
      });
    }
  }

  Future<void> _updateExpectedCash(CashSession session) async {
    final repo = widget.services.cashSessions;
    if (repo == null) return;
    try {
      final expected = await repo.expectedCash(session);
      if (mounted) {
        setState(() => _expectedCash = expected);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading && _session == null) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: PieColors.inkSecondary,
            ),
          ),
        ),
      );
    }

    final session = _session;
    final hasOpenShift = session != null && session.isOpen;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;
    final isMobile = width < 600;

    if (hasOpenShift) {
      final displayCash = _expectedCash > 0 ? _expectedCash : session.openingFloat;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // نقدية الدرج
          Tooltip(
            message: 'نقدية الدرج: ${PieTypography.formatEgp(displayCash)} — اضغط لعرض تفاصيل الوردية',
            child: InkWell(
              borderRadius: PieRadius.borderSm,
              onTap: widget.onNavigateToShiftDetails,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 10 : (isMobile ? 6 : 8),
                  vertical: isMobile ? 3 : 5,
                ),
                decoration: BoxDecoration(
                  color: PieColors.surface2,
                  borderRadius: PieRadius.borderSm,
                  border: Border.all(color: PieColors.borderMuted),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.point_of_sale_rounded,
                      size: isMobile ? 12 : 14,
                      color: PieColors.cashierAccent,
                    ),
                    const SizedBox(width: 4),
                    if (isDesktop) ...[
                      Text(
                        'نقدية الدرج: ',
                        style: PieTypography.caption.copyWith(
                          color: PieColors.inkSecondary,
                        ),
                      ),
                    ] else if (!isMobile) ...[
                      Text(
                        'الدرج: ',
                        style: PieTypography.caption.copyWith(
                          color: PieColors.inkSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    Text(
                      isMobile
                          ? '${displayCash.toStringAsFixed(0)} ج.م'
                          : PieTypography.formatEgp(displayCash),
                      style: PieTypography.caption.copyWith(
                        color: PieColors.cashierAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 11 : 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: isMobile ? 3 : 6),

          // زر إغلاق الوردية
          if (!widget.isCloseShiftTab) ...[
            if (isDesktop)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onNavigateToCloseShift,
                  borderRadius: PieRadius.borderSm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: PieColors.cashierSurface,
                      borderRadius: PieRadius.borderSm,
                      border: Border.all(
                        color: PieColors.cashierAccent.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lock_clock_rounded,
                          size: 14,
                          color: PieColors.cashierAccent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'إغلاق الوردية',
                          style: PieTypography.caption.copyWith(
                            color: PieColors.cashierAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(32, 32),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(
                  Icons.lock_clock_rounded,
                  size: 18,
                  color: PieColors.cashierAccent,
                ),
                tooltip: 'إغلاق الوردية',
                onPressed: widget.onNavigateToCloseShift,
              ),
          ],
          SizedBox(width: isMobile ? 2 : 4),
        ],
      );
    } else {
      // الوردية مغلقة
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDesktop)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  final session = await OpenShiftDialog.show(context);
                  if (session != null && mounted) {
                    setState(() {
                      _session = session;
                      _isInitialLoading = false;
                    });
                    _updateExpectedCash(session);
                  }
                },
                borderRadius: PieRadius.borderSm,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: PieColors.stateSynced.withValues(alpha: 0.15),
                    borderRadius: PieRadius.borderSm,
                    border: Border.all(
                      color: PieColors.stateSynced.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_open_rounded,
                        size: 14,
                        color: PieColors.stateSynced,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'فتح الوردية',
                        style: PieTypography.caption.copyWith(
                          color: PieColors.stateSynced,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(
                Icons.lock_open_rounded,
                size: 18,
                color: PieColors.stateSynced,
              ),
              tooltip: 'فتح الوردية',
              onPressed: () async {
                final session = await OpenShiftDialog.show(context);
                if (session != null && mounted) {
                  setState(() {
                    _session = session;
                    _isInitialLoading = false;
                  });
                  _updateExpectedCash(session);
                }
              },
            ),
          const SizedBox(width: 4),
        ],
      );
    }
  }
}

