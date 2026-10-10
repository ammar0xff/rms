import '../../core/widgets/status.dart';
import '../../data/mock/mock_data.dart';

String money(double value, {String symbol = '\$'}) {
  final negative = value < 0;
  final v = value.abs().toStringAsFixed(2);
  return '${negative ? '-' : ''}$symbol$v';
}

(String label, StatusTone tone) syncStateView(SyncState state) => switch (state) {
      SyncState.local => ('Local', StatusTone.neutral),
      SyncState.pending => ('Pending sync', StatusTone.warning),
      SyncState.synced => ('Synced', StatusTone.positive),
      SyncState.conflict => ('Conflict', StatusTone.negative),
    };

(String label, StatusTone tone) ticketStateView(TicketState state) =>
    switch (state) {
      TicketState.queued => ('Queued', StatusTone.info),
      TicketState.preparing => ('Preparing', StatusTone.warning),
      TicketState.ready => ('Ready', StatusTone.positive),
    };
