import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/audit_log.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_payment_repository.dart';
import 'package:rms/src/domain/models/audit_entry.dart';
import 'package:rms/src/domain/models/payment.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_audit_${_seq++}');

void main() {
  late LocalDatabase db;

  setUp(() async {
    db = await _memoryDb();
  });

  tearDown(() => db.close());

  test('records and lists entries newest first', () async {
    final log = AuditLog(db);
    await log.record(AuditEntry(
      id: 'a',
      action: AuditAction.recordPayment,
      entityType: 'payment',
      entityId: 'p1',
      summary: 'old',
      at: DateTime(2026, 1, 1),
    ));
    await log.record(AuditEntry(
      id: 'b',
      action: AuditAction.recordCollection,
      entityType: 'collection',
      entityId: 'c1',
      summary: 'new',
      at: DateTime(2026, 1, 2),
    ));

    final entries = await log.list();
    expect(entries, hasLength(2));
    expect(entries.first.id, 'b');
    expect(entries.last.id, 'a');
    expect(await log.count(), 2);
  });

  test('recording a payment writes an audit row atomically', () async {
    final log = AuditLog(db);
    final payments =
        LocalPaymentRepository(db, outbox: OutboxStore(db), audit: log);

    await payments.recordPayment(const PaymentDraft(
      orderLocalId: 'o1',
      orderRef: 'O-1',
      amount: 20,
      method: PaymentMethod.cash,
      createdOffline: true,
    ));

    final entries = await log.list();
    expect(entries, hasLength(1));
    expect(entries.single.action, AuditAction.recordPayment);
    expect(entries.single.amount, 20);
    expect(entries.single.createdOffline, isTrue);
  });

  test('round-trips through a record', () {
    final entry = AuditEntry(
      id: 'x',
      action: AuditAction.approveRequest,
      entityType: 'approval',
      entityId: 'a1',
      summary: 's',
      at: DateTime(2026, 1, 1),
      actor: 'manager',
      amount: -5,
      createdOffline: true,
    );
    final restored = AuditEntry.fromRecord(entry.toRecord());
    expect(restored.action, AuditAction.approveRequest);
    expect(restored.actor, 'manager');
    expect(restored.amount, -5);
    expect(restored.createdOffline, isTrue);
  });
}
