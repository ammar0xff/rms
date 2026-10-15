import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_customer_repository.dart';
import 'package:rms/src/data/sync/record_mirror.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() =>
    LocalDatabase.memory('rms_cust_${_seq++}');

class _Mirror implements RecordMirror {
  final List<({String type, String id, Map<String, Object?> snapshot})>
      calls = [];

  @override
  Future<void> write({
    required String entityType,
    required String entityId,
    required Map<String, Object?> snapshot,
  }) async {
    calls.add((type: entityType, id: entityId, snapshot: snapshot));
  }
}

void main() {
  late LocalDatabase db;
  late LocalCustomerRepository repo;

  setUp(() async {
    db = await _memoryDb();
    repo = LocalCustomerRepository(db, mirror: _Mirror());
  });

  tearDown(() => db.close());

  group('LocalCustomerRepository', () {
    test('starts empty', () async {
      expect(await repo.listCustomers(), isEmpty);
    });

    test('rejects a blank name', () async {
      await expectLater(
        repo.createCustomer(name: '   '),
        throwsA(isA<ArgumentError>()),
      );
      expect(await repo.listCustomers(), isEmpty);
    });

    test('creates a customer with its sync command atomically', () async {
      final customer = await repo.createCustomer(
        name: '  محمد السيد  ',
        phone: '+20 100 555 0142',
        notes: 'الدور الثالث',
      );

      // Trimmed at the boundary, dirty until acknowledged.
      expect(customer.name, 'محمد السيد');
      expect(customer.phone, '+20 100 555 0142');
      expect(customer.syncStatus, SyncStatus.pendingSync);

      final queued = await OutboxStore(db).all();
      expect(queued, hasLength(1));
      expect(queued.single.entityType, 'customer');
      expect(queued.single.entityId, customer.id);
      expect(queued.single.operationType, 'createCustomer');
      expect(queued.single.payload['name'], 'محمد السيد');
    });

    test('an ack marks the customer synced and mirrors it', () async {
      final mirror = _Mirror();
      final synced = LocalCustomerRepository(db, mirror: mirror);
      final customer = await synced.createCustomer(name: 'سارة');

      final store = OutboxStore(db);
      for (final e in await store.all()) {
        await store.markSynced(e.operationId);
      }
      await synced.applySynced(OutboxEntry(
        operationId: 'op-ack',
        entityType: 'customer',
        entityId: customer.id,
        operationType: 'createCustomer',
        payload: const {},
        schemaVersion: 1,
        idempotencyKey: 'idem-ack',
        createdAt: DateTime(2026, 10, 15),
        syncStatus: OutboxStatus.synced,
      ));

      expect(
        (await synced.listCustomers()).single.syncStatus,
        SyncStatus.synced,
      );
      expect(mirror.calls, hasLength(1));
      expect(mirror.calls.single.type, 'customer');
      expect(mirror.calls.single.snapshot['name'], 'سارة');
    });

    test('ignores other entities', () async {
      await repo.createCustomer(name: 'عمر');
      await repo.applySynced(OutboxEntry(
        operationId: 'op-x',
        entityType: 'order',
        entityId: 'o-1',
        operationType: 'createOrder',
        payload: const {},
        schemaVersion: 1,
        idempotencyKey: 'idem-x',
        createdAt: DateTime(2026, 10, 15),
        syncStatus: OutboxStatus.synced,
      ));

      expect(
        (await repo.listCustomers()).single.syncStatus,
        SyncStatus.pendingSync,
      );
    });
  });

  group('OutboxStore.pruneSynced', () {
    test('removes only acknowledged rows', () async {
      final store = OutboxStore(db);
      await repo.createCustomer(name: 'أ');
      await repo.createCustomer(name: 'ب');
      for (final e in await store.all()) {
        await store.markSynced(e.operationId);
      }
      await repo.createCustomer(name: 'ج');

      expect(await store.pruneSynced(), 2);
      final remaining = await store.all();
      expect(remaining, hasLength(1));
      expect(remaining.single.syncStatus, SyncStatus.pendingSync);
    });

    test('is a no-op on an empty outbox', () async {
      expect(await OutboxStore(db).pruneSynced(), 0);
    });
  });
}
