import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_menu_repository.dart';
import 'package:rms/src/data/sync/record_mirror.dart';
import 'package:rms/src/domain/models/menu_item.dart';

MenuItemModel _item(
  String id, {
  String? name,
  required String category,
  double price = 10,
  String station = 'حار',
  bool available = true,
}) =>
    MenuItemModel(
      id: id,
      name: name ?? id,
      category: category,
      price: price,
      station: station,
      available: available,
    );

int _seq = 0;

Future<LocalDatabase> _memoryDb() =>
    LocalDatabase.memory('rms_menu_${_seq++}');

void main() {
  late LocalDatabase db;
  late LocalMenuRepository repo;

  setUp(() async {
    db = await _memoryDb();
    repo = LocalMenuRepository(db);
  });

  tearDown(() => db.close());

  test('starts with an empty menu', () async {
    expect(await repo.listMenu(), isEmpty);
  });

  test('caches items and lists them sorted by category then name', () async {
    await repo.cacheMenu([
      _item('pizza', name: 'بيتزا', category: 'بيتزا'),
      _item('salad', name: 'سلطة', category: 'سلطات'),
      _item('pasta', name: 'باستا', category: 'باستا'),
    ]);

    final items = await repo.listMenu();
    expect(items.map((m) => m.id).toList(), ['pasta', 'pizza', 'salad']);
  });

  test('an upsert stamps pendingSync and queues a command', () async {
    await repo.upsertMenuItem(_item('a', category: 'x'));

    final stored = (await repo.listMenu()).single;
    expect(stored.syncStatus, 'pendingSync');
    final queued = await OutboxStore(db).all();
    expect(queued, hasLength(1));
    expect(queued.single.entityType, 'menuItem');
    expect(queued.single.operationType, 'upsertMenuItem');
    expect(queued.single.payload['available'], isTrue);
  });

  test('an ack marks the item synced and mirrors it', () async {
    final mirror = _Mirror();
    final synced = LocalMenuRepository(db, mirror: mirror);
    await synced.upsertMenuItem(_item('a', category: 'x'));

    final store = OutboxStore(db);
    for (final e in await store.all()) {
      await store.markSynced(e.operationId);
    }
    await synced.applySynced(OutboxEntry(
      operationId: 'op-ack',
      entityType: 'menuItem',
      entityId: 'a',
      operationType: 'upsertMenuItem',
      payload: const {},
      schemaVersion: 1,
      idempotencyKey: 'idem-ack',
      createdAt: DateTime(2026, 10, 15),
      syncStatus: OutboxStatus.synced,
    ));

    expect((await synced.listMenu()).single.syncStatus, 'synced');
    expect(mirror.calls, hasLength(1));
    expect(mirror.calls.single.type, 'menuItem');
  });

  test('cacheMenu replaces the previous cache by default', () async {
    await repo.cacheMenu([_item('a', category: 'x')]);
    await repo.cacheMenu([_item('b', category: 'y')]);

    final items = await repo.listMenu();
    expect(items.map((m) => m.id).toList(), ['b']);
  });

  test('listMenu filters by category', () async {
    await repo.cacheMenu([
      _item('pizza', category: 'بيتزا'),
      _item('pasta', category: 'باستا'),
    ]);

    final items = await repo.listMenu(category: 'باستا');
    expect(items.map((m) => m.id).toList(), ['pasta']);
  });

  test('listMenu can return only available items', () async {
    await repo.cacheMenu([
      _item('sold-out', category: 'حلويات', available: false),
      _item('espresso', category: 'مشروبات'),
    ]);

    final items = await repo.listMenu(onlyAvailable: true);
    expect(items.map((m) => m.id).toList(), ['espresso']);
  });

  test('listMenu combines category and availability filters', () async {
    await repo.cacheMenu([
      _item('latte', category: 'مشروبات'),
      _item('cola', category: 'مشروبات', available: false),
      _item('water', category: 'أخرى'),
    ]);

    final items =
        await repo.listMenu(category: 'مشروبات', onlyAvailable: true);
    expect(items.map((m) => m.id).toList(), ['latte']);
  });

  test('upsertMenuItem inserts then updates an existing record', () async {
    await repo.upsertMenuItem(_item('pizza', category: 'بيتزا', price: 9));
    await repo.upsertMenuItem(
      _item('pizza', category: 'بيتزا', price: 12, available: false),
    );

    final items = await repo.listMenu();
    expect(items, hasLength(1));
    expect(items.single.price, 12);
    expect(items.single.available, isFalse);
  });

  test('clearMenu removes every cached item', () async {
    await repo.cacheMenu([_item('pizza', category: 'بيتزا')]);
    await repo.clearMenu();
    expect(await repo.listMenu(), isEmpty);
  });
}

class _Mirror implements RecordMirror {
  final List<({String type, String id})> calls = [];

  @override
  Future<void> write({
    required String entityType,
    required String entityId,
    required Map<String, Object?> snapshot,
  }) async {
    calls.add((type: entityType, id: entityId));
  }
}
