import '../../domain/models/audit_entry.dart';
import '../../domain/models/report.dart';
import '../local/audit_log.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_store.dart';
import 'cash_session_repository.dart';
import 'delivery_repository.dart';
import 'inventory_repository.dart';
import 'order_repository.dart';
import 'payment_repository.dart';
import 'purchase_repository.dart';
import 'reports_repository.dart';
import 'supplier_repository.dart';

/// Reporting read-model composed from the local-first repositories.
///
/// It holds no state of its own: every [load] re-reads the append-only sources
/// and folds them into one snapshot, so a report can never show a stale mix of
/// half-updated totals. The outbox supplies the freshness metadata
/// (last acknowledgement, pending/failed/conflict counts).
class LocalReportsRepository implements ReportsRepository {
  LocalReportsRepository(
    this._orders,
    this._payments,
    this._deliveries,
    this._cashSessions,
    this._inventory,
    this._purchases,
    this._suppliers, {
    AuditLog? audit,
    OutboxStore? outbox,
    this.windowDays = 7,
    this.auditLimit = 8,
  })  : _audit = audit,
        _outbox = outbox;

  final OrderRepository _orders;
  final PaymentRepository _payments;
  final DeliveryRepository _deliveries;
  final CashSessionRepository _cashSessions;
  final InventoryRepository _inventory;
  final PurchaseRepository _purchases;
  final SupplierRepository _suppliers;
  final AuditLog? _audit;
  final OutboxStore? _outbox;

  /// Number of days in the rolling sales window.
  final int windowDays;

  /// How many recent audit rows to include.
  final int auditLimit;

  @override
  Future<ReportsSnapshot> load({DateTime? now}) async {
    final generatedAt = now ?? DateTime.now();

    final orders = await _orders.listOrders();
    final payments = await _payments.listPayments();
    final collections = await _deliveries.listCollections();
    final sessions = await _cashSessions.listSessions();
    final items = await _inventory.listItems();
    final movements = await _inventory.listMovements();
    final purchases = await _purchases.listPurchases();
    final suppliers = await _suppliers.listSuppliers();

    final audit = _audit == null
        ? const <AuditEntry>[]
        : await _audit.list(limit: auditLimit);
    final outbox = _outbox == null
        ? const <OutboxEntry>[]
        : await _outbox.all();

    return ReportsSnapshot.from(
      generatedAt: generatedAt,
      orders: orders,
      payments: payments,
      collections: collections,
      cashSessions: sessions,
      items: items,
      movements: movements,
      purchases: purchases,
      suppliers: suppliers,
      audit: audit,
      outbox: outbox,
      windowDays: windowDays,
    );
  }
}
