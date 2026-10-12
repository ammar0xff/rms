import '../../domain/models/kitchen_ticket.dart';

abstract class KitchenRepository {
  Future<List<KitchenTicketModel>> listTickets({String? station, Set<TicketState>? states});

  Future<void> upsertTicket(KitchenTicketModel ticket);

  Future<void> transitionTicket(String id, TicketState newState, {DateTime? now});

  Future<void> clearTickets();

  Future<void> cacheTickets(List<KitchenTicketModel> tickets, {bool replace = true});
}
