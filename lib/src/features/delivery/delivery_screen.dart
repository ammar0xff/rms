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
import '../../data/repositories/delivery_repository.dart';
import '../../domain/assignment/delivery_assignment.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/delivery.dart';
import '../common/format.dart';

StatusTone _stateTone(DeliveryState state) => switch (state) {
      DeliveryState.waiting => StatusTone.neutral,
      DeliveryState.assigned => StatusTone.info,
      DeliveryState.onRoute => StatusTone.warning,
      DeliveryState.delivered => StatusTone.positive,
    };

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  List<DeliveryModel> _deliveries = const [];
  List<DriverModel> _drivers = const [];
  List<CollectionModel> _collections = const [];
  bool _autoAssignEnabled = false;
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
    final repo = services.deliveries;
    if (repo == null) return;
    final deliveries = await repo.listDeliveries();
    final drivers = await repo.listDrivers();
    final collections = await repo.listCollections();
    // Auto-assignment is only permitted while the server flag is on; the cached
    // manifest keeps that permission available offline.
    final features = services.features;
    final autoAssign = features == null
        ? false
        : await features.isEnabled(DeliveryAssignmentPolicy.autoAssignFlagKey);
    if (!mounted) return;
    setState(() {
      _deliveries = deliveries;
      _drivers = drivers;
      _collections = collections;
      _autoAssignEnabled = autoAssign;
    });
  }

  List<DeliveryModel> get _open =>
      _deliveries.where((d) => d.state.isOpen).toList();

  List<DeliveryModel> get _waiting =>
      _deliveries.where((d) => d.state == DeliveryState.waiting).toList();

  List<CollectionModel> get _pendingSettlements => _collections
      .where((c) => c.settlementStatus == SettlementStatus.pending)
      .toList();

  double get _outstandingTotal => _pendingSettlements.fold(
        0,
        (sum, c) => sum + c.amount,
      );

  double get _settledTotal => _collections
      .where((c) => c.settlementStatus == SettlementStatus.settled)
      .fold(0, (sum, c) => sum + c.amount);

  double get _offlineCollections => _pendingSettlements
      .where((c) => c.createdOffline)
      .fold(0, (sum, c) => sum + c.amount);

  CollectionModel? _collectionFor(String deliveryId) {
    for (final collection in _collections) {
      if (collection.deliveryId == deliveryId) return collection;
    }
    return null;
  }

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
    final driver = DeliveryAssignmentPolicy.pickDriver(
      deliveries: _deliveries,
      drivers: _drivers,
    );
    if (driver == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('لا يوجد سائقون متاحون')),
      );
      return;
    }
    final outcome =
        await repo.assignDriver(waiting.id, driver, baseDriver: waiting.driver);
    await _load();
    _refreshMonitor();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          outcome == AssignmentOutcome.conflict
              ? 'تعارض إسناد على ${waiting.id}: طلب المراجعة'
              : 'أُسندت المهمة ${waiting.id} إلى $driver',
        ),
      ),
    );
  }

  /// Assigns every waiting job to the least-loaded available driver in one shot.
  ///
  /// Only offered when the server flag permits provisional local assignment; the
  /// batch is applied atomically by the repository and reconciled later.
  Future<void> _autoAssignAll() async {
    final repo = AppScope.of(context).deliveries;
    final messenger = ScaffoldMessenger.of(context);
    if (repo == null) return;
    final results = await repo.autoAssignWaiting();
    await _load();
    _refreshMonitor();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          results.isEmpty
              ? 'لا توجد مهام بانتظار الإسناد'
              : 'أُسندت ${results.length} مهمة تلقائيًا',
        ),
      ),
    );
  }

  Future<void> _assign(DeliveryModel delivery) async {
    final repo = AppScope.of(context).deliveries;
    final messenger = ScaffoldMessenger.of(context);
    if (repo == null) return;
    if (delivery.state != DeliveryState.waiting) return;
    final driver = DeliveryAssignmentPolicy.pickDriver(
      deliveries: _deliveries,
      drivers: _drivers,
    );
    if (driver == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('لا يوجد سائقون متاحون')),
      );
      return;
    }
    final outcome = await repo.assignDriver(
      delivery.id,
      driver,
      baseDriver: delivery.driver,
    );
    await _load();
    _refreshMonitor();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          outcome == AssignmentOutcome.conflict
              ? 'تعارض إسناد على ${delivery.id}: طلب المراجعة'
              : 'أُسندت المهمة ${delivery.id} إلى $driver',
        ),
      ),
    );
  }

  Future<void> _advance(DeliveryModel delivery) async {
    final repo = AppScope.of(context).deliveries;
    if (repo == null) return;
    final next = switch (delivery.state) {
      DeliveryState.assigned => DeliveryState.onRoute,
      DeliveryState.onRoute => DeliveryState.delivered,
      _ => null,
    };
    if (next == null) return;
    try {
      await repo.updateState(delivery.id, next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حركة غير صالحة لهذه المهمة')),
      );
      return;
    }
    await _load();
    _refreshMonitor();
  }

  /// Records the cash collected for a delivered job (one collection per job).
  Future<void> _collect(DeliveryModel delivery) async {
    final repo = AppScope.of(context).deliveries;
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (repo == null) return;
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _CollectionDialog(total: delivery.amount),
    );
    if (amount == null) return;
    final offline = services.sync?.isOnline != true;
    await repo.recordCollection(
      deliveryId: delivery.id,
      amount: amount,
      createdOffline: offline,
    );
    await _load();
    _refreshMonitor();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          offline
              ? 'سُجّل تحصيل ${money(amount)} محليًا · يُسوّى عند الاتصال'
              : 'سُجّل تحصيل ${money(amount)}',
        ),
      ),
    );
  }

  Future<void> _finalize(CollectionModel collection) async {
    final repo = AppScope.of(context).deliveries;
    final messenger = ScaffoldMessenger.of(context);
    if (repo == null) return;
    await repo.finalizeSettlement(collection.deliveryId);
    await _load();
    _refreshMonitor();
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('أُرسل طلب التسوية للخادم · الاعتماد بعد التحقق')),
    );
  }

  /// Brings the "something changed" bus up to date for the dashboard badge.
  void _refreshMonitor() {
    unawaited(SyncMonitor.instance.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: SyncMonitor.instance,
      builder: (context, _) {
        final canFinalize = services.sync != null && SyncMonitor.instance.online;
        return PageBody(
          children: [
            GridRow(children: [
              StatCard(
                label: 'توصيلات نشطة',
                value: '${_open.length}',
                delta: '${_waiting.length} بانتظار الإسناد',
              ),
              StatCard(
                label: 'بانتظار الإسناد',
                value: '${_waiting.length}',
                delta: '—',
                deltaTone: DeltaTone.neutral,
              ),
              StatCard(
                label: 'قيد التسوية',
                value: money(_outstandingTotal),
                delta: '${_pendingSettlements.length} عملية',
                deltaTone: DeltaTone.neutral,
              ),
              StatCard(
                label: 'مُسوّى',
                value: money(_settledTotal),
                delta: 'معتمد من الخادم',
                deltaTone: DeltaTone.positive,
              ),
            ]),
            ResponsiveRow(
              gap: AppSpacing.lg,
              children: [
                _deliveryTable(),
                _driversPanel(),
              ],
            ),
            _settlementQueue(canFinalize),
            _OfflineCollectionNotice(offlineTotal: _offlineCollections),
          ],
        );
      },
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_autoAssignEnabled) ...[
                    RmsButton(
                      label: 'إسناد تلقائي',
                      icon: Icons.auto_awesome,
                      variant: BtnVariant.primary,
                      onPressed: _waiting.isEmpty || _drivers.isEmpty
                          ? null
                          : _autoAssignAll,
                    ),
                    const SizedBox(width: 8),
                  ],
                  RmsButton(
                    label: 'إسناد التالي',
                    icon: Icons.bolt,
                    onPressed: _assignNext,
                  ),
                ],
              ),
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('المهمة', flex: 2),
              RmsColumn('الطلب', flex: 2),
              RmsColumn('السائق', flex: 2),
              RmsColumn('العنوان', flex: 4),
              RmsColumn('الحالة', flex: 3),
              RmsColumn('التسوية', flex: 3),
              RmsColumn('إجراء', width: 110),
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
                  _settlementCell(d),
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

  Widget _settlementCell(DeliveryModel d) {
    if (!d.state.isDelivered) {
      return Text('—', style: AppText.tableCell);
    }
    return Tag(
      label: d.settlementStatus.label,
      tone: d.settlementStatus == SettlementStatus.settled
          ? StatusTone.positive
          : StatusTone.warning,
    );
  }

  Widget _actionButton(DeliveryModel d) {
    return switch (d.state) {
      DeliveryState.waiting => RmsButton(
          label: 'إسناد',
          onPressed: _drivers.isEmpty ? null : () => _assign(d),
        ),
      DeliveryState.assigned => RmsButton(label: 'بدء', onPressed: () => _advance(d)),
      DeliveryState.onRoute => RmsButton(
          label: 'تم التسليم',
          variant: BtnVariant.primary,
          onPressed: () => _advance(d),
        ),
      DeliveryState.delivered => _settledAction(d),
    };
  }

  Widget _settledAction(DeliveryModel d) {
    final collection = _collectionFor(d.id);
    if (collection == null) {
      return RmsButton(
        label: 'تسجيل تحصيل',
        variant: BtnVariant.primary,
        onPressed: () => _collect(d),
      );
    }
    if (collection.settlementStatus == SettlementStatus.settled) {
      return const Tag(label: 'مُسوّى', tone: StatusTone.positive);
    }
    return const Tag(label: 'قيد التسوية', tone: StatusTone.warning);
  }

  Widget _driversPanel() {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'السائقون',
            subtitle: 'الوردية · 12:00–20:00',
            trailing: Tag(
              label: _autoAssignEnabled
                  ? 'إسناد تلقائي مُفعّل'
                  : 'إسناد تلقائي متوقف',
              tone: _autoAssignEnabled ? StatusTone.info : StatusTone.neutral,
            ),
          ),
          const SizedBox(height: 12),
          for (final driver in _drivers) ...[
            _DriverRow(
              driver: driver,
              active: _open.where((d) => d.driver == driver.name).length,
              collected: _collections
                  .where((c) => c.driver == driver.name)
                  .fold(0.0, (sum, c) => sum + c.amount),
            ),
            const SizedBox(height: 12),
          ],
          const Divider(height: 20, color: AppColors.borderSubtle),
          Row(
            children: [
              Text('قائمة تسوية التحصيلات المعلقة',
                  style: AppText.bodyStrong.copyWith(fontSize: 12)),
              const Spacer(),
              Tag(
                label: '${_pendingSettlements.length} معلقة',
                tone: _pendingSettlements.isEmpty
                    ? StatusTone.positive
                    : StatusTone.warning,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'لا يمكن إنهاء تحصيلات المسجلة محليًا بدون تحقق من الخادم.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }

  Widget _settlementQueue(bool canFinalize) {
    final pending = _pendingSettlements;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: SectionHeader(
              title: 'قائمة التسوية المعلقة',
              subtitle: canFinalize
                  ? 'الطلبات المحصلة محليًا جاهزة للمطابقة مع الخادم'
                  : 'يتطلب اتصالًا بالخادم لإنهاء التسوية',
              trailing: Tag(
                label: '${pending.length} عملية · ${money(_outstandingTotal)}',
                tone: pending.isEmpty ? StatusTone.positive : StatusTone.warning,
              ),
            ),
          ),
          if (pending.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Text('لا توجد تسويات معلقة.', style: AppText.caption),
            )
          else
            RmsTable(
              columns: const [
                RmsColumn('الطلب', flex: 2),
                RmsColumn('السائق', flex: 3),
                RmsColumn('الطريقة', flex: 2),
                RmsColumn('الحالة', flex: 2),
                RmsColumn('إجراء', width: 140),
                RmsColumn('المبلغ', flex: 2, align: TextAlign.right),
              ],
              rows: [
                for (final c in pending)
                  [
                    Text(c.orderRef, style: AppText.tableCellPrimary),
                    Text(c.driver, style: AppText.tableCell),
                    Text(c.method.label, style: AppText.tableCell),
                    Tag(
                      label: c.createdOffline ? 'محلي' : 'متصل',
                      tone: c.createdOffline ? StatusTone.warning : StatusTone.neutral,
                    ),
                    RmsButton(
                      label: 'إنهاء التسوية',
                      icon: Icons.verified_outlined,
                      onPressed: canFinalize ? () => _finalize(c) : null,
                    ),
                    Text(money(c.amount),
                        style: AppText.tableCellPrimary
                            .copyWith(fontWeight: FontWeight.w600)),
                  ],
              ],
            ),
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
              Text('$active نشطة', style: AppText.caption),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(collected),
                style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
            Text(active > 0 ? 'في التوصيل' : 'متاح',
                style: AppText.caption),
          ],
        ),
      ],
    );
  }
}

class _CollectionDialog extends StatefulWidget {
  const _CollectionDialog({required this.total});

  final double total;

  @override
  State<_CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<_CollectionDialog> {
  late final TextEditingController _amount =
      TextEditingController(text: widget.total.toStringAsFixed(2));

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(_amount.text.trim());
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('تسجيل تحصيل ${money(widget.total)}'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'المبلغ المحصّل',
            prefixText: 'ج.م ',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (text) {
            final parsed = double.tryParse(text.trim());
            if (parsed != null && parsed > 0) Navigator.pop(context, parsed);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: (value != null && value > 0)
              ? () => Navigator.pop(context, value)
              : null,
          child: const Text('تسجيل'),
        ),
      ],
    );
  }
}

class _OfflineCollectionNotice extends StatelessWidget {
  const _OfflineCollectionNotice({required this.offlineTotal});

  final double offlineTotal;

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
          StatusText(
            label: offlineTotal > 0
                ? '${money(offlineTotal)} دون اتصال'
                : 'مطابقة معلقة',
            tone: StatusTone.warning,
          ),
        ],
      ),
    );
  }
}
