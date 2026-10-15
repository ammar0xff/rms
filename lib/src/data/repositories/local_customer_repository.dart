import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/customer.dart';
import '../local/audit_log.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import '../sync/record_mirror.dart';
import 'customer_repository.dart';

/// Local-first customer directory backed by the on-device store.
///
/// [createCustomer] writes the record and its outbox entry in a single
/// transaction, so a crash can never leave an unsynced customer without a
/// matching sync command (or a sync command for a customer that does not
/// exist) — the same guarantee every other repository makes.
class LocalCustomerRepository implements CustomerRepository {
  LocalCustomerRepository(
    this._db, {
    OutboxStore? outbox,
    AuditLog? audit,
    Uuid? uuid,
    DateTime Function()? clock,
    RecordMirror? mirror,
  })  : _outbox = outbox ?? OutboxStore(_db),
        _audit = audit ?? AuditLog(_db),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now,
        _mirror = mirror;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final AuditLog _audit;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Best-effort data mirror (see [RecordMirror]). Null outside Firebase
  /// mode, where there is nowhere to mirror to.
  final RecordMirror? _mirror;

  @override
  Future<List<CustomerModel>> listCustomers() async {
    final snapshots = await LocalStores.customers.find(_db.db);
    final customers =
        snapshots.map((s) => CustomerModel.fromRecord(s.value)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return customers;
  }

  @override
  Future<CustomerModel> createCustomer({
    required String name,
    String phone = '',
    String notes = '',
    bool createdOffline = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A customer needs a name');
    }
    final now = _clock();
    final customer = CustomerModel(
      id: _uuid.v4(),
      name: trimmed,
      phone: phone.trim(),
      notes: notes.trim(),
      createdAt: now,
      syncStatus: SyncStatus.pendingSync,
    );
    final entry = OutboxEntry(
      operationId: _uuid.v4(),
      entityType: 'customer',
      entityId: customer.id,
      operationType: 'createCustomer',
      payload: {
        'id': customer.id,
        'name': customer.name,
        'phone': customer.phone,
        'notes': customer.notes,
      },
      schemaVersion: AppVersion.localSchemaVersion,
      idempotencyKey: _uuid.v4(),
      createdAt: now,
    );

    await _db.transaction((txn) async {
      await LocalStores.customers
          .record(customer.id)
          .put(txn, customer.toRecord());
      await _outbox.append(txn, entry);
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.createCustomer,
          entityType: 'customer',
          entityId: customer.id,
          summary: 'عميل جديد · ${customer.name}',
          at: now,
        ),
      );
    });
    AppLogger.info(
        'Customer ${customer.id} queued (offline=$createdOffline).');
    return customer;
  }

  @override
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'customer') return;
    final record = LocalStores.customers.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final customer = CustomerModel.fromRecord(existing);
    if (!await _outbox.hasOutstandingFor(
        entityType: 'customer', entityId: entry.entityId)) {
      customer.syncStatus = SyncStatus.synced;
    }
    await record.put(_db.db, customer.toRecord());
    await mirrorRecord(
      _mirror,
      entityType: 'customer',
      entityId: entry.entityId,
      snapshot: customer.toRecord(),
    );
  }
}
