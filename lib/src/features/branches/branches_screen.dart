import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/blocks.dart';
import '../../core/widgets/role_ui.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/models/branch.dart';
import '../../domain/models/inventory_item.dart';
import '../../domain/models/stock_transfer.dart';
import '../common/format.dart';

class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  ConsolidationSnapshot? _snapshot;
  List<StockTransfer> _transfers = const [];
  bool _available = true;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).branches;
    if (repo == null) {
      if (!mounted) return;
      setState(() {
        _available = false;
        _snapshot = null;
      });
      return;
    }
    final snapshot = await repo.consolidate();
    final transfersRepo = AppScope.of(context).transfers;
    final transfers = transfersRepo == null
        ? const <StockTransfer>[]
        : await transfersRepo.listTransfers();
    if (!mounted) return;
    setState(() {
      _available = true;
      _snapshot = snapshot;
      _transfers = transfers;
    });
  }

  Future<void> _receiveTransfer(StockTransfer transfer) async {
    final repo = AppScope.of(context).transfers;
    if (repo == null) return;
    try {
      await repo.receiveTransfer(transfer.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الاستلام — جرّب تاني')),
      );
      return;
    }
    await _load();
  }

  Future<void> _requestTransfer() async {
    final services = AppScope.of(context);
    final transfers = services.transfers;
    final inventory = services.inventory;
    if (transfers == null || inventory == null) return;
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final items = await inventory.listItems();
    if (!mounted) return;
    final input = await showDialog<_TransferInput>(
      context: context,
      builder: (_) => _TransferDialog(
        branches: snapshot.branches.map((b) => b.branch).toList(),
        items: items,
      ),
    );
    if (input == null) return;
    await transfers.requestTransfer(
      itemId: input.itemId,
      itemName: input.itemName,
      quantity: input.quantity,
      unit: input.unit,
      fromBranchId: input.fromBranch.id,
      fromBranchName: input.fromBranch.name,
      toBranchId: input.toBranch.id,
      toBranchName: input.toBranch.name,
      courier: input.courier,
      note: input.note,
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اتطلب الإمداد وهيستنى الطرف التاني')),
    );
  }

  Future<void> _exportCsv() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    await Clipboard.setData(ClipboardData(text: snapshot.toCsv()));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('تقرير توحيد الفروع اتنسخ CSV.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    if (!_available) {
      return const PageBody(
        children: [
          EmptyState(
            icon: Icons.storefront_outlined,
            title: 'توحيد الفروع غير متاح',
            message:
                'مفيش مخزن محلي في الجلسة دي، فمش هنقدر نجمّع بيانات الفروع.',
          ),
        ],
      );
    }

    return PageBody(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (snapshot != null) ...[
                  StatusText(
                    label: _freshnessLabel(snapshot),
                    tone: _freshnessTone(snapshot),
                  ),
                  const SizedBox(width: 12),
                ],
                IconBtn(
                    icon: Icons.refresh, tooltip: 'حدّث', onPressed: _load),
                const SizedBox(width: 8),
                RmsButton(
                  label: 'نزّل CSV',
                  icon: Icons.download,
                  onPressed: snapshot == null ? null : _exportCsv,
                ),
              ],
            );
            if (c.maxWidth >= 600) {
              return Row(
                children: [
                  const Expanded(
                    child: SectionHeader(
                      title: 'توحيد الفروع',
                      subtitle:
                          'فرع الجهاز مقري مباشرة من المخازن · وباقي الفروع من آخر تجميع اتزامن',
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
                  title: 'توحيد الفروع',
                  subtitle:
                      'فرع الجهاز مقري مباشرة من المخازن · وباقي الفروع من آخر تجميع اتزامن',
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
        if (snapshot == null)
          const SurfaceCard(
            child: Text('بنجمّع بيانات الفروع دلوقتي…', style: AppText.caption),
          )
        else ...[
          _kpiGrid(snapshot),
          _branchesCard(snapshot),
          _TransferCard(
            transfers: _transfers,
            onRequest: _requestTransfer,
            onReceive: _receiveTransfer,
            onAdvance: (t) async {
              final repo = AppScope.of(context).transfers;
              if (repo == null) return;
              await repo.advanceTransfer(t.id);
              await _load();
            },
            onCancel: (t) async {
              final repo = AppScope.of(context).transfers;
              if (repo == null) return;
              await repo.cancelTransfer(t.id);
              await _load();
            },
          ),
          const SurfaceCard(
            level: SurfaceLevel.secondary,
            child: Row(
              children: [
                Icon(Icons.hub_outlined, size: 16, color: AppColors.info),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'فرع الجهاز ده بيتحسب لحظيًا من السجلات الإضافة-فقط، وباقي الفروع من آخر تجميع وصل من السيرفر. فالتوحيد متسق من غير نت، واللي بيتغيّر بس حداثة البيانات: الفروع المتأخرة أو اللي مفيش عندها تجميع لسه بتبان بوضوح بدل ما تتحسب صفر.',
                    style: AppText.body,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _kpiGrid(ConsolidationSnapshot snapshot) {
    return GridRow(children: [
      StatCard(
        label: 'إجمالي المبيعات',
        value: money(snapshot.totalSales),
        delta: '${snapshot.reportingCount} فرع',
        deltaTone: DeltaTone.neutral,
      ),
      StatCard(
        label: 'الطلبات',
        value: '${snapshot.totalOrders}',
        delta: 'على النت',
        deltaTone: DeltaTone.neutral,
      ),
      StatCard(
        label: 'التحصيل',
        value: money(snapshot.totalCollected),
        delta: snapshot.isPartial ? 'بيانات جزئية' : 'خلصان',
        deltaTone: snapshot.isPartial ? DeltaTone.neutral : DeltaTone.positive,
      ),
      StatCard(
        label: 'وحدات المخزون',
        value: _qty(snapshot.totalInventoryUnits),
        delta: 'مجموع الرصيد المتاح',
        deltaTone: DeltaTone.neutral,
      ),
    ]);
  }

  Widget _branchesCard(ConsolidationSnapshot snapshot) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: SectionHeader(
              title: 'شبكة الفروع',
              subtitle: 'مبيعات، طلبات، تحصيل ومخزون لكل فرع',
              trailing: Tag(
                label: '${snapshot.activeCount} نشط · ${snapshot.branchCount} إجمالي',
                tone: StatusTone.info,
              ),
            ),
          ),
          RmsTable(
            onRowTap: (i) => _showDetail(snapshot.branches[i]),
            columns: const [
              RmsColumn('الفرع', flex: 4),
              RmsColumn('الحالة', flex: 2),
              RmsColumn('الطلبات', flex: 2),
              RmsColumn('المبيعات', flex: 3, align: TextAlign.right),
              RmsColumn('التحصيل', flex: 3, align: TextAlign.right),
              RmsColumn('المخزون', flex: 2, align: TextAlign.right),
              RmsColumn('المصدر', flex: 3),
              RmsColumn('الحداثة', flex: 3),
            ],
            rows: [
              for (final breakdown in snapshot.branches)
                [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(breakdown.branch.name,
                          style: AppText.tableCellPrimary),
                      Text(
                        '${breakdown.branch.code} · ${breakdown.branch.city}',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                  Tag(
                    label: breakdown.branch.status.label,
                    tone: _statusTone(breakdown.branch.status),
                  ),
                  Text('${breakdown.rollup?.orders ?? '—'}',
                      style: AppText.tableCell),
                  Text(
                    breakdown.rollup == null
                        ? '—'
                        : money(breakdown.rollup!.sales),
                    style: AppText.tableCellPrimary,
                  ),
                  Text(
                    breakdown.rollup == null
                        ? '—'
                        : money(breakdown.rollup!.collected),
                    style: AppText.tableCellPrimary,
                  ),
                  Text(
                    breakdown.rollup == null
                        ? '—'
                        : _qty(breakdown.rollup!.inventoryUnits),
                    style: AppText.tableCell,
                  ),
                  _sourceTag(breakdown),
                  Text(
                    _age(breakdown.rollup?.asOf),
                    style: AppText.caption,
                  ),
                ],
            ],
          ),
        ],
      ),
    );
  }

  /// Read-only drill-down: the row's figures plus provenance (live vs
  /// cached, how old). No actions — branches are managed elsewhere.
  void _showDetail(BranchBreakdown breakdown) {
    final rollup = breakdown.rollup;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(breakdown.branch.name, style: AppText.h1),
                ),
                _sourceTag(breakdown),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${breakdown.branch.code} · ${breakdown.branch.city}',
              style: AppText.caption,
            ),
            const SizedBox(height: 12),
            KvPanel(pairs: [
              ('الطلبات', rollup == null ? '—' : '${rollup.orders}'),
              ('المبيعات',
                  rollup == null ? '—' : money(rollup.sales)),
              ('التحصيل',
                  rollup == null ? '—' : money(rollup.collected)),
              ('المخزون',
                  rollup == null ? '—' : _qty(rollup.inventoryUnits)),
              (
                'عمليات معلقة',
                rollup == null ? '—' : '${rollup.pending}',
              ),
              ('حداثة البيانات', _age(rollup?.asOf)),
            ]),
            const SizedBox(height: 16),
            RmsButton(
              label: 'اقفل',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

/// Transfer tracker: open transfers with their next action, closed
/// history below. Request sheet picks donor, receiver, item, and quantity.
class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.transfers,
    required this.onRequest,
    required this.onReceive,
    required this.onAdvance,
    required this.onCancel,
  });

  final List<StockTransfer> transfers;
  final VoidCallback onRequest;
  final ValueChanged<StockTransfer> onReceive;
  final ValueChanged<StockTransfer> onAdvance;
  final ValueChanged<StockTransfer> onCancel;

  @override
  Widget build(BuildContext context) {
    final open = transfers.where((t) => t.status.isOpen).toList();
    final closed =
        transfers.where((t) => !t.status.isOpen).take(5).toList();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'تحويلات المخزون',
            subtitle: 'إمداد بين الفروع بتتبع واضح',
            trailing: RmsButton(
              label: 'طلب إمداد',
              icon: Icons.add,
              onPressed: onRequest,
            ),
          ),
          const SizedBox(height: 12),
          if (open.isEmpty)
            const Text('مفيش تحويلات مفتوحة.',
                style: AppText.caption)
          else
            for (final t in open) ...[
              _TransferRow(
                transfer: t,
                onAdvance: () => onAdvance(t),
                onReceive: () => onReceive(t),
                onCancel: () => onCancel(t),
              ),
              const SizedBox(height: 10),
            ],
          if (closed.isNotEmpty) ...[
            const Divider(height: 20),
            for (final t in closed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${t.itemName} × ${t.quantity} · ${t.status.label}',
                  style: AppText.caption,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.transfer,
    required this.onAdvance,
    required this.onReceive,
    required this.onCancel,
  });

  final StockTransfer transfer;
  final VoidCallback onAdvance;
  final VoidCallback onReceive;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = transfer;
    final nextLabel = switch (t.status) {
      TransferStatus.requested => 'اعتماد',
      TransferStatus.approved => 'شحن',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FeedRow(
          tone: StatusTone.info,
          title: '${t.itemName} × ${t.quantity} ${t.unit}',
          subtitle: '${t.fromBranchName} ← ${t.toBranchName}'
              '${t.courier.isEmpty ? '' : ' · ${t.courier}'}',
          trailing: Tag(label: t.status.label, tone: StatusTone.info),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (nextLabel != null)
              RmsButton(label: nextLabel, onPressed: onAdvance),
            if (t.status == TransferStatus.inTransit)
              RmsButton(
                label: 'أكّد الاستلام',
                variant: BtnVariant.primary,
                onPressed: onReceive,
              ),
            if (t.status.isOpen)
              RmsButton(
                label: 'إلغاء',
                variant: BtnVariant.ghost,
                onPressed: onCancel,
              ),
          ],
        ),
      ],
    );
  }
}

class _TransferInput {
  _TransferInput({
    required this.fromBranch,
    required this.toBranch,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.courier,
    this.note,
  });

  final BranchModel fromBranch;
  final BranchModel toBranch;
  final String itemId;
  final String itemName;
  final double quantity;
  final String unit;
  final String courier;
  final String? note;
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.branches, required this.items});

  final List<BranchModel> branches;
  final List<InventoryItemModel> items;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  late BranchModel _from = widget.branches.first;
  late BranchModel _to = widget.branches.length > 1
      ? widget.branches[1]
      : widget.branches.first;
  InventoryItemModel? _item;
  final _qty = TextEditingController();
  final _courier = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.items.isNotEmpty) _item = widget.items.first;
  }

  @override
  void dispose() {
    _qty.dispose();
    _courier.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qty = double.tryParse(_qty.text.trim());
    final valid = _item != null &&
        qty != null &&
        qty > 0 &&
        _from.id != _to.id;
    return DialogShell(
      title: 'طلب إمداد بين الفروع',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _drop<BranchModel>(
            label: 'من فرع',
            value: _from,
            options: widget.branches,
            title: (b) => b.name,
            onPick: (b) => setState(() => _from = b),
          ),
          const SizedBox(height: 10),
          _drop<BranchModel>(
            label: 'إلى فرع',
            value: _to,
            options: widget.branches,
            title: (b) => b.name,
            onPick: (b) => setState(() => _to = b),
          ),
          const SizedBox(height: 10),
          _drop<InventoryItemModel>(
            label: 'الصنف',
            value: _item,
            options: widget.items,
            title: (i) => '${i.name} (${i.unit})',
            onPick: (i) => setState(() => _item = i),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'الكمية',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _courier,
            decoration: const InputDecoration(
              labelText: 'المندوب (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        RmsButton(
          label: 'إلغاء',
          variant: BtnVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RmsButton(
          label: 'ابعت الطلب',
          onPressed: valid
              ? () => Navigator.of(context).pop(
                    _TransferInput(
                      fromBranch: _from,
                      toBranch: _to,
                      itemId: _item!.id,
                      itemName: _item!.name,
                      quantity: qty!,
                      unit: _item!.unit,
                      courier: _courier.text.trim(),
                      note: _note.text.trim().isEmpty
                          ? null
                          : _note.text.trim(),
                    ),
                  )
              : null,
        ),
      ],
    );
  }

  Widget _drop<T>({
    required String label,
    required T? value,
    required List<T> options,
    required String Function(T) title,
    required ValueChanged<T> onPick,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o, child: Text(title(o))),
      ],
      onChanged: (v) {
        if (v != null) onPick(v);
      },
    );
  }
}

  Widget _sourceTag(BranchBreakdown breakdown) {
    if (breakdown.live) {
      return const Tag(label: 'مباشر', tone: StatusTone.positive);
    }
    if (!breakdown.hasData) {
      return const Tag(label: 'مفيش بيانات', tone: StatusTone.neutral);
    }
    if (breakdown.stale) {
      return const Tag(label: 'متأخر', tone: StatusTone.warning);
    }
    return const Tag(label: 'مخزّن', tone: StatusTone.info);
  }

  static StatusTone _statusTone(BranchStatus status) => switch (status) {
        BranchStatus.active => StatusTone.positive,
        BranchStatus.paused => StatusTone.warning,
        BranchStatus.closed => StatusTone.neutral,
      };

  static String _freshnessLabel(ConsolidationSnapshot snapshot) {
    if (snapshot.staleCount > 0) {
      return '${snapshot.staleCount} فرع متأخر';
    }
    if (snapshot.missingCount > 0) {
      return '${snapshot.missingCount} فرع من غير بيانات';
    }
    return 'خلصان · ${snapshot.reportingCount} فرع';
  }

  static StatusTone _freshnessTone(ConsolidationSnapshot snapshot) {
    if (snapshot.staleCount > 0) return StatusTone.warning;
    if (snapshot.missingCount > 0) return StatusTone.neutral;
    return StatusTone.positive;
  }

  static String _age(DateTime? at) {
    if (at == null) return '—';
    final age = DateTime.now().difference(at);
    if (age.inSeconds < 60) return 'دلوقتي';
    if (age.inMinutes < 60) return 'قبل ${age.inMinutes} دقيقة';
    if (age.inHours < 24) return 'قبل ${age.inHours} ساعة';
    return 'قبل ${age.inDays} يوم';
  }

  static String _qty(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
}
