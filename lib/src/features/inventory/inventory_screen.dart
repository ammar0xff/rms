import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../domain/models/inventory_item.dart';
import '../../domain/models/stock_movement.dart';
import '../common/format.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<InventoryItemModel> _items = const [];
  List<StockMovementModel> _movements = const [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).inventory;
    if (repo == null) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _movements = const [];
      });
      return;
    }
    final items = await repo.listItems();
    final movements = await repo.listMovements();
    if (!mounted) return;
    setState(() {
      _items = items;
      _movements = movements;
    });
  }

  int get _lowCount => _items.where((i) => i.isLow).length;

  int get _conflictCount =>
      _items.where((i) => i.syncStatus == SyncStatus.conflict).length;

  int get _pendingMovements =>
      _movements.where((m) => m.syncStatus != SyncStatus.synced).length;

  Future<void> _recordMovement() async {
    final repo = AppScope.of(context).inventory;
    if (repo == null || _items.isEmpty) return;
    final input = await showDialog<_MovementInput>(
      context: context,
      builder: (_) => _MovementDialog(items: _items),
    );
    if (input == null) return;
    await repo.recordMovement(
      itemId: input.itemId,
      delta: input.delta,
      reason: input.reason,
      reference: input.reference,
      createdOffline: true,
    );
    await _load();
    _notify('تم تسجيل الحركة في السجل المحلي.');
  }

  Future<void> _countStock() async {
    final repo = AppScope.of(context).inventory;
    if (repo == null || _items.isEmpty) return;
    final input = await showDialog<_CountInput>(
      context: context,
      builder: (_) => _CountDialog(items: _items),
    );
    if (input == null) return;
    final item = _items.firstWhere((i) => i.id == input.itemId);
    final outcome = await repo.adjustToCount(
      itemId: input.itemId,
      counted: input.counted,
      baseRevision: item.localRevision,
      createdOffline: true,
    );
    await _load();
    _notify(outcome == StockCountOutcome.conflict
        ? 'تعارض جرد: أُبقي الرصيد الأحدث وأُضيف الجرد للمراجعة.'
        : 'تم تحديث الرصيد بعد الجرد.');
  }

  void _notify(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final names = {for (final item in _items) item.id: item.name};
    return PageBody(
      children: [
        GridRow(children: [
          StatCard(label: 'أصناف متتبعة', value: '${_items.length}'),
          StatCard(
            label: 'أقل من حد إعادة الطلب',
            value: '$_lowCount',
            delta: 'مطلوب إجراء',
            deltaTone: _lowCount > 0 ? DeltaTone.negative : DeltaTone.positive,
          ),
          StatCard(
            label: 'حركات في السجل',
            value: '${_movements.length}',
            delta: '$_pendingMovements بانتظار المزامنة',
            deltaTone: DeltaTone.neutral,
          ),
          StatCard(
            label: 'تعارضات مخزون',
            value: '$_conflictCount',
            delta: 'مراجعة',
            deltaTone:
                _conflictCount > 0 ? DeltaTone.negative : DeltaTone.positive,
          ),
        ]),
        LayoutBuilder(
          builder: (context, c) {
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RmsButton(
                  label: 'جرد',
                  icon: Icons.fact_check_outlined,
                  variant: BtnVariant.secondary,
                  onPressed: _items.isEmpty ? null : _countStock,
                ),
                const SizedBox(width: 8),
                RmsButton(
                  label: 'تسجيل حركة',
                  icon: Icons.add,
                  onPressed: _items.isEmpty ? null : _recordMovement,
                ),
              ],
            );
            if (c.maxWidth >= 600) {
              return Row(
                children: [
                  const Expanded(
                    child: SectionHeader(
                      title: 'مستويات المخزون',
                      subtitle: 'الحركات تُسجّل إضافة فقط وتُحل صراحة عند المزامنة',
                    ),
                  ),
                  actions,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: 'مستويات المخزون',
                  subtitle: 'الحركات تُسجّل إضافة فقط وتُحل صراحة عند المزامنة',
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: actions,
                ),
              ],
            );
          },
        ),
        if (_items.isEmpty)
          const SurfaceCard(
            child: Text('لا توجد أصناف مخزون بعد.', style: AppText.caption),
          )
        else
          SurfaceCard(
            padding: EdgeInsets.zero,
            clip: true,
            child: RmsTable(
              columns: const [
                RmsColumn('الصنف', flex: 4),
                RmsColumn('المتاح', flex: 2),
                RmsColumn('حد إعادة الطلب', flex: 2),
                RmsColumn('الحالة', flex: 3),
                RmsColumn('المزامنة', flex: 3),
              ],
              rows: [
                for (final item in _items)
                  [
                    Text(item.name, style: AppText.tableCellPrimary),
                    Text(
                      '${_qty(item.onHand)} ${item.unit}',
                      style: AppText.tableCellPrimary
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text('${_qty(item.reorderAt)} ${item.unit}',
                        style: AppText.tableCell),
                    StatusText(
                      label: item.isLow ? 'أقل من حد إعادة الطلب' : 'سليم',
                      tone: item.isLow ? StatusTone.warning : StatusTone.positive,
                    ),
                    StatusText(
                      label: orderSyncView(item.syncStatus).$1,
                      tone: orderSyncView(item.syncStatus).$2,
                    ),
                  ],
              ],
            ),
          ),
        _ledgerCard(names),
        const SurfaceCard(
          level: SurfaceLevel.secondary,
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تُعلَّم حركات المخزون المتزامنة من أجهزة معزولة كتعارضات وتتطلب حلاً صريحًا — لا حلّ تلقائي أبدًا.',
                  style: AppText.body,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ledgerCard(Map<String, String> names) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: SectionHeader(
              title: 'سجل الحركات',
              subtitle: 'إضافة فقط · الرصيد هو مجموع الحركات',
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('الوقت', width: 70),
              RmsColumn('الصنف', flex: 3),
              RmsColumn('السبب', flex: 2),
              RmsColumn('المرجع', flex: 3),
              RmsColumn('الكمية', flex: 2, align: TextAlign.right),
              RmsColumn('المزامنة', flex: 3),
            ],
            rows: [
              for (final m in _movements.reversed)
                [
                  Text(_time(m.at), style: AppText.caption),
                  Text(names[m.itemId] ?? m.itemId,
                      style: AppText.tableCellPrimary),
                  Text(m.reason.label, style: AppText.tableCell),
                  Text(m.reference ?? '—', style: AppText.tableCell),
                  Text(
                    _signed(m.delta),
                    style: AppText.tableCellPrimary.copyWith(
                      fontWeight: FontWeight.w600,
                      color: m.isIncrease
                          ? AppColors.positive
                          : AppColors.negative,
                    ),
                  ),
                  StatusText(
                    label: orderSyncView(m.syncStatus).$1,
                    tone: orderSyncView(m.syncStatus).$2,
                  ),
                ],
            ],
          ),
        ],
      ),
    );
  }

  static String _qty(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);

  static String _signed(double value) =>
      '${value > 0 ? '+' : ''}${_qty(value)}';

  static String _time(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _MovementInput {
  const _MovementInput({
    required this.itemId,
    required this.delta,
    required this.reason,
    this.reference,
  });

  final String itemId;
  final double delta;
  final StockMovementReason reason;
  final String? reference;
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({required this.items});

  final List<InventoryItemModel> items;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  late String _itemId = widget.items.first.id;
  StockMovementReason _reason = StockMovementReason.receipt;
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _ref = TextEditingController();

  @override
  void dispose() {
    _qty.dispose();
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsedQty = double.tryParse(_qty.text.trim());
    final valid = parsedQty != null && parsedQty != 0;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('تسجيل حركة مخزون'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('الصنف', style: AppText.caption),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in widget.items)
                    ChoiceChip(
                      label: Text(item.name),
                      selected: _itemId == item.id,
                      onSelected: (_) => setState(() => _itemId = item.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('السبب', style: AppText.caption),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in StockMovementReason.values)
                    ChoiceChip(
                      label: Text(reason.label),
                      selected: _reason == reason,
                      onSelected: (_) => setState(() => _reason = reason),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _qty,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'الكمية',
                  helperText: 'موجب للإضافة، سالب للصرف',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ref,
                decoration: const InputDecoration(labelText: 'المرجع (اختياري)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: valid
              ? () {
                  final delta = double.parse(_qty.text.trim());
                  final reference = _ref.text.trim();
                  Navigator.pop(
                    context,
                    _MovementInput(
                      itemId: _itemId,
                      delta: delta,
                      reason: _reason,
                      reference: reference.isEmpty ? null : reference,
                    ),
                  );
                }
              : null,
          child: const Text('تسجيل'),
        ),
      ],
    );
  }
}

class _CountInput {
  const _CountInput({required this.itemId, required this.counted});

  final String itemId;
  final double counted;
}

class _CountDialog extends StatefulWidget {
  const _CountDialog({required this.items});

  final List<InventoryItemModel> items;

  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  late String _itemId = widget.items.first.id;
  final TextEditingController _counted = TextEditingController();

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items.firstWhere((i) => i.id == _itemId);
    final parsedCount = double.tryParse(_counted.text.trim());
    final valid = parsedCount != null && parsedCount >= 0;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('جرد المخزون'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('الصنف', style: AppText.caption),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final candidate in widget.items)
                    ChoiceChip(
                      label: Text(candidate.name),
                      selected: _itemId == candidate.id,
                      onSelected: (_) => setState(() => _itemId = candidate.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'الرصيد الحالي ${_InventoryScreenState._qty(item.onHand)} ${item.unit}',
                style: AppText.caption,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _counted,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'الكمية المعدودة',
                  helperText: 'يُسجَّل الفرق كتسوية جرد',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: valid
              ? () {
                  final counted = double.parse(_counted.text.trim());
                  Navigator.pop(
                    context,
                    _CountInput(itemId: _itemId, counted: counted),
                  );
                }
              : null,
          child: const Text('تطبيق الجرد'),
        ),
      ],
    );
  }
}
