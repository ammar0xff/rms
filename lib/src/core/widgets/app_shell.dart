import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../../domain/models/app_role.dart';
import '../../domain/models/app_user.dart';
import '../../features/accounting/accounting_screen.dart';
import '../../features/branches/branches_screen.dart';
import '../../features/conflicts/conflicts_screen.dart';
import '../../features/customers/customers_screen.dart';
import '../../features/database/database_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/delivery/delivery_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/team/team_screen.dart';
import '../di/app_services.dart';
import '../../features/menu/menu_screen.dart';
import '../../features/pos/pos_screen.dart';
import '../../features/purchasing/purchasing_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shift/shift_screen.dart';
import '../../features/system/system_screen.dart';
import '../../features/sync/sync_center_screen.dart';
import '../../features/updates/update_controller.dart';
import '../../domain/update/update_prompt_mode.dart';
import '../../features/updates/update_prompt.dart';
import 'buttons.dart';
import 'role_ui.dart';
import 'status.dart';
import 'sync_chip.dart';

class NavEntry {
  const NavEntry(this.id, this.label, this.icon, this.builder);
  final String id;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

class NavGroup {
  const NavGroup(this.label, this.entries);
  final String label;
  final List<NavEntry> entries;
}

final navGroups = <NavGroup>[
  NavGroup('العمليات', [
    NavEntry('shift', 'الوردية', Icons.today_outlined, _shift),
    NavEntry('dashboard', 'لوحة التحكم', Icons.space_dashboard_outlined,
        _dashboard),
    NavEntry('pos', 'نقطة البيع', Icons.point_of_sale_outlined, _pos),
    NavEntry('delivery', 'التوصيل', Icons.moped_outlined, _delivery),
  ]),
  NavGroup('الإدارة', [
    NavEntry('menu', 'القائمة', Icons.restaurant_menu_outlined, _menu),
    NavEntry('inventory', 'المخزون', Icons.inventory_2_outlined, _inventory),
    NavEntry('purchasing', 'المشتريات', Icons.shopping_cart_outlined,
        _purchasing),
    NavEntry('customers', 'العملاء', Icons.people_alt_outlined, _customers),
    NavEntry('accounting', 'المحاسبة', Icons.receipt_long_outlined,
        _accounting),
    NavEntry('reports', 'التقارير', Icons.insights_outlined, _reports),
    NavEntry('branches', 'الفروع', Icons.storefront_outlined, _branches),
  ]),
  NavGroup('النظام', [
    NavEntry('system', 'النظام', Icons.monitor_heart_outlined, _system),
    NavEntry('sync', 'مركز المزامنة', Icons.sync_outlined, _sync),
    NavEntry('database', 'قاعدة البيانات', Icons.storage_outlined, _database),
    NavEntry('conflicts', 'التعارضات', Icons.call_split_outlined, _conflicts),
    NavEntry('team', 'الفريق', Icons.group_outlined, _team),
    NavEntry('settings', 'الإعدادات', Icons.settings_outlined, _settings),
  ]),
];

List<NavEntry> get _flatEntries =>
    [for (final g in navGroups) ...g.entries];

/// Navigation shape per role: bottom tabs, More-grid contents, landing screen.
///
/// The signed-in account is the key to what is displayed: one APK, five
/// different apps sharing a theme. Anything not listed here is unreachable
/// for the role — on narrow screens and, via the filtered sidebar, on wide
/// ones too.
class _RoleNav {
  const _RoleNav({
    required this.tabs,
    required this.more,
    required this.home,
  });

  /// Bottom-bar entry ids, in order.
  final List<String> tabs;

  /// More-grid entry ids, in display order.
  final List<String> more;

  /// Landing entry id.
  final String home;
}

const _allIds = [
  'dashboard', 'pos', 'delivery', 'menu', 'inventory',
  'purchasing', 'customers', 'accounting', 'reports', 'branches',
  'sync', 'conflicts', 'team', 'settings',
];

_RoleNav _navFor(AppRole role) => switch (role) {
      // Mobile-first: deliveries, then everything else behind المزيد.
      AppRole.driver => const _RoleNav(
          tabs: ['delivery'],
          more: ['delivery', 'sync', 'settings'],
          home: 'delivery',
        ),
      AppRole.cashier => const _RoleNav(
          tabs: ['shift', 'pos'],
          more: [
            'shift', 'dashboard', 'pos', 'menu', 'customers', 'sync',
            'settings',
          ],
          home: 'shift',
        ),
      AppRole.manager => const _RoleNav(
          tabs: ['dashboard', 'pos', 'delivery'],
          more: [..._allIds, 'system'],
          home: 'dashboard',
        ),
      AppRole.developer => const _RoleNav(
          tabs: ['system', 'sync'],
          more: [..._allIds, 'database', 'system'],
          home: 'system',
        ),
    };

Widget _dashboard(BuildContext c) => const DashboardScreen();
Widget _pos(BuildContext c) => const PosScreen();
Widget _delivery(BuildContext c) => const DeliveryScreen();
Widget _menu(BuildContext c) => const MenuScreen();
Widget _inventory(BuildContext c) => const InventoryScreen();
Widget _purchasing(BuildContext c) => const PurchasingScreen();
Widget _customers(BuildContext c) => const CustomersScreen();
Widget _accounting(BuildContext c) => const AccountingScreen();
Widget _reports(BuildContext c) => const ReportsScreen();
Widget _branches(BuildContext c) => const BranchesScreen();
Widget _sync(BuildContext c) => const SyncCenterScreen();
Widget _database(BuildContext c) => const DatabaseScreen();
Widget _conflicts(BuildContext c) => const ConflictsScreen();
Widget _team(BuildContext c) => const TeamScreen();
Widget _settings(BuildContext c) => const SettingsScreen();
Widget _shift(BuildContext c) => const ShiftScreen();
Widget _system(BuildContext c) => const SystemScreen();

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _selected = 'dashboard';

  /// Bodies by entry id, kept mounted while the session lasts. Rebuilding the
  /// body on every selection wiped screen state — a half-built POS cart, typed
  /// search, kitchen scroll position — on each tab switch. Cached bodies stay
  /// alive offstage instead; only 'more' rebuilds, since it is stateless and
  /// needs the fresh selection highlight.
  ///
  /// Cleared on every account change: a shared device must never show the
  /// previous operator's screens to the next one.
  final _bodies = <String, Widget>{};

  Widget _bodyFor(String id, BuildContext context) {
    if (id == 'more') {
      final role = _role;
      final user = _user;
      return _MoreScreen(
        allowedIds: role == null ? const {} : {..._navFor(role).more},
        selected: _selected,
        user: user,
        onSelect: _select,
        onSignOut: () => AppScope.of(context).auth.signOut(),
      );
    }
    return _bodies.putIfAbsent(id, () => _entryFor(id).builder(context));
  }

  NavEntry _entryFor(String id) =>
      _flatEntries.firstWhere((e) => e.id == id, orElse: () => _flatEntries.first);

  StreamSubscription<AppUser?>? _authSub;
  String? _authUid;
  AppUser? _user;
  AppRole? _role;

  UpdateController? _updates;
  bool _dismissedOptional = false;

  /// Bottom-bar index: the role's tabs, or المزيد for everything else —
  /// including the menu grid itself.
  int _barIndex(List<String> tabs) {
    final i = tabs.indexOf(_selected);
    return i == -1 ? tabs.length : i;
  }

  void _select(String id) {
    setState(() => _selected = id);
  }

  void _onBarTap(List<String> tabs, int index) {
    _select(index < tabs.length ? tabs[index] : 'more');
  }

  Future<void> _onUser(AppUser? user) async {
    if (!mounted) return;
    if (user?.uid == _authUid && _role != null) return;
    setState(() {
      _authUid = user?.uid;
      _user = user;
      _role = null;
      _bodies.clear();
    });
    if (user == null) return;
    final role =
        await AppScope.of(context).auth.roleFor(user).catchError((_) => AppRole.cashier);
    if (!mounted) return;
    setState(() {
      _role = role;
      _selected = _navFor(role).home;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authSub ??=
        AppScope.of(context).auth.authStateChanges().listen(_onUser);
    if (_updates != null) return;
    final runtime = AppScope.of(context).updateRuntime;
    if (runtime == null) return;
    final controller = UpdateController(runtime: runtime);
    _updates = controller;
    // A check after the first frame, so startup is never blocked on the network.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.refresh());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _updates?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = _role;
    // Role unresolved: the account is the key to what is displayed, so nothing
    // renders before it. This also covers the sign-out gap.
    if (role == null) {
      return const Scaffold(
        backgroundColor: AppColors.base,
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final updates = _updates;
        final nav = _navFor(role);
        // Guard against a selection the role cannot see (e.g. right after the
        // account changed and before the home reset lands).
        final selected =
            (nav.tabs.contains(_selected) || nav.more.contains(_selected) || _selected == 'more')
                ? _selected
                : nav.home;
        final allowed = {...nav.tabs, ...nav.more};
        final sidebarGroups = [
          for (final group in navGroups)
            NavGroup(group.label, [
              for (final entry in group.entries)
                if (allowed.contains(entry.id)) entry,
            ]),
        ]..removeWhere((group) => group.entries.isEmpty);
        // Every visited screen stays mounted offstage; the visible one is the
        // only one laid out. Entries build lazily on first visit (see
        // [_bodies]), so startup still mounts a single screen.
        if (selected != 'more') _bodyFor(selected, context);
        final stacked = Stack(
          children: [
            for (final id in _bodies.keys)
              Offstage(
                offstage: id != selected,
                child: TickerMode(
                  enabled: id == selected,
                  child: _bodies[id]!,
                ),
              ),
            if (selected == 'more') _bodyFor('more', context),
          ],
        );
        final title =
            selected == 'more' ? 'المزيد' : _entryFor(selected).label;
        return Stack(
          children: [
            Scaffold(
              body: SafeArea(
                child: wide
                    ? Row(
                        children: [
                          _Sidebar(
                            groups: sidebarGroups,
                            selected: selected,
                            onSelect: _select,
                            user: _user,
                            accent: roleAccent(role),
                          ),
                          const VerticalDivider(width: 1, color: AppColors.borderStrong),
                          Expanded(
                            child: Column(
                              children: [
                                _TopBar(title: title),
                                const Divider(height: 1, color: AppColors.borderStrong),
                                Expanded(child: stacked),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _TopBar(title: title),
                          const Divider(height: 1, color: AppColors.borderStrong),
                          Expanded(child: stacked),
                        ],
                      ),
              ),
              bottomNavigationBar: wide
                  ? null
                  : BottomNavigationBar(
                      currentIndex: _barIndex(nav.tabs),
                      onTap: (index) => _onBarTap(nav.tabs, index),
                      type: BottomNavigationBarType.fixed,
                      backgroundColor: AppColors.surface,
                      selectedItemColor: roleAccent(role),
                      unselectedItemColor: AppColors.fgMuted,
                      selectedLabelStyle: AppText.label,
                      unselectedLabelStyle: AppText.label,
                      items: [
                        for (final id in nav.tabs)
                          BottomNavigationBarItem(
                            icon: Icon(_entryFor(id).icon),
                            label: _tabLabel(id),
                          ),
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.apps_outlined),
                          activeIcon: Icon(Icons.apps),
                          label: 'المزيد',
                        ),
                      ],
                    ),
            ),
            // A mandatory update, an update in flight, or a finished attempt is
            // laid over the whole app: there is nothing useful to do until it
            // is resolved. Deferring an optional release lasts for the rest of
            // this session — but only for the dismissible prompt. A deferral
            // must never suppress a mandatory release, an in-flight update, or
            // a failure the operator has to see.
            if (updates != null &&
                !(_dismissedOptional &&
                    updates.state.mode == UpdatePromptMode.dismissible))
              UpdatePrompt(
                controller: updates,
                onDismissed: () => setState(() => _dismissedOptional = true),
              ),
          ],
        );
      },
    );
  }
}

/// Short thumb-sized labels for bottom tabs. The full entry labels stay in the
/// sidebar and the More grid, where there is room for them.
String _tabLabel(String id) => switch (id) {
      'shift' => 'الوردية',
      'system' => 'النظام',
      'dashboard' => 'الرئيسية',
      'pos' => 'البيع',
      'delivery' => 'التوصيل',
      'menu' => 'القائمة',
      'sync' => 'المزامنة',
      _ => _flatEntries
          .firstWhere((e) => e.id == id, orElse: () => _flatEntries.first)
          .label,
    };

/// The menu grid behind المزيد: every destination, grouped, thumb-reachable.
///
/// Fourteen entries cannot fit a bottom bar, and the drawer they lived in was
/// built for a mouse. On a phone the overflow belongs in a screen of its own.
class _MoreScreen extends StatelessWidget {
  const _MoreScreen({
    required this.allowedIds,
    required this.selected,
    required this.user,
    required this.onSelect,
    required this.onSignOut,
  });

  final Set<String> allowedIds;
  final String selected;
  final AppUser? user;
  final ValueChanged<String> onSelect;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final role = user?.role ?? AppRole.cashier;
    final name = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : (user?.email ?? '—');
    final groups = [
      for (final group in navGroups)
        NavGroup(group.label, [
          for (final entry in group.entries)
            if (allowedIds.contains(entry.id)) entry,
        ]),
    ]..removeWhere((group) => group.entries.isEmpty);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Identity header: on narrow screens the sidebar (and its user row)
        // does not exist, so this is where the account shows itself — and
        // where a shared device signs out.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.borderStrong),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.hover,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  user?.initials ?? '؟',
                  style: AppText.bodyStrong,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Tag(label: role.label, tone: StatusTone.info),
                  ],
                ),
              ),
              RmsButton(
                label: 'اخرج',
                icon: Icons.logout,
                variant: BtnVariant.ghost,
                onPressed: onSignOut,
              ),
            ],
          ),
        ),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(group.label.toUpperCase(), style: AppText.label),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.92,
            ),
            itemCount: group.entries.length,
            itemBuilder: (context, i) {
              final entry = group.entries[i];
              final active = entry.id == selected;
              return GestureDetector(
                onTap: () => onSelect(entry.id),
                child: Container(
                  decoration: BoxDecoration(
                    color: active ? AppColors.brandSoft : AppColors.surface,
                    border: Border.all(
                      color: active ? AppColors.brandLine : AppColors.borderStrong,
                    ),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        entry.icon,
                        size: 24,
                        color: active ? AppColors.brand : AppColors.fgSecondary,
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          entry.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            fontWeight: FontWeight.w500,
                            color: active ? AppColors.brand : AppColors.fgMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.groups,
    required this.selected,
    required this.onSelect,
    required this.user,
    required this.accent,
  });

  final List<NavGroup> groups;
  final String selected;
  final ValueChanged<String> onSelect;
  final AppUser? user;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.sidebarWidth,
      color: AppColors.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No fixed height: the two header texts must fit whatever the font
          // metrics give them. A rigid 48px box overflowed by 1px the moment
          // the branch name wrapped to two lines.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'R',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFFFBF2),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('RMS',
                          style: AppText.bodyStrong.copyWith(height: 1.1)),
                      Text('فرع بوابة الشمال',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderStrong),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 5),
                    child: Text(group.label.toUpperCase(), style: AppText.label),
                  ),
                  for (final entry in group.entries)
                    _NavTile(
                      entry: entry,
                      active: entry.id == selected,
                      accent: accent,
                      onTap: () => onSelect(entry.id),
                    ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderStrong),
          _UserRow(user: user),
        ],
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({required this.entry, required this.active, required this.accent, required this.onTap});

  final NavEntry entry;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
decoration: BoxDecoration(
              color: active
                  ? widget.accent.withValues(alpha: 0.10)
                  : _hover
                      ? Colors.black.withValues(alpha: 0.03)
                      : null,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
          child: Row(
            children: [
              Icon(
                widget.entry.icon,
                size: 15,
                color: active
                    ? widget.accent
                    : _hover
                        ? AppColors.fgSecondary
                        : AppColors.fgMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.entry.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.navItem.copyWith(
                    color: active ? AppColors.fgBright : AppColors.fgMuted,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final name = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : (user?.email ?? '—');
    final role = user?.role ?? AppRole.cashier;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              color: AppColors.hover,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              (user?.initials ?? '؟'),
              style: AppText.caption,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong,
                ),
                Text(role.label, style: AppText.caption),
              ],
            ),
          ),
          const Icon(Icons.unfold_more, size: 14, color: AppColors.fgGhost),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    // Title plus live sync state on every screen, both widths. The old
    // search and notifications buttons had no handlers and the branch pill
    // was a hardcoded label with a dead dropdown arrow — all three violated
    // the no-dead-controls rule, so all three are gone. Per-screen search
    // lives in ListToolbar, where it filters something real.
    return SizedBox(
      height: AppSpacing.topBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Flexible(
              child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.pageTitle),
            ),
            const Spacer(),
            const SyncChip(),
          ],
        ),
      ),
    );
  }
}
