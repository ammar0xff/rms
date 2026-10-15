import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/cash_session.dart';
import '../../domain/models/payment.dart';
import '../../domain/money.dart';
import '../local/audit_log.dart';
import '../sync/record_mirror.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import 'cash_session_repository.dart';

/// Local-first cashier sessions.
///
/// The drawer total is derived from the cash payments and delivery collections
/// recorded on this device, so a session can be counted and closed offline. The
/// close command is queued for the backend and the session is only marked synced
/// once that command is acknowledged.
class LocalCashSessionRepository implements CashSessionRepository {
  LocalCashSessionRepository(
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

  /// Best-effort data mirror (see [RecordMirror]). Null outside Firebase
  /// mode, where there is nowhere to mirror to.
  final RecordMirror? _mirror;

  @override
  Future<List<CashSession>> listSessions() async {
    final snapshots = await LocalStores.cashSessions.find(_db.db);
    final sessions =
        snapshots.map((s) => CashSession.fromRecord(s.value)).toList()
          ..sort((a, b) => a.openedAt.compareTo(b.openedAt));
    return sessions;
  }

  @override
  Future<CashSession?> currentSession() async {
    final snapshots = await LocalStores.cashSessions.find(
      _db.db,
      finder: Finder(
        filter: Filter.equals('status', CashSessionStatus.open.name),
      ),
    );
    if (snapshots.isEmpty) return null;
    final sessions =
        snapshots.map((s) => CashSession.fromRecord(s.value)).toList()
          ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return sessions.first;
  }

  @override
  Future<CashSession> openSession({
    required double openingFloat,
    bool createdOffline = false,
  }) async {
    final now = _clock();
    final id = _uuid.v4();
    final session = CashSession(
      id: id,
      openedAt: now,
      openingFloat: openingFloat,
      createdOffline: createdOffline,
    );
    await _db.transaction((txn) async {
      final open = await LocalStores.cashSessions.find(
        txn,
        finder: Finder(
          filter: Filter.equals('status', CashSessionStatus.open.name),
        ),
      );
      if (open.isNotEmpty) return; // a session is already open
      await LocalStores.cashSessions.record(id).put(txn, session.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityId: id,
          operationType: 'openCashSession',
          createdAt: now,
          payload: {
            'id': id,
            'openingFloat': openingFloat,
            'openedAt': now.toIso8601String(),
          },
        ),
      );
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.openCashSession,
          entityType: 'cashSession',
          entityId: id,
          summary: 'فتح جلسة برأس مال ${openingFloat.toStringAsFixed(2)}',
          at: now,
          amount: openingFloat,
          createdOffline: createdOffline,
        ),
      );
    });
    return await currentSession() ?? session;
  }

  @override
  Future<CashSession> closeSession(
    String id, {
    required double countedCash,
    String? note,
  }) async {
    final now = _clock();
    CashSession? closed;
    await _db.transaction((txn) async {
      final record = LocalStores.cashSessions.record(id);
      final existing = await record.get(txn);
      if (existing == null) return;
      final session = CashSession.fromRecord(existing);
      if (!session.isOpen) {
        closed = session;
        return;
      }
      final expected = roundMoney(await _expectedCash(txn, session, now));
      final variance = roundMoney(countedCash - expected);
      session.closedAt = now;
      session.countedCash = countedCash;
      session.expectedCash = expected;
      session.status = CashSessionStatus.closed;
      session.note = note;
      session.syncStatus = SyncStatus.pendingSync;
      await record.put(txn, session.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityId: id,
          operationType: 'closeCashSession',
          createdAt: now,
          payload: {
            'id': id,
            'countedCash': countedCash,
            'expectedCash': expected,
            'variance': variance,
          },
        ),
      );
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.closeCashSession,
          entityType: 'cashSession',
          entityId: id,
          summary:
              'إغلاق جلسة · متوقع ${expected.toStringAsFixed(2)} · فرق ${variance.toStringAsFixed(2)}',
          at: now,
          amount: variance,
          createdOffline: true,
        ),
      );
      closed = session;
    });
    final result = closed;
    if (result == null) {
      throw StateError('cash session $id not found');
    }
    return result;
  }

  @override
  Future<double> expectedCash(CashSession session) => _db.transaction(
        (txn) => _expectedCash(txn, session, session.closedAt ?? _clock()),
      );

  Future<double> _expectedCash(
    Transaction txn,
    CashSession session,
    DateTime asOf,
  ) async {
    var total = session.openingFloat;
    final from = session.openedAt.toIso8601String();
    final to = asOf.toIso8601String();

    final payments = await LocalStores.payments.find(
      txn,
      finder: Finder(
        filter: Filter.and([
          Filter.greaterThanOrEquals('createdAt', from),
          Filter.lessThanOrEquals('createdAt', to),
          Filter.equals('method', PaymentMethod.cash.name),
        ]),
      ),
    );
    for (final snapshot in payments) {
      total += (snapshot.value['amount'] as num?)?.toDouble() ?? 0;
    }

    final collections = await LocalStores.collections.find(
      txn,
      finder: Finder(
        filter: Filter.and([
          Filter.greaterThanOrEquals('collectedAt', from),
          Filter.lessThanOrEquals('collectedAt', to),
          Filter.equals('method', PaymentMethod.cash.name),
        ]),
      ),
    );
    for (final snapshot in collections) {
      total += (snapshot.value['amount'] as num?)?.toDouble() ?? 0;
    }

    return total;
  }

  /// Marks a session as synced once its command is acknowledged.
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'cashSession') return;
    final record = LocalStores.cashSessions.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final session = CashSession.fromRecord(existing);
    if (!await _outbox.hasOutstandingFor(entityType: 'cashSession', entityId: entry.entityId)) {
      session.syncStatus = SyncStatus.synced;
    }
    await record.put(_db.db, session.toRecord());
    await _mirror?.write(
      entityType: 'cashSession',
      entityId: entry.entityId,
      snapshot: session.toRecord(),
    );
  }

  /// Writes pre-existing sessions without queueing commands (demo seeding).
  Future<void> seedSessions(List<CashSession> sessions) async {
    if (sessions.isEmpty) return;
    await _db.transaction((txn) async {
      for (final session in sessions) {
        await LocalStores.cashSessions
            .record(session.id)
            .put(txn, session.toRecord());
      }
    });
    AppLogger.info('Seeded ${sessions.length} demo cash sessions.');
  }

  OutboxEntry _entry({
    required String entityId,
    required String operationType,
    required DateTime createdAt,
    required Map<String, Object?> payload,
  }) =>
      OutboxEntry(
        operationId: _uuid.v4(),
        entityType: 'cashSession',
        entityId: entityId,
        operationType: operationType,
        payload: Map<String, dynamic>.from(payload),
        schemaVersion: AppVersion.localSchemaVersion,
        idempotencyKey: _uuid.v4(),
        createdAt: createdAt,
      );
}
