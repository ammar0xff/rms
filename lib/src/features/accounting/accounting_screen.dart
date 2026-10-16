import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/blocks.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/pin_gate.dart';
import '../../data/services/pin_service.dart';
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
import '../../domain/models/order.dart';
import '../../domain/models/payment.dart';
import '../../domain/models/permissions.dart';
import '../../data/services/permission_service.dart';
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
  List<Order> _orders = const [];
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

    final ordersRepo = AppScope.of(context).orders;
    final orders =
        ordersRepo == null ? const <Order>[] : await ordersRepo.listOrders();
    if (!mounted) return;
    setState(() {
      _orders = orders;
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
      builder: (_) => CloseSessionDialog(expected: _expected ?? session.openingFloat),
    );
    if (counted == null) return;
    await sessions.closeSession(session.id, countedCash: counted);
    await _load();
  }

  Future<void> _decide(ApprovalRequest request,
      {required bool approved, String? note}) async {
    final approvals = AppScope.of(context).approvals;
    if (approvals == null) return;
    // Approving money passes the manager PIN when one is set. Demo mode
    // has no PIN store, so approval stays one tap there.
    if (approved && await PinService().isSet) {
      if (!mounted) return;
      final passed = await showDialog<bool>(
        context: context,
        builder: (_) => PinGateDialog(
          title: 'اعتماد ${money(request.amount)}',
          onVerify: (pin) => PinService().verify(pin),
        ),
      );
      if (passed != true) return;
    }
    await approvals.decide(request.id, approved: approved, note: note);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(approved
            ? 'اتعتمدت واتبلغ الكاشير'
            : 'اترفضت واتسجّل السبب'),
      ),
    );
  }

  Future<void> _requestVoid(Order order) async {
    if (!await userCan(AppScope.of(context), Permissions.orderVoid)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('صلاحية طلب الإلغاء مش متاحة لدورك')),
      );
      return;
    }
    final approvals = AppScope.of(context).approvals;
    if (approvals == null || order.voided) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const RejectReasonSheet(
        title: 'إلغاء الفاتورة',
        subtitle: 'السبب بيتسجّل مع طلب الإلغاء وبيستنى المدير.',
        confirmLabel: 'اطلب الإلغاء',
      ),
    );
    if (reason == null || reason.isEmpty) return;
    await approvals.requestVoid(
      orderLocalId: order.localId,
      orderRef: order.provisionalOrderNumber,
      amount: order.total,
      reason: reason,
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اتطلب الإلغاء وهيستنى المدير')),
    );
  }

  Future<void> _reprint(Order order) async {
    final print = AppScope.of(context).print;
    if (print == null || !mounted) return;
    await print.printReceipt(
      order.provisionalOrderNumber,
      {
        'total': order.total,
        'items': [
          for (final item in order.items)
            {'name': item.name, 'qty': item.quantity, 'price': item.unitPrice},
        ],
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اتبعتت الفاتورة للطباعة تاني')),
    );
  }

  /// Reject always carries a reason: quick chips plus a free note.
  Future<void> _reject(ApprovalRequest request) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const RejectReasonSheet(),
    );
    if (note == null || note.isEmpty) return;
    await _decide(request, approved: false, note: note);
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
            label: 'فيزا متسددة',
            value: money(_cardTotal),
            delta: '${_payments.where((p) => p.method == PaymentMethod.card).length} عملية',
            deltaTone: DeltaTone.positive,
          ),
          StatCard(
            label: 'بيتزامن',
            value: money(_pendingTotal),
            delta: '${_payments.where((p) => p.syncStatus != SyncStatus.synced).length} سجل',
            deltaTone: DeltaTone.neutral,
          ),
          StatCard(
            label: 'استرجاعات',
            value: money(_refundTotal),
            delta: '${_payments.where((p) => p.isRefund).length} مراجعة',
            deltaTone: DeltaTone.negative,
          ),
        ]),
        ResponsiveRow(
          breakpoint: 800,
          children: [
            _cashSessionCard(),
            _approvalsPanel(),
          ],
        ),
        _ledgerCard(),
        _ArchiveCard(
          orders: _orders,
          onReceipt: _reprint,
          onVoid: _requestVoid,
        ),
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
              trailing: Tag(label: 'مقفولة', tone: StatusTone.neutral),
            ),
            const SizedBox(height: 12),
            if (closed != null) ...[
              KeyValue(
                label: 'آخر قفل',
                value: _time(closed.closedAt ?? closed.openedAt),
              ),
              KeyValue(
                label: 'الدرج المتوقع',
                value: money(closed.expectedCash ?? closed.openingFloat),
              ),
              KeyValue(
                label: 'الكاش المعدود',
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
                child: Text('مفيش جلسة نقدية اتفتحت لسه.', style: AppText.caption),
              ),
            const SizedBox(height: 12),
            RmsButton(
              label: 'افتح جلسة جديدة',
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
            ('مبيعات كاش', money(_cashTotal)),
            ('الدرج المتوقع', money(expected)),
            ('درج معدود', '— لسه ما اتعدّش'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          RmsButton(
            label: 'عِدّ واقفل الجلسة',
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
            subtitle: 'الإجراءات المالية محتاجة اعتماد',
          ),
          const SizedBox(height: 12),
          if (requests.isEmpty && actions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('مفيش عمليات مالية مستنية المراجعة.',
                  style: AppText.caption),
            ),
          for (var i = 0; i < requests.length; i++) ...[
            _ApprovalRequestRow(
              request: requests[i],
              canApprove: online && services.approvals != null,
              onApprove: () => _decide(requests[i], approved: true),
              onReject: () => _reject(requests[i]),
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
              subtitle: 'إضافة بس · التكرار بيتمسح عند المزامنة',
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
                  Text(p.isRefund ? 'استرجاع' : 'دفعة', style: AppText.tableCell),
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

/// Reject/void reason: three quick chips plus a free note. Empty confirms
/// nothing — the dialog returns null and the request stays pending.
class RejectReasonSheet extends StatefulWidget {
  const RejectReasonSheet({
    this.title = 'ارفض بسبب',
    this.subtitle = 'السبب بيتسجّل مع الرفض وبيظهر للكاشير.',
    this.confirmLabel = 'تأكيد الرفض',
  });

  final String title;
  final String subtitle;
  final String confirmLabel;

  @override
  State<RejectReasonSheet> createState() => _RejectReasonSheetState();
}

class _RejectReasonSheetState extends State<RejectReasonSheet> {
  static const _chips = ['خطأ كاشير', 'شكوى طعام', 'تراجع العميل'];

  String? _picked;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _result {
    final custom = _note.text.trim();
    if (_picked == null) return custom;
    return custom.isEmpty ? _picked! : '${_picked!} · $custom';
  }

  @override
  Widget build(BuildContext context) {
    return DialogShell(
      title: widget.title,
      subtitle: widget.subtitle,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final chip in _chips)
                ChoiceChip(
                  label: Text(chip),
                  selected: _picked == chip,
                  onSelected: (_) =>
                      setState(() => _picked = _picked == chip ? null : chip),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              hintText: 'اكتب سبب الرفض…',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
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
          label: widget.confirmLabel,
          variant: BtnVariant.primary,
          onPressed: _result.isEmpty
              ? null
              : () => Navigator.of(context).pop(_result),
        ),
      ],
    );
  }
}

/// Invoice archive: search plus status chips over every order, with
/// receipt view and approval-gated void per row. Voided rows stay visible
/// with their reason — the audit trail lives here, not in a delete.
class _ArchiveCard extends StatefulWidget {
  const _ArchiveCard({
    required this.orders,
    required this.onReceipt,
    required this.onVoid,
  });

  final List<Order> orders;
  final ValueChanged<Order> onReceipt;
  final ValueChanged<Order> onVoid;

  @override
  State<_ArchiveCard> createState() => _ArchiveCardState();
}

class _ArchiveCardState extends State<_ArchiveCard> {
  String _query = '';
  int _filter = 0;

  List<Order> get _visible {
    final q = _query.trim();
    var list = widget.orders;
    if (_filter == 1) {
      list = list.where((o) => !o.voided).toList();
    } else if (_filter == 2) {
      list = list.where((o) => o.voided).toList();
    }
    if (q.isEmpty) return list;
    return list
        .where((o) =>
            o.provisionalOrderNumber.contains(q) ||
            o.items.any((i) => i.name.contains(q)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: SectionHeader(
              title: 'سجل الفواتير',
              subtitle: 'إعادة طباعة وإلغاء بموافقة',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: ListToolbar(
              hint: 'دوّر برقم الفاتورة أو صنف…',
              onQuery: (v) => setState(() => _query = v),
              filters: const ['الكل', 'سليمة', 'ملغاة'],
              selected: _filter,
              onFilter: (i) => setState(() => _filter = i),
            ),
          ),
          if (_visible.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text('مفيش فواتير بالفلتر ده.',
                  style: AppText.caption),
            )
          else
            RmsTable(
              columns: const [
                RmsColumn('الفاتورة', flex: 3),
                RmsColumn('الأصناف', flex: 2),
                RmsColumn('الحالة', flex: 2),
                RmsColumn('إجراء', width: 190, align: TextAlign.center),
                RmsColumn('الإجمالي', flex: 2, align: TextAlign.right),
              ],
              rows: [
                for (final order in _visible.take(30))
                  [
                    Text(order.provisionalOrderNumber,
                        style: AppText.tableCellPrimary),
                    Text('${order.items.length}',
                        style: AppText.tableCell),
                    order.voided
                        ? const Tag(
                            label: 'ملغاة', tone: StatusTone.neutral)
                        : const Tag(
                            label: 'سليمة', tone: StatusTone.positive),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        RmsButton(
                          label: 'الفاتورة',
                          variant: BtnVariant.secondary,
                          dense: true,
                          onPressed: () => _showReceipt(order),
                        ),
                        if (!order.voided)
                          RmsButton(
                            label: 'إلغاء',
                            variant: BtnVariant.ghost,
                            dense: true,
                            onPressed: () => widget.onVoid(order),
                          ),
                      ],
                    ),
                    Text(money(order.total),
                        textAlign: TextAlign.right,
                        style: AppText.tableCellPrimary.copyWith(
                            fontWeight: FontWeight.w600)),
                  ],
              ],
            ),
        ],
      ),
    );
  }

  void _showReceipt(Order order) {
    showDialog<void>(
      context: context,
      builder: (_) => DialogShell(
        title: 'فاتورة ${order.provisionalOrderNumber}',
        subtitle: order.voided
            ? 'ملغاة · ${order.voidReason ?? ''}'
            : null,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.name} × ${item.quantity}',
                        style: AppText.tableCellPrimary,
                      ),
                    ),
                    Text(money(item.unitPrice * item.quantity),
                        style: AppText.tableCell),
                  ],
                ),
              ),
            const Divider(height: 16),
            Row(
              children: [
                const Expanded(
                    child: Text('الإجمالي',
                        style: AppText.bodyStrong)),
                Text(money(order.total),
                    style:
                        AppText.h1.copyWith(fontSize: 18)),
              ],
            ),
          ],
        ),
        actions: [
          RmsButton(
            label: 'اقفل',
            variant: BtnVariant.ghost,
            onPressed: () => Navigator.of(context).pop(),
          ),
          RmsButton(
            label: 'اطبع تاني',
            icon: Icons.print_outlined,
            onPressed: () {
              Navigator.of(context).pop();
              widget.onReceipt(order);
            },
          ),
        ],
      ),
    );
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
    // The text column plus amount plus two buttons never fits a phone-width
    // card in one row, so the buttons sit on their own wrapping line.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
              style:
                  AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 6,
          runSpacing: 6,
          children: [
            RmsButton(
              label: 'رفض',
              variant: BtnVariant.ghost,
              onPressed: onReject,
            ),
            RmsButton(
              label: 'اعتماد',
              variant: BtnVariant.primary,
              onPressed: canApprove ? onApprove : null,
            ),
          ],
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

class CloseSessionDialog extends StatefulWidget {
  const CloseSessionDialog({required this.expected});

  final double expected;

  @override
  State<CloseSessionDialog> createState() => _CountDialogState();
}

class _DenomButton extends StatelessWidget {
  const _DenomButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 16, color: AppColors.fgSecondary),
      ),
    );
  }
}

class _CountDialogState extends State<CloseSessionDialog> {
  final TextEditingController _counted = TextEditingController();

  /// Denomination counts; every stepper writes through the same field so
  /// free typing and counting never disagree.
  final Map<int, int> _denoms = {200: 0, 100: 0, 50: 0, 20: 0, 10: 0, 5: 0};

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  void _bump(int denom, int by) {
    final current = double.tryParse(_counted.text.trim()) ?? 0;
    final next = (current + denom * by).clamp(0, 99999999).toDouble();
    setState(() {
      _denoms[denom] = ((_denoms[denom] ?? 0) + by).clamp(0, 9999);
      _counted.text = next.toStringAsFixed(2);
    });
  }

  String _varianceLabel(double? counted) {
    if (counted == null) return 'دخّل المعدود عشان تشوف الفرق';
    final diff = counted - widget.expected;
    if (diff == 0) return 'مطابقة تامة 100%';
    if (diff < 0) return 'فيه عجز ${money(diff.abs())}';
    return 'فيه زيادة ${money(diff)}';
  }

  Color _varianceTone(double? counted) {
    if (counted == null) return AppColors.fgDim;
    final diff = counted - widget.expected;
    if (diff == 0) return AppColors.positive;
    return diff < 0 ? AppColors.negative : AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(_counted.text.trim());
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('عِدّ واقفل الجلسة'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'الكاش المعدود',
                  prefixText: 'ج.م ',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (text) {
                  final parsed = double.tryParse(text.trim());
                  if (parsed != null && parsed >= 0) {
                    Navigator.pop(context, parsed);
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                _varianceLabel(value),
                style: AppText.caption.copyWith(
                    color: _varianceTone(value)),
              ),
              const SizedBox(height: 12),
              const Text('عدّ بالفئات', style: AppText.bodyStrong),
              const SizedBox(height: 4),
              for (final denom in _denoms.keys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text('$denom ج.م',
                            style: AppText.tableCellPrimary),
                      ),
                      const Spacer(),
                      _DenomButton(
                          icon: Icons.remove,
                          onTap: () => _bump(denom, -1)),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${_denoms[denom]}',
                          textAlign: TextAlign.center,
                          style: AppText.tableCellPrimary,
                        ),
                      ),
                      _DenomButton(
                          icon: Icons.add, onTap: () => _bump(denom, 1)),
                    ],
                  ),
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
          onPressed: (value != null && value >= 0)
              ? () => Navigator.pop(context, value)
              : null,
          child: const Text('اقفل الجلسة'),
        ),
      ],
    );
  }
}
