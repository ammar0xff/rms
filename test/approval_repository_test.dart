import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:rms/src/data/local/audit_log.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_approval_repository.dart';
import 'package:rms/src/domain/models/approval_request.dart';
import 'package:rms/src/domain/models/audit_entry.dart';
import 'package:rms/src/domain/models/payment.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_appr_${_seq++}');

void main() {
  late LocalDatabase db;
  late AuditLog audit;
  late LocalApprovalRepository repo;

  setUp(() async {
    db = await _memoryDb();
    audit = AuditLog(db);
    repo = LocalApprovalRepository(
      db,
      outbox: OutboxStore(db),
      audit: audit,
      clock: () => DateTime(2026, 10, 13, 14),
    );
  });

  tearDown(() => db.close());

  Future<List<PaymentModel>> payments() async {
    final snapshots = await LocalStores.payments.find(db.db);
    return snapshots.map((s) => PaymentModel.fromRecord(s.value)).toList();
  }

  test('a refund request queues without posting money', () async {
    final request = await repo.requestRefund(
      orderLocalId: 'o1',
      orderRef: 'O-1',
      amount: 25,
      reason: 'طبق معاد',
    );

    expect(request.isPending, isTrue);
    expect(await payments(), isEmpty);
    expect(await LocalStores.payments.find(db.db), isEmpty);

    final ops = await OutboxStore(db).all();
    expect(ops.single.operationType, 'requestRefund');
    final actions = (await audit.list()).map((e) => e.action);
    expect(actions, contains(AuditAction.requestApproval));
  });

  test('approving posts a negative payment exactly once', () async {
    final request = await repo.requestRefund(
      orderLocalId: 'o1',
      orderRef: 'O-1',
      amount: 25,
      reason: 'x',
    );

    final decided = await repo.decide(request.id, approved: true);
    expect(decided?.status, ApprovalStatus.approved);

    final posted = await payments();
    expect(posted, hasLength(1));
    expect(posted.single.amount, -25);
    expect(posted.single.isRefund, isTrue);

    // Idempotent: deciding again never posts a second correction.
    await repo.decide(request.id, approved: true);
    expect(await payments(), hasLength(1));

    final ops = (await OutboxStore(db).all()).map((e) => e.operationType);
    expect(ops, containsAll(<String>['requestRefund', 'approveRefund', 'recordPayment']));
    final actions = (await audit.list()).map((e) => e.action);
    expect(actions, containsAll(<AuditAction>[
      AuditAction.recordRefund,
      AuditAction.approveRequest,
    ]));
  });

  test('rejecting posts no payment', () async {
    final request = await repo.requestRefund(
      orderLocalId: 'o1',
      orderRef: 'O-1',
      amount: 25,
      reason: 'x',
    );

    await repo.decide(request.id, approved: false);

    expect(await payments(), isEmpty);
    final requests = await repo.listRequests();
    expect(requests.single.status, ApprovalStatus.rejected);
    final actions = (await audit.list()).map((e) => e.action);
    expect(actions, contains(AuditAction.rejectRequest));
  });

  test('acknowledgement marks the request synced', () async {
    final request = await repo.requestRefund(
      orderLocalId: 'o1',
      orderRef: 'O-1',
      amount: 25,
      reason: 'x',
    );

    await repo.applySynced(OutboxEntry(
      operationId: 'op',
      entityType: 'approval',
      entityId: request.id,
      operationType: 'requestRefund',
      payload: const {},
      schemaVersion: 2,
      idempotencyKey: 'k',
      createdAt: DateTime(2026, 10, 13, 14),
    ));

    expect((await repo.listRequests()).single.syncStatus, SyncStatus.synced);
  });
}
