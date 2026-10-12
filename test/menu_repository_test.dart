import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/repositories/local_menu_repository.dart';
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
