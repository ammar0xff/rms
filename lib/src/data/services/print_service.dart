import '../../domain/models/kitchen_ticket.dart';
import '../../domain/services/print_adapter.dart';

class PrintService {
  PrintService({PrintAdapter? adapter}) : _adapter = adapter ?? LocalPrintAdapter();

  final PrintAdapter _adapter;

  PrintAdapter get adapter => _adapter;

  Future<void> printKitchenTicket(KitchenTicketModel ticket) =>
      _adapter.printKitchenTicket(ticket);
  Future<void> printReceipt(String orderRef, Map<String, dynamic> payload) =>
      _adapter.printReceipt(orderRef, payload);
  Future<void> queueJob(PrintJob job) => _adapter.queueJob(job);

  List<PrintJob> get jobs =>
      _adapter is LocalPrintAdapter ? _adapter.jobs : const [];
  Stream<List<PrintJob>> get jobsStream =>
      _adapter is LocalPrintAdapter
          ? _adapter.jobsStream
          : const Stream.empty();
}
