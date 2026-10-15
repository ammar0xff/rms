import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../domain/models/order.dart';
import '../common/format.dart';

/// The cashier's home: how is my shift going.
///
/// Today only — sales, orders, average ticket, and what has not synced yet —
/// plus the most recent orders. The POS tab next to it does the selling; this
/// screen answers "how am I doing" without digging through reports. Cashier
/// home; other roles never route here.
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
    final orders = AppScope.of(context).orders;
    if (orders == null) return;
    final list = await orders.listOrders();
    if (!mounted) return;
    setState(() {
      _hasStore = true;
      _stats = ShiftStats.of(list, DateTime.now());
    });
  }

  String _time(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: PageBody(
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: 'وردية اليوم',
                  subtitle: _hasStore ? null : 'لا يوجد مخزن متاح',
                ),
                const SizedBox(height: 12),
                GridRow(children: [
                  StatCard(label: 'المبيعات', value: money(_stats.sales)),
                  StatCard(
                      label: 'الطلبات', value: '${_stats.orders}'),
                  StatCard(
                    label: 'متوسط الفاتورة',
                    value: money(_stats.averageTicket),
                  ),
                ]),
                if (_stats.unsynced > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const StatusDot(tone: StatusTone.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${money(_stats.unsynced)} لم تُزامَن بعد',
                          style: AppText.tableCellPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SurfaceCard(
            padding: EdgeInsets.zero,
            clip: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: SectionHeader(title: 'أحدث الطلبات'),
                ),
                if (!_hasStore)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(
                      'لا يوجد مخزن متاح لعرض الطلبات.',
                      style: AppText.caption,
                    ),
                  )
                else if (_stats.recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(
                      'لا توجد طلبات اليوم بعد. البيع من تبويب البيع.',
                      style: AppText.caption,
                    ),
                  )
                else
                  RmsTable(
                    columns: const [
                      RmsColumn('الطلب', flex: 3),
                      RmsColumn('الوقت', flex: 2),
                      RmsColumn('الحالة', flex: 2),
                      RmsColumn('الإجمالي', flex: 2, align: TextAlign.right),
                    ],
                    rows: [
                      for (final o in _stats.recent)
                        [
                          Text(
                            o.provisionalOrderNumber,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.tableCellPrimary,
                          ),
                          Text(_time(o.createdAt),
                              style: AppText.tableCell),
                          StatusText(
                            label: o.syncStatus == SyncStatus.synced
                                ? 'مُزامَن'
                                : 'محلي',
                            tone: o.syncStatus == SyncStatus.synced
                                ? StatusTone.positive
                                : StatusTone.warning,
                          ),
                          Text(
                            money(o.total),
                            textAlign: TextAlign.right,
                            style: AppText.tableCellPrimary.copyWith(
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
