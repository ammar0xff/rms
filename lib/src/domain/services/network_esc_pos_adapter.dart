import 'dart:convert';
import '../models/facility_settings.dart';
import '../models/kitchen_ticket.dart';
import 'print_adapter.dart';
import 'socket_printer/socket_printer_transport.dart';

/// Network ESC/POS Print Adapter.
///
/// Sends ESC/POS command sequences over a raw TCP socket (default port 9100)
/// to thermal network/Ethernet printers, while preserving the local job queue.
class NetworkEscPosPrintAdapter implements PrintAdapter {
  NetworkEscPosPrintAdapter({
    required this.settingsProvider,
    PrintAdapter? localFallback,
    SocketPrinterTransport? transport,
  })  : _local = localFallback ?? LocalPrintAdapter(),
        _transport = transport ?? createSocketPrinterTransport();

  final Future<FacilitySettings> Function() settingsProvider;
  final PrintAdapter _local;
  final SocketPrinterTransport _transport;

  PrintAdapter get localAdapter => _local;

  /// Tests connectivity to the given printer host and port.
  Future<bool> testPrinterConnection(String host, int port) =>
      _transport.testConnection(host, port);

  @override
  Future<void> printKitchenTicket(KitchenTicketModel ticket) async {
    await _local.printKitchenTicket(ticket);

    final settings = await settingsProvider();
    if (!settings.networkPrintingEnabled || settings.printerIp.trim().isEmpty) {
      return;
    }

    final bytes = _buildKitchenTicketEscPos(ticket, settings);
    await _transport.sendBytes(
      settings.printerIp.trim(),
      settings.printerPort,
      bytes,
    );
  }

  @override
  Future<void> printReceipt(String orderRef, Map<String, dynamic> payload) async {
    await _local.printReceipt(orderRef, payload);

    final settings = await settingsProvider();
    if (!settings.networkPrintingEnabled || settings.printerIp.trim().isEmpty) {
      return;
    }

    final bytes = _buildReceiptEscPos(orderRef, payload, settings);
    await _transport.sendBytes(
      settings.printerIp.trim(),
      settings.printerPort,
      bytes,
    );
  }

  @override
  Future<void> queueJob(PrintJob job) => _local.queueJob(job);

  List<int> _buildKitchenTicketEscPos(
    KitchenTicketModel ticket,
    FacilitySettings settings,
  ) {
    final buffer = <int>[];

    // ESC @: Initialize printer
    buffer.addAll([0x1B, 0x40]);
    // Center alignment: ESC a 1
    buffer.addAll([0x1B, 0x61, 0x01]);
    // Double height & double width: GS ! 0x11
    buffer.addAll([0x1D, 0x21, 0x11]);
    buffer.addAll(utf8.encode('*** بون مطبخ - ${ticket.station} ***\n'));
    // Normal text: GS ! 0x00
    buffer.addAll([0x1D, 0x21, 0x00]);
    buffer.addAll(utf8.encode('رقم الطلب: ${ticket.orderRef}\n'));
    buffer.addAll(utf8.encode('الوقت: ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}\n'));
    buffer.addAll(utf8.encode('--------------------------------\n'));

    // Left alignment: ESC a 0
    buffer.addAll([0x1B, 0x61, 0x00]);
    for (final item in ticket.items) {
      buffer.addAll([0x1B, 0x45, 0x01]); // Bold
      buffer.addAll(utf8.encode('• $item\n'));
      buffer.addAll([0x1B, 0x45, 0x00]); // Normal
    }

    buffer.addAll(utf8.encode('--------------------------------\n\n\n'));
    // Cut paper: GS V 66 0
    buffer.addAll([0x1D, 0x56, 0x42, 0x00]);

    return buffer;
  }

  List<int> _buildReceiptEscPos(
    String orderRef,
    Map<String, dynamic> payload,
    FacilitySettings settings,
  ) {
    final buffer = <int>[];

    // ESC @: Initialize printer
    buffer.addAll([0x1B, 0x40]);
    // Center alignment: ESC a 1
    buffer.addAll([0x1B, 0x61, 0x01]);
    // Bold & header
    buffer.addAll([0x1B, 0x45, 0x01]);
    final title = settings.receiptName.isNotEmpty
        ? settings.receiptName
        : settings.nameAr;
    buffer.addAll(utf8.encode('$title\n'));
    buffer.addAll([0x1B, 0x45, 0x00]);

    if (settings.taxId.isNotEmpty) {
      buffer.addAll(utf8.encode('الرقم الضريبي: ${settings.taxId}\n'));
    }
    buffer.addAll(utf8.encode('فاتورة طلب: $orderRef\n'));
    buffer.addAll(utf8.encode('--------------------------------\n'));

    // Items
    buffer.addAll([0x1B, 0x61, 0x00]);
    final total = payload['total'] ?? payload['amount'] ?? 0.0;
    final paymentMethod = payload['method'] ?? 'نقدي';
    buffer.addAll(utf8.encode('طريقة الدفع: $paymentMethod\n'));
    buffer.addAll([0x1B, 0x45, 0x01]);
    buffer.addAll(utf8.encode('الإجمالي: $total ${settings.currency}\n'));
    buffer.addAll([0x1B, 0x45, 0x00]);

    buffer.addAll(utf8.encode('--------------------------------\n'));
    if (settings.receiptFooter.isNotEmpty) {
      buffer.addAll([0x1B, 0x61, 0x01]);
      buffer.addAll(utf8.encode('${settings.receiptFooter}\n'));
    }

    buffer.addAll(utf8.encode('\n\n\n'));
    // Cut paper: GS V 66 0
    buffer.addAll([0x1D, 0x56, 0x42, 0x00]);

    return buffer;
  }
}
