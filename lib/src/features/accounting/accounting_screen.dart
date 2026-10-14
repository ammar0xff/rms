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
import '../../data/local/outbox/outbox_entry.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../domain/models/approval_request.dart';
import '../../domain/models/cash_session.dart';
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
  List<ApprovalRequest> _approvals = const [];
  List<OutboxEntry> _actions = const [];
  CashSession? _session;
  CashSession? _lastClosed;
  double? _expected;
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

    final sessions = services.cashSessions;
    CashSession? current;
    CashSession? lastClosed;
    double? expected;
    if (sessions != null) {
      final all = await sessions.listSessions();
      current = await sessions.currentSession();
      if (current != null) {
        expected = await sessions.expectedCash(current);
      } else if (all.isNotEmpty) {
        lastClosed = all.last;
      }
    }

    final approvalsRepo = services.approvals;
    final approvals = approvalsRepo == null
        ? const <ApprovalRequest>[]
        : (await approvalsRepo.listRequests())
            .where((r) => r.isPending)
            .toList();

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
      _session = current;
      _lastClosed = lastClosed;
      _expected = expected;
      _approvals = approvals;
      _actions = actions;
    });
  }

  Future<void> _openSession() async {
    final sessions = AppScope.of(context).cashSessions;
    if (sessions == null) return;
    await sessions.openSession(openingFloat: _openingFloat, createdOffline: true);
    await _load();
  }

  Future<void> _closeSession(CashSession session) async {
    final sessions = AppScope.of(context).cashSessions;
    if (sessions == null) return;
    final counted = await showDialog<double>(
      context: context,
      builder: (_) => _CountDialog(expected: _expected ?? session.openingFloat),
    );
    if (counted == null) return;
    await sessions.closeSession(session.id, countedCash: counted);
    await _load();
  }

  Future<void> _decide(ApprovalRequest request, {required bool approved}) async {
    final approvals = AppScope.of(context).approvals;
    if (approvals == null) return;
    await approvals.decide(request.id, approved: approved);
    await _load();
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
            delta: 'متوقع ${money((_expected ?? _openingFloat) + _cashTotal)}',
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
            label: 'استردادات',
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
    final services = AppScope.of(context);
    final repo = services.cashSessions;
    final session = _session;

    if (session == null) {
      final closed = _lastClosed;
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'جلسة النقدية',
              trailing: Tag(label: 'مغلقة', tone: StatusTone.neutral),
            ),
            const SizedBox(height: 12),
            if (closed != null) ...[
              KeyValue(
                label: 'آخر إغلاق',
                value: _time(closed.closedAt ?? closed.openedAt),
              ),
              KeyValue(
                label: 'الدرج المتوقع',
                value: money(closed.expectedCash ?? closed.openingFloat),
              ),
              KeyValue(
                label: 'النقد المعدود',
                value: money(closed.countedCash ?? 0),
              ),
              KeyValue(
                label: 'الفرق',
                value: money(closed.variance ?? 0),
                valueColor: (closed.variance ?? 0).abs() < 0.005
                    ? AppColors.positive
                    : AppColors.negative,
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('لم تُفتح أي جلسة نقدية بعد.', style: AppText.caption),
              ),
            const SizedBox(height: 12),
            RmsButton(
              label: 'فتح جلسة جديدة',
              icon: Icons.lock_open_outlined,
              variant: BtnVariant.primary,
              dense: false,
              onPressed: repo == null ? null : _openSession,
            ),
          ],
        ),
      );
    }

    final expected = _expected ?? session.openingFloat;
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
            ('الفتح', _time(session.openedAt)),
            ('رأس مال الفتح', money(session.openingFloat)),
            ('مبيعات نقدية', money(_cashTotal)),
            ('الدرج المتوقع', money(expected)),
            ('درج معدود', '— لم يُعد بعد'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          RmsButton(
            label: 'عدّ وإغلاق الجلسة',
            icon: Icons.calculate_outlined,
            dense: false,
            onPressed: repo == null ? null : () => _closeSession(session),
          ),
        ],
      ),
    );
  }

  Widget _approvalsPanel() {
    final services = AppScope.of(context);
    final online = services.sync != null && SyncMonitor.instance.online;
    final requests = _approvals.take(4).toList();
    final actions = _actions.take(2).toList();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'يحتاج مراجعة',
            subtitle: 'الإجراءات المالية تتطلب اعتمادًا',
          ),
          const SizedBox(height: 12),
          if (requests.isEmpty && actions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('لا توجد عمليات مالية بانتظار المراجعة.',
                  style: AppText.caption),
            ),
          for (var i = 0; i < requests.length; i++) ...[
            _ApprovalRequestRow(
              request: requests[i],
              canApprove: online && services.approvals != null,
              onApprove: () => _decide(requests[i], approved: true),
              onReject: () => _decide(requests[i], approved: false),
            ),
            if (i != requests.length - 1 || actions.isNotEmpty)
              const SizedBox(height: 10),
          ],
          for (var i = 0; i < actions.length; i++) ...[
            _ApprovalRow(entry: actions[i]),
            if (i != actions.length - 1) const SizedBox(height: 10),
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
            // No trailing action: تصدير was wired to a no-op. Export returns
            // when there is a destination for the file.
            child: SectionHeader(
              title: 'سجل المعاملات',
              subtitle: 'إضافة فقط · إزالة التكرار عند المزامنة',
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

class _ApprovalRequestRow extends StatelessWidget {
  const _ApprovalRequestRow({
    required this.request,
    required this.canApprove,
    required this.onApprove,
    required this.onReject,
  });

  final ApprovalRequest request;
  final bool canApprove;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const StatusDot(tone: StatusTone.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${request.kind.label} · ${request.orderRef}',
                  style: AppText.tableCellPrimary),
              Text(
                request.reason,
                style: AppText.caption,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Text(
          money(request.amount),
          style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        RmsButton(
          label: 'رفض',
          variant: BtnVariant.ghost,
          onPressed: onReject,
        ),
        const SizedBox(width: 6),
        RmsButton(
          label: 'اعتماد',
          variant: BtnVariant.primary,
          onPressed: canApprove ? onApprove : null,
        ),
      ],
    );
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
                style: AppText.caption,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (amount != null)
          Text(money(amount),
              style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _CountDialog extends StatefulWidget {
  const _CountDialog({required this.expected});

  final double expected;

  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  final TextEditingController _counted = TextEditingController();

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(_counted.text.trim());
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('عدّ وإغلاق الجلسة'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الدرج المتوقع ${money(widget.expected)}',
                style: AppText.caption),
            const SizedBox(height: 12),
            TextField(
              controller: _counted,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'النقد المعدود',
                prefixText: 'ج.م ',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (text) {
                final parsed = double.tryParse(text.trim());
                if (parsed != null && parsed >= 0) Navigator.pop(context, parsed);
              },
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
          onPressed: (value != null && value >= 0)
              ? () => Navigator.pop(context, value)
              : null,
          child: const Text('إغلاق الجلسة'),
        ),
      ],
    );
  }
}
