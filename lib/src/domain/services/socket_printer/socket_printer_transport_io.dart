import 'dart:io';
import 'socket_printer_transport_stub.dart';

SocketPrinterTransport createSocketPrinterTransport() => _IoSocketPrinterTransport();

class _IoSocketPrinterTransport implements SocketPrinterTransport {
  @override
  Future<bool> testConnection(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> sendBytes(
    String host,
    int port,
    List<int> bytes, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(bytes);
      await socket.flush();
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
