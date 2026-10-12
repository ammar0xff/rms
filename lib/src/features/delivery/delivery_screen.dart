import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/models/delivery.dart';
import '../common/format.dart';

StatusTone _stateTone(DeliveryState state) => switch (state) {
      DeliveryState.waiting => StatusTone.neutral,
      DeliveryState.assigned => StatusTone.info,
      DeliveryState.onRoute => StatusTone.warning,
      DeliveryState.delivered => StatusTone.positive,
      DeliveryState.collected => StatusTone.positive,
    };

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  List<DeliveryModel> _deliveries = const [];
  List<DriverModel> _drivers = const [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).deliveries;
    if (repo == null) return;
    final deliveries = await repo.listDeliveries();
    final drivers = await repo.listDrivers();
    if (!mounted) return;
    setState(() {
      _deliveries = deliveries;
      _drivers = drivers;
    });
  }

  List<DeliveryModel> get _open =>
      _deliveries.where((d) => d.state.isOpen).toList();

  List<DeliveryModel> get _waiting =>
      _deliveries.where((d) => d.state == DeliveryState.waiting).toList();

  double get _offlineCollections => _deliveries
      .where((d) => d.state == DeliveryState.collected && d.offline)
      .fold(0, (sum, d) => sum + d.amount);

  Future<void> _assignNext() async {
    final repo = AppScope.of(context).deliveries;
    final messenger = ScaffoldMessenger.of(context);
    if (repo == null) return;
    final waiting = _waiting.firstOrNull;
    if (waiting == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('لا توجد مهام بانتظار الإسناد')),
      );
      return;
    }
    if (_drivers.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('لا يوجد سائقون متاحون')),
      );
      return;
    }
    final driver = _leastLoadedDriver();
    await repo.assignDriver(waiting.id, driver.name);
    await _load();
    _refreshMonitor();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('أُسندت المهمة ${waiting.id} إلى ${driver.name}')),
    );
  }

  Future<void> _advance(DeliveryModel delivery) async {
    final repo = AppScope.of(context).deliveries;
    if (repo == null) return;
    if (delivery.state == DeliveryState.waiting) {
      await _assignNextFor(delivery);
      return;
    }
    final next = switch (delivery.state) {
      DeliveryState.assigned => DeliveryState.onRoute,
      DeliveryState.onRoute => DeliveryState.collected,
      _ => null,
    };
    if (next == null) return;
    await repo.updateState(delivery.id, next);
    await _load();
    _refreshMonitor();
  }

  Future<void> _assignNextFor(DeliveryModel delivery) async {
    final repo = AppScope.of(context).deliveries;
    if (repo == null || _drivers.isEmpty) return;
    await repo.assignDriver(delivery.id, _leastLoadedDriver().name);
    await _load();
    _refreshMonitor();
  }

  DriverModel _leastLoadedDriver() {
    final open = _open;
    return _drivers.reduce((a, b) {
      final loadA = open.where((d) => d.driver == a.name).length;
      final loadB = open.where((d) => d.driver == b.name).length;
      return loadB < loadA ? b : a;
    });
  }

  /// Brings the "something changed" bus up to date for the dashboard badge.
  void _refreshMonitor() {
    unawaited(SyncMonitor.instance.refresh());
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        GridRow(children: [
          StatCard(label: 'توصيلات نشطة', value: '${_open.length}', delta: '${_waiting.length} بانتظار الإسناد'),
          StatCard(
            label: 'بانتظار الإسناد',
            value: '${_waiting.length}',
            delta: '—',
            deltaTone: DeltaTone.neutral,
          ),
          StatCard(
            label: 'تحصيلات دون اتصال',
            value: money(_offlineCollections),
            delta: 'تسوية معلقة',
            deltaTone: DeltaTone.neutral,
          ),
          StatCard(
            label: 'مكتملة',
            value: '${_deliveries.where((d) => d.state == DeliveryState.collected).length}',
            delta: 'تم التحصيل',
            deltaTone: DeltaTone.positive,
          ),
        ]),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _deliveryTable()),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: _driversPanel()),
          ],
        ),
        const _OfflineCollectionNotice(),
      ],
    );
  }

  Widget _deliveryTable() {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: SectionHeader(
              title: 'التوصيلات',
              trailing: RmsButton(label: 'إسناد التالي', icon: Icons.bolt, onPressed: _assignNext),
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('المهمة', flex: 2),
              RmsColumn('الطلب', flex: 2),
              RmsColumn('السائق', flex: 2),
              RmsColumn('العنوان', flex: 4),
              RmsColumn('الحالة', flex: 3),
              RmsColumn('إجراء', width: 90),
              RmsColumn('المبلغ', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final d in _deliveries)
                [
                  Text(d.id, style: AppText.tableCellPrimary),
                  Text(d.orderRef, style: AppText.tableCell),
                  Text(d.driver, style: AppText.tableCell),
                  Text(d.address, style: AppText.tableCell, overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      StatusDot(tone: d.offline ? StatusTone.warning : _stateTone(d.state)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(d.state.label, style: AppText.tableCell, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  _actionButton(d),
                  Text(money(d.amount),
                      style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
                ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(DeliveryModel d) {
    return switch (d.state) {
      DeliveryState.waiting => RmsButton(
          label: 'إسناد',
          onPressed: _drivers.isEmpty ? null : () => _advance(d),
        ),
      DeliveryState.assigned => RmsButton(label: 'بدء', onPressed: () => _advance(d)),
      DeliveryState.onRoute => RmsButton(
          label: 'تحصيل',
          variant: BtnVariant.primary,
          onPressed: () => _advance(d),
        ),
      DeliveryState.delivered || DeliveryState.collected =>
        const SizedBox.shrink(),
    };
  }

  Widget _driversPanel() {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'السائقون', subtitle: 'الوردية · 12:00–20:00'),
          const SizedBox(height: 12),
          for (final driver in _drivers) ...[
            _DriverRow(
              driver: driver,
              active: _open.where((d) => d.driver == driver.name).length,
              collected: _deliveries
                  .where((d) =>
                      d.driver == driver.name && d.state == DeliveryState.collected)
                  .fold(0.0, (sum, d) => sum + d.amount),
            ),
            const SizedBox(height: 12),
          ],
          const Divider(height: 20, color: AppColors.borderSubtle),
          Row(
            children: [
              Text('قائمة تسوية التحصيلات المعلقة', style: AppText.bodyStrong.copyWith(fontSize: 12)),
              const Spacer(),
              Tag(
                label: '${_deliveries.where((d) => d.offline).length} مسودات',
                tone: StatusTone.warning,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'لا يمكن إنهاء تحصيلات المسجلة محليًا بدون تحقق من الخادم.',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          const RmsButton(label: 'فتح قائمة التسوية', icon: Icons.arrow_forward, onPressed: null, dense: false),
        ],
      ),
    );
  }
}

class _DriverRow extends StatelessWidget {
  const _DriverRow({
    required this.driver,
    required this.active,
    required this.collected,
  });

  final DriverModel driver;
  final int active;
  final double collected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(color: AppColors.hover, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(driver.name.substring(0, 1), style: AppText.caption),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(driver.name, style: AppText.tableCellPrimary),
              Text('$active نشطة', style: AppText.caption.copyWith(fontSize: 10)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(collected),
                style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
            Text(active > 0 ? 'في التوصيل' : 'متاح',
                style: AppText.caption.copyWith(fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

class _OfflineCollectionNotice extends StatelessWidget {
  const _OfflineCollectionNotice();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      level: SurfaceLevel.secondary,
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.info),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppText.body,
                children: const [
                  TextSpan(text: 'التحصيل المسجل محليًا هو مطالبة وليس دليلاً على الاستلام. '),
                  TextSpan(
                    text: 'المطابقة واعتماد التسوية يتطلبان تحققًا من الخادم.',
                    style: TextStyle(color: AppColors.fgBright, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          const StatusText(label: 'مطابقة معلقة', tone: StatusTone.warning),
        ],
      ),
    );
  }
}
