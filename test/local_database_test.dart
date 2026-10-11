import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:sembast/sembast.dart';

void main() {
  group('LocalDatabase', () {
    test('commits and reads records inside a transaction', () async {
      final db = await LocalDatabase.memory();
      final store = stringMapStoreFactory.store('t');

      await db.transaction((txn) => store.record('a').put(txn, {'v': 1}));

      expect((await store.record('a').get(db.db))?['v'], 1);
      await db.close();
    });

    test('a failing transaction rolls back every write', () async {
      final db = await LocalDatabase.memory();
      final store = stringMapStoreFactory.store('t');

      await expectLater(
        db.transaction((txn) async {
          await store.record('a').put(txn, {'v': 1});
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
      expect(await store.find(db.db), isEmpty);
      await db.close();
    });
  });
}
