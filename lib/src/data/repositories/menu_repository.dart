import '../../domain/models/menu_item.dart';
import '../local/outbox/outbox_entry.dart';

abstract class MenuRepository {
  Future<List<MenuItemModel>> listMenu({String? category, bool onlyAvailable = false});

  Future<void> cacheMenu(List<MenuItemModel> items, {bool replace = true});

  Future<void> upsertMenuItem(MenuItemModel item);

  /// Folds a sync acknowledgement back into the item.
  Future<void> applySynced(OutboxEntry entry);

  Future<void> clearMenu();
}
