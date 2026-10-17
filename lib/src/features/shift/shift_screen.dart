import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/role_ui.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../domain/models/app_role.dart';
import '../../domain/models/cash_session.dart';
import '../../domain/models/order.dart';
import '../accounting/accounting_screen.dart';
import '../common/format.dart';
import '../customers/customers_screen.dart';
import '../pos/pos_screen.dart';
import 'shift_blocks.dart';

/// The cashier's home: how is my shift going, and sell the next order.
///
/// Today only — sales in the hero, orders and ticket below, the live queue
/// under that. Selling is one tap away: the hero button and the quick tiles
/// open focused full-screen flows (POS, customers, cash session) and back
/// returns here. Cashier home; other roles never route here.
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

/// Shift figures computed from today's orders. Pure so the math is unit
/// tested without a widget tree or a database.
class ShiftStats {
  const ShiftStats({
    required this.sales,
    required this.orders,
    required this.unsynced,
    required this.recent,
  });

  final double sales;
  final int orders;
  final double unsynced;
  final List<Order> recent;

  double get averageTicket => orders == 0 ? 0 : sales / orders;

  static ShiftStats of(List<Order> orders, DateTime now) {
    final today = orders.where((o) {
      if (o.voided) return false;
      final created = o.createdAt;
      return created.year == now.year &&
          created.month == now.month &&
          created.day == now.day;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ShiftStats(
      sales: today.fold(0.0, (sum, o) => sum + o.total),
      orders: today.length,
      unsynced: today
          .where((o) => o.syncStatus != SyncStatus.synced)
          .fold(0.0, (sum, o) => sum + o.total),
      recent: today.take(5).toList(),
    );
  }
}

class _ShiftScreenState extends State<ShiftScreen> {
  ShiftStats _stats =
      const ShiftStats(sales: 0, orders: 0, unsynced: 0, recent: []);
  CashSession? _session;
  bool _hasStore = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final orders = services.orders;
    if (orders == null) return;
    final list = await orders.listOrders();
    // The session is optional: a branch can sell without a cash drawer
    // session open, and the strip then says so rather than inventing figures.
    final sessions = services.cashSessions;
    final open = sessions == null ? null : await sessions.currentSession();
    if (!mounted) return;
    setState(() {
      _hasStore = true;
      _session = open;
      _stats = ShiftStats.of(list, DateTime.now());
    });
  }

  String _time(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  void _open(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(AppRole.cashier);
    return RefreshIndicator(
      onRefresh: _load,
      child: PageBody(
        children: [
          ShiftStatusStrip(session: _session),
          const SizedBox(height: 12),
          RoleHero(
            role: AppRole.cashier,
            icon: Icons.schedule,
            kicker: 'شيفت النهاردة',
            title: !_hasStore
                ? 'مفيش مخزن متاح'
                : (_stats.orders == 0 ? 'شيفت جديد' : 'شيفت شغال'),
            subtitle: _stats.unsynced > 0
                ? '${money(_stats.unsynced)} لسه ما اتزامنش'
                : 'كل المبيعات على الجهاز',
            value: money(_stats.sales),
            valueLabel: 'ج.م مبيعات النهاردة',
            action: RmsButton(
              label: 'بيع جديد',
              icon: Icons.point_of_sale,
              variant: BtnVariant.primary,
              onPressed: () => _open(const PosScreen()),
            ),
          ),
          GridRow(
            children: [
              KpiCard(
                label: 'الأوردرات',
                value: '${_stats.orders}',
                icon: Icons.receipt_long_outlined,
                accent: accent,
              ),
              KpiCard(
                label: 'متوسط الفاتورة',
                value: money(_stats.averageTicket),
                icon: Icons.payments_outlined,
                accent: accent,
              ),
            ],
          ),
          GridRow(
            children: [
              QuickActionTile(
                icon: Icons.group_outlined,
                label: 'العملاء',
                accent: accent,
                onTap: () => _open(const CustomersScreen()),
              ),
              QuickActionTile(
                icon: Icons.account_balance_wallet_outlined,
                label: 'الجلسة والقفل',
                accent: accent,
                onTap: () => _open(const AccountingScreen()),
              ),
            ],
          ),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'أحدث الطلبات'),
                const SizedBox(height: 12),
                if (!_hasStore)
                  const Text(
                    'مفيش مخزن متاح لعرض الأوردرات.',
                    style: AppText.caption,
                  )
                else if (_stats.recent.isEmpty)
                  const Text(
                    'لسه مفيش أوردرات النهاردة. البيع من تبويب البيع.',
                    style: AppText.caption,
                  )
                else
                  for (final o in _stats.recent) ...[
                    FeedRow(
                      tone: o.syncStatus == SyncStatus.synced
                          ? StatusTone.positive
                          : StatusTone.warning,
                      title: o.provisionalOrderNumber,
                      subtitle:
                          '${_time(o.createdAt)} · ${o.items.length} صنف',
                      trailing: Text(
                        money(o.total),
                        style: AppText.tableCellPrimary.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (o != _stats.recent.last) ...[
                      const SizedBox(height: 10),
                      const Divider(
                        height: 1,
                        color: AppColors.borderSubtle,
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
