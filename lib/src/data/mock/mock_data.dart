class MenuItem {
  const MenuItem({
    required this.name,
    required this.category,
    required this.price,
    required this.station,
    this.available = true,
  });

  final String name;
  final String category;
  final double price;
  final String station;
  final bool available;
}

class PosOrder {
  const PosOrder({
    required this.number,
    required this.type,
    required this.total,
    required this.status,
    required this.sync,
    required this.time,
    this.provisional = false,
  });

  final String number;
  final String type;
  final double total;
  final String status;
  final SyncState sync;
  final String time;
  final bool provisional;
}

enum SyncState { local, pending, synced, conflict }

class KitchenTicket {
  const KitchenTicket({
    required this.id,
    required this.orderRef,
    required this.station,
    required this.items,
    required this.state,
    required this.ageMinutes,
    this.provisional = false,
  });

  final String id;
  final String orderRef;
  final String station;
  final List<String> items;
  final TicketState state;
  final int ageMinutes;
  final bool provisional;
}

enum TicketState { queued, preparing, ready }

class DeliveryJob {
  const DeliveryJob({
    required this.id,
    required this.orderRef,
    required this.driver,
    required this.address,
    required this.amount,
    required this.state,
    required this.offline,
  });

  final String id;
  final String orderRef;
  final String driver;
  final String address;
  final double amount;
  final String state;
  final bool offline;
}

class DriverRow {
  const DriverRow({
    required this.name,
    required this.status,
    required this.active,
    required this.collected,
  });

  final String name;
  final String status;
  final int active;
  final double collected;
}

class InventoryRow {
  const InventoryRow({
    required this.item,
    required this.unit,
    required this.onHand,
    required this.reorderAt,
  });

  final String item;
  final String unit;
  final double onHand;
  final double reorderAt;

  bool get low => onHand <= reorderAt;
}

class CustomerRow {
  const CustomerRow({
    required this.name,
    required this.phone,
    required this.orders,
    required this.spend,
    required this.lastVisit,
  });

  final String name;
  final String phone;
  final int orders;
  final double spend;
  final String lastVisit;
}

class LedgerRow {
  const LedgerRow({
    required this.time,
    required this.type,
    required this.ref,
    required this.amount,
    required this.method,
    required this.sync,
  });

  final String time;
  final String type;
  final String ref;
  final double amount;
  final String method;
  final SyncState sync;
}

class ConflictRow {
  const ConflictRow({
    required this.id,
    required this.entity,
    required this.type,
    required this.detectedAt,
    required this.severity,
  });

  final String id;
  final String entity;
  final String type;
  final String detectedAt;
  final String severity;
}

class SyncOperationRow {
  const SyncOperationRow({
    required this.operationId,
    required this.entity,
    required this.type,
    required this.status,
    required this.attempts,
    this.lastError,
  });

  final String operationId;
  final String entity;
  final String type;
  final String status;
  final int attempts;
  final String? lastError;
}

abstract final class MockData {
  static const menu = <MenuItem>[
    MenuItem(name: 'بيتزا مارغريتا', category: 'بيتزا', price: 9.50, station: 'حار'),
    MenuItem(name: 'بيتزا بيبروني', category: 'بيتزا', price: 11.00, station: 'حار'),
    MenuItem(name: 'باستا تربل', category: 'باستا', price: 13.50, station: 'حار'),
    MenuItem(name: 'أرابياتا', category: 'باستا', price: 11.50, station: 'حار'),
    MenuItem(name: 'سلطة سيزر', category: 'سلطات', price: 8.00, station: 'بارد'),
    MenuItem(name: 'سلطة يونانية', category: 'سلطات', price: 8.50, station: 'بارد'),
    MenuItem(name: 'خبز بالثوم', category: 'مقبلات', price: 4.50, station: 'حار'),
    MenuItem(name: 'بطاطس مقلية', category: 'مقبلات', price: 3.50, station: 'قلاية'),
    MenuItem(name: 'أجنحة دجاج', category: 'مقبلات', price: 7.50, station: 'قلاية'),
    MenuItem(name: 'تيراميسو', category: 'حلويات', price: 6.00, station: 'بارد', available: false),
    MenuItem(name: 'إسبريسو', category: 'مشروبات', price: 2.50, station: 'البار'),
    MenuItem(name: 'كولا', category: 'مشروبات', price: 3.00, station: 'البار'),
  ];

  static const orders = <PosOrder>[
    PosOrder(number: 'ORD-4821', type: 'صالة', total: 42.50, status: 'بيتجهز', sync: SyncState.synced, time: '12:41'),
    PosOrder(number: 'T-019', type: 'تيك أواي', total: 18.00, status: 'جاهز', sync: SyncState.pending, time: '12:44', provisional: true),
    PosOrder(number: 'ORD-4820', type: 'توصيل', total: 27.50, status: 'في الطريق', sync: SyncState.synced, time: '12:33'),
    PosOrder(number: 'T-018', type: 'تيك أواي', total: 9.50, status: 'خلصان', sync: SyncState.conflict, time: '12:20', provisional: true),
    PosOrder(number: 'ORD-4819', type: 'صالة', total: 63.00, status: 'خلصان', sync: SyncState.synced, time: '12:05'),
  ];

  static const tickets = <KitchenTicket>[
    KitchenTicket(id: 'KT-2210', orderRef: 'ORD-4821', station: 'حار', state: TicketState.preparing, ageMinutes: 6, items: ['2× بيتزا مارغريتا', '1× باستا تربل']),
    KitchenTicket(id: 'KT-2211', orderRef: 'T-019', station: 'قلاية', state: TicketState.queued, ageMinutes: 3, items: ['1× بطاطس مقلية', '1× أجنحة دجاج'], provisional: true),
    KitchenTicket(id: 'KT-2209', orderRef: 'ORD-4820', station: 'بارد', state: TicketState.ready, ageMinutes: 14, items: ['1× سلطة سيزر', '1× تيراميسو']),
    KitchenTicket(id: 'KT-2212', orderRef: 'T-019', station: 'البار', state: TicketState.queued, ageMinutes: 2, items: ['2× كولا'], provisional: true),
  ];

  static const deliveries = <DeliveryJob>[
    DeliveryJob(id: 'DL-0093', orderRef: 'ORD-4820', driver: 'مروان ر.', address: '42 شارع الأرز، شقة 3ب', amount: 27.50, state: 'في الطريق', offline: false),
    DeliveryJob(id: 'DL-0094', orderRef: 'ORD-4822', driver: 'سارة ك.', address: '11 طريق البتولا', amount: 34.00, state: 'مُسند', offline: true),
    DeliveryJob(id: 'DL-0095', orderRef: 'ORD-4823', driver: 'غير مُسند', address: '7 شارع الأرز', amount: 21.50, state: 'مستني الاستلام', offline: false),
    DeliveryJob(id: 'DL-0096', orderRef: 'T-019', driver: 'مروان ر.', address: 'استلام من الفرع', amount: 18.00, state: 'تم التحصيل (محلي)', offline: true),
  ];

  static const drivers = <DriverRow>[
    DriverRow(name: 'مروان ر.', status: 'في التوصيل', active: 2, collected: 145.50),
    DriverRow(name: 'سارة ك.', status: 'غير متصل', active: 1, collected: 88.00),
    DriverRow(name: 'ديڤ ب.', status: 'متاح', active: 0, collected: 0),
  ];

  static const inventory = <InventoryRow>[
    InventoryRow(item: 'موزاريلا', unit: 'كجم', onHand: 4.2, reorderAt: 6),
    InventoryRow(item: 'صلصة الطماطم', unit: 'لتر', onHand: 12.0, reorderAt: 5),
    InventoryRow(item: 'باستا (بيني)', unit: 'كجم', onHand: 8.1, reorderAt: 4),
    InventoryRow(item: 'أجنحة دجاج', unit: 'كجم', onHand: 2.0, reorderAt: 3),
    InventoryRow(item: 'حبوب القهوة', unit: 'كجم', onHand: 5.5, reorderAt: 2),
    InventoryRow(item: 'زيت الزيتون', unit: 'لتر', onHand: 3.0, reorderAt: 2),
  ];

  static const customers = <CustomerRow>[
    CustomerRow(name: 'محمد السيد', phone: '+20 100 555 0142', orders: 27, spend: 892.40, lastVisit: '2 يوليو'),
    CustomerRow(name: 'سارة أحمد', phone: '+20 100 555 0198', orders: 14, spend: 431.20, lastVisit: '28 يونيو'),
    CustomerRow(name: 'عمر خالد', phone: '+20 100 555 0107', orders: 41, spend: 1502.90, lastVisit: '3 يوليو'),
    CustomerRow(name: 'ليلى حسن', phone: '+20 100 555 0123', orders: 6, spend: 154.00, lastVisit: '15 يونيو'),
  ];

  static const ledger = <LedgerRow>[
    LedgerRow(time: '12:44', type: 'نقدي', ref: 'T-019', amount: 18.00, method: 'نقدي', sync: SyncState.pending),
    LedgerRow(time: '12:41', type: 'فيزا', ref: 'ORD-4821', amount: 42.50, method: 'جهاز نقاط البيع', sync: SyncState.synced),
    LedgerRow(time: '12:33', type: 'نقدي', ref: 'ORD-4820', amount: 27.50, method: 'نقدي', sync: SyncState.synced),
    LedgerRow(time: '12:20', type: 'استرجاع', ref: 'T-018', amount: -9.50, method: 'فيزا', sync: SyncState.conflict),
    LedgerRow(time: '12:05', type: 'فيزا', ref: 'ORD-4819', amount: 63.00, method: 'جهاز نقاط البيع', sync: SyncState.synced),
    LedgerRow(time: '11:58', type: 'تحصيل', ref: 'DL-0091', amount: 31.20, method: 'نقدي', sync: SyncState.synced),
  ];

  static const conflicts = <ConflictRow>[
    ConflictRow(id: 'CF-102', entity: 'طلب T-018', type: 'تضارب في النسخة', detectedAt: '12:38', severity: 'مالي'),
    ConflictRow(id: 'CF-103', entity: 'توصيل DL-0094', type: 'إعادة إسناد أثناء عدم الاتصال', detectedAt: '12:41', severity: 'إسناد'),
    ConflictRow(id: 'CF-104', entity: 'المخزون: أجنحة', type: 'حركة متزامنة', detectedAt: '12:35', severity: 'مخزون'),
  ];

  static const syncOperations = <SyncOperationRow>[
    SyncOperationRow(operationId: 'op_9f2a…', entity: 'localOrders/T-019', type: 'إنشاء طلب', status: 'pending', attempts: 0),
    SyncOperationRow(operationId: 'op_71bd…', entity: 'payments/pay_44', type: 'تسجيل دفعة', status: 'in_progress', attempts: 1),
    SyncOperationRow(operationId: 'op_03cc…', entity: 'orders/T-018', type: 'استرجاع', status: 'conflict', attempts: 3, lastError: 'تضارب في النسخة'),
    SyncOperationRow(operationId: 'op_a812…', entity: 'deliveries/DL-0094', type: 'حدث توصيل', status: 'retryable_failure', attempts: 4, lastError: 'انتهت المهلة'),
    SyncOperationRow(operationId: 'op_5510…', entity: 'inventory/wings', type: 'حركة مخزون', status: 'requires_user_action', attempts: 2, lastError: 'تغيير متزامن'),
    SyncOperationRow(operationId: 'op_7c1e…', entity: 'print/kt_2212', type: 'طباعة تذكرة', status: 'synced', attempts: 1),
  ];

  static const salesTrend = <double>[
    420, 510, 480, 620, 700, 660, 810, 760, 880, 940, 870, 1020,
  ];

  static const hourlySales = <double>[
    2, 1, 1, 3, 6, 9, 14, 18, 12, 8, 5, 3,
  ];
}