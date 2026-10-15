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
import '../../data/repositories/purchase_repository.dart';
import '../../data/repositories/supplier_repository.dart';
import '../../domain/models/inventory_item.dart';
import '../../domain/models/purchase_order.dart';
import '../../domain/models/supplier.dart';
import '../common/format.dart';

class PurchasingScreen extends StatefulWidget {
  const PurchasingScreen({super.key});

  @override
  State<PurchasingScreen> createState() => _PurchasingScreenState();
}

class _PurchasingScreenState extends State<PurchasingScreen> {
  List<SupplierModel> _suppliers = const [];
  List<PurchaseOrderModel> _purchases = const [];
  List<InventoryItemModel> _items = const [];
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
    final suppliers = services.suppliers;
    final purchases = services.purchases;
    final inventory = services.inventory;
    if (suppliers == null || purchases == null) {
      if (!mounted) return;
      setState(() {
        _suppliers = const [];
        _purchases = const [];
        _items = const [];
      });
      return;
    }
    final supplierList = await suppliers.listSuppliers();
    final purchaseList = await purchases.listPurchases();
    final itemList = inventory == null ? const <InventoryItemModel>[] : await inventory.listItems();
    if (!mounted) return;
    setState(() {
      _suppliers = supplierList;
      _purchases = purchaseList;
      _items = itemList;
    });
  }

  List<PurchaseOrderModel> get _open =>
      _purchases.where((p) => p.isOpen).toList();

  double get _openValue => _open.fold<double>(0, (sum, p) => sum + p.total);

  double get _payables =>
      _suppliers.fold<double>(0, (sum, s) => sum + s.payable);

  Future<void> _addSupplier() async {
    final repo = AppScope.of(context).suppliers;
    if (repo == null) return;
    final input = await showDialog<_SupplierInput>(
      context: context,
      builder: (_) => const _SupplierDialog(),
    );
    if (input == null) return;
    await repo.createSupplier(
      name: input.name,
      phone: input.phone,
      category: input.category,
      createdOffline: true,
    );
    await _load();
    _notify('المورد اتحفظ على الجهاز.');
  }

  Future<void> _createPurchase() async {
    final repo = AppScope.of(context).purchases;
    if (repo == null || _suppliers.isEmpty || _items.isEmpty) return;
    final input = await showDialog<_PurchaseInput>(
      context: context,
      builder: (_) => _PurchaseDialog(suppliers: _suppliers, items: _items),
    );
    if (input == null) return;
    await repo.createPurchase(
      supplierId: input.supplierId,
      supplierName: input.supplierName,
      reference: input.reference,
      lines: input.lines,
      createdOffline: true,
    );
    await _load();
    _notify('أمر الشراء اتعمل على الجهاز.');
  }

  Future<void> _receive(PurchaseOrderModel purchase) async {
    final repo = AppScope.of(context).purchases;
    if (repo == null) return;
    final outcome = await repo.receivePurchase(purchase.id, createdOffline: true);
    await _load();
    _notify(switch (outcome) {
      PurchaseReceiveOutcome.received =>
        'الأمر اتسلّم واترحّل للمخزون.',
      PurchaseReceiveOutcome.alreadyReceived => 'الأمر ده اتسلّم قبل كده.',
      PurchaseReceiveOutcome.notFound => 'أمر الشراء مش موجود.',
    });
  }

  Future<void> _cancelPurchase(PurchaseOrderModel purchase) async {
    final repo = AppScope.of(context).purchases;
    if (repo == null) return;
    final outcome = await repo.cancelPurchase(purchase.id, createdOffline: true);
    await _load();
    _notify(switch (outcome) {
      PurchaseCancelOutcome.cancelled => 'أمر الشراء اتلغى.',
      PurchaseCancelOutcome.alreadyReceived => 'مينفعش تلغي أمر اتسلّم قبل كده.',
      PurchaseCancelOutcome.alreadyCancelled => 'الأمر ده اتلغى قبل كده.',
      PurchaseCancelOutcome.notFound => 'أمر الشراء مش موجود.',
    });
  }

  Future<void> _paySupplier(SupplierModel supplier) async {
    final repo = AppScope.of(context).suppliers;
    if (repo == null || supplier.payable <= 0) return;
    final input = await showDialog<_PaymentInput>(
      context: context,
      builder: (_) => _PaymentDialog(supplier: supplier),
    );
    if (input == null) return;
    final outcome = await repo.recordSupplierPayment(
      supplierId: supplier.id,
      amount: input.amount,
      reference: input.reference,
      createdOffline: true,
    );
    await _load();
    _notify(switch (outcome) {
      SupplierPaymentOutcome.recorded => 'التسديد اتسجّل على الجهاز.',
      SupplierPaymentOutcome.notFound => 'المورد مش موجود.',
      SupplierPaymentOutcome.invalidAmount =>
        'دخّل مبلغ صح أكبر من صفر.',
      SupplierPaymentOutcome.exceedsPayable =>
        'المبلغ أكبر من المستحق على المورد.',
    });
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        GridRow(children: [
          StatCard(label: 'الموردون', value: '${_suppliers.length}'),
          StatCard(
            label: 'أوامر مفتوحة',
            value: '${_open.length}',
            delta: 'مستني الاستلام',
            deltaTone: _open.isEmpty ? DeltaTone.positive : DeltaTone.neutral,
          ),
          StatCard(
            label: 'قيمة الأوامر المفتوحة',
            value: money(_openValue),
            deltaTone: DeltaTone.neutral,
          ),
          StatCard(
            label: 'مستحقات الموردين',
            value: money(_payables),
            delta: 'التزامات',
            deltaTone: DeltaTone.negative,
          ),
        ]),
        _supplierCard(),
        _purchaseCard(),
        const SurfaceCard(
          level: SurfaceLevel.secondary,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.info),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'استلام أمر الشراء بيحوّل بنوده لدفتر المخزون في نفس العملية، فالمخزون والأمر مينفصلوش والاستلام ميتكررش.',
                  style: AppText.body,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _supplierCard() {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                const Expanded(
                  child: SectionHeader(
                    title: 'الموردون',
                    subtitle: 'دليل الموردين ومستحقاتهم',
                  ),
                ),
                RmsButton(
                  label: 'ضيف مورد',
                  icon: Icons.person_add_alt,
                  variant: BtnVariant.secondary,
                  onPressed: _addSupplier,
                ),
              ],
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('المورد', flex: 4),
              RmsColumn('الفئة', flex: 3),
              RmsColumn('الهاتف', flex: 3),
              RmsColumn('المستحق', flex: 3, align: TextAlign.right),
              RmsColumn('المزامنة', flex: 3),
              RmsColumn('إجراء', width: 96, align: TextAlign.center),
            ],
            rows: [
              for (final supplier in _suppliers)
                [
                  Text(supplier.name, style: AppText.tableCellPrimary),
                  Text(
                    supplier.category.isEmpty ? '—' : supplier.category,
                    style: AppText.tableCell,
                  ),
                  Text(
                    supplier.phone.isEmpty ? '—' : supplier.phone,
                    style: AppText.tableCell,
                  ),
                  Text(money(supplier.payable), style: AppText.tableCellPrimary),
                  StatusText(
                    label: orderSyncView(supplier.syncStatus).$1,
                    tone: orderSyncView(supplier.syncStatus).$2,
                  ),
                  RmsButton(
                    label: 'تسديد',
                    variant: BtnVariant.secondary,
                    dense: true,
                    onPressed: supplier.payable > 0
                        ? () => _paySupplier(supplier)
                        : null,
                  ),
                ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _purchaseCard() {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                const Expanded(
                  child: SectionHeader(
                    title: 'أوامر الشراء',
                    subtitle: 'استلام الأمر بيزوّد المخزون',
                  ),
                ),
                RmsButton(
                  label: 'أمر شراء جديد',
                  icon: Icons.add,
                  onPressed: _suppliers.isEmpty || _items.isEmpty
                      ? null
                      : _createPurchase,
                ),
              ],
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('المرجع', flex: 3),
              RmsColumn('المورد', flex: 4),
              RmsColumn('البنود', width: 70, align: TextAlign.center),
              RmsColumn('الإجمالي', flex: 3, align: TextAlign.right),
              RmsColumn('الحالة', flex: 3),
              RmsColumn('المزامنة', flex: 3),
              RmsColumn('إجراء', width: 150, align: TextAlign.center),
            ],
            rows: [
              for (final purchase in _purchases)
                [
                  Text(purchase.reference, style: AppText.tableCellPrimary),
                  Text(purchase.supplierName, style: AppText.tableCell),
                  Text(
                    '${purchase.lines.length}',
                    style: AppText.tableCell,
                    textAlign: TextAlign.center,
                  ),
                  Text(money(purchase.total), style: AppText.tableCellPrimary),
                  StatusText(
                    label: purchase.status.label,
                    tone: switch (purchase.status) {
                      PurchaseOrderStatus.received => StatusTone.positive,
                      PurchaseOrderStatus.cancelled => StatusTone.neutral,
                      PurchaseOrderStatus.ordered => StatusTone.warning,
                    },
                  ),
                  StatusText(
                    label: orderSyncView(purchase.syncStatus).$1,
                    tone: orderSyncView(purchase.syncStatus).$2,
                  ),
                  if (purchase.isOpen)
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        RmsButton(
                          label: 'استلام',
                          variant: BtnVariant.secondary,
                          dense: true,
                          onPressed: () => _receive(purchase),
                        ),
                        RmsButton(
                          label: 'إلغاء',
                          variant: BtnVariant.ghost,
                          dense: true,
                          onPressed: () => _cancelPurchase(purchase),
                        ),
                      ],
                    )
                  else
                    const Text('—', style: AppText.tableCell),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplierInput {
  const _SupplierInput({
    required this.name,
    required this.phone,
    required this.category,
  });

  final String name;
  final String phone;
  final String category;
}

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog();

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _category = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('إضافة مورد'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'اسم المورد'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'الهاتف (اختياري)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'الفئة (اختياري)'),
            ),
          ],
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
                  final name = _name.text.trim();
                  Navigator.pop(
                    context,
                    _SupplierInput(
                      name: name,
                      phone: _phone.text.trim(),
                      category: _category.text.trim(),
                    ),
                  );
                }
              : null,
          child: const Text('احفظ'),
        ),
      ],
    );
  }
}

class _PaymentInput {
  const _PaymentInput({required this.amount, required this.reference});

  final double amount;
  final String reference;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.supplier});

  final SupplierModel supplier;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reference = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final valid = amount > 0 && amount <= widget.supplier.payable;
    final entered = _amount.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('تسديد · ${widget.supplier.name}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'المستحق الحالي ${money(widget.supplier.payable)}',
              style: AppText.tableCellPrimary,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'المرجع (اختياري)'),
            ),
            if (entered && !valid) ...[
              const SizedBox(height: 8),
              Text(
                'لازم المبلغ يبقى أكبر من صفر وميعدّيش المستحق.',
                style: AppText.caption.copyWith(color: AppColors.negative),
              ),
            ],
          ],
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
                  final reference = _reference.text.trim();
                  Navigator.pop(
                    context,
                    _PaymentInput(
                      amount: amount,
                      reference: reference.isEmpty ? 'تسديد مورد' : reference,
                    ),
                  );
                }
              : null,
          child: const Text('تسديد'),
        ),
      ],
    );
  }
}

class _PurchaseInput {
  const _PurchaseInput({
    required this.supplierId,
    required this.supplierName,
    required this.reference,
    required this.lines,
  });

  final String supplierId;
  final String supplierName;
  final String reference;
  final List<PurchaseOrderLine> lines;
}

class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({required this.suppliers, required this.items});

  final List<SupplierModel> suppliers;
  final List<InventoryItemModel> items;

  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  late String _supplierId = widget.suppliers.first.id;
  late String _itemId = widget.items.first.id;
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _cost = TextEditingController();
  final List<PurchaseOrderLine> _lines = [];

  @override
  void dispose() {
    _reference.dispose();
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _addLine() {
    final item = widget.items.firstWhere((i) => i.id == _itemId);
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    final cost = double.tryParse(_cost.text.trim()) ?? 0;
    if (qty <= 0 || cost < 0) return;
    setState(() {
      _lines.add(
        PurchaseOrderLine(
          itemId: item.id,
          name: item.name,
          quantity: qty,
          unitCost: cost,
        ),
      );
      _qty.clear();
      _cost.clear();
    });
  }

  double get _draftTotal =>
      _lines.fold<double>(0, (sum, line) => sum + line.total);

  @override
  Widget build(BuildContext context) {
    final reference = _reference.text.trim();
    final canSubmit = reference.isNotEmpty && _lines.isNotEmpty;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('أمر شراء جديد'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('المورد', style: AppText.caption),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final supplier in widget.suppliers)
                    ChoiceChip(
                      label: Text(supplier.name),
                      selected: _supplierId == supplier.id,
                      onSelected: (_) =>
                          setState(() => _supplierId = supplier.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reference,
                decoration: const InputDecoration(labelText: 'المرجع'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text('البنود', style: AppText.caption),
              const SizedBox(height: 6),
              for (final line in _lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${line.name} × ${_qtyLabel(line.quantity)}',
                          style: AppText.tableCell,
                        ),
                      ),
                      Text(money(line.total), style: AppText.tableCellPrimary),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        color: AppColors.negative,
                        onPressed: () => setState(() => _lines.remove(line)),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 20),
              Text('ضيف بند', style: AppText.caption),
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qty,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'الكمية'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _cost,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(labelText: 'تكلفة الوحدة'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  RmsButton(
                    label: 'ضيف',
                    variant: BtnVariant.secondary,
                    dense: true,
                    onPressed: _addLine,
                  ),
                ],
              ),
              if (_lines.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'الإجمالي ${money(_draftTotal)}',
                  style: AppText.tableCellPrimary,
                ),
              ],
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
          onPressed: canSubmit
              ? () {
                  final supplier = widget.suppliers
                      .firstWhere((s) => s.id == _supplierId);
                  Navigator.pop(
                    context,
                    _PurchaseInput(
                      supplierId: supplier.id,
                      supplierName: supplier.name,
                      reference: reference,
                      lines: List.of(_lines),
                    ),
                  );
                }
              : null,
          child: const Text('إنشاء'),
        ),
      ],
    );
  }

  static String _qtyLabel(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
}
