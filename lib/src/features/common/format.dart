import '../../core/widgets/status.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../domain/models/kitchen_ticket.dart';
import '../../data/mock/mock_data.dart' hide TicketState;

String money(double value, {String symbol = 'ج.م'}) {
  final negative = value < 0;
  final v = value.abs().toStringAsFixed(2);
  return '${negative ? '-' : ''}$v $symbol';
}

(String label, StatusTone tone) orderSyncView(SyncStatus status) =>
    switch (status) {
      SyncStatus.localOnly => ('على الجهاز', StatusTone.neutral),
      SyncStatus.pendingSync => ('بيتزامن', StatusTone.warning),
      SyncStatus.synced => ('اتزامن', StatusTone.positive),
      SyncStatus.conflict => ('تعارض', StatusTone.negative),
    };

(String label, StatusTone tone) syncStateView(SyncState state) => switch (state) {
      SyncState.local => ('على الجهاز', StatusTone.neutral),
      SyncState.pending => ('بيتزامن', StatusTone.warning),
      SyncState.synced => ('اتزامن', StatusTone.positive),
      SyncState.conflict => ('تعارض', StatusTone.negative),
    };

