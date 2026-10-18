abstract interface class SocketPrinterTransport {
  Future<bool> testConnection(String host, int port, {Duration timeout});
  Future<bool> sendBytes(String host, int port, List<int> bytes, {Duration timeout});
}

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
