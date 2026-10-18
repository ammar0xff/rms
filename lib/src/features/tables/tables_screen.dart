import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/dining_table.dart';

/// Screen 4: Tables Floor (إدارة الصالة والطاولات)
///
/// Functional contract:
/// - Occupancy summary bar
/// - Status filter pills with counts
/// - Table cards with code, zone, capacity, state, party, steward, elapsed, running bill
/// - Explicit per-state actions
class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  TableStatus? _selectedStatusFilter;
  String _selectedZone = 'الكل';
  List<DiningTable> _tables = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTables());
  }

  Future<void> _loadTables() async {
    final repo = AppScope.of(context).tables;
    if (repo == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final list = await repo.listTables();
    if (mounted) {
      setState(() {
        _tables = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final tablesRepo = services.tables;

    if (tablesRepo == null) {
      return const PieEmptyState(
        title: 'قاعدة بيانات الطاولات غير متاحة',
        description: 'اتأكد من تهيئة قاعدة البيانات المحلية على الجهاز.',
        icon: Icons.error_outline_rounded,
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: PieColors.cashierAccent),
      );
    }

    final allTables = _tables;
        final zones = ['الكل', ...{for (final t in allTables) t.zone}];

        final vacantCount = allTables.where((t) => t.status == TableStatus.vacant).length;
        final occupiedCount = allTables.where((t) => t.status == TableStatus.occupied).length;
        final billRequestedCount =
            allTables.where((t) => t.status == TableStatus.billRequested).length;

        var displayedTables = allTables;
        if (_selectedStatusFilter != null) {
          displayedTables =
              displayedTables.where((t) => t.status == _selectedStatusFilter).toList();
        }
        if (_selectedZone != 'الكل') {
          displayedTables = displayedTables.where((t) => t.zone == _selectedZone).toList();
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              // Occupancy Summary Bar
              _buildOccupancySummary(
                total: allTables.length,
                vacant: vacantCount,
                occupied: occupiedCount,
                billRequested: billRequestedCount,
              ),

              // Filter Rails (Status Pills + Zone Selector)
              _buildFilterRail(zones),

              // Table Grid
              Expanded(
                child: displayedTables.isEmpty
                    ? const PieEmptyState(
                        title: 'مفيش طاولات مطابقة',
                        description: 'جرب تختار فلتر تاني أو قسماً مختلفاً من الصالة.',
                        icon: Icons.table_restaurant_outlined,
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth < 600;
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: isMobile ? 600 : 340,
                              mainAxisExtent: isMobile ? 195 : 210,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                            ),
                            itemCount: displayedTables.length,
                            itemBuilder: (context, index) {
                              final table = displayedTables[index];
                              return _buildTableCard(table);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
  }

  Widget _buildOccupancySummary({
    required int total,
    required int vacant,
    required int occupied,
    required int billRequested,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: PieColors.surface1,
        border: Border(bottom: BorderSide(color: PieColors.border, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSummaryItem('إجمالي الطاولات', total, PieColors.ink),
            const SizedBox(width: 20),
            _buildSummaryItem('شاغرة', vacant, const Color(0xFF4ADE80)),
            const SizedBox(width: 20),
            _buildSummaryItem('مشغولة', occupied, PieColors.cashierAccent),
            const SizedBox(width: 20),
            _buildSummaryItem('طلب الحساب', billRequested, const Color(0xFFF87171)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PieNumeral.count(
          count,
          style: PieTypography.monoHeading.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
        ),
      ],
    );
  }

  Widget _buildFilterRail(List<String> zones) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: PieColors.canvas,
        border: Border(bottom: BorderSide(color: PieColors.border, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatusChip(null, 'الكل'),
            const SizedBox(width: 6),
            _buildStatusChip(TableStatus.vacant, 'شاغرة'),
            const SizedBox(width: 6),
            _buildStatusChip(TableStatus.occupied, 'مشغولة'),
            const SizedBox(width: 6),
            _buildStatusChip(TableStatus.billRequested, 'طلب الحساب'),
            const SizedBox(width: 16),
            Container(width: 1, height: 24, color: PieColors.border),
            const SizedBox(width: 16),
            Text('المنطقة:', style: PieTypography.caption),
            const SizedBox(width: 8),
            for (final zone in zones) ...[
              ActionChip(
                label: Text(zone),
                backgroundColor: _selectedZone == zone ? PieColors.surface3 : PieColors.surface1,
                side: BorderSide(
                  color: _selectedZone == zone ? PieColors.cashierAccent : PieColors.border,
                ),
                labelStyle: PieTypography.caption.copyWith(
                  color: _selectedZone == zone ? PieColors.cashierAccent : PieColors.inkSecondary,
                ),
                onPressed: () => setState(() => _selectedZone = zone),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(TableStatus? status, String label) {
    final isSelected = _selectedStatusFilter == status;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      backgroundColor: PieColors.surface1,
      selectedColor: PieColors.cashierSurface,
      side: BorderSide(
        color: isSelected ? PieColors.cashierAccent : PieColors.border,
      ),
      labelStyle: PieTypography.caption.copyWith(
        color: isSelected ? PieColors.cashierAccent : PieColors.inkSecondary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      onSelected: (_) => setState(() => _selectedStatusFilter = status),
    );
  }

  Widget _buildTableCard(DiningTable table) {
    final elapsedMinutes = table.seatedAt == null
        ? null
        : DateTime.now().difference(table.seatedAt!).inMinutes;

    return PieCard(
      padding: const EdgeInsets.all(14),
      isActive: table.status == TableStatus.billRequested,
      activeColor: const Color(0xFFF87171),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Table Code & State Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: PieColors.surface2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: PieColors.border),
                    ),
                    child: Text(
                      table.code,
                      style: PieTypography.monoHeading.copyWith(
                        fontWeight: FontWeight.w700,
                        color: PieColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    table.zone,
                    style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
                  ),
                ],
              ),
              PieBadge.tableState(table.status),
            ],
          ),

          // Details: Party Size, Steward, Elapsed
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (table.status != TableStatus.vacant) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'الضيوف: ${table.partySize} أفراد • ${table.steward.isEmpty ? "بدون ويتر" : table.steward}',
                      style: PieTypography.caption,
                    ),
                    if (elapsedMinutes != null)
                      Text(
                        'منذ $elapsedMinutes دقيقة',
                        style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الحساب الجاري:', style: PieTypography.caption),
                    PieNumeral.money(
                      table.runningTotal,
                      style: PieTypography.monoBody.copyWith(
                        fontWeight: FontWeight.w700,
                        color: PieColors.cashierAccent,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  'السعة: ${table.capacity} مقاعد',
                  style: PieTypography.body.copyWith(color: PieColors.inkMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  'جاهزة لاستقبال الطلبات',
                  style: PieTypography.caption.copyWith(color: const Color(0xFF4ADE80)),
                ),
              ],
            ],
          ),

          // Per-state action button
          _buildTableActionButton(table),
        ],
      ),
    );
  }

  Widget _buildTableActionButton(DiningTable table) {
    final services = AppScope.of(context);

    switch (table.status) {
      case TableStatus.vacant:
        return PieButton.secondary(
          onPressed: () => _showOccupyDialog(table),
          label: 'تسكين الضيوف',
          icon: Icons.person_add_alt_1_rounded,
          height: 38,
        );
      case TableStatus.occupied:
        return PieButton.ghost(
          onPressed: () async {
            await services.tables?.requestBill(table.id);
            _loadTables();
          },
          label: 'طلب الحساب',
          icon: Icons.receipt_long_rounded,
          height: 38,
        );
      case TableStatus.billRequested:
        return PieButton.primary(
          onPressed: () async {
            await services.tables?.clearTable(table.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: PieColors.surface2,
                  content: Text('تم تحصيل الحساب وتفريغ الطاولة'),
                ),
              );
              _loadTables();
            }
          },
          label: 'تحصيل وتفريغ الطاولة',
          icon: Icons.check_circle_outline_rounded,
          accentColor: const Color(0xFFF87171),
          height: 38,
        );
    }
  }

  void _showOccupyDialog(DiningTable table) {
    final services = AppScope.of(context);
    final partyController = TextEditingController(text: '2');
    final stewardController = TextEditingController(text: 'أحمد');

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: PieColors.surfaceOverlay,
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تسكين طاولة ${table.code}',
                  style: PieTypography.heading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: partyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'عدد الأفراد'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stewardController,
                  decoration: const InputDecoration(labelText: 'اسم الويتر المسؤول'),
                ),
                const SizedBox(height: 20),
                PieButton.primary(
                  onPressed: () async {
                    final party = int.tryParse(partyController.text) ?? 2;
                    final steward = stewardController.text.trim();
                    await services.tables?.seatTable(
                      tableId: table.id,
                      partySize: party,
                      steward: steward,
                    );
                    if (mounted) {
                      Navigator.of(context).pop();
                      _loadTables();
                    }
                  },
                  label: 'تسكين وفتح الطاولة',
                  accentColor: PieColors.cashierAccent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
