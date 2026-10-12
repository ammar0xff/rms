import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/kitchen_ticket.dart';
import 'package:rms/src/domain/services/print_adapter.dart';

void main() {
  test('LocalPrintAdapter queues kitchen ticket', () async {
    final adapter = LocalPrintAdapter();
    final ticket = KitchenTicketModel(
      id: 'T1',
      orderRef: 'ORD-1',
      station: 'بار',
      items: const ['قهوة'],
      state: TicketState.queued,
      createdAt: DateTime(2025, 1, 1),
    );
    await adapter.printKitchenTicket(ticket);
    expect(adapter.jobs.length, 1);
    expect(adapter.jobs.first.type, 'kitchen_ticket');
    expect(adapter.jobs.first.payload['id'], 'T1');
    adapter.dispose();
  });

  test('LocalPrintAdapter prints receipt and caps jobs', () async {
    final adapter = LocalPrintAdapter(maxJobs: 2);
    await adapter.printReceipt('ORD-2', {'total': 10});
    await adapter.printReceipt('ORD-3', {'total': 20});
    await adapter.printReceipt('ORD-4', {'total': 30});
    expect(adapter.jobs.length, 2);
    expect(adapter.jobs.first.payload['orderRef'], 'ORD-3');
    expect(adapter.jobs.last.payload['orderRef'], 'ORD-4');
    adapter.dispose();
  });

  test('LocalPrintAdapter emits stream on queue', () async {
    final adapter = LocalPrintAdapter();
    final completer = Completer<List<PrintJob>>();
    final sub = adapter.jobsStream.listen(completer.complete);
    await adapter.queueJob(const PrintJob(id: 'j1', type: 'test', payload: {}));
    final jobs = await completer.future.timeout(const Duration(seconds: 1));
    expect(jobs.length, 1);
    await sub.cancel();
    adapter.dispose();
  });

  test('clear empties jobs and emits', () async {
    final adapter = LocalPrintAdapter();
    await adapter.queueJob(const PrintJob(id: 'j1', type: 'test', payload: {}));
    expect(adapter.jobs.isNotEmpty, true);
    adapter.clear();
    expect(adapter.jobs.isEmpty, true);
    adapter.dispose();
  });
}
