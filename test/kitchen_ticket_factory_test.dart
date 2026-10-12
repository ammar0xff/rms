import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/kitchen_ticket.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/services/kitchen_ticket_factory.dart';

Order _order({List<OrderItem> items = const [], bool createdOffline = false}) =>
    Order(
      localId: 'local-1',
      provisionalOrderNumber: 'O-20261012-ABC123',
      items: items,
      createdOffline: createdOffline,
    );

void main() {
  const clock = DateTime(2026, 10, 12, 10, 30);
  KitchenTicketFactory factory() => KitchenTicketFactory(clock: () => clock);

  test('returns no tickets for an empty order', () {
    expect(factory().fromOrder(_order()), isEmpty);
  });

  test('groups lines into one ticket per station', () {
    final tickets = factory().fromOrder(_order(items: const [
      OrderItem(
          productId: 'p1', name: 'بيتزا', unitPrice: 9, quantity: 1, station: 'حار'),
      OrderItem(
          productId: 'p2', name: 'كولا', unitPrice: 3, quantity: 1, station: 'البار'),
      OrderItem(
          productId: 'p3', name: 'باستا', unitPrice: 12, quantity: 1, station: 'حار'),
    ]));

    expect(tickets, hasLength(2));
    final hot = tickets.firstWhere((t) => t.station == 'حار');
    final bar = tickets.firstWhere((t) => t.station == 'البار');
    expect(hot.items, ['بيتزا', 'باستا']);
    expect(bar.items, ['كولا']);
  });

  test('labels repeated quantities', () {
    final tickets = factory().fromOrder(_order(items: const [
      OrderItem(
          productId: 'p1', name: 'ماء', unitPrice: 2, quantity: 3, station: 'البار'),
    ]));
    expect(tickets.single.items, ['ماء × 3']);
  });

  test('routes station-less lines to the default station', () {
    final tickets = factory().fromOrder(_order(items: const [
      OrderItem(productId: 'p1', name: 'شاي', unitPrice: 2, quantity: 1),
    ]));
    expect(tickets.single.station, KitchenTicketFactory.defaultStation);
  });

  test('queues tickets seeded from the order identity and clock', () {
    final tickets = factory().fromOrder(_order(
      items: const [
        OrderItem(
            productId: 'p1', name: 'بيتزا', unitPrice: 9, quantity: 1, station: 'حار'),
      ],
      createdOffline: true,
    ));

    final ticket = tickets.single;
    expect(ticket.orderRef, 'O-20261012-ABC123');
    expect(ticket.state, TicketState.queued);
    expect(ticket.createdAt, clock);
    expect(ticket.queuedAt, clock);
    expect(ticket.provisional, isTrue);
    expect(ticket.id, startsWith('T-'));
  });

  test('generates a distinct id per ticket', () {
    final tickets = factory().fromOrder(_order(items: const [
      OrderItem(
          productId: 'p1', name: 'بيتزا', unitPrice: 9, quantity: 1, station: 'حار'),
      OrderItem(
          productId: 'p2', name: 'كولا', unitPrice: 3, quantity: 1, station: 'البار'),
    ]));
    expect(tickets.map((t) => t.id).toSet(), hasLength(2));
  });
}
