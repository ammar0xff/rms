import 'socket_printer_transport_interface.dart';

SocketPrinterTransport createSocketPrinterTransport() => _StubSocketPrinterTransport();

class _StubSocketPrinterTransport implements SocketPrinterTransport {
  @override
  Future<bool> testConnection(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async =>
      false;

  @override
  Future<bool> sendBytes(
    String host,
    int port,
    List<int> bytes, {
    Duration timeout = const Duration(seconds: 3),
  }) async =>
      false;
}
