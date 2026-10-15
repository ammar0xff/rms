import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../domain/money.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/supplier.dart';
import '../local/audit_log.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import 'supplier_repository.dart';

/// Local-first supplier directory backed by the on-device store.
class LocalSupplierRepository implements SupplierRepository {
  LocalSupplierRepository(
    this._db, {
    OutboxStore? outbox,
    AuditLog? audit,
    Uuid? uuid,
    DateTime Function()? clock,
  })  : _outbox = outbox ?? OutboxStore(_db),
        _audit = audit ?? AuditLog(_db),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final AuditLog _audit;
  final Uuid _uuid;
  final DateTime Function() _clock;

  @override
  Future<List<SupplierModel>> listSuppliers() async {
    final snapshots = await LocalStores.suppliers.find(_db.db);
    final suppliers =
        snapshots.map((s) => SupplierModel.fromRecord(s.value)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return suppliers;
  }

  @override
  Future<SupplierModel> createSupplier({
    required String name,
    String phone = '',
    String category = '',
    double payable = 0,
    bool createdOffline = false,
  }) async {
    final now = _clock();
    final id = _uuid.v4();
    final supplier = SupplierModel(
      id: id,
      name: name,
      phone: phone,
      category: category,
      payable: payable,
    );
    await _db.transaction((txn) async {
      await LocalStores.suppliers.record(id).put(txn, supplier.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityType: 'supplier',
          entityId: id,
          operationType: 'saveSupplier',
          createdAt: now,
          payload: {
            'id': id,
            'name': name,
            'phone': phone,
            'category': category,
            'payable': payable,
          },
        ),
      );
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.saveSupplier,
          entityType: 'supplier',
          entityId: id,
          summary: 'مورد · $name',
          at: now,
          createdOffline: createdOffline,
        ),
      );
    });
    AppLogger.info('Supplier $id created ($name).');
    return supplier;
  }

  @override
  Future<SupplierPaymentOutcome> recordSupplierPayment({
    required String supplierId,
    required double amount,
    required String reference,
    bool createdOffline = false,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      return SupplierPaymentOutcome.invalidAmount;
    }
    var outcome = SupplierPaymentOutcome.notFound;
    await _db.transaction((txn) async {
      final record = LocalStores.suppliers.record(supplierId);
      final existing = await record.get(txn);
      if (existing == null) {
        outcome = SupplierPaymentOutcome.notFound;
        return;
      }
      final supplier = SupplierModel.fromRecord(existing);
      if (amount > supplier.payable) {
        outcome = SupplierPaymentOutcome.exceedsPayable;
        return;
      }
      final now = _clock();
      supplier.payable = roundMoney(supplier.payable - amount);
      supplier.localRevision = supplier.localRevision + 1;
      supplier.syncStatus = SyncStatus.pendingSync;
      await record.put(txn, supplier.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityType: 'supplier',
          entityId: supplierId,
          operationType: 'paySupplier',
          createdAt: now,
          payload: {
            'id': supplierId,
            'amount': amount,
            'reference': reference,
            'payable': supplier.payable,
          },
        ),
      );
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.paySupplier,
          entityType: 'supplier',
          entityId: supplierId,
          summary: 'تسديد $reference · ${supplier.name}',
          at: now,
          amount: amount,
          createdOffline: createdOffline,
        ),
      );
      outcome = SupplierPaymentOutcome.recorded;
    });
    return outcome;
  }

  /// Marks a supplier synced once the backend acknowledges it.
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'supplier') return;
    final record = LocalStores.suppliers.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final supplier = SupplierModel.fromRecord(existing);
    if (!await _outbox.hasOutstandingFor(entityType: 'supplier', entityId: entry.entityId)) {
      supplier.syncStatus = SyncStatus.synced;
    }
    await record.put(_db.db, supplier.toRecord());
  }

  /// Writes pre-existing suppliers without queueing commands (demo seeding).
  Future<void> seedSuppliers(List<SupplierModel> suppliers) async {
    if (suppliers.isEmpty) return;
    await _db.transaction((txn) async {
      for (final supplier in suppliers) {
        await LocalStores.suppliers
            .record(supplier.id)
            .put(txn, supplier.toRecord());
      }
    });
    AppLogger.info('Seeded ${suppliers.length} demo suppliers.');
  }

  OutboxEntry _entry({
    required String entityType,
    required String entityId,
    required String operationType,
    required DateTime createdAt,
    required Map<String, Object?> payload,
  }) =>
      OutboxEntry(
        operationId: _uuid.v4(),
        entityType: entityType,
        entityId: entityId,
        operationType: operationType,
        payload: Map<String, dynamic>.from(payload),
        schemaVersion: AppVersion.localSchemaVersion,
        idempotencyKey: _uuid.v4(),
        createdAt: createdAt,
      );
}
