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
      if (replace) {
        await LocalStores.menu.delete(txn);
      }
      for (final item in items) {
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
