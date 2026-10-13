import 'package:sembast/sembast.dart';

import '../local_stores.dart';
import 'local_migration.dart';

/// The ordered list of migrations the app knows how to apply.
///
/// Append new steps; never edit or reorder a released one. Fresh installs start
/// at v0 and run the whole list, while an existing install resumes from the
/// version stored in [LocalStores.meta].
final List<LocalMigration> defaultLocalMigrations = [
  /// Baseline: the schema as it existed before the migration framework.
  LocalMigration(
    from: 0,
    to: 1,
    id: 'baseline',
    description: 'Initial local schema.',
    run: (txn) async {},
  ),

  /// Backfill fields introduced with separate settlement tracking, so records
  /// written before the split read consistently after the upgrade.
  LocalMigration(
    from: 1,
    to: 2,
    id: 'settlement-split',
    description: 'Stamp local revisions and settlement status defaults.',
    run: (txn) async {
      final deliveries = await LocalStores.deliveries.find(txn);
      for (final snapshot in deliveries) {
        final record = Map<String, Object?>.from(snapshot.value);
        record.putIfAbsent('localRevision', () => 1);
        record.putIfAbsent('settlementStatus', () => 'pending');
        await LocalStores.deliveries.record(snapshot.key).put(txn, record);
      }

      final collections = await LocalStores.collections.find(txn);
      for (final snapshot in collections) {
        final record = Map<String, Object?>.from(snapshot.value);
        record.putIfAbsent('settlementStatus', () => 'pending');
        record.putIfAbsent('createdOffline', () => false);
        await LocalStores.collections.record(snapshot.key).put(txn, record);
      }
    },
  ),

  /// Introduces the stock ledger. No stock existed before this step, but any
  /// hand-written inventory record is stamped with the revision/sync defaults
  /// the ledger reads, so it stays consistent after the upgrade.
  LocalMigration(
    from: 2,
    to: 3,
    id: 'stock-ledger',
    description: 'Introduce the stock ledger and stamp revision defaults.',
    run: (txn) async {
      final items = await LocalStores.inventory.find(txn);
      for (final snapshot in items) {
        final record = Map<String, Object?>.from(snapshot.value);
        record.putIfAbsent('localRevision', () => 1);
        record.putIfAbsent('syncStatus', () => 'pendingSync');
        await LocalStores.inventory.record(snapshot.key).put(txn, record);
      }
    },
  ),
];
