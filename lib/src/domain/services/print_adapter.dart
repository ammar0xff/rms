import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/kitchen_ticket.dart';

@immutable
class PrintJob {
  const PrintJob({
    required this.id,
    required this.type,
    required this.payload,
    this.createdAt,
  });

  final String id;
  final String type; // e.g. 'kitchen_ticket', 'receipt'
  final Map<String, dynamic> payload;
  final DateTime? createdAt;
}

abstract class PrintAdapter {
  Future<void> printKitchenTicket(KitchenTicketModel ticket);
  Future<void> printReceipt(String orderRef, Map<String, dynamic> payload);
  Future<void> queueJob(PrintJob job);
}

class LocalPrintAdapter implements PrintAdapter {
  LocalPrintAdapter({this.onJobQueued, this.maxJobs = 50});

  final void Function(PrintJob job)? onJobQueued;
  final int maxJobs;

  final List<PrintJob> _jobs = [];
  final StreamController<List<PrintJob>> _controller =
      StreamController<List<PrintJob>>.broadcast();

  List<PrintJob> get jobs => List.unmodifiable(_jobs);
  Stream<List<PrintJob>> get jobsStream => _controller.stream;

  void clear() {
    _jobs.clear();
    _controller.add(jobs);
  }

  @override
  Future<void> printKitchenTicket(KitchenTicketModel ticket) async {
    final job = PrintJob(
      id: 'kitchen_${ticket.id}',
      type: 'kitchen_ticket',
      payload: {
        'id': ticket.id,
        'orderRef': ticket.orderRef,
        'station': ticket.station,
        'items': ticket.items,
        'state': ticket.state.name,
        'provisional': ticket.provisional,
      },
      createdAt: DateTime.now(),
    );
    await queueJob(job);
  }

  @override
  Future<void> printReceipt(String orderRef, Map<String, dynamic> payload) async {
    final job = PrintJob(
      id: 'receipt_${orderRef}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'receipt',
      payload: {'orderRef': orderRef, ...payload},
      createdAt: DateTime.now(),
    );
    await queueJob(job);
  }

  @override
  Future<void> queueJob(PrintJob job) async {
    _jobs.add(job);
    if (_jobs.length > maxJobs) {
      _jobs.removeRange(0, _jobs.length - maxJobs);
    }
    _controller.add(jobs);
    if (onJobQueued != null) {
      onJobQueued!(job);
    }
  }

  void dispose() {
    _controller.close();
  }
}
