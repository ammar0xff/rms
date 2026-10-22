import 'dart:js_interop';
import 'receipt_printer_interface.dart';

@JS('piePrintReceiptHtml')
external bool _piePrintReceiptHtml(JSString html);

@JS('pieOpenReceiptTab')
external bool _pieOpenReceiptTab(JSString html);

ReceiptPrinterTransport createReceiptPrinterTransport() => _WebReceiptPrinterTransport();

class _WebReceiptPrinterTransport implements ReceiptPrinterTransport {
  @override
  bool printHtml(String html) {
    try {
      return _piePrintReceiptHtml(html.toJS);
    } catch (e) {
      // ignore: avoid_print
      print('[ReceiptPrinterWeb] printHtml error: $e');
      return false;
    }
  }

  @override
  bool openHtmlInTab(String html) {
    try {
      return _pieOpenReceiptTab(html.toJS);
    } catch (e) {
      // ignore: avoid_print
      print('[ReceiptPrinterWeb] openHtmlInTab error: $e');
      return false;
    }
  }
}

