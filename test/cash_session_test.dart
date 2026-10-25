import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:rms/src/data/local/audit_log.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_cash_session_repository.dart';
import 'package:rms/src/domain/models/audit_entry.dart';
import 'package:rms/src/data/sync/record_mirror.dart';
import 'package:rms/src/domain/models/payment.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_cash_${_seq++}');

void main() {
  late LocalDatabase db;
  late AuditLog audit;
  late LocalCashSessionRepository repo;
  late DateTime now;

  setUp(() async {
    db = await _memoryDb();
    audit = AuditLog(db);
    now = DateTime(2026, 10, 13, 14);
    repo = LocalCashSessionRepository(
      db,
      outbox: OutboxStore(db),
      audit: audit,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  test('opening a session queues a command and audits it', () async {
    final session =
        await repo.openSession(openingFloat: 200, createdOffline: true);

    expect(session.isOpen, isTrue);
    expect(session.openingFloat, 200);
    expect((await repo.currentSession())?.id, session.id);

    final outbox = await OutboxStore(db).all();
    expect(outbox.single.operationType, 'openCashSession');
    expect((await audit.list()).single.action, AuditAction.openCashSession);
  });

  test('a second open returns the existing session', () async {
    final first = await repo.openSession(openingFloat: 200);
    final second = await repo.openSession(openingFloat: 999);

    expect(second.id, first.id);
    final open = (await OutboxStore(db).all())
        .where((e) => e.operationType == 'openCashSession');
    expect(open, hasLength(1));
  });

  test('expected cash counts cash payments and collections only', () async {
    final session = await repo.openSession(openingFloat: 100);

    await LocalStores.payments.record('p1').put(
          db.db,
          PaymentModel(
            id: 'p1',
            orderLocalId: 'o1',
            orderRef: 'O-1',
            amount: 30,
            method: PaymentMethod.cash,
            createdAt: DateTime(2026, 10, 13, 14, 10),
          ).toRecord(),
        );
    await LocalStores.payments.record('p2').put(
          db.db,
          PaymentModel(
            id: 'p2',
            orderLocalId: 'o2',
            orderRef: 'O-2',
            amount: 50,
            method: PaymentMethod.card,
            createdAt: DateTime(2026, 10, 13, 14, 11),
          ).toRecord(),
        );
    await LocalStores.collections.record('c1').put(db.db, {
      'id': 'c1',
      'deliveryId': 'D1',
      'orderRef': 'T-1',
      'driver': 'x',
      'amount': 20.0,
      'method': 'cash',
      'collectedAt': DateTime(2026, 10, 13, 14, 12).toIso8601String(),
      'createdOffline': true,
      'settlementStatus': 'pending',
      'syncStatus': 'pendingSync',
    });

    now = DateTime(2026, 10, 13, 15);
    // While delivery collection is pending, it must NOT enter the drawer
    expect(await repo.expectedCash(session), 130); // 100 + 30

    // Once settled, custody is handed over and enters the cashier drawer
    await LocalStores.collections.record('c1').put(db.db, {
      'id': 'c1',
      'deliveryId': 'D1',
      'orderRef': 'T-1',
      'driver': 'x',
      'amount': 20.0,
      'method': 'cash',
      'collectedAt': DateTime(2026, 10, 13, 14, 12).toIso8601String(),
      'settledAt': DateTime(2026, 10, 13, 14, 30).toIso8601String(),
      'createdOffline': true,
      'settlementStatus': 'settled',
      'syncStatus': 'pendingSync',
    });
    expect(await repo.expectedCash(session), 150); // 100 + 30 + 20
  });

  test('closing records the variance and queues a command', () async {
    final session = await repo.openSession(openingFloat: 200);

    final closed = await repo.closeSession(session.id, countedCash: 205);

    expect(closed.isOpen, isFalse);
    expect(closed.expectedCash, 200);
    expect(closed.countedCash, 205);
    expect(closed.variance, 5);

    final close = (await OutboxStore(db).all())
        .firstWhere((e) => e.operationType == 'closeCashSession');
    expect(close.payload['variance'], 5.0);
    final actions = (await audit.list()).map((e) => e.action);
    expect(actions, contains(AuditAction.closeCashSession));
  });

  test('acknowledgement marks the session synced', () async {
    final session = await repo.openSession(openingFloat: 200);
    expect((await repo.listSessions()).single.syncStatus,
        SyncStatus.pendingSync);

    // Engine order: entries are marked synced before fold-back, so
    // a quiet-guard refusal here would mean genuinely outstanding
    // work, not test scaffolding.
    for (final e in await OutboxStore(db).all()) {
      await OutboxStore(db).markSynced(e.operationId);
    }
    await repo.applySynced(OutboxEntry(
      operationId: 'op',
      entityType: 'cashSession',
      entityId: session.id,
      operationType: 'openCashSession',
      payload: const {},
      schemaVersion: 2,
      idempotencyKey: 'k',
      createdAt: DateTime(2026, 10, 13, 14),
    ));

    expect((await repo.listSessions()).single.syncStatus, SyncStatus.synced);
  });

  test('openSession and closeSession mirror immediately to Firestore mirror', () async {
    final mirror = _RecordingMirror();
    final mirrorRepo = LocalCashSessionRepository(
      db,
      outbox: OutboxStore(db),
      audit: audit,
      clock: () => now,
      mirror: mirror,
    );

    final session = await mirrorRepo.openSession(openingFloat: 350);
    expect(mirror.writes, hasLength(1));
    expect(mirror.writes.first.type, 'cashSession');
    expect(mirror.writes.first.id, session.id);
    expect(mirror.writes.first.data['status'], 'open');

    await mirrorRepo.closeSession(session.id, countedCash: 350);
    expect(mirror.writes, hasLength(2));
    expect(mirror.writes[1].type, 'cashSession');
    expect(mirror.writes[1].id, session.id);
    expect(mirror.writes[1].data['status'], 'closed');
  });
}

class _RecordingMirror implements RecordMirror {
  final List<({String type, String id, Map<String, Object?> data})> writes = [];

  @override
  Future<void> write({
    required String entityType,
    required String entityId,
    required Map<String, Object?> snapshot,
  }) async {
    writes.add((type: entityType, id: entityId, data: snapshot));
  }
}
