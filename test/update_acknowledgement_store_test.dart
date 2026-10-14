import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/data/local/update_acknowledgement_store.dart';
import 'package:rms/src/domain/update/local_work_snapshot.dart';
import 'package:rms/src/domain/update/update_acknowledgement.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() =>
    LocalDatabase.memory('rms_ack_store_${_seq++}');

UpdateAcknowledgement _ack({int stuckCount = 3}) => UpdateAcknowledgement(
      stuckCount: stuckCount,
      acknowledgedAt: DateTime.utc(2026, 10, 14, 9, 30),
      acknowledgedBy: 'shift-lead',
      note: 'network down at the branch',
    );

void main() {
  group('LocalUpdateAcknowledgementStore', () {
    test('returns null when nothing has been acknowledged', () async {
      final db = await _memoryDb();
      expect(await LocalUpdateAcknowledgementStore(db).load(), isNull);
    });

    test('round-trips an acknowledgement', () async {
      final db = await _memoryDb();
      final store = LocalUpdateAcknowledgementStore(db);

      await store.save(_ack());
      final loaded = await store.load();

      expect(loaded, isNotNull);
      expect(loaded!.stuckCount, 3);
      expect(loaded.acknowledgedBy, 'shift-lead');
      expect(loaded.note, 'network down at the branch');
      expect(loaded.acknowledgedAt, DateTime.utc(2026, 10, 14, 9, 30));
    });

    test('a later acknowledgement replaces an earlier one', () async {
      final db = await _memoryDb();
      final store = LocalUpdateAcknowledgementStore(db);

      await store.save(_ack(stuckCount: 3));
      await store.save(_ack(stuckCount: 9));

      expect((await store.load())!.stuckCount, 9);
    });

    // The store shares the `config` store with the cached manifest and the
    // device update status. Each uses its own key, so none can clobber another
    // — worth pinning, because a collision here would silently reset the
    // operator's sign-off.
    test('coexists with another config key', () async {
      final db = await _memoryDb();
      final store = LocalUpdateAcknowledgementStore(db);

      await LocalStores.config.record('someOtherSetting').put(db.db, {
        'value': 'keep me',
      });
      await store.save(_ack());

      expect(
        (await LocalStores.config.record('someOtherSetting').get(db.db))!['value'],
        'keep me',
      );
      expect((await store.load())!.stuckCount, 3);
    });

    // A corrupt row is treated as absent so the AC-35 gate falls back to
    // demanding a fresh acknowledgement, rather than reading a half-written
    // record as permission to install over unsynced work.
    test('treats a corrupt row as absent', () async {
      final db = await _memoryDb();

      await LocalStores.config
          .record(LocalUpdateAcknowledgementStore.acknowledgementKey)
          .put(db.db, {'stuckCount': 'three'});

      expect(await LocalUpdateAcknowledgementStore(db).load(), isNull);
    });

    test('treats a row with no count as absent', () async {
      final db = await _memoryDb();

      await LocalStores.config
          .record(LocalUpdateAcknowledgementStore.acknowledgementKey)
          .put(db.db, {'acknowledgedBy': 'someone'});

      expect(await LocalUpdateAcknowledgementStore(db).load(), isNull);
    });

    test('treats a negative count as absent', () async {
      final db = await _memoryDb();

      await LocalStores.config
          .record(LocalUpdateAcknowledgementStore.acknowledgementKey)
          .put(db.db, {
        'stuckCount': -1,
        'acknowledgedAt': DateTime.utc(2026, 10, 14).toIso8601String(),
      });

      expect(await LocalUpdateAcknowledgementStore(db).load(), isNull);
    });

    test('treats an unparseable timestamp as absent', () async {
      final db = await _memoryDb();

      await LocalStores.config
          .record(LocalUpdateAcknowledgementStore.acknowledgementKey)
          .put(db.db, {'stuckCount': 3, 'acknowledgedAt': 'not a date'});

      expect(await LocalUpdateAcknowledgementStore(db).load(), isNull);
    });

    // The free-text fields must not be cast. A row holding a number where a
    // string belongs used to throw out of load(), which runs inside the update
    // flow — taking sync down instead of falling back to needing a sign-off.
    test('survives a row whose free-text fields are not strings', () async {
      final db = await _memoryDb();

      await LocalStores.config
          .record(LocalUpdateAcknowledgementStore.acknowledgementKey)
          .put(db.db, {
        'stuckCount': 3,
        'acknowledgedAt': DateTime.utc(2026, 10, 14).toIso8601String(),
        'acknowledgedBy': 42,
        'note': ['unexpected'],
      });

      final loaded = await LocalUpdateAcknowledgementStore(db).load();

      // The row is usable; the two malformed fields simply come back empty.
      expect(loaded, isNotNull);
      expect(loaded!.stuckCount, 3);
      expect(loaded.acknowledgedBy, '');
      expect(loaded.note, '');
    });

    // The count is what `covers()` compares against, so a stored sign-off must
    // stop covering once the stuck backlog grows past what was reviewed — and
    // must not cover work a sync could still deliver on its own.
    test('a stored acknowledgement stops covering once stuck work grows',
        () async {
      final db = await _memoryDb();
      final store = LocalUpdateAcknowledgementStore(db);

      await store.save(_ack(stuckCount: 3));
      final ack = (await store.load())!;

      expect(ack.covers(const LocalWorkSnapshot(conflict: 3)), isTrue);
      expect(ack.covers(const LocalWorkSnapshot(conflict: 2)), isTrue);
      expect(ack.covers(const LocalWorkSnapshot(conflict: 4)), isFalse);
    });

    test('a stored acknowledgement never covers deliverable work', () async {
      final db = await _memoryDb();
      final store = LocalUpdateAcknowledgementStore(db);

      await store.save(_ack(stuckCount: 3));
      final ack = (await store.load())!;

      // Pending work is not stuck; a sync can push it. Signing off on stuck
      // items must not authorise installing over a backlog that is still owed.
      expect(ack.covers(const LocalWorkSnapshot(pending: 1)), isFalse);
    });

    test('a stored acknowledgement covers nothing when no work is stuck',
        () async {
      final db = await _memoryDb();
      final store = LocalUpdateAcknowledgementStore(db);

      await store.save(_ack(stuckCount: 3));
      final ack = (await store.load())!;

      expect(ack.covers(const LocalWorkSnapshot()), isFalse);
    });
  });
}
