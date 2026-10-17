import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/app_role.dart';
import '../../domain/models/inventory_item.dart';
import '../../domain/models/stock_movement.dart';
import '../../data/repositories/inventory_repository.dart';

/// Screen 21: Inventory levels, reorder alerts, movement ledger, and stale-safe
/// physical count adjustment.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<InventoryItemModel> _items = [];
  List<StockMovementModel> _movements = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _onlyLowStock = false;
  InventoryItemModel? _selectedItem;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final repo = AppScope.of(context).inventory;
    if (repo == null) {
      setState(() => _isLoading = false);
      return;
    }
    final items = await repo.listItems();
    final movements = await repo.listMovements();
    if (mounted) {
      setState(() {
        _items = items;
        _movements = movements.reversed.toList(); // Newest first for UI
        if (_selectedItem != null) {
          _selectedItem = items.where((i) => i.id == _selectedItem!.id).firstOrNull;
        }
        _isLoading = false;
      });
    }
  }

  List<InventoryItemModel> get _filteredItems {
    return _items.where((item) {
      if (_onlyLowStock && !item.isLow) return false;
      if (_searchQuery.isNotEmpty && !item.name.contains(_searchQuery)) {
        return false;
      }
      return true;
    }).toList();
  }

  void _openCountSheet(InventoryItemModel item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PhysicalCountSheet(
        item: item,
        onCountApplied: () {
          Navigator.pop(sheetContext);
          _loadData();
        },
      ),
    );
  }

  void _openMovementDialog(InventoryItemModel item) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => _QuickMovementDialog(
        item: item,
        onMovementSaved: () {
          Navigator.pop(dialogCtx);
          _loadData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        appBar: AppBar(
          backgroundColor: PieColors.surface1,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'إدارة المخزون والمستودع',
            style: PieTypography.h2.copyWith(color: PieColors.textPrimary),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: PieColors.textSecondary),
              tooltip: 'تحديث البيانات',
              onPressed: _loadData,
            ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: PieColors.roleManager,
            indicatorWeight: 3,
            labelColor: PieColors.roleManager,
            unselectedLabelColor: PieColors.textMuted,
            labelStyle: PieTypography.label.copyWith(fontWeight: FontWeight.bold),
            tabs: [
              Tab(
                text: 'أرصدة الأصناف (${_items.length})',
                icon: const Icon(Icons.inventory_2_outlined, size: 20),
              ),
              Tab(
                text: 'سجل الحركات (${_movements.length})',
                icon: const Icon(Icons.receipt_long_outlined, size: 20),
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: PieColors.roleManager),
              )
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildItemsTab(),
                  _buildMovementsTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildItemsTab() {
    final filtered = _filteredItems;
    final lowStockCount = _items.where((i) => i.isLow).length;
    final isDesktop = MediaQuery.of(context).size.width >= 1024;

    return Column(
      children: [
        // Filter toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: PieColors.surface2,
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'بحث باسم الصنف...',
                      hintStyle: PieTypography.body.copyWith(color: PieColors.textMuted),
                      prefixIcon: const Icon(Icons.search, color: PieColors.textMuted, size: 20),
                      filled: true,
                      fillColor: PieColors.well,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: Text(
                  'النواقص ($lowStockCount)',
                  style: PieTypography.caption.copyWith(
                    color: _onlyLowStock ? PieColors.stateError : PieColors.textSecondary,
                    fontWeight: _onlyLowStock ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: _onlyLowStock,
                selectedColor: PieColors.stateError.withValues(alpha: 0.15),
                backgroundColor: PieColors.well,
                side: BorderSide(
                  color: _onlyLowStock ? PieColors.stateError : PieColors.borderMuted,
                ),
                onSelected: (val) => setState(() => _onlyLowStock = val),
              ),
            ],
          ),
        ),

        // Items list & Desktop detail split
        Expanded(
          child: filtered.isEmpty
              ? const PieEmptyState(
                  icon: Icons.inventory_outlined,
                  title: 'لا توجد أصناف تطابق البحث',
                  subtitle: 'تأكد من كتابة الاسم بدقة أو ألغِ تفعيل فلتر النواقص.',
                )
              : isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) => _buildItemCard(
                              filtered[i],
                              isSelected: _selectedItem?.id == filtered[i].id,
                              onTap: () => setState(() => _selectedItem = filtered[i]),
                            ),
                          ),
                        ),
                        Container(width: 1, color: PieColors.borderSubtle),
                        Expanded(
                          flex: 2,
                          child: _selectedItem == null
                              ? const Center(
                                  child: Text(
                                    'اختر صنفاً لعرض تفاصيل حركاته ومستوياته',
                                    style: TextStyle(color: PieColors.textMuted),
                                  ),
                                )
                              : _buildItemDetailPane(_selectedItem!),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) => _buildItemCard(filtered[i]),
                    ),
        ),
      ],
    );
  }

  Widget _buildItemCard(
    InventoryItemModel item, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PieCard(
        role: AppRole.manager,
        surface: isSelected ? PieColors.surface3 : PieColors.surface2,
        borderColor: isSelected
            ? PieColors.roleManager
            : (item.isLow ? PieColors.stateError.withValues(alpha: 0.5) : null),
        onTap: onTap ?? () => _openCountSheet(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'الوحدة: ${item.unit}',
                            style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'المراجعة: ر.${item.localRevision}',
                            style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (item.isLow)
                  const PieBadge(
                    label: 'دون حد الطلب',
                    variant: PieBadgeVariant.error,
                  )
                else
                  const PieBadge(
                    label: 'متوفر',
                    variant: PieBadgeVariant.synced,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PieColors.well,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الرصيد الفعلي الحالي',
                        style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          PieNumeral.value(
                            item.onHand,
                            decimals: 2,
                            style: PieTypography.h2.copyWith(
                              color: item.isLow ? PieColors.stateError : PieColors.roleManager,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.unit,
                            style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'نقطة إعادة الطلب',
                        style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          PieNumeral.value(
                            item.reorderAt,
                            decimals: 2,
                            style: PieTypography.body.copyWith(
                              color: PieColors.textMuted,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.unit,
                            style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PieButton(
                    label: 'تسوية الجرد الفعلي',
                    icon: Icons.checklist_rtl_outlined,
                    variant: PieButtonVariant.secondary,
                    role: AppRole.manager,
                    onPressed: () => _openCountSheet(item),
                  ),
                ),
                const SizedBox(width: 8),
                PieButton(
                  label: 'حركة سريعة',
                  icon: Icons.swap_vert,
                  variant: PieButtonVariant.ghost,
                  role: AppRole.manager,
                  onPressed: () => _openMovementDialog(item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemDetailPane(InventoryItemModel item) {
    final itemMovements = _movements.where((m) => m.itemId == item.id).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تفاصيل الصنف: ${item.name}',
            style: PieTypography.h2.copyWith(color: PieColors.textPrimary),
          ),
          const SizedBox(height: 12),
          PieCard(
            surface: PieColors.surface2,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('معرف الصنف:', style: TextStyle(color: PieColors.textSecondary)),
                    Text(item.id, style: const TextStyle(color: PieColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('المراجعة المحلية الحالية:', style: TextStyle(color: PieColors.textSecondary)),
                    Text('v${item.localRevision}', style: const TextStyle(color: PieColors.roleManager, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'حركات هذا الصنف (${itemMovements.length})',
            style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: itemMovements.isEmpty
                ? const PieEmptyState(
                    icon: Icons.history,
                    title: 'لا توجد حركات مسجلة لهذا الصنف',
                  )
                : ListView.builder(
                    itemCount: itemMovements.length,
                    itemBuilder: (ctx, i) => _buildMovementCard(itemMovements[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementsTab() {
    if (_movements.isEmpty) {
      return const PieEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'سجل حركات المخزون فارغ',
        subtitle: 'ستظهر هنا كل حركات البيع، التوريد، التلف، والتسويات الجردية.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _movements.length,
      itemBuilder: (ctx, i) => _buildMovementCard(_movements[i]),
    );
  }

  Widget _buildMovementCard(StockMovementModel m) {
    final item = _items.where((i) => i.id == m.itemId).firstOrNull;
    final itemName = item?.name ?? m.itemId;
    final unit = item?.unit ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PieCard(
        surface: PieColors.surface2,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: m.isIncrease
                    ? PieColors.stateSynced.withValues(alpha: 0.15)
                    : PieColors.stateError.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                m.isIncrease ? Icons.arrow_upward : Icons.arrow_downward,
                color: m.isIncrease ? PieColors.stateSynced : PieColors.stateError,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        itemName,
                        style: PieTypography.body.copyWith(
                          color: PieColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: PieColors.well,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          m.reason.label,
                          style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _formatTime(m.at),
                        style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                      ),
                      if (m.reference != null && m.reference!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          'مرجع: ${m.reference}',
                          style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                        ),
                      ],
                      if (m.baseRevision != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          'مبني على ر.${m.baseRevision}',
                          style: PieTypography.caption.copyWith(color: PieColors.roleManager),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Text(
                      m.isIncrease ? '+' : '',
                      style: PieTypography.body.copyWith(
                        color: m.isIncrease ? PieColors.stateSynced : PieColors.stateError,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    PieNumeral.value(
                      m.delta,
                      decimals: 2,
                      style: PieTypography.body.copyWith(
                        color: m.isIncrease ? PieColors.stateSynced : PieColors.stateError,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                PieBadge(
                  label: m.createdOffline ? 'محلي' : 'متزامن',
                  variant: m.createdOffline
                      ? PieBadgeVariant.localOnly
                      : PieBadgeVariant.synced,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Physical count adjustment sheet verifying base revision.
class _PhysicalCountSheet extends StatefulWidget {
  const _PhysicalCountSheet({
    required this.item,
    required this.onCountApplied,
  });

  final InventoryItemModel item;
  final VoidCallback onCountApplied;

  @override
  State<_PhysicalCountSheet> createState() => _PhysicalCountSheetState();
}

class _PhysicalCountSheetState extends State<_PhysicalCountSheet> {
  late TextEditingController _countController;
  bool _isSubmitting = false;
  String? _conflictError;

  @override
  void initState() {
    super.initState();
    _countController = TextEditingController(text: widget.item.onHand.toString());
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  Future<void> _submitCount() async {
    final val = double.tryParse(_countController.text.trim());
    if (val == null || val < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال كمية عددية صحيحة أكبر من أو تساوي صفراً')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _conflictError = null;
    });

    final repo = AppScope.of(context).inventory;
    if (repo == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    // Call adjustToCount passing current item.localRevision as baseRevision
    final outcome = await repo.adjustToCount(
      itemId: widget.item.id,
      counted: val,
      baseRevision: widget.item.localRevision,
      createdOffline: true,
    );

    if (!mounted) return;

    if (outcome == StockCountOutcome.applied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تثبيت جرد صنف "${widget.item.name}" بنجاح.'),
          backgroundColor: PieColors.stateSynced,
        ),
      );
      widget.onCountApplied();
    } else {
      setState(() {
        _isSubmitting = false;
        _conflictError =
            'تنبيه تعارض: تم تسجيل حركة جديدة على هذا الصنف في الخلفية أثناء عملية الجرد! '
            'تم تعليق التسوية لمنع مسح الحركات الأحدث تلقائياً.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = (double.tryParse(_countController.text) ?? widget.item.onHand) - widget.item.onHand;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: PieColors.surface2,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24,
          left: 20,
          right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'جرد فعلي: ${widget.item.name}',
                  style: PieTypography.h2.copyWith(color: PieColors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: PieColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'أدخل الكمية المحصورة فعلياً في المستودع. يتم ربط العملية برقم المراجعة ر.${widget.item.localRevision} لحمايتها من الكتابة فوق حركات موازية.',
              style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (_conflictError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PieColors.stateError.withValues(alpha: 0.15),
                  border: Border.all(color: PieColors.stateError),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: PieColors.stateError),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _conflictError!,
                        style: PieTypography.body.copyWith(color: PieColors.stateError),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PieColors.well,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'الرصيد الدفتري الحالي المسجل:',
                        style: PieTypography.body.copyWith(color: PieColors.textSecondary),
                      ),
                      Row(
                        children: [
                          PieNumeral.value(
                            widget.item.onHand,
                            decimals: 2,
                            style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                          ),
                          const SizedBox(width: 4),
                          Text(widget.item.unit, style: const TextStyle(color: PieColors.textMuted)),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: PieColors.borderSubtle),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'الكمية الفعلية المحصورة:',
                        style: PieTypography.body.copyWith(
                          color: PieColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        height: 48,
                        child: TextField(
                          controller: _countController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          style: PieTypography.h2.copyWith(color: PieColors.roleManager),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: PieColors.surface3,
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: PieColors.roleManager),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'فارق التسوية الناتج:',
                        style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                      ),
                      Row(
                        children: [
                          Text(
                            diff >= 0 ? '+${diff.toStringAsFixed(2)}' : diff.toStringAsFixed(2),
                            style: PieTypography.body.copyWith(
                              color: diff == 0
                                  ? PieColors.textMuted
                                  : (diff > 0 ? PieColors.stateSynced : PieColors.stateError),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(widget.item.unit, style: const TextStyle(color: PieColors.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: PieButton(
                label: _isSubmitting ? 'جاري التحقق والتثبيت...' : 'تثبيت رصيد الجرد الفعلي',
                icon: Icons.check_circle_outline,
                role: AppRole.manager,
                variant: PieButtonVariant.primary,
                onPressed: _isSubmitting ? null : _submitCount,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick manual relative movement dialog (e.g. spoilage, receipt).
class _QuickMovementDialog extends StatefulWidget {
  const _QuickMovementDialog({
    required this.item,
    required this.onMovementSaved,
  });

  final InventoryItemModel item;
  final VoidCallback onMovementSaved;

  @override
  State<_QuickMovementDialog> createState() => _QuickMovementDialogState();
}

class _QuickMovementDialogState extends State<_QuickMovementDialog> {
  final _amountController = TextEditingController();
  final _refController = TextEditingController();
  StockMovementReason _reason = StockMovementReason.receipt;
  bool _isOutbound = false;

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال كمية صحيحة أكبر من صفر')),
      );
      return;
    }

    final repo = AppScope.of(context).inventory;
    if (repo == null) return;

    final delta = _isOutbound ? -amount : amount;
    await repo.recordMovement(
      itemId: widget.item.id,
      delta: delta,
      reason: _reason,
      reference: _refController.text.trim().isEmpty ? null : _refController.text.trim(),
      createdOffline: true,
    );

    widget.onMovementSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: PieColors.surface2,
        title: Text(
          'تسجيل حركة سريعة: ${widget.item.name}',
          style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('إدخال (+)')),
                      selected: !_isOutbound,
                      selectedColor: PieColors.stateSynced.withValues(alpha: 0.2),
                      onSelected: (val) {
                        setState(() {
                          _isOutbound = false;
                          _reason = StockMovementReason.receipt;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('إخراج (-)')),
                      selected: _isOutbound,
                      selectedColor: PieColors.stateError.withValues(alpha: 0.2),
                      onSelected: (val) {
                        setState(() {
                          _isOutbound = true;
                          _reason = StockMovementReason.spoilage;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('السبب:', style: PieTypography.caption.copyWith(color: PieColors.textSecondary)),
              const SizedBox(height: 4),
              DropdownButtonFormField<StockMovementReason>(
                value: _reason,
                dropdownColor: PieColors.surface3,
                style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: PieColors.well,
                  border: OutlineInputBorder(),
                ),
                items: (_isOutbound
                        ? [
                            StockMovementReason.spoilage,
                            StockMovementReason.adjustment,
                            StockMovementReason.transfer,
                          ]
                        : [
                            StockMovementReason.receipt,
                            StockMovementReason.customerReturn,
                            StockMovementReason.adjustment,
                          ])
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _reason = val);
                },
              ),
              const SizedBox(height: 16),
              Text('الكمية (${widget.item.unit}):', style: PieTypography.caption.copyWith(color: PieColors.textSecondary)),
              const SizedBox(height: 4),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: '0.00',
                  filled: true,
                  fillColor: PieColors.well,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text('ملاحظة أو رقم المرجع:', style: PieTypography.caption.copyWith(color: PieColors.textSecondary)),
              const SizedBox(height: 4),
              TextField(
                controller: _refController,
                style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'مثال: رقم إذن الاستلام أو تقرير التلف',
                  filled: true,
                  fillColor: PieColors.well,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: PieColors.textMuted)),
          ),
          PieButton(
            label: 'حفظ الحركة',
            role: AppRole.manager,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
