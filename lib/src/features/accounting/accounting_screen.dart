import 'package:flutter/material.dart';

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
import '../../data/local/outbox/outbox_entry.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../domain/models/payment.dart';
import '../common/format.dart';

const double _openingFloat = 200;

class AccountingScreen extends StatefulWidget {
  const AccountingScreen({super.key});

  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen> {
  List<PaymentModel> _payments = const [];
  List<OutboxEntry> _actions = const [];
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
    final payments = services.payments;
    final loaded =
        payments == null ? const <PaymentModel>[] : await payments.listPayments();
    final outbox = services.outbox;
    final actions = outbox == null
        ? const <OutboxEntry>[]
        : (await outbox.all())
            .where((e) =>
                e.syncStatus == OutboxStatus.conflict ||
                e.syncStatus == OutboxStatus.requiresUserAction ||
                e.syncStatus == OutboxStatus.permanentlyRejected)
            .toList();
    if (!mounted) return;
    setState(() {
      _payments = loaded;
      _actions = actions;
    });
  }

  double get _cashTotal => _payments
      .where((p) => p.method == PaymentMethod.cash)
      .fold(0, (sum, p) => sum + p.amount);

  double get _cardTotal => _payments
      .where((p) => p.method == PaymentMethod.card)
      .fold(0, (sum, p) => sum + p.amount);

  double get _pendingTotal => _payments
      .where((p) => p.syncStatus != SyncStatus.synced)
      .fold(0, (sum, p) => sum + p.amount);

  double get _refundTotal => _payments
      .where((p) => p.isRefund)
      .fold(0, (sum, p) => sum + p.amount);

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        GridRow(children: [
          StatCard(
            label: 'النقدية في الدرج',
            value: money(_cashTotal),
            delta: 'متوقع ${money(_openingFloat + _cashTotal)}',
            deltaTone: DeltaTone.positive,
          ),
          StatCard(
            label: 'بطاقات مسددة',
            value: money(_cardTotal),
            delta: '${_payments.where((p) => p.method == PaymentMethod.card).length} عملية',
            deltaTone: DeltaTone.positive,
          ),
          StatCard(
            label: 'قيد المزامنة',
            value: money(_pendingTotal),
            delta: '${_payments.where((p) => p.syncStatus != SyncStatus.synced).length} سجل',
            deltaTone: DeltaTone.neutral,
          ),
          StatCard(
            label: 'استردادات اليوم',
            value: money(_refundTotal),
            delta: '${_payments.where((p) => p.isRefund).length} مراجعة',
            deltaTone: DeltaTone.negative,
          ),
        ]),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _cashSessionCard()),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: _approvalsPanel()),
          ],
        ),
        _ledgerCard(),
      ],
    );
  }

  Widget _cashSessionCard() {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'جلسة النقدية',
            trailing: Tag(label: 'مفتوحة', tone: StatusTone.positive),
          ),
          const SizedBox(height: 12),
          for (final (k, v) in [
            ('الفتح', '12:00'),
            ('رأس مال الفتح', money(_openingFloat)),
            ('مبيعات نقدية', money(_cashTotal)),
            ('الدرج المتوقع', money(_openingFloat + _cashTotal)),
            ('درج معدود', '— لم يُعد بعد'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          const RmsButton(
            label: 'عدّ وإغلاق الجلسة',
            icon: Icons.calculate_outlined,
            onPressed: null,
            dense: false,
          ),
        ],
      ),
    );
  }

  Widget _approvalsPanel() {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'يحتاج مراجعة', subtitle: 'الإجراءات المالية تتطلب اعتمادًا'),
          const SizedBox(height: 12),
          if (_actions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('لا توجد عمليات مالية بانتظار المراجعة.',
                  style: AppText.caption),
            ),
          for (var i = 0; i < _actions.length && i < 4; i++) ...[
            _ApprovalRow(entry: _actions[i]),
            if (i != _actions.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _ledgerCard() {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: SectionHeader(
              title: 'سجل المعاملات',
              subtitle: 'إضافة فقط · إزالة التكرار عند المزامنة',
              trailing: RmsButton(label: 'تصدير', icon: Icons.download, onPressed: () {}),
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('الوقت', width: 70),
              RmsColumn('النوع', flex: 2),
              RmsColumn('المرجع', flex: 3),
              RmsColumn('الطريقة', flex: 2),
              RmsColumn('المزامنة', flex: 3),
              RmsColumn('المبلغ', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final p in _payments.reversed)
                [
                  Text(_time(p.createdAt), style: AppText.caption),
                  Text(p.isRefund ? 'استرداد' : 'دفعة', style: AppText.tableCell),
                  Text(p.orderRef, style: AppText.tableCellPrimary),
                  Text(p.method.label, style: AppText.tableCell),
                  StatusText(
                    label: orderSyncView(p.syncStatus).$1,
                    tone: orderSyncView(p.syncStatus).$2,
                  ),
                  Text(
                    money(p.amount),
                    style: AppText.tableCellPrimary.copyWith(
                      fontWeight: FontWeight.w600,
                      color: p.amount < 0 ? AppColors.negative : AppColors.fgBright,
                    ),
                  ),
                ],
            ],
          ),
        ],
      ),
    );
  }

  static String _time(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({required this.entry});

  final OutboxEntry entry;

  double? get _amount {
    final amount = entry.payload['amount'] ?? entry.payload['total'];
    return amount is num ? amount.toDouble() : null;
  }

  StatusTone get _tone => entry.syncStatus == OutboxStatus.conflict
      ? StatusTone.negative
      : StatusTone.warning;

  @override
  Widget build(BuildContext context) {
    final amount = _amount;
    return Row(
      children: [
        StatusDot(tone: _tone),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${entry.entityType} · ${entry.entityId}',
                  style: AppText.tableCellPrimary),
              Text(
                entry.lastError ?? entry.operationType,
                style: AppText.caption.copyWith(fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (amount != null)
          Text(money(amount),
              style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        const RmsButton(label: 'مراجعة', onPressed: null),
      ],
    );
  }
}
