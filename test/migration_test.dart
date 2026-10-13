import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/data/local/migrations/local_migration.dart';
import 'package:rms/src/data/local/migrations/local_migration_registry.dart';
import 'package:rms/src/data/local/migrations/local_migration_runner.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_mig_${_seq++}');

void main() {
  late LocalDatabase db;

  setUp(() async {
    db = await _memoryDb();
  });

  tearDown(() => db.close());

  test('applies pending migrations and records the version', () async {
    final runner = LocalMigrationRunner(db, defaultLocalMigrations);
    expect(await runner.currentVersion(), 0);

    final outcome = await runner.run(targetVersion: 2);

    expect(outcome.succeeded, isTrue);
    expect(outcome.fromVersion, 0);
    expect(outcome.toVersion, 2);
    expect(outcome.applied, ['baseline', 'settlement-split']);
    expect(outcome.changed, isTrue);
    expect(await runner.currentVersion(), 2);
  });

  test('is idempotent once at the target version', () async {
    final runner = LocalMigrationRunner(db, defaultLocalMigrations);
    await runner.run(targetVersion: 2);

    final again = await runner.run(targetVersion: 2);
    expect(again.applied, isEmpty);
    expect(again.changed, isFalse);
    expect(again.toVersion, 2);
  });

  test('backfills new fields without disturbing existing records', () async {
    await LocalStores.deliveries.record('D1').put(db.db, {
      'id': 'D1',
      'orderRef': 'O-1',
      'address': 'x',
      'amount': 10.0,
      'state': 'delivered',
      'createdAt': DateTime(2026).toIso8601String(),
      'driver': 'مروان ر.',
      'offline': false,
      'syncStatus': 'synced',
    });

    final runner = LocalMigrationRunner(db, defaultLocalMigrations);
    await runner.run(targetVersion: 2);

    final record = await LocalStores.deliveries.record('D1').get(db.db);
    expect(record, isNotNull);
    expect(record!['localRevision'], 1);
    expect(record['settlementStatus'], 'pending');
    expect(record['orderRef'], 'O-1');
  });

  test('preserves pending outbox entries across a migration', () async {
    final outbox = OutboxStore(db);
    await outbox.save(OutboxEntry(
      operationId: 'op-1',
      entityType: 'delivery',
      entityId: 'D1',
      operationType: 'createDelivery',
      payload: const {'id': 'D1'},
      schemaVersion: 1,
      idempotencyKey: 'k1',
      createdAt: DateTime(2026),
    ));

    final runner = LocalMigrationRunner(db, defaultLocalMigrations);
    await runner.run(targetVersion: 2);

    final all = await outbox.all();
    expect(all, hasLength(1));
    expect(all.single.operationId, 'op-1');
    expect(await outbox.pending(), hasLength(1));
  });

  test('a failing migration rolls back and keeps the prior version', () async {
    final outbox = OutboxStore(db);
    await outbox.save(OutboxEntry(
      operationId: 'op-keep',
      entityType: 'order',
      entityId: 'O-1',
      operationType: 'createOrder',
      payload: const {},
      schemaVersion: 1,
      idempotencyKey: 'k2',
      createdAt: DateTime(2026),
    ));

    final runner = LocalMigrationRunner(db, [
      LocalMigration(from: 0, to: 1, id: 'ok', run: (txn) async {
        await LocalStores.meta.record('touch').put(txn, {'value': 1});
      }),
      LocalMigration(from: 1, to: 2, id: 'boom', run: (txn) async {
        throw StateError('boom');
      }),
    ]);

    final outcome = await runner.run(targetVersion: 2);

    expect(outcome.succeeded, isFalse);
    expect(outcome.toVersion, 1);
    expect(outcome.applied, ['ok']);
    expect(outcome.error, contains('boom'));
    expect(await runner.currentVersion(), 1);
    expect(await outbox.pending(), hasLength(1));
  });

  test('stops at a gap in the migration list', () async {
    final runner = LocalMigrationRunner(db, [
      LocalMigration(from: 0, to: 1, id: 'a', run: (txn) async {}),
      LocalMigration(from: 2, to: 3, id: 'b', run: (txn) async {}),
    ]);

    final outcome = await runner.run(targetVersion: 3);

    expect(outcome.succeeded, isFalse);
    expect(outcome.toVersion, 1);
    expect(outcome.applied, ['a']);
    expect(await runner.currentVersion(), 1);
  });
}
