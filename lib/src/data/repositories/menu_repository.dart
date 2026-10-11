import '../../domain/models/menu_item.dart';

abstract class MenuRepository {
  Future<List<MenuItemModel>> listMenu({String? category, bool onlyAvailable = false});

  Future<void> cacheMenu(List<MenuItemModel> items, {bool replace = true});

  Future<void> upsertMenuItem(MenuItemModel item);

  Future<void> clearMenu();
}
