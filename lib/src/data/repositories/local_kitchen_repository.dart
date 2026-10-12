import 'package:sembast/sembast.dart';

import '../../domain/models/kitchen_ticket.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import 'kitchen_repository.dart';

class LocalKitchenRepository implements KitchenRepository {
  LocalKitchenRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final LocalDatabase _db;
  final DateTime Function() _clock;

  @override
  Future<void> cacheTickets(List<KitchenTicketModel> tickets, {bool replace = true}) async {
    await _db.transaction((txn) async {
      if (replace) {
        await LocalStores.kitchenTickets.delete(txn);
      }
      for (final ticket in tickets) {
        await LocalStores.kitchenTickets.record(ticket.id).put(txn, ticket.toRecord());
      }
    });
  }

  @override
  Future<void> clearTickets() async {
    await LocalStores.kitchenTickets.delete(_db.db);
  }

  @override
  Future<List<KitchenTicketModel>> listTickets({String? station, Set<TicketState>? states}) async {
    final finder = Finder(
      filter: _buildFilter(station: station, states: states),
      sortOrders: [SortOrder('createdAt'), SortOrder('id')],
    );
    final snapshots = await LocalStores.kitchenTickets.find(_db.db, finder: finder);
    return snapshots.map((s) => KitchenTicketModel.fromRecord(s.value)).toList();
  }

  @override
  Future<void> transitionTicket(String id, TicketState newState, {DateTime? now}) async {
    final time = now ?? _clock();
    await _db.transaction((txn) async {
      final record = LocalStores.kitchenTickets.record(id);
      final existing = await record.get(txn);
      if (existing == null) return;
      var ticket = KitchenTicketModel.fromRecord(existing);
      DateTime? queuedAt = ticket.queuedAt;
      DateTime? preparingAt = ticket.preparingAt;
      DateTime? readyAt = ticket.readyAt;
      DateTime? completedAt = ticket.completedAt;
      if (newState == TicketState.queued && queuedAt == null) {
        queuedAt = time;
      }
      if (newState == TicketState.preparing && preparingAt == null) {
        preparingAt = time;
      }
      if (newState == TicketState.ready && readyAt == null) {
        readyAt = time;
      }
      if (newState == TicketState.completed && completedAt == null) {
        completedAt = time;
      }
      ticket = ticket.copyWith(
        state: newState,
        queuedAt: queuedAt,
        preparingAt: preparingAt,
        readyAt: readyAt,
        completedAt: completedAt,
        lastModifiedAt: time,
      );
      await record.put(txn, ticket.toRecord());
    });
  }

  @override
  Future<void> upsertTicket(KitchenTicketModel ticket) async {
    await LocalStores.kitchenTickets.record(ticket.id).put(_db.db, ticket.toRecord());
  }

  static Filter? _buildFilter({String? station, Set<TicketState>? states}) {
    final filters = <Filter>[];
    if (station != null && station != 'الكل') {
      filters.add(Filter.equals('station', station));
    }
    if (states != null && states.isNotEmpty) {
      filters.add(
        Filter.inList('state', states.map((s) => s.name).toList()),
      );
    }
    if (filters.isEmpty) return null;
    if (filters.length == 1) return filters.single;
    return Filter.and(filters);
  }
}
