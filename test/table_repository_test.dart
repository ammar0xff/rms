import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/repositories/local_table_repository.dart';
import 'package:rms/src/domain/models/dining_table.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_tbl_$_seq');

void main() {
  late LocalDatabase db;
  late LocalTableRepository repo;

  DiningTable table({
    String id = 'T-H-1',
    String code = 'T-01',
    String zone = 'الصالة',
  }) =>
      DiningTable(id: id, code: code, zone: zone, capacity: 4);

  setUp(() async {
    db = await _memoryDb();
    _seq++;
    repo = LocalTableRepository(db);
    await repo.saveFloor([table(), table(id: 'T-H-2', code: 'T-02')]);
  });

  tearDown(() => db.close());

  test('seats, bills, and clears a table in order', () async {
    var seated = await repo.seatTable(
      tableId: 'T-H-1',
      partySize: 3,
      steward: 'سارة',
      orderRef: 'طلب-001',
    );
    expect(seated.status, TableStatus.occupied);
    expect(seated.partySize, 3);
    expect(seated.seatedAt, isNotNull);

    final billed = await repo.requestBill('T-H-1');
    expect(billed.status, TableStatus.billRequested);

    final cleared = await repo.clearTable('T-H-1');
    expect(cleared.status, TableStatus.vacant);
    expect(cleared.partySize, 0);
    expect(cleared.currentOrderRef, isNull);
  });

  test('seating an occupied table throws', () async {
    await repo.seatTable(tableId: 'T-H-1', partySize: 2);
    expect(
      repo.seatTable(tableId: 'T-H-1', partySize: 2),
      throwsStateError,
    );
  });

  test('saveFloor refuses tables with an open tab', () async {
    await repo.seatTable(tableId: 'T-H-1', partySize: 2);
    expect(
      repo.saveFloor([table()]),
      throwsStateError,
    );
  });

  test('lists ordered by zone then code', () async {
    final tables = await repo.listTables();
    expect(tables.map((t) => t.code), ['T-01', 'T-02']);
  });
}
