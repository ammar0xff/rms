import 'receipt_printer_interface.dart';

ReceiptPrinterTransport createReceiptPrinterTransport() => _StubReceiptPrinterTransport();

class _StubReceiptPrinterTransport implements ReceiptPrinterTransport {
  @override
  bool printHtml(String html) => false;
}
