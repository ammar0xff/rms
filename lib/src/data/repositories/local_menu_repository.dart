import 'package:sembast/sembast.dart';

import '../../domain/models/menu_item.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import 'menu_repository.dart';

/// Caches the menu locally for offline reads (pricing snapshots included).
class LocalMenuRepository implements MenuRepository {
  LocalMenuRepository(this._db);

  final LocalDatabase _db;

  @override
  Future<void> cacheMenu(List<MenuItemModel> items, {bool replace = true}) async {
    await _db.transaction((txn) async {
      // Dirty rows (e.g. a toggled availability not yet pushed) survive the
      // replace instead of being destroyed with it.
      final dirty = <String, Map<String, Object?>>{};
      if (replace) {
        final existing = await LocalStores.menu.find(txn);
        for (final s in existing) {
          final item = MenuItemModel.fromRecord(s.value);
          if (item.syncStatus != 'synced') dirty[item.id] = s.value;
        }
        await LocalStores.menu.delete(txn);
        for (final e in dirty.entries) {
          await LocalStores.menu.record(e.key).put(txn, e.value);
        }
      }
      for (final item in items) {
        if (dirty.containsKey(item.id)) continue;
        await LocalStores.menu.record(item.id).put(txn, item.toRecord());
      }
    });
  }

  @override
  Future<void> clearMenu() async {
    await LocalStores.menu.delete(_db.db);
  }

  @override
  Future<List<MenuItemModel>> listMenu({String? category, bool onlyAvailable = false}) async {
    final finder = Finder(
      filter: _buildFilter(category: category, onlyAvailable: onlyAvailable),
      sortOrders: [SortOrder('category'), SortOrder('name')],
    );
    final snapshots = await LocalStores.menu.find(_db.db, finder: finder);
    return snapshots
        .map((s) => MenuItemModel.fromRecord(s.value))
        .toList();
  }

  @override
  Future<void> upsertMenuItem(MenuItemModel item) async {
    await LocalStores.menu.record(item.id).put(_db.db, item.toRecord());
  }

  static Filter? _buildFilter({
    String? category,
    bool onlyAvailable = false,
  }) {
    if (category != null && onlyAvailable) {
      return Filter.and([
        Filter.equals('category', category),
        Filter.equals('available', true),
      ]);
    }
    if (category != null) {
      return Filter.equals('category', category);
    }
    if (onlyAvailable) {
      return Filter.equals('available', true);
    }
    return null;
  }
}
