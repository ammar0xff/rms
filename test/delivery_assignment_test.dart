import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/assignment/delivery_assignment.dart';
import 'package:rms/src/domain/models/delivery.dart';

DeliveryModel _job(
  String id, {
  DeliveryState state = DeliveryState.waiting,
  String driver = DeliveryModel.unassignedDriver,
  int minute = 0,
}) =>
    DeliveryModel(
      id: id,
      orderRef: 'ORD-$id',
      address: 'عنوان $id',
      amount: 10,
      state: state,
      createdAt: DateTime(2026, 10, 12, 12, minute),
      driver: driver,
    );

void main() {
  test('pickDriver returns null when no courier is available', () {
    expect(
      DeliveryAssignmentPolicy.pickDriver(deliveries: const [], drivers: const []),
      isNull,
    );
    expect(
      DeliveryAssignmentPolicy.pickDriver(
        deliveries: const [],
        drivers: const [DriverModel(id: 'd1', name: 'Ali', available: false)],
      ),
      isNull,
    );
  });

  test('pickDriver chooses the least-loaded available courier', () {
    final deliveries = [
      _job('a', state: DeliveryState.assigned, driver: 'Ali'),
      _job('b', state: DeliveryState.onRoute, driver: 'Basma'),
      // Delivered jobs no longer load a courier.
      _job('c', state: DeliveryState.delivered, driver: 'Nour'),
    ];
    const drivers = [
      DriverModel(id: 'd1', name: 'Ali'),
      DriverModel(id: 'd2', name: 'Basma'),
      DriverModel(id: 'd3', name: 'Nour'),
    ];

    expect(
      DeliveryAssignmentPolicy.pickDriver(
        deliveries: deliveries,
        drivers: drivers,
      ),
      'Nour',
    );
  });

  test('pickDriver ignores unavailable couriers even when idle', () {
    final deliveries = [
      _job('a', state: DeliveryState.assigned, driver: 'Ali'),
      _job('b', state: DeliveryState.assigned, driver: 'Ali'),
    ];
    const drivers = [
      DriverModel(id: 'd1', name: 'Ali'),
      DriverModel(id: 'd2', name: 'Basma', available: false),
    ];

    expect(
      DeliveryAssignmentPolicy.pickDriver(
        deliveries: deliveries,
        drivers: drivers,
      ),
      'Ali',
    );
  });

  test('pickDriver breaks ties by name, then id', () {
    const drivers = [
      DriverModel(id: 'z', name: 'Zed'),
      DriverModel(id: 'a', name: 'Ali'),
    ];
    expect(
      DeliveryAssignmentPolicy.pickDriver(deliveries: const [], drivers: drivers),
      'Ali',
    );
  });

  test('plan leaves non-waiting jobs alone', () {
    final deliveries = [
      _job('a', state: DeliveryState.onRoute, driver: 'Ali'),
      _job('b'),
    ];
    const drivers = [DriverModel(id: 'd1', name: 'Ali')];

    final plan = DeliveryAssignmentPolicy.plan(
      deliveries: deliveries,
      drivers: drivers,
    );
    expect(plan, hasLength(1));
    expect(plan.single.deliveryId, 'b');
  });

  test('plan spreads waiting jobs as evenly as possible, oldest first', () {
    final deliveries = [
      _job('c', minute: 30),
      _job('a', minute: 10),
      _job('b', minute: 20),
    ];
    const drivers = [
      DriverModel(id: 'd1', name: 'Ali'),
      DriverModel(id: 'd2', name: 'Basma'),
    ];

    final plan = DeliveryAssignmentPolicy.plan(
      deliveries: deliveries,
      drivers: drivers,
    );

    // Oldest first (a, b, c), alternating between the two couriers.
    expect(plan.map((p) => p.deliveryId).toList(), ['a', 'b', 'c']);
    expect(plan.map((p) => p.driver).toList(), ['Ali', 'Basma', 'Ali']);
  });

  test('plan accounts for the couriers\' current open load', () {
    final deliveries = [
      _job('x', state: DeliveryState.assigned, driver: 'Ali'),
      _job('y', state: DeliveryState.onRoute, driver: 'Ali'),
      _job('n'),
    ];
    const drivers = [
      DriverModel(id: 'd1', name: 'Ali'),
      DriverModel(id: 'd2', name: 'Basma'),
    ];

    final plan = DeliveryAssignmentPolicy.plan(
      deliveries: deliveries,
      drivers: drivers,
    );
    expect(plan.single.deliveryId, 'n');
    expect(plan.single.driver, 'Basma');
  });

  test('plan is empty when no courier is available', () {
    expect(
      DeliveryAssignmentPolicy.plan(
        deliveries: [_job('a')],
        drivers: const [DriverModel(id: 'd1', name: 'Ali', available: false)],
      ),
      isEmpty,
    );
  });

  test('plan is deterministic for the same inputs', () {
    final deliveries = [_job('a'), _job('b'), _job('c'), _job('d'), _job('e')];
    const drivers = [
      DriverModel(id: 'd1', name: 'Ali'),
      DriverModel(id: 'd2', name: 'Basma'),
    ];

    final first = DeliveryAssignmentPolicy.plan(
      deliveries: deliveries,
      drivers: drivers,
    );
    final second = DeliveryAssignmentPolicy.plan(
      deliveries: deliveries,
      drivers: drivers,
    );

    expect(
      first.map((p) => '${p.deliveryId}:${p.driver}').toList(),
      second.map((p) => '${p.deliveryId}:${p.driver}').toList(),
    );
  });
}
