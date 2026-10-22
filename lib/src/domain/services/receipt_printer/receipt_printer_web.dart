import 'dart:js_interop';
import 'receipt_printer_interface.dart';

@JS('piePrintReceiptHtml')
external bool _piePrintReceiptHtml(JSString html);

ReceiptPrinterTransport createReceiptPrinterTransport() => _WebReceiptPrinterTransport();

class _WebReceiptPrinterTransport implements ReceiptPrinterTransport {
  @override
  bool printHtml(String html) {
    try {
      return _piePrintReceiptHtml(html.toJS);
    } catch (_) {
      return false;
    }
  }
}
