import 'package:flutter/material.dart';

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

class CartLine {
  CartLine(this.item, {this.quantity = 1, this.note});
  final MenuItem item;
  int quantity;
  String? note;
  double get total => item.price * quantity;
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
    MenuItem(name: 'Margherita Pizza', category: 'Pizza', price: 9.50, station: 'Hot'),
    MenuItem(name: 'Pepperoni Pizza', category: 'Pizza', price: 11.00, station: 'Hot'),
    MenuItem(name: 'Truffle Pasta', category: 'Pasta', price: 13.50, station: 'Hot'),
    MenuItem(name: 'Arrabbiata', category: 'Pasta', price: 11.50, station: 'Hot'),
    MenuItem(name: 'Caesar Salad', category: 'Salads', price: 8.00, station: 'Cold'),
    MenuItem(name: 'Greek Salad', category: 'Salads', price: 8.50, station: 'Cold'),
    MenuItem(name: 'Garlic Bread', category: 'Sides', price: 4.50, station: 'Hot'),
    MenuItem(name: 'Fries', category: 'Sides', price: 3.50, station: 'Fryer'),
    MenuItem(name: 'Chicken Wings', category: 'Sides', price: 7.50, station: 'Fryer'),
    MenuItem(name: 'Tiramisu', category: 'Desserts', price: 6.00, station: 'Cold', available: false),
    MenuItem(name: 'Espresso', category: 'Drinks', price: 2.50, station: 'Bar'),
    MenuItem(name: 'Craft Cola', category: 'Drinks', price: 3.00, station: 'Bar'),
  ];

  static const orders = <PosOrder>[
    PosOrder(number: 'ORD-4821', type: 'Dine-in', total: 42.50, status: 'Preparing', sync: SyncState.synced, time: '12:41'),
    PosOrder(number: 'T-019', type: 'Takeaway', total: 18.00, status: 'Ready', sync: SyncState.pending, time: '12:44', provisional: true),
    PosOrder(number: 'ORD-4820', type: 'Delivery', total: 27.50, status: 'Out for delivery', sync: SyncState.synced, time: '12:33'),
    PosOrder(number: 'T-018', type: 'Takeaway', total: 9.50, status: 'Completed', sync: SyncState.conflict, time: '12:20', provisional: true),
    PosOrder(number: 'ORD-4819', type: 'Dine-in', total: 63.00, status: 'Completed', sync: SyncState.synced, time: '12:05'),
  ];

  static const tickets = <KitchenTicket>[
    KitchenTicket(id: 'KT-2210', orderRef: 'ORD-4821', station: 'Hot', state: TicketState.preparing, ageMinutes: 6, items: ['2× Margherita Pizza', '1× Truffle Pasta']),
    KitchenTicket(id: 'KT-2211', orderRef: 'T-019', station: 'Fryer', state: TicketState.queued, ageMinutes: 3, items: ['1× Fries', '1× Chicken Wings'], provisional: true),
    KitchenTicket(id: 'KT-2209', orderRef: 'ORD-4820', station: 'Cold', state: TicketState.ready, ageMinutes: 14, items: ['1× Caesar Salad', '1× Tiramisu']),
    KitchenTicket(id: 'KT-2212', orderRef: 'T-019', station: 'Bar', state: TicketState.queued, ageMinutes: 2, items: ['2× Craft Cola'], provisional: true),
  ];

  static const deliveries = <DeliveryJob>[
    DeliveryJob(id: 'DL-0093', orderRef: 'ORD-4820', driver: 'Marco R.', address: '42 Oak Lane, Apt 3B', amount: 27.50, state: 'Out for delivery', offline: false),
    DeliveryJob(id: 'DL-0094', orderRef: 'ORD-4822', driver: 'Sara K.', address: '11 Birch Road', amount: 34.00, state: 'Assigned', offline: true),
    DeliveryJob(id: 'DL-0095', orderRef: 'ORD-4823', driver: 'Unassigned', address: '7 Cedar Court', amount: 21.50, state: 'Awaiting pickup', offline: false),
    DeliveryJob(id: 'DL-0096', orderRef: 'T-019', driver: 'Marco R.', address: 'Walk-in', amount: 18.00, state: 'Collected (local)', offline: true),
  ];

  static const drivers = <DriverRow>[
    DriverRow(name: 'Marco R.', status: 'On delivery', active: 2, collected: 145.50),
    DriverRow(name: 'Sara K.', status: 'Offline', active: 1, collected: 88.00),
    DriverRow(name: 'Dev P.', status: 'Available', active: 0, collected: 0),
  ];

  static const inventory = <InventoryRow>[
    InventoryRow(item: 'Mozzarella', unit: 'kg', onHand: 4.2, reorderAt: 6),
    InventoryRow(item: 'Tomato sauce', unit: 'L', onHand: 12.0, reorderAt: 5),
    InventoryRow(item: 'Pasta (penne)', unit: 'kg', onHand: 8.1, reorderAt: 4),
    InventoryRow(item: 'Chicken wings', unit: 'kg', onHand: 2.0, reorderAt: 3),
    InventoryRow(item: 'Coffee beans', unit: 'kg', onHand: 5.5, reorderAt: 2),
    InventoryRow(item: 'Olive oil', unit: 'L', onHand: 3.0, reorderAt: 2),
  ];

  static const customers = <CustomerRow>[
    CustomerRow(name: 'Daniel Okafor', phone: '+1 555 0142', orders: 27, spend: 892.40, lastVisit: 'Jul 2'),
    CustomerRow(name: 'Priya Nair', phone: '+1 555 0198', orders: 14, spend: 431.20, lastVisit: 'Jun 28'),
    CustomerRow(name: 'Luca Bianchi', phone: '+1 555 0107', orders: 41, spend: 1502.90, lastVisit: 'Jul 3'),
    CustomerRow(name: 'Hana Suzuki', phone: '+1 555 0123', orders: 6, spend: 154.00, lastVisit: 'Jun 15'),
  ];

  static const ledger = <LedgerRow>[
    LedgerRow(time: '12:44', type: 'Cash', ref: 'T-019', amount: 18.00, method: 'Cash', sync: SyncState.pending),
    LedgerRow(time: '12:41', type: 'Card', ref: 'ORD-4821', amount: 42.50, method: 'Terminal', sync: SyncState.synced),
    LedgerRow(time: '12:33', type: 'Cash', ref: 'ORD-4820', amount: 27.50, method: 'Cash', sync: SyncState.synced),
    LedgerRow(time: '12:20', type: 'Refund', ref: 'T-018', amount: -9.50, method: 'Card', sync: SyncState.conflict),
    LedgerRow(time: '12:05', type: 'Card', ref: 'ORD-4819', amount: 63.00, method: 'Terminal', sync: SyncState.synced),
    LedgerRow(time: '11:58', type: 'Collection', ref: 'DL-0091', amount: 31.20, method: 'Cash', sync: SyncState.synced),
  ];

  static const conflicts = <ConflictRow>[
    ConflictRow(id: 'CF-102', entity: 'Order T-018', type: 'Revision mismatch', detectedAt: '12:38', severity: 'Financial'),
    ConflictRow(id: 'CF-103', entity: 'Delivery DL-0094', type: 'Reassigned while offline', detectedAt: '12:41', severity: 'Assignment'),
    ConflictRow(id: 'CF-104', entity: 'Inventory: wings', type: 'Concurrent movement', detectedAt: '12:35', severity: 'Stock'),
  ];

  static const syncOperations = <SyncOperationRow>[
    SyncOperationRow(operationId: 'op_9f2a…', entity: 'localOrders/T-019', type: 'createOrder', status: 'pending', attempts: 0),
    SyncOperationRow(operationId: 'op_71bd…', entity: 'payments/pay_44', type: 'createPayment', status: 'in_progress', attempts: 1),
    SyncOperationRow(operationId: 'op_03cc…', entity: 'orders/T-018', type: 'refund', status: 'conflict', attempts: 3, lastError: 'Revision mismatch'),
    SyncOperationRow(operationId: 'op_a812…', entity: 'deliveries/DL-0094', type: 'driverEvent', status: 'retryable_failure', attempts: 4, lastError: 'Timeout'),
    SyncOperationRow(operationId: 'op_5510…', entity: 'inventory/wings', type: 'stockMovement', status: 'requires_user_action', attempts: 2, lastError: 'Concurrent change'),
    SyncOperationRow(operationId: 'op_7c1e…', entity: 'print/kt_2212', type: 'printTicket', status: 'synced', attempts: 1),
  ];

  static const salesTrend = <double>[
    420, 510, 480, 620, 700, 660, 810, 760, 880, 940, 870, 1020,
  ];

  static const hourlySales = <double>[
    2, 1, 1, 3, 6, 9, 14, 18, 12, 8, 5, 3,
  ];
}
