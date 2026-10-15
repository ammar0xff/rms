import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../core/widgets/sync_chip.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../data/mock/mock_data.dart';
import '../../domain/models/branch.dart';
import '../../domain/models/inventory_item.dart';
import '../../domain/models/order.dart';
import '../common/format.dart';
import 'dashboard_metrics.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Order> _orders = const [];
  ConsolidationSnapshot? _snapshot;
  bool _hasRepo = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    SyncMonitor.instance.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an inherited widget, so the first read has to happen here
    // rather than in initState.
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  @override
  void dispose() {
    SyncMonitor.instance.removeListener(_load);
    super.dispose();
  }

  /// Reads local orders and the consolidated branch snapshot. When no store is
  /// available the screen falls back to demo figures so the layout is still
  /// meaningful, and the branch card shows its unavailable state.
  Future<void> _load() async {
    if (!mounted) return;
    final services = AppScope.of(context);
    final orders = services.orders;
    final branches = services.branches;
    final list =
        orders == null ? const <Order>[] : await orders.listOrders();
    final snapshot = branches == null ? null : await branches.consolidate();
    if (!mounted) return;
    setState(() {
      _orders = list;
      _hasRepo = orders != null;
      _snapshot = snapshot;
    });
  }

  @override
  Widget build(BuildContext context) {
    final useMock = !_hasRepo;
    final metrics = DashboardMetrics.fromOrders(_orders);
    final monitor = SyncMonitor.instance;

    // _load already returns a Future, so it plugs straight into the refresh
    // indicator: pull down for fresh orders and branch totals.
    return RefreshIndicator(
      onRefresh: _load,
      child: PageBody(
        children: [
        // Mock figures must never wear the مباشر tag: without a store these
        // numbers are fabricated, and an operator could act on them.
        if (useMock)
          const SurfaceCard(
            level: SurfaceLevel.secondary,
            child: Row(
              children: [
                Icon(Icons.science_outlined,
                    size: 16, color: AppColors.warning),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'بيانات تجريبية — مفيش مخزن متاح على الجهاز',
                    style: AppText.tableCellPrimary,
                  ),
                ),
              ],
            ),
          ),
        HeroKpi(
          label: 'صافي مبيعات اليوم',
          value: useMock ? '8,412.50 ج.م' : money(metrics.todayTotal),
          delta: useMock ? '+12.4%' : null,
          deltaTone: DeltaTone.positive,
          subtext: useMock
              ? 'مقارنة بمتوسط 14 يومًا'
              : 'على الجهاز ده · ${metrics.todayOrders} أوردر',
          spark: useMock ? MockData.salesTrend : metrics.hourlySales,
        ),
        GridRow(children: [
          StatCard(
            label: 'الطلبات',
            value: useMock ? '312' : '${metrics.todayOrders}',
            delta: useMock ? '+8.1%' : null,
          ),
          StatCard(
            label: 'متوسط الفاتورة',
            value: useMock ? '26.96 ج.م' : money(metrics.averageTicket),
            delta: useMock ? '+2.3%' : null,
          ),
          StatCard(
            label: 'عمليات دون اتصال اليوم',
            value: useMock ? '37' : '${metrics.offlineOrders}',
            delta: '${monitor.pending} قيد الانتظار',
            deltaTone: DeltaTone.neutral,
          ),
        ]),
        _SalesCard(
          data: useMock ? MockData.hourlySales : metrics.hourlySales,
          subtitle: useMock ? 'النهاردة · آخر تحديث 12:45' : 'النهاردة · على الجهاز',
          live: !useMock && monitor.online,
          extraStats: useMock
              ? const [('الطلبات', '312'), ('داخل الصالة / توصيل', '198 / 74')]
              : [
                  ('الطلبات', '${metrics.todayOrders}'),
                  ('ما اتزامنتش', '${metrics.unsyncedOrders}'),
                ],
        ),
        ResponsiveRow(
          gap: AppSpacing.lg,
          children: [
            _RecentOrders(orders: useMock ? null : _orders),
            const _AlertsPanel(),
          ],
        ),
        ResponsiveRow(
          gap: AppSpacing.lg,
          children: [
            const _SyncHealthCard(),
            _BranchCard(snapshot: _snapshot),
          ],
        ),
        ],
      ),
    );
  }
}

class _SalesCard extends StatelessWidget {
  const _SalesCard({
    required this.data,
    required this.subtitle,
    required this.extraStats,
    this.live = true,
  });

  final List<double> data;
  final String subtitle;
  final List<(String, String)> extraStats;
  final bool live;

  static const _hours = [
    '10ص', '11ص', '12م', '1م', '2م', '3م', '4م', '5م', '6م', '7م', '8م', '9م',
  ];

  static String _fmtTick(double v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k.toStringAsFixed(k == k.roundToDouble() ? 0 : 1)}k';
    }
    return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  }

  static String _peakTime(int index) {
    final h = 10 + index;
    final amPm = h < 12 ? 'ص' : 'م';
    final h12 = h == 12 ? 12 : h % 12;
    return '$h12:00 $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final rawMax = data.isEmpty ? 1.0 : data.reduce((a, b) => a > b ? a : b);
    final top = ((rawMax / 5).ceil() * 5).toDouble();
    final ticks = <double>[top, top / 2, (top / 4).roundToDouble(), 0];
    var peak = 0;
    for (var i = 0; i < data.length; i++) {
      if (data[i] > data[peak]) peak = i;
    }

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: SectionHeader(
              title: 'المبيعات بالساعة',
              subtitle: subtitle,
              trailing: Tag(
                label: live ? 'مباشر' : 'دون اتصال',
                tone: live ? StatusTone.positive : StatusTone.warning,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 42,
                    height: 160,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final v in ticks)
                          Text(_fmtTick(v), style: AppText.caption),
                      ],
                    ),
                  ),
                  Expanded(
                    child: MiniBars(
                      values: data,
                      height: 160,
                      highlightIndex: peak,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            // Mirrored for RTL: the y-axis gutter is the Row's first child,
            // which lays out on the right. Every third label only — twelve
            // Arabic hour names in ~230px collide.
            padding: const EdgeInsets.only(right: 62, left: 20, top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < _hours.length; i++)
                  i % 3 == 0
                      ? Text(_hours[i], style: AppText.caption)
                      : const SizedBox(width: 8),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                _FooterStat(label: 'ساعة الذروة', value: _peakTime(peak)),
                const _VDivider(),
                for (var i = 0; i < extraStats.length; i++) ...[
                  _FooterStat(label: extraStats[i].$1, value: extraStats[i].$2),
                  if (i != extraStats.length - 1) const _VDivider(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterStat extends StatelessWidget {
  const _FooterStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // Stacked: label over value. Side-by-side in a ~90px lane truncated both.
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, overflow: TextOverflow.ellipsis, style: AppText.caption),
          const SizedBox(height: 2),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
                color: AppColors.fgSecondary, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 24,
        color: AppColors.borderStrong,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );
}

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({this.orders});

  /// Real local orders, or null to fall back to demo rows.
  final List<Order>? orders;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            // No trailing action: عرض الكل used to sit here wired to a no-op,
            // a button that looks alive and does nothing. There is no orders
            // list destination to point it at; when there is, it goes back.
            child: SectionHeader(
              title: 'آخر الطلبات',
            ),
          ),
          if (orders == null) _mockTable() else _realTable(),
        ],
      ),
    );
  }

  Widget _mockTable() {
    return RmsTable(
      columns: const [
        RmsColumn('الطلب', flex: 3),
        RmsColumn('النوع', flex: 2),
        RmsColumn('الحالة', flex: 3),
        RmsColumn('المزامنة', flex: 3),
        RmsColumn('الإجمالي', flex: 2, align: TextAlign.right),
      ],
      rows: [
        for (final o in MockData.orders)
          [
            Row(
              children: [
                Flexible(
                  child: Text(o.number, overflow: TextOverflow.ellipsis, style: AppText.tableCellPrimary),
                ),
                if (o.provisional) ...[
                  const SizedBox(width: 6),
                  const Tag(label: 'مؤقت', tone: StatusTone.neutral),
                ],
              ],
            ),
            Text(o.type, style: AppText.tableCell),
            Text(o.status, style: AppText.tableCell),
            StatusText(label: syncStateView(o.sync).$1, tone: syncStateView(o.sync).$2),
            Text(money(o.total), style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
          ],
      ],
    );
  }

  Widget _realTable() {
    final recent = [...orders!]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return RmsTable(
      columns: const [
        RmsColumn('الطلب', flex: 3),
        RmsColumn('الأصناف', flex: 2),
        RmsColumn('المزامنة', flex: 3),
        RmsColumn('الإجمالي', flex: 2, align: TextAlign.right),
      ],
      rows: [
        for (final o in recent.take(6))
          [
            Row(
              children: [
                Flexible(
                  child: Text(o.provisionalOrderNumber, overflow: TextOverflow.ellipsis, style: AppText.tableCellPrimary),
                ),
                if (o.syncStatus != SyncStatus.synced) ...[
                  const SizedBox(width: 6),
                  const Tag(label: 'على الجهاز', tone: StatusTone.neutral),
                ],
              ],
            ),
            Text('${o.items.length}', style: AppText.tableCell),
            StatusText(label: orderSyncView(o.syncStatus).$1, tone: orderSyncView(o.syncStatus).$2),
            Text(money(o.total), style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
          ],
      ],
    );
  }
}

class _AlertsPanel extends StatefulWidget {
  const _AlertsPanel();

  @override
  State<_AlertsPanel> createState() => _AlertsPanelState();
}

class _AlertsPanelState extends State<_AlertsPanel> {
  List<InventoryItemModel> _lowStock = const [];
  bool _hasStore = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  // Real low-stock rows from the inventory store. Previously this panel always
  // rendered fixture rows, even in production with a live store beside it.
  Future<void> _load() async {
    final inventory = AppScope.of(context).inventory;
    if (inventory == null) return;
    final items = await inventory.listItems();
    if (!mounted) return;
    setState(() {
      _hasStore = true;
      _lowStock = items.where((i) => i.isLow).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final monitor = SyncMonitor.instance;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'التنبيهات'),
          const SizedBox(height: 12),
          if (!_hasStore)
            const Text(
              'مفيش مخزن متاح لفحص المخزون.',
              style: AppText.caption,
            )
          else if (_lowStock.isEmpty)
            const Row(
              children: [
                StatusDot(tone: StatusTone.positive),
                SizedBox(width: 8),
                Expanded(
                  child: Text('المخزون فوق حد إعادة الطلب',
                      style: AppText.tableCellPrimary),
                ),
              ],
            )
          else
            for (final item in _lowStock) ...[
              Row(
                children: [
                  const StatusDot(tone: StatusTone.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${item.name} أقل من حد إعادة الطلب',
                        style: AppText.tableCellPrimary),
                  ),
                  Text('${item.onHand}${item.unit}',
                      style: AppText.caption),
                ],
              ),
              const SizedBox(height: 10),
            ],
          const Divider(height: 20, color: AppColors.borderSubtle),
          Row(
            children: [
              StatusDot(tone: monitor.conflicts > 0 ? StatusTone.negative : StatusTone.positive),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  monitor.conflicts > 0
                      ? '${monitor.conflicts} تعارضات غير محلولة'
                      : 'مفيش تعارضات',
                  style: AppText.tableCellPrimary,
                ),
              ),
              if (monitor.conflicts > 0)
                const Icon(Icons.chevron_right, size: 14, color: AppColors.fgGhost),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const StatusDot(tone: StatusTone.info),
              const SizedBox(width: 8),
              const Expanded(child: Text('مزامنة القائمة: متخزنة على الجهاز', style: AppText.tableCellPrimary)),
              Text(_sinceLabel(monitor), style: AppText.caption),
            ],
          ),
        ],
      ),
    );
  }

  String _sinceLabel(SyncMonitor monitor) {
    if (monitor.total == 0) return 'لسه ما اتزامنش';
    final d = monitor.sinceLastSync;
    if (d.inMinutes < 1) return 'دلوقتي';
    if (d.inMinutes < 60) return 'قبل ${d.inMinutes} د';
    return 'قبل ${d.inHours} س';
  }
}

class _SyncHealthCard extends StatelessWidget {
  const _SyncHealthCard();

  @override
  Widget build(BuildContext context) {
    final monitor = SyncMonitor.instance;
    final ratio = monitor.total == 0 ? 1.0 : monitor.synced / monitor.total;
    final percent = (ratio * 100).round();
    final hasFailures = monitor.failed > 0 || monitor.conflicts > 0;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'صحة المزامنة',
            trailing: const SyncChip(),
          ),
          const SizedBox(height: 14),
          const SyncStatRow(),
          const SizedBox(height: 14),
          ProgressBar(
            value: ratio,
            color: hasFailures ? AppColors.negative : AppColors.positive,
          ),
          const SizedBox(height: 8),
          Text(_explain(monitor, percent), style: AppText.caption),
        ],
      ),
    );
  }

  String _explain(SyncMonitor monitor, int percent) {
    if (monitor.total == 0) {
      return monitor.online
          ? 'مفيش عمليات على الجهاز في الطابور. الجهاز متصل بالسيرفر.'
          : 'مفيش عمليات في الطابور على الجهاز. المزامنة هتبدأ لما الاتصال يرجع.';
    }
    final synced = 'اتزامن $percent% من ${monitor.total} عملية على الجهاز ده.';
    if (monitor.online) return '$synced الجهاز متصل بالسيرفر.';
    return '$synced شغال من غير نت — ${monitor.pending} عملية في الطابور على الجهاز.';
  }
}

/// Compact branch status driven by the consolidation read-model: the device's
/// own branch is read live, every other branch contributes its last synced
/// aggregate, and stale/missing branches are flagged rather than zeroed.
class _BranchCard extends StatelessWidget {
  const _BranchCard({required this.snapshot});

  final ConsolidationSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final snapshot = this.snapshot;
    if (snapshot == null) {
      return const SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: 'حالة الفرع'),
            SizedBox(height: 12),
            Text(
              'توحيد الفروع غير متاح في هذه الجلسة.',
              style: AppText.caption,
            ),
          ],
        ),
      );
    }
    final local = snapshot.localBranch;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'حالة الفرع',
            subtitle: local == null
                ? null
                : '${local.branch.name} · ${local.branch.code}',
            trailing: Tag(
              label: _coverageLabel(snapshot),
              tone: _coverageTone(snapshot),
            ),
          ),
          const SizedBox(height: 12),
          KvPanel(pairs: [
            ('مبيعات الشبكة', money(snapshot.totalSales)),
            ('طلبات الشبكة', '${snapshot.totalOrders}'),
            ('تحصيل الشبكة', money(snapshot.totalCollected)),
            ('مخزون الشبكة', _qty(snapshot.totalInventoryUnits)),
            (
              'تغطية الفروع',
              '${snapshot.reportingCount} من ${snapshot.branchCount}',
            ),
          ]),
        ],
      ),
    );
  }

  static String _coverageLabel(ConsolidationSnapshot snapshot) {
    if (snapshot.staleCount > 0) return '${snapshot.staleCount} متأخر';
    if (snapshot.missingCount > 0) return '${snapshot.missingCount} بلا بيانات';
    return 'خلصان';
  }

  static StatusTone _coverageTone(ConsolidationSnapshot snapshot) {
    if (snapshot.staleCount > 0) return StatusTone.warning;
    if (snapshot.missingCount > 0) return StatusTone.neutral;
    return StatusTone.positive;
  }

  static String _qty(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
}
