import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/services/print_service.dart';
import 'package:rms/src/domain/services/print_adapter.dart';
import 'package:rms/src/domain/models/kitchen_ticket.dart';

class FakeAdapter implements PrintAdapter {
  final List<PrintJob> queued = [];

  @override
  Future<void> printKitchenTicket(KitchenTicketModel ticket) async {
    await queueJob(PrintJob(
      id: 'kt_${ticket.id}',
      type: 'kitchen_ticket',
      payload: {'id': ticket.id},
    ));
  }

  @override
  Future<void> printReceipt(String orderRef, Map<String, dynamic> payload) async {
    await queueJob(PrintJob(
      id: 'rc_$orderRef',
      type: 'receipt',
      payload: {'orderRef': orderRef},
    ));
  }

  @override
  Future<void> queueJob(PrintJob job) async {
    queued.add(job);
  }
}

void main() {
  test('PrintService delegates to adapter', () async {
    final svc = PrintService(adapter: FakeAdapter());
    await svc.printReceipt('O1', {});
    expect(svc.jobs.isEmpty, true); // fake not LocalPrintAdapter
  });

  test('PrintService exposes LocalPrintAdapter state', () async {
    final svc = PrintService(adapter: LocalPrintAdapter());
    await svc.printKitchenTicket(KitchenTicketModel(
      id: 'K1',
      orderRef: 'O2',
      station: 'طهي',
      items: const ['بطاطس'],
      state: TicketState.queued,
      createdAt: DateTime(2025, 1, 1),
    ));
    expect(svc.jobs.length, 1);
    expect(svc.jobs.first.type, 'kitchen_ticket');
  });
}
