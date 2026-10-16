import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/dining_table.dart';
import '../local/audit_log.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import '../sync/record_mirror.dart';
import 'table_repository.dart';

/// Local-first dine-in floor state. Every mutation writes its outbox
/// command in the same transaction as the record.
class LocalTableRepository implements TableRepository {
  LocalTableRepository(
    this._db, {
    OutboxStore? outbox,
    AuditLog? audit,
    Uuid? uuid,
    DateTime Function()? clock,
    RecordMirror? mirror,
  })  : _outbox = outbox ?? OutboxStore(_db),
        _audit = audit ?? AuditLog(_db),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now,
        _mirror = mirror;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final AuditLog _audit;
  final Uuid _uuid;
  final DateTime Function() _clock;
  final RecordMirror? _mirror;

  @override
  Future<List<DiningTable>> listTables() async {
    final snapshots = await LocalStores.tables.find(_db.db);
    final tables =
        snapshots.map((s) => DiningTable.fromRecord(s.value)).toList()
          ..sort((a, b) {
            final zone = a.zone.compareTo(b.zone);
            return zone != 0 ? zone : a.code.compareTo(b.code);
          });
    return tables;
  }

  Future<DiningTable> _mutate(
    String tableId,
    String operationType,
    AuditAction action,
    String summary,
    DiningTable Function(DiningTable table, DateTime now) apply,
  ) async {
    final now = _clock();
    DiningTable? result;
    await _db.transaction((txn) async {
      final record = LocalStores.tables.record(tableId);
      final existing = await record.get(txn);
      if (existing == null) {
        throw StateError('table $tableId not found');
      }
      final table = DiningTable.fromRecord(existing);
      result = apply(table, now);
      result!.syncStatus = SyncStatus.pendingSync;
      await record.put(txn, result!.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityId: tableId,
          operationType: operationType,
          createdAt: now,
          payload: result!.toRecord(),
        ),
      );
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: action,
          entityType: 'table',
          entityId: tableId,
          summary: summary,
          at: now,
        ),
      );
    });
    final done = result!;
    await mirrorRecord(
      _mirror,
      entityType: 'table',
      entityId: tableId,
      snapshot: done.toRecord(),
    );
    return done;
  }

  OutboxEntry _entry({
    required String entityId,
    required String operationType,
    required DateTime createdAt,
    required Map<String, Object?> payload,
  }) =>
      OutboxEntry(
        operationId: _uuid.v4(),
        entityType: 'table',
        entityId: entityId,
        operationType: operationType,
        payload: payload,
        schemaVersion: AppVersion.localSchemaVersion,
        idempotencyKey: _uuid.v4(),
        createdAt: createdAt,
      );

  @override
  Future<DiningTable> seatTable({
    required String tableId,
    required int partySize,
    String steward = '',
    String? orderRef,
  }) async {
    if (partySize <= 0) {
      throw ArgumentError.value(partySize, 'partySize', 'must be positive');
    }
    return _mutate(tableId, 'seatTable', AuditAction.seatTable,
        'تسكين طاولة $tableId · $partySize أفراد', (table, now) {
      if (table.status != TableStatus.vacant) {
        throw StateError('table $tableId is not vacant');
      }
      table.status = TableStatus.occupied;
      table.partySize = partySize;
      table.steward = steward;
      table.currentOrderRef = orderRef;
      table.seatedAt = now;
      return table;
    });
  }

  @override
  Future<DiningTable> requestBill(String tableId) =>
      _mutate(tableId, 'requestBill', AuditAction.seatTable,
          'طلب الشيك · طاولة $tableId', (table, now) {
        if (table.status != TableStatus.occupied) {
          throw StateError('table $tableId has no open tab');
        }
        table.status = TableStatus.billRequested;
        return table;
      });

  @override
  Future<DiningTable> clearTable(String tableId) =>
      _mutate(tableId, 'clearTable', AuditAction.clearTable,
          'تحرير طاولة $tableId', (table, now) {
        table.status = TableStatus.vacant;
        table.partySize = 0;
        table.steward = '';
        table.currentOrderRef = null;
        table.runningTotal = 0;
        table.seatedAt = null;
        return table;
      });

  @override
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'table') return;
    final record = LocalStores.tables.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final table = DiningTable.fromRecord(existing);
    if (!await _outbox.hasOutstandingFor(
        entityType: 'table', entityId: entry.entityId)) {
      table.syncStatus = SyncStatus.synced;
    }
    await record.put(_db.db, table.toRecord());
    await mirrorRecord(
      _mirror,
      entityType: 'table',
      entityId: entry.entityId,
      snapshot: table.toRecord(),
    );
  }

  @override
  Future<void> saveFloor(List<DiningTable> tables) async {
    final now = _clock();
    await _db.transaction((txn) async {
      for (final table in tables) {
        final record = LocalStores.tables.record(table.id);
        final existing = await record.get(txn);
        if (existing != null) {
          final current = DiningTable.fromRecord(existing);
          if (current.status != TableStatus.vacant) {
            throw StateError(
                'table ${table.id} has an open tab and cannot be redefined');
          }
        }
        await record.put(txn, table.toRecord());
      }
      await _outbox.append(
        txn,
        OutboxEntry(
          operationId: _uuid.v4(),
          entityType: 'table',
          entityId: 'floor',
          operationType: 'saveFloor',
          payload: {
            'count': tables.length,
          },
          schemaVersion: AppVersion.localSchemaVersion,
          idempotencyKey: _uuid.v4(),
          createdAt: now,
        ),
      );
    });
  }
}
