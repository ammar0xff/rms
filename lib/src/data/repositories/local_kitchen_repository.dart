import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/kitchen_ticket.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_store.dart';
import '../sync/record_mirror.dart';
import 'kitchen_repository.dart';

class LocalKitchenRepository implements KitchenRepository {
  LocalKitchenRepository(
    this._db, {
    DateTime Function()? clock,
    OutboxStore? outbox,
    Uuid? uuid,
    RecordMirror? mirror,
  })  : _clock = clock ?? DateTime.now,
        _outbox = outbox ?? OutboxStore(_db),
        _uuid = uuid ?? const Uuid(),
        _mirror = mirror;

  final LocalDatabase _db;
  final DateTime Function() _clock;
  final OutboxStore _outbox;
  final Uuid _uuid;

  /// Best-effort data mirror (see [RecordMirror]). Null outside Firebase
  /// mode, where there is nowhere to mirror to.
  final RecordMirror? _mirror;

  OutboxEntry _entry({
    required String entityId,
    required String operationType,
    required DateTime createdAt,
    required Map<String, dynamic> payload,
  }) =>
      OutboxEntry(
        operationId: _uuid.v4(),
        entityType: 'kitchenTicket',
        entityId: entityId,
        operationType: operationType,
        payload: payload,
        schemaVersion: 1,
        idempotencyKey: _uuid.v4(),
        createdAt: createdAt,
      );

  @override
  Future<void> cacheTickets(List<KitchenTicketModel> tickets, {bool replace = true}) async {
    await _db.transaction((txn) async {
      // Tickets now queue sync commands, so a replace must not destroy rows
      // with unsynced work. Dirty rows survive; the rest refresh.
      final dirty = <String, Map<String, Object?>>{};
      if (replace) {
        final existing = await LocalStores.kitchenTickets.find(txn);
        for (final s in existing) {
          final ticket = KitchenTicketModel.fromRecord(s.value);
          if (ticket.syncStatus != 'synced') dirty[ticket.id] = s.value;
        }
        await LocalStores.kitchenTickets.delete(txn);
        for (final e in dirty.entries) {
          await LocalStores.kitchenTickets.record(e.key).put(txn, e.value);
        }
      }
      for (final ticket in tickets) {
        if (dirty.containsKey(ticket.id)) continue;
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
      // Tickets move forward only: queued → preparing → ready → completed.
      // Backward transitions corrupt the stage timestamps and can resurrect
      // completed tickets into live lanes. Same-state repeats are no-ops.
      if (newState.index < ticket.state.index) {
        throw StateError(
          'illegal ticket transition ${ticket.state.name} -> ${newState.name}',
        );
      }
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
        syncStatus: 'pendingSync',
      );
      await record.put(txn, ticket.toRecord());
      // State moves sync like everything else: previously transitions wrote
      // no command, so offline tickets never reached the backend and dispatch
      // failures vanished without a trace.
      await _outbox.append(
        txn,
        _entry(
          entityId: id,
          operationType: 'ticketState',
          createdAt: time,
          payload: {'id': id, 'state': newState.name},
        ),
      );
    });
  }

  @override
  Future<void> upsertTicket(KitchenTicketModel ticket) async {
    final now = _clock();
    // Stamped dirty: the factory default is 'synced', which would leave a
    // ticket that never went up looking acknowledged.
    final dirty = ticket.copyWith(syncStatus: 'pendingSync');
    await _db.transaction((txn) async {
      await LocalStores.kitchenTickets.record(ticket.id).put(txn, dirty.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityId: ticket.id,
          operationType: 'upsertTicket',
          createdAt: now,
          payload: {
            'id': ticket.id,
            'orderRef': ticket.orderRef,
            'station': ticket.station,
            'state': ticket.state.name,
          },
        ),
      );
    });
  }

  @override
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'kitchenTicket') return;
    final record = LocalStores.kitchenTickets.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final ticket = KitchenTicketModel.fromRecord(existing);
    if (!await _outbox.hasOutstandingFor(
        entityType: 'kitchenTicket', entityId: entry.entityId)) {
      await record.put(
        _db.db,
        ticket.copyWith(syncStatus: 'synced').toRecord(),
      );
    }
    // Mirror the settled state, not the pre-flip read: re-read after the
    // write above so the snapshot carries the flipped flag.
    final settled = await record.get(_db.db);
    await _mirror?.write(
      entityType: 'kitchenTicket',
      entityId: entry.entityId,
      snapshot: settled ?? existing,
    );
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
