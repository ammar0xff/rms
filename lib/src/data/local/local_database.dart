import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';

import 'platform/db_factory.dart';

/// Owns the local document store.
///
/// Every business change that must reach the backend is committed in a single
/// [transaction] together with its outbox entry, so the two can never diverge.
class LocalDatabase {
  LocalDatabase._(this.db);

  final Database db;

  /// Opens the platform-appropriate store (file on native, IndexedDB on web).
  static Future<LocalDatabase> openPlatform() async =>
      LocalDatabase._(await openPlatformDatabase());

  /// Ephemeral store, used as a safe fallback and by lightweight tests.
  static Future<LocalDatabase> memory([String name = 'rms_local']) async =>
      LocalDatabase._(await databaseFactoryMemory.openDatabase(name));

  static LocalDatabase fromDatabase(Database db) => LocalDatabase._(db);

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) =>
      db.transaction(action);

  Future<void> close() => db.close();
}
