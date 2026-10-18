abstract interface class SocketPrinterTransport {
  Future<bool> testConnection(String host, int port, {Duration timeout});
  Future<bool> sendBytes(String host, int port, List<int> bytes, {Duration timeout});
}
