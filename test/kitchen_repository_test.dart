import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/repositories/local_kitchen_repository.dart';
import 'package:rms/src/domain/models/kitchen_ticket.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() =>
    LocalDatabase.memory('rms_kitchen_${_seq++}');

KitchenTicketModel _ticket(
  String id, {
  String station = 'حار',
  TicketState state = TicketState.queued,
  DateTime? createdAt,
}) =>
    KitchenTicketModel(
      id: id,
      orderRef: 'O-20261012-ABC123',
      station: station,
      items: const ['بيتزا'],
      state: state,
      createdAt: createdAt ?? DateTime(2026, 10, 12, 10),
    );

void main() {
  late LocalDatabase db;
  late LocalKitchenRepository repo;
  final clock = DateTime(2026, 10, 12, 11, 30);

  setUp(() async {
    db = await _memoryDb();
    repo = LocalKitchenRepository(db, clock: () => clock);
  });

  tearDown(() => db.close());

  test('starts with no tickets', () async {
    expect(await repo.listTickets(), isEmpty);
  });

  test('upserts and lists tickets', () async {
    await repo.upsertTicket(_ticket('T-1'));
    final tickets = await repo.listTickets();
    expect(tickets, hasLength(1));
    expect(tickets.single.id, 'T-1');
    expect(tickets.single.items, ['بيتزا']);
  });

  test('filters by station, treating الكل as no filter', () async {
    await repo.upsertTicket(_ticket('T-1', station: 'حار'));
    await repo.upsertTicket(_ticket('T-2', station: 'بارد'));

    expect((await repo.listTickets(station: 'حار')).single.id, 'T-1');
    expect(await repo.listTickets(station: 'الكل'), hasLength(2));
  });

  test('filters by state set', () async {
    await repo.upsertTicket(_ticket('T-1', state: TicketState.queued));
    await repo.upsertTicket(_ticket('T-2', state: TicketState.ready));

    final ready = await repo.listTickets(states: {TicketState.ready});
    expect(ready.single.id, 'T-2');
  });

  test('transition stamps each stage and persists the completed state',
      () async {
    await repo.upsertTicket(_ticket('T-1'));

    await repo.transitionTicket('T-1', TicketState.preparing);
    var ticket = (await repo.listTickets()).single;
    expect(ticket.state, TicketState.preparing);
    expect(ticket.preparingAt, clock);

    await repo.transitionTicket('T-1', TicketState.ready);
    ticket = (await repo.listTickets()).single;
    expect(ticket.state, TicketState.ready);
    expect(ticket.readyAt, clock);

    await repo.transitionTicket('T-1', TicketState.completed);
    ticket = (await repo.listTickets()).single;
    expect(ticket.state, TicketState.completed);
    expect(ticket.completedAt, clock);
    // Earlier milestones are preserved.
    expect(ticket.preparingAt, clock);
    expect(ticket.readyAt, clock);
  });

  test('transition on an unknown id is a no-op', () async {
    await repo.transitionTicket('missing', TicketState.ready);
    expect(await repo.listTickets(), isEmpty);
  });

  test('cacheTickets replaces the queue by default', () async {
    await repo.upsertTicket(_ticket('T-old'));
    await repo.cacheTickets([_ticket('T-new')]);
    expect((await repo.listTickets()).single.id, 'T-new');
  });

  test('clearTickets empties the queue', () async {
    await repo.upsertTicket(_ticket('T-1'));
    await repo.clearTickets();
    expect(await repo.listTickets(), isEmpty);
  });

  test('moves a ticket forward through the lane states', () async {
    await repo.upsertTicket(_ticket('T-1'));

    await repo.transitionTicket('T-1', TicketState.preparing);
    await repo.transitionTicket('T-1', TicketState.ready);
    await repo.transitionTicket('T-1', TicketState.completed);

    expect((await repo.listTickets()).single.state, TicketState.completed);
  });

  test('repeating the current state is a silent no-op', () async {
    await repo.upsertTicket(_ticket('T-1', state: TicketState.preparing));

    await repo.transitionTicket('T-1', TicketState.preparing);

    expect((await repo.listTickets()).single.state, TicketState.preparing);
  });

  test('refuses to move a ticket backward', () async {
    await repo.upsertTicket(_ticket('T-1', state: TicketState.ready));

    await expectLater(
      repo.transitionTicket('T-1', TicketState.preparing),
      throwsA(isA<StateError>()),
    );
    // And the failed move changed nothing.
    expect((await repo.listTickets()).single.state, TicketState.ready);
  });

  test('refuses to resurrect a completed ticket', () async {
    await repo.upsertTicket(_ticket('T-1', state: TicketState.completed));

    await expectLater(
      repo.transitionTicket('T-1', TicketState.queued),
      throwsA(isA<StateError>()),
    );
    expect((await repo.listTickets()).single.state, TicketState.completed);
  });
}
