import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/report.dart';
import '../common/format.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportsSnapshot? _snapshot;
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
    final repo = AppScope.of(context).reports;
    if (repo == null) {
      if (!mounted) return;
      setState(() {
        _available = false;
        _snapshot = null;
      });
      return;
    }
    final snapshot = await repo.load();
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
    _notify('تم نسخ التقرير بصيغة CSV إلى الحافظة.');
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    if (!_available) {
      return const PageBody(
        children: [
          EmptyState(
            icon: Icons.insights_outlined,
            title: 'التقارير غير متاحة',
            message:
                'لا يتوفر مخزن محلي في هذه الجلسة، لذا لا يمكن بناء التقارير من البيانات المعتمدة.',
          ),
        ],
      );
    }

    return PageBody(
      children: [
        Row(
          children: [
            const SectionHeader(
              title: 'التقارير',
              subtitle: 'قراءة محلية من المخازن الإضافة-فقط · تبقى متسقة دون اتصال',
            ),
            const Spacer(),
            if (snapshot != null) ...[
              StatusText(
                label: _freshnessLabel(snapshot),
                tone: _freshnessTone(snapshot),
              ),
              const SizedBox(width: 12),
            ],
            IconBtn(
              icon: Icons.refresh,
              tooltip: 'تحديث',
              onPressed: _load,
            ),
            const SizedBox(width: 8),
            RmsButton(
              label: 'تصدير CSV',
              icon: Icons.download,
              onPressed: snapshot == null ? null : _exportCsv,
            ),
          ],
        ),
        if (snapshot == null)
          const SurfaceCard(
            child: Text('جارٍ تجميع البيانات…', style: AppText.caption),
          )
        else ...[
          _hero(snapshot),
          _kpiGrid(snapshot),
          _trendCard(snapshot.sales),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _inventoryCard(snapshot.inventory)),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: _paymentMixCard(snapshot.payments)),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _purchasingCard(snapshot.purchasing)),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: _cashCard(snapshot.cash)),
            ],
          ),
          _auditCard(snapshot.recentAudit),
          const SurfaceCard(
            level: SurfaceLevel.secondary,
            child: Row(
              children: [
                Icon(Icons.verified_outlined, size: 16, color: AppColors.info),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تُحسب كل الأرقام من السجلات الإضافة-فقط (الطلبات، الدفعات، التحصيلات، دفتر المخزون، أوامر الشراء)، لذا تبقى متسقة بعد العمليات المتزامنة وانقطاع الاتصال. يشير عدد العمليات قيد المزامنة إلى مدى تأخر البيانات عن الخادم.',
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

  Widget _hero(ReportsSnapshot snapshot) {
    final days = snapshot.sales.byDay;
    String? delta;
    var tone = DeltaTone.neutral;
    if (days.length >= 2) {
      final previous = days[days.length - 2].total;
      final latest = days[days.length - 1].total;
      if (previous > 0) {
        final pct = (latest - previous) / previous * 100;
        delta = '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';
        tone = pct >= 0 ? DeltaTone.positive : DeltaTone.negative;
      }
    }
    return HeroKpi(
      label: 'مبيعات آخر ${days.length} أيام',
      value: money(snapshot.sales.total),
      delta: delta,
      deltaTone: tone,
      subtext:
          '${snapshot.sales.orders} طلب · متوسط ${money(snapshot.sales.averageTicket)}',
      spark: [for (final day in days) day.total],
    );
  }

  Widget _kpiGrid(ReportsSnapshot snapshot) {
    final pendingTone = snapshot.pendingOperations > 0
        ? DeltaTone.neutral
        : DeltaTone.positive;
    return GridRow(children: [
      StatCard(
        label: 'الطلبات',
        value: '${snapshot.sales.orders}',
        delta: 'متوسط ${money(snapshot.sales.averageTicket)}',
        deltaTone: DeltaTone.neutral,
      ),
      StatCard(
        label: 'صافي التحصيل',
        value: money(snapshot.payments.net),
        delta: 'استردادات ${money(snapshot.payments.refunds)}',
        deltaTone: snapshot.payments.refunds > 0
            ? DeltaTone.negative
            : DeltaTone.positive,
      ),
      StatCard(
        label: 'قيد المزامنة',
        value: '${snapshot.pendingOperations}',
        delta: snapshot.isStale ? 'بيانات غير مؤكدة' : 'متزامن بالكامل',
        deltaTone: pendingTone,
      ),
      StatCard(
        label: 'أقل من حد الطلب',
        value: '${snapshot.inventory.lowCount}',
        delta: 'من ${snapshot.inventory.itemCount} صنف',
        deltaTone: snapshot.inventory.lowCount > 0
            ? DeltaTone.negative
            : DeltaTone.positive,
      ),
    ]);
  }

  Widget _trendCard(ReportSales sales) {
    final days = sales.byDay;
    final values = [for (final day in days) day.total];
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    final best = sales.bestDay;
    final bestIndex = best == null
        ? null
        : days.indexWhere((d) => d.day == best.day);
    final top = max <= 0 ? 1.0 : max;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: SectionHeader(
              title: 'اتجاه المبيعات',
              subtitle: 'نافذة متجددة حسب تواريخ الإنشاء المحلية',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 48,
                    height: 180,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final fraction in const [1.0, 0.75, 0.5, 0.25, 0.0])
                          Text(
                            _compact(top * fraction),
                            style: AppText.caption.copyWith(fontSize: 9),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: MiniBars(
                      values: values,
                      height: 180,
                      highlightIndex: bestIndex,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 68, right: 20, top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final day in days)
                  Text(
                    _weekday(day.day),
                    style: AppText.caption.copyWith(fontSize: 9),
                  ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                _FooterStat(
                  label: 'أفضل يوم',
                  value: best == null ? '—' : _weekday(best.day),
                ),
                const _VDivider(),
                _FooterStat(
                  label: 'إجمالي النافذة',
                  value: money(sales.total),
                ),
                const _VDivider(),
                _FooterStat(
                  label: 'المتوسط / اليوم',
                  value: money(days.isEmpty ? 0 : sales.total / days.length),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inventoryCard(ReportInventory inventory) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'المخزون',
            subtitle: 'الرصيد هو مجموع دفتر الحركات',
          ),
          const SizedBox(height: 12),
          KvPanel(pairs: [
            ('أصناف متتبعة', '${inventory.itemCount}'),
            ('أقل من حد الطلب', '${inventory.lowCount}'),
            ('إجمالي الوحدات', _qty(inventory.onHandUnits)),
            ('حركات السجل', '${inventory.movementCount}'),
            ('حركات قيد المزامنة', '${inventory.pendingMovements}'),
            ('وارد / صادر', '${_qty(inventory.receivedIn)} / ${_qty(inventory.issuedOut)}'),
          ]),
        ],
      ),
    );
  }

  Widget _paymentMixCard(ReportPayments payments) {
    final total = payments.cash + payments.card;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'خليط الدفع',
            subtitle: 'دفتر الدفعات الإضافة-فقط',
          ),
          const SizedBox(height: 16),
          _MixRow(
            label: 'نقدي',
            value: money(payments.cash),
            pct: total <= 0 ? '0%' : '${(payments.cash / total * 100).round()}%',
            color: AppColors.positive,
          ),
          _MixRow(
            label: 'بطاقة',
            value: money(payments.card),
            pct: total <= 0 ? '0%' : '${(payments.card / total * 100).round()}%',
            color: AppColors.info,
          ),
          _MixRow(
            label: 'استردادات',
            value: money(payments.refunds),
            pct: '${payments.refundCount}',
            color: AppColors.negative,
          ),
          _MixRow(
            label: 'تحصيلات التوصيل',
            value: money(payments.collections),
            pct: '${payments.collectionsCount}',
            color: AppColors.purple,
          ),
          const Divider(height: 24, color: AppColors.borderSubtle),
          Row(
            children: [
              StatusDot(
                tone: payments.offlinePending > 0
                    ? StatusTone.warning
                    : StatusTone.positive,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  payments.offlinePending > 0
                      ? 'مدفوعات دون اتصال بانتظار التسوية'
                      : 'لا مدفوعات معلّقة محليًا',
                  style: AppText.tableCell,
                ),
              ),
              Text(
                money(payments.offlinePending),
                style: AppText.tableCellPrimary
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _purchasingCard(ReportPurchasing purchasing) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'المشتريات',
            subtitle: 'أوامر الشراء ومستحقات الموردين',
          ),
          const SizedBox(height: 12),
          KvPanel(pairs: [
            ('موردون', '${purchasing.supplierCount}'),
            ('مستحقات الموردين', money(purchasing.payables)),
            ('أوامر مفتوحة', '${purchasing.openOrders}'),
            ('قيمة الأوامر المفتوحة', money(purchasing.openValue)),
            ('أوامر مستلمة', '${purchasing.receivedOrders}'),
            ('قيمة المستلم', money(purchasing.receivedValue)),
          ]),
        ],
      ),
    );
  }

  Widget _cashCard(ReportCash cash) {
    final tone = cash.variance == 0
        ? AppColors.positive
        : cash.variance < 0
            ? AppColors.negative
            : AppColors.warning;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'الجلسات النقدية',
            subtitle: 'المتوقع مقابل المعدود عند الإغلاق',
          ),
          const SizedBox(height: 12),
          KvPanel(pairs: [
            ('جلسات مفتوحة', '${cash.openSessions}'),
            ('جلسات مغلقة', '${cash.closedSessions}'),
            ('رصيد افتتاحي', money(cash.openingFloat)),
            ('المتوقع', money(cash.expectedTotal)),
            ('المعدود', money(cash.countedTotal)),
          ]),
          const Divider(height: 20, color: AppColors.borderSubtle),
          Row(
            children: [
              Expanded(
                child: Text('فرق الجرد', style: AppText.caption),
              ),
              Text(
                money(cash.variance),
                style: AppText.tableCellPrimary.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _auditCard(List<AuditEntry> entries) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: SectionHeader(
              title: 'أحدث الأحداث',
              subtitle: 'سجل التدقيق الإضافة-فقط',
            ),
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text('لا توجد أحداث مسجلة بعد.', style: AppText.caption),
            )
          else
            RmsTable(
              columns: const [
                RmsColumn('الوقت', width: 64),
                RmsColumn('الإجراء', flex: 3),
                RmsColumn('التفاصيل', flex: 6),
                RmsColumn('المبلغ', flex: 2, align: TextAlign.right),
              ],
              rows: [
                for (final entry in entries)
                  [
                    Text(_time(entry.at), style: AppText.caption),
                    Text(entry.action.label, style: AppText.tableCellPrimary),
                    Text(entry.summary, style: AppText.tableCell),
                    Text(
                      entry.amount == null ? '—' : money(entry.amount!),
                      style: AppText.tableCellPrimary,
                    ),
                  ],
              ],
            ),
        ],
      ),
    );
  }

  static String _freshnessLabel(ReportsSnapshot snapshot) {
    final pending = snapshot.pendingOperations;
    final suffix = pending > 0 ? ' · $pending قيد المزامنة' : '';
    if (snapshot.lastSyncedAt == null) {
      return 'لا مزامنة بعد$suffix';
    }
    return 'آخر مزامنة ${_relative(DateTime.now().difference(snapshot.lastSyncedAt!))}$suffix';
  }

  static StatusTone _freshnessTone(ReportsSnapshot snapshot) {
    if (snapshot.conflictOperations > 0) return StatusTone.negative;
    if (snapshot.failedOperations > 0) return StatusTone.warning;
    if (snapshot.pendingOperations > 0) return StatusTone.warning;
    if (snapshot.lastSyncedAt == null) return StatusTone.neutral;
    return StatusTone.positive;
  }

  static String _relative(Duration age) {
    if (age.inSeconds < 60) return 'الآن';
    if (age.inMinutes < 60) return 'قبل ${age.inMinutes} دقيقة';
    if (age.inHours < 24) return 'قبل ${age.inHours} ساعة';
    return 'قبل ${age.inDays} يوم';
  }

  static String _weekday(DateTime day) => switch (day.weekday) {
        1 => 'الإثنين',
        2 => 'الثلاثاء',
        3 => 'الأربعاء',
        4 => 'الخميس',
        5 => 'الجمعة',
        6 => 'السبت',
        _ => 'الأحد',
      };

  static String _compact(double value) {
    if (value <= 0) return '0';
    if (value >= 1000) {
      final k = value / 1000;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
    }
    return value.toStringAsFixed(0);
  }

  static String _qty(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);

  static String _time(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _FooterStat extends StatelessWidget {
  const _FooterStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Text(label, style: AppText.caption),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                color: AppColors.fgSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 12, color: AppColors.borderStrong);
}

class _MixRow extends StatelessWidget {
  const _MixRow({
    required this.label,
    required this.value,
    required this.pct,
    required this.color,
  });

  final String label;
  final String value;
  final String pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppText.tableCell.copyWith(color: AppColors.fgSecondary),
            ),
          ),
          Text(value, style: AppText.tableCellPrimary),
          const SizedBox(width: 14),
          SizedBox(
            width: 34,
            child: Text(pct, textAlign: TextAlign.right, style: AppText.caption),
          ),
        ],
      ),
    );
  }
}
