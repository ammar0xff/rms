import 'outbox_entry.dart';

/// The slice of the transactional outbox the UI depends on.
///
/// Deliberately narrower than the full [OutboxStore]: the update readiness
/// gate only needs to count what is outstanding, and the conflict screen only
/// needs to read and persist entries. Declaring just those lets the settings
/// screen be exercised with an in-memory fake — a widget test cannot drive the
/// real Sembast-backed store, because it does not settle under the test
/// binding.
///
/// Write paths that must commit atomically with a business change keep using
/// [OutboxStore.append] with an explicit transaction; this contract is only for
/// callers with nothing to commit alongside.
abstract class OutboxAccess {
  /// Every entry, oldest first.
  Future<List<OutboxEntry>> all();

  /// Persists [entry] in its own transaction.
  Future<void> save(OutboxEntry entry);

  /// Deletes acknowledged entries. Only `synced` rows go, so pruning can
  /// never lose work, only history.
  Future<int> pruneSynced();
}