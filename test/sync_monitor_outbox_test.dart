import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/state/sync_monitor.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';

int _seq = 0;

OutboxEntry _entry(String id, OutboxStatus status) => OutboxEntry(
      operationId: id,
      entityType: 'order',
      entityId: id,
      operationType: 'createOrder',
      payload: const {},
      schemaVersion: 1,
      idempotencyKey: id,
      createdAt: DateTime.utc(2026, 10, 12),
      syncStatus: status,
    );

void main() {
  test('refresh derives pending/failed/conflicts/synced/total from outbox', () async {
    final db = await LocalDatabase.memory('rms_monitor_${_seq++}');
    final outbox = OutboxStore(db);

    await outbox.save(_entry('a', OutboxStatus.synced));
    await outbox.save(_entry('b', OutboxStatus.pending));
    await outbox.save(_entry('c', OutboxStatus.retryableFailure));
    await outbox.save(_entry('d', OutboxStatus.permanentlyRejected));
    await outbox.save(_entry('e', OutboxStatus.conflict));

    final monitor = SyncMonitor.instance;
    monitor.attach(outbox: outbox);
    await monitor.refresh();

    expect(monitor.total, 5);
    expect(monitor.synced, 1);
    expect(monitor.pending, 2);
    expect(monitor.failed, 1);
    expect(monitor.conflicts, 1);

    // Detach so the singleton does not leak state into other tests.
    monitor.attach();
    await monitor.refresh();
    expect(monitor.total, 0);

    await db.close();
  });
}
