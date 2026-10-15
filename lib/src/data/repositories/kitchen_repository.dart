import '../../domain/models/kitchen_ticket.dart';
import '../local/outbox/outbox_entry.dart';

abstract class KitchenRepository {
  Future<List<KitchenTicketModel>> listTickets({String? station, Set<TicketState>? states});

  Future<void> upsertTicket(KitchenTicketModel ticket);

  Future<void> transitionTicket(String id, TicketState newState, {DateTime? now});

  /// Folds a sync acknowledgement back into the ticket.
  Future<void> applySynced(OutboxEntry entry);

  Future<void> clearTickets();

  Future<void> cacheTickets(List<KitchenTicketModel> tickets, {bool replace = true});
}
