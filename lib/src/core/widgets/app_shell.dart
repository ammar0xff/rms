import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../../features/accounting/accounting_screen.dart';
import '../../features/branches/branches_screen.dart';
import '../../features/conflicts/conflicts_screen.dart';
import '../../features/customers/customers_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/delivery/delivery_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/kitchen/kitchen_screen.dart';
import '../di/app_services.dart';
import '../../features/menu/menu_screen.dart';
import '../../features/pos/pos_screen.dart';
import '../../features/purchasing/purchasing_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/sync/sync_center_screen.dart';
import '../../features/updates/update_controller.dart';
import '../../features/updates/update_prompt.dart';
import 'buttons.dart';
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
    NavEntry('dashboard', 'لوحة التحكم', Icons.space_dashboard_outlined,
        _dashboard),
    NavEntry('pos', 'نقطة البيع', Icons.point_of_sale_outlined, _pos),
    NavEntry('kitchen', 'المطبخ', Icons.soup_kitchen_outlined, _kitchen),
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
    NavEntry('sync', 'مركز المزامنة', Icons.sync_outlined, _sync),
    NavEntry('conflicts', 'التعارضات', Icons.call_split_outlined, _conflicts),
    NavEntry('settings', 'الإعدادات', Icons.settings_outlined, _settings),
  ]),
];

List<NavEntry> get _flatEntries =>
    [for (final g in navGroups) ...g.entries];

Widget _dashboard(BuildContext c) => const DashboardScreen();
Widget _pos(BuildContext c) => const PosScreen();
Widget _kitchen(BuildContext c) => const KitchenScreen();
Widget _delivery(BuildContext c) => const DeliveryScreen();
Widget _menu(BuildContext c) => const MenuScreen();
Widget _inventory(BuildContext c) => const InventoryScreen();
Widget _purchasing(BuildContext c) => const PurchasingScreen();
Widget _customers(BuildContext c) => const CustomersScreen();
Widget _accounting(BuildContext c) => const AccountingScreen();
Widget _reports(BuildContext c) => const ReportsScreen();
Widget _branches(BuildContext c) => const BranchesScreen();
Widget _sync(BuildContext c) => const SyncCenterScreen();
Widget _conflicts(BuildContext c) => const ConflictsScreen();
Widget _settings(BuildContext c) => const SettingsScreen();

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _selected = 'dashboard';

  /// The five thumb-reachable destinations. Everything else lives under المزيد.
  static const _primaryIds = ['dashboard', 'pos', 'kitchen', 'delivery'];

  UpdateController? _updates;
  bool _dismissedOptional = false;

  NavEntry get _current =>
      _flatEntries.firstWhere((e) => e.id == _selected, orElse: () => _flatEntries.first);

  /// Bottom-bar index: the four primaries, or المزيد for everything else —
  /// including the menu grid itself.
  int get _barIndex {
    final i = _primaryIds.indexOf(_selected);
    return i == -1 ? 4 : i;
  }

  void _select(String id) {
    setState(() => _selected = id);
  }

  void _onBarTap(int index) {
    _select(index < 4 ? _primaryIds[index] : 'more');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    _updates?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final updates = _updates;
        final body = _selected == 'more'
            ? _MoreScreen(selected: _selected, onSelect: _select)
            : _current.builder(context);
        return Stack(
          children: [
            Scaffold(
              body: SafeArea(
                child: wide
                    ? Row(
                        children: [
                          _Sidebar(selected: _selected, onSelect: _select),
                          const VerticalDivider(width: 1, color: AppColors.borderStrong),
                          Expanded(
                            child: Column(
                              children: [
                                _TopBar(
                                  title: _selected == 'more' ? 'المزيد' : _current.label,
                                ),
                                const Divider(height: 1, color: AppColors.borderStrong),
                                Expanded(child: body),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _TopBar(
                            title: _selected == 'more' ? 'المزيد' : _current.label,
                          ),
                          const Divider(height: 1, color: AppColors.borderStrong),
                          Expanded(child: body),
                        ],
                      ),
              ),
              bottomNavigationBar: wide
                  ? null
                  : BottomNavigationBar(
                      currentIndex: _barIndex,
                      onTap: _onBarTap,
                      type: BottomNavigationBarType.fixed,
                      backgroundColor: AppColors.surface,
                      selectedItemColor: AppColors.brand,
                      unselectedItemColor: AppColors.fgMuted,
                      selectedLabelStyle: AppText.label,
                      unselectedLabelStyle: AppText.label,
                      items: const [
                        BottomNavigationBarItem(
                          icon: Icon(Icons.space_dashboard_outlined),
                          activeIcon: Icon(Icons.space_dashboard),
                          label: 'الرئيسية',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.point_of_sale_outlined),
                          activeIcon: Icon(Icons.point_of_sale),
                          label: 'البيع',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.soup_kitchen_outlined),
                          activeIcon: Icon(Icons.soup_kitchen),
                          label: 'المطبخ',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.moped_outlined),
                          activeIcon: Icon(Icons.moped),
                          label: 'التوصيل',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.apps_outlined),
                          activeIcon: Icon(Icons.apps),
                          label: 'المزيد',
                        ),
                      ],
                    ),
            ),
            // A mandatory update, an update in flight, or a failed attempt is
            // laid over the whole app: there is nothing useful to do until it
            // is resolved. An optional release is a dialog the operator may
            // defer, and a deferral lasts for the rest of this session.
            if (updates != null && !_dismissedOptional)
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

/// The menu grid behind المزيد: every destination, grouped, thumb-reachable.
///
/// Fourteen entries cannot fit a bottom bar, and the drawer they lived in was
/// built for a mouse. On a phone the overflow belongs in a screen of its own.
class _MoreScreen extends StatelessWidget {
  const _MoreScreen({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final group in navGroups) ...[
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
  const _Sidebar({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

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
                for (final group in navGroups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 5),
                    child: Text(group.label.toUpperCase(), style: AppText.label),
                  ),
                  for (final entry in group.entries)
                    _NavTile(
                      entry: entry,
                      active: entry.id == selected,
                      onTap: () => onSelect(entry.id),
                    ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderStrong),
          const _UserRow(),
        ],
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({required this.entry, required this.active, required this.onTap});

  final NavEntry entry;
  final bool active;
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
                  ? Colors.black.withValues(alpha: 0.05)
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
                    ? AppColors.brand
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
  const _UserRow();

  @override
  Widget build(BuildContext context) {
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
            child: const Text('أ', style: AppText.caption),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('أمّار', style: AppText.bodyStrong),
                Text('مدير', style: AppText.caption),
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
    return SizedBox(
      height: AppSpacing.topBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, c) {
            // Phones cannot fit title + branch pill + sync chip + two icon
            // buttons in 360px. Narrow keeps menu, title, sync state and
            // search; the branch pill and notifications stay on wide screens.
            final narrow = c.maxWidth < 600;
            return Row(
              children: [
                Flexible(
                  child: Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.pageTitle),
                ),
                if (!narrow) ...[
                  const SizedBox(width: 10),
                  Container(width: 1, height: 14, color: AppColors.borderStrong),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.borderStrong),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      children: [
                        Text('الفرع', style: AppText.caption),
                        const SizedBox(width: 4),
                        Text('بوابة الشمال',
                            style: AppText.tableCellPrimary),
                        const SizedBox(width: 4),
                        const Icon(Icons.unfold_more, size: 12, color: AppColors.fgGhost),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                const SyncChip(),
                const SizedBox(width: 10),
                const IconBtn(icon: Icons.search, tooltip: 'بحث'),
                if (!narrow) ...[
                  const SizedBox(width: 8),
                  const IconBtn(icon: Icons.notifications_none, tooltip: 'الإشعارات'),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
