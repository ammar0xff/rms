import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/menu_item.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_store.dart';
import '../sync/record_mirror.dart';
import 'menu_repository.dart';

/// Caches the menu locally for offline reads (pricing snapshots included).
class LocalMenuRepository implements MenuRepository {
  LocalMenuRepository(
    this._db, {
    OutboxStore? outbox,
    Uuid? uuid,
    RecordMirror? mirror,
  })  : _outbox = outbox ?? OutboxStore(_db),
        _uuid = uuid ?? const Uuid(),
        _mirror = mirror;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final Uuid _uuid;

  /// Best-effort data mirror (see [RecordMirror]). Null outside Firebase
  /// mode, where there is nowhere to mirror to.
  final RecordMirror? _mirror;

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
    // Stamped dirty: availability toggles used to land as 'synced', which hid
    // them from sync and let the next cache replace destroy them.
    final dirty = item.syncStatus == 'synced'
        ? item.copyWith(syncStatus: 'pendingSync')
        : item;
    final now = DateTime.now();
    await _db.transaction((txn) async {
      await LocalStores.menu.record(item.id).put(txn, dirty.toRecord());
      await _outbox.append(
        txn,
        OutboxEntry(
          operationId: _uuid.v4(),
          entityType: 'menuItem',
          entityId: item.id,
          operationType: 'upsertMenuItem',
          payload: {
            'id': item.id,
            'available': item.available,
            'price': item.price,
          },
          schemaVersion: 1,
          idempotencyKey: _uuid.v4(),
          createdAt: now,
        ),
      );
    });
  }

  @override
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'menuItem') return;
    final record = LocalStores.menu.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final item = MenuItemModel.fromRecord(existing);
    if (!await _outbox.hasOutstandingFor(
        entityType: 'menuItem', entityId: entry.entityId)) {
      await record.put(
        _db.db,
        item.copyWith(syncStatus: 'synced').toRecord(),
      );
    }
    final settled = await record.get(_db.db);
    await mirrorRecord(
      _mirror,
      entityType: 'menuItem',
      entityId: entry.entityId,
      snapshot: settled ?? existing,
    );
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
