import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/repositories/local_inventory_repository.dart';
import 'package:rms/src/data/repositories/local_transfer_repository.dart';
import 'package:rms/src/domain/models/inventory_item.dart';
import 'package:rms/src/domain/models/stock_transfer.dart';

int _seq = 100;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_trf_$_seq');

void main() {
  late LocalDatabase db;
  late LocalInventoryRepository inventory;
  late LocalTransferRepository repo;

  setUp(() async {
    db = await _memoryDb();
    _seq++;
    inventory = LocalInventoryRepository(db);
    await inventory.cacheItems([
      InventoryItemModel(
        id: 'i1',
        name: 'دجاج',
        unit: 'كجم',
        onHand: 10,
        reorderAt: 2,
      ),
    ]);
    repo = LocalTransferRepository(db, inventory: inventory);
  });

  tearDown(() => db.close());

  Future<StockTransfer> requested() => repo.requestTransfer(
        itemId: 'i1',
        itemName: 'دجاج',
        quantity: 5,
        unit: 'كجم',
        fromBranchId: 'BR-02',
        fromBranchName: 'المعادي',
        toBranchId: 'BR-01',
        toBranchName: 'الرئيسي',
      );

  test('advances requested -> approved -> inTransit in order only', () async {
    final transfer = await requested();
    expect(transfer.status, TransferStatus.requested);

    // Receiving before transit is illegal.
    expect(repo.receiveTransfer(transfer.id), throwsStateError);

    final approved = await repo.advanceTransfer(transfer.id);
    expect(approved.status, TransferStatus.approved);
    final transit = await repo.advanceTransfer(transfer.id);
    expect(transit.status, TransferStatus.inTransit);
  });

  test('receive posts stock and is idempotent', () async {
    final transfer = await requested();
    await repo.advanceTransfer(transfer.id);
    await repo.advanceTransfer(transfer.id);

    final received = await repo.receiveTransfer(transfer.id);
    expect(received.status, TransferStatus.received);

    // Stock leg posted exactly once no matter how often receive runs.
    final again = await repo.receiveTransfer(transfer.id);
    expect(again.status, TransferStatus.received);
    final items = await inventory.listItems();
    expect(items.single.onHand, 15);
  });

  test('cancel closes an open transfer, never a received one', () async {
    final transfer = await requested();
    final cancelled = await repo.cancelTransfer(transfer.id);
    expect(cancelled.status, TransferStatus.cancelled);

    final second = await requested();
    await repo.advanceTransfer(second.id);
    await repo.advanceTransfer(second.id);
    await repo.receiveTransfer(second.id);
    expect(repo.cancelTransfer(second.id), throwsStateError);
  });
}
