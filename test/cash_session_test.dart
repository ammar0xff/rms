import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/audit_log.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_cash_session_repository.dart';
import 'package:rms/src/domain/models/audit_entry.dart';
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
}
