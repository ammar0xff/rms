import 'package:uuid/uuid.dart';

import '../models/kitchen_ticket.dart';
import '../models/order.dart';

/// Turns a persisted order into the kitchen tickets the KDS needs, grouped by
/// the station that prepares each line.
///
/// The factory is intentionally synchronous and dependency-injected (clock and
/// id generator) so the routing rules can be unit-tested deterministically.
class KitchenTicketFactory {
  KitchenTicketFactory({Uuid? uuid, DateTime Function()? clock})
      : _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Station used when a line carries none (e.g. records made before stations
  /// were tracked).
  static const defaultStation = 'عام';

  /// Builds one queued ticket per station found in [order], each listing the
  /// lines that station must prepare.
  List<KitchenTicketModel> fromOrder(Order order) {
    final byStation = <String, List<String>>{};
    for (final item in order.items) {
      final station = item.station.isEmpty ? defaultStation : item.station;
      byStation.putIfAbsent(station, () => <String>[]).add(_label(item));
    }
    final now = _clock();
    return [
      for (final entry in byStation.entries)
        KitchenTicketModel(
          id: 'T-${_uuid.v4().split('-').first.toUpperCase()}',
          orderRef: order.provisionalOrderNumber,
          station: entry.key,
          items: entry.value,
          state: TicketState.queued,
          createdAt: now,
          queuedAt: now,
          provisional: order.createdOffline,
        ),
    ];
  }

  static String _label(OrderItem item) {
    final base = item.quantity > 1
        ? '${item.name} × ${item.quantity}'
        : item.name;
    final note = item.note?.trim() ?? '';
    return note.isEmpty ? base : '$base (ملاحظة: $note)';
  }
}
