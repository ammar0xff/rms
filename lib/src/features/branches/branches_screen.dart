import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/app_services.dart';
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
import '../../domain/models/branch.dart';
import '../common/format.dart';

class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  ConsolidationSnapshot? _snapshot;
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
    if (!mounted) return;
    setState(() {
      _available = true;
      _snapshot = snapshot;
    });
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
