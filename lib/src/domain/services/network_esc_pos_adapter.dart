import '../models/facility_settings.dart';
import '../models/kitchen_ticket.dart';
import 'esc_pos/arabic_esc_pos_encoder.dart';
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

  List<int> _encode(String text, FacilitySettings settings) {
    return ArabicEscPosEncoder.encode(text, codepage: settings.printerCodepage);
  }

  List<int> _buildKitchenTicketEscPos(
    KitchenTicketModel ticket,
    FacilitySettings settings,
  ) {
    final buffer = <int>[];

    // ESC @: Initialize printer
    buffer.addAll([0x1B, 0x40]);
    // Select configured printer codepage (ESC t <n>)
    buffer.addAll(ArabicEscPosEncoder.codepageSelectBytes(settings.printerCodepage));
    // Center alignment: ESC a 1
    buffer.addAll([0x1B, 0x61, 0x01]);
    // Double height & double width: GS ! 0x11
    buffer.addAll([0x1D, 0x21, 0x11]);
    buffer.addAll(_encode('*** بون مطبخ - ${ticket.station} ***\n', settings));
    // Normal text: GS ! 0x00
    buffer.addAll([0x1D, 0x21, 0x00]);
    buffer.addAll(_encode('رقم الطلب: ${ticket.orderRef}\n', settings));
    buffer.addAll(_encode('الوقت: ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}\n', settings));
    buffer.addAll(_encode('--------------------------------\n', settings));

    // Left alignment: ESC a 0
    buffer.addAll([0x1B, 0x61, 0x00]);
    for (final item in ticket.items) {
      buffer.addAll([0x1B, 0x45, 0x01]); // Bold
      buffer.addAll(_encode('• $item\n', settings));
      buffer.addAll([0x1B, 0x45, 0x00]); // Normal
    }

    buffer.addAll(_encode('--------------------------------\n\n\n', settings));
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
    // Select configured printer codepage (ESC t <n>)
    buffer.addAll(ArabicEscPosEncoder.codepageSelectBytes(settings.printerCodepage));
    // Center alignment: ESC a 1
    buffer.addAll([0x1B, 0x61, 0x01]);
    // Bold & header
    buffer.addAll([0x1B, 0x45, 0x01]);
    final title = settings.receiptName.isNotEmpty
        ? settings.receiptName
        : settings.nameAr;
    buffer.addAll(_encode('$title\n', settings));
    buffer.addAll([0x1B, 0x45, 0x00]);

    if (settings.taxId.isNotEmpty) {
      buffer.addAll(_encode('الرقم الضريبي: ${settings.taxId}\n', settings));
    }
    buffer.addAll(_encode('فاتورة طلب: $orderRef\n', settings));
    buffer.addAll(_encode('--------------------------------\n', settings));

    // Items
    buffer.addAll([0x1B, 0x61, 0x00]);
    final total = payload['total'] ?? payload['amount'] ?? 0.0;
    final paymentMethod = payload['method'] ?? 'نقدي';
    buffer.addAll(_encode('طريقة الدفع: $paymentMethod\n', settings));
    buffer.addAll([0x1B, 0x45, 0x01]);
    buffer.addAll(_encode('الإجمالي: $total ${settings.currency}\n', settings));
    buffer.addAll([0x1B, 0x45, 0x00]);

    buffer.addAll(_encode('--------------------------------\n', settings));
    if (settings.receiptFooter.isNotEmpty) {
      buffer.addAll([0x1B, 0x61, 0x01]);
      buffer.addAll(_encode('${settings.receiptFooter}\n', settings));
    }

    buffer.addAll(_encode('\n\n\n', settings));
    // Cut paper: GS V 66 0
    buffer.addAll([0x1D, 0x56, 0x42, 0x00]);

    return buffer;
  }
}
