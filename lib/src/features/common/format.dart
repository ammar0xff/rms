import '../../core/widgets/status.dart';
import '../../domain/models/kitchen_ticket.dart';
import '../../data/mock/mock_data.dart' hide TicketState;

String money(double value, {String symbol = 'ج.م'}) {
  final negative = value < 0;
  final v = value.abs().toStringAsFixed(2);
  return '${negative ? '-' : ''}$v $symbol';
}

(String label, StatusTone tone) syncStateView(SyncState state) => switch (state) {
      SyncState.local => ('محلي', StatusTone.neutral),
      SyncState.pending => ('قيد المزامنة', StatusTone.warning),
      SyncState.synced => ('متزامن', StatusTone.positive),
      SyncState.conflict => ('تعارض', StatusTone.negative),
    };

(String label, StatusTone tone) ticketStateView(TicketState state) =>
    switch (state) {
      TicketState.queued => ('في الانتظار', StatusTone.info),
      TicketState.preparing => ('قيد التحضير', StatusTone.warning),
      TicketState.ready => ('جاهز', StatusTone.positive),
      TicketState.completed => ('مكتمل', StatusTone.neutral),
    };