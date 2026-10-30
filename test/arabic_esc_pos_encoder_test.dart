import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/facility_settings.dart';
import 'package:rms/src/domain/models/kitchen_ticket.dart';
import 'package:rms/src/domain/services/esc_pos/arabic_esc_pos_encoder.dart';
import 'package:rms/src/domain/services/network_esc_pos_adapter.dart';
import 'package:rms/src/domain/services/socket_printer/socket_printer_transport.dart';

class _FakeSocketTransport implements SocketPrinterTransport {
  List<int>? sentBytes;
  String? host;
  int? port;

  @override
  Future<bool> sendBytes(String host, int port, List<int> bytes, {Duration timeout = const Duration(seconds: 5)}) async {
    this.host = host;
    this.port = port;
    sentBytes = bytes;
    return true;
  }

  @override
  Future<bool> testConnection(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async => true;
}

void main() {
  group('ArabicEscPosEncoder Tests', () {
    test('Arabic shaping correctly transforms characters into presentation forms', () {
      final input = 'شاي';
      final shaped = ArabicEscPosEncoder.shapeArabic(input);
      // Seen/Sheen initial (0xFEB7), Alef final (0xFE8E), Yeh isolated (0xFEF1)
      expect(shaped, isNot(equals(input)));
      expect(shaped.runes.first, 0xFEB7); // Sheen initial form
    });

    test('Lam-Alef ligatures are recognized and combined', () {
      final input = 'لا';
      final shaped = ArabicEscPosEncoder.shapeArabic(input);
      // Lam-Alef ligature (0xFEFB)
      expect(shaped.runes.length, 1);
      expect(shaped.runes.first, 0xFEFB);
    });

    test('reorderBidi reverses Arabic tokens while preserving English and numbers', () {
      final input = 'فاتورة #123';
      final formatted = ArabicEscPosEncoder.formatForPrinter(input);
      // Contains the number intact
      expect(formatted.contains('123'), isTrue);
    });

    test('codepageSelectBytes returns expected ESC/POS sequences', () {
      expect(ArabicEscPosEncoder.codepageSelectBytes('CP864'), [0x1B, 0x74, 28]);
      expect(ArabicEscPosEncoder.codepageSelectBytes('Windows-1256'), [0x1B, 0x74, 72]);
      expect(ArabicEscPosEncoder.codepageSelectBytes('UTF-8'), [0x1B, 0x74, 0]);
    });
  });

  group('NetworkEscPosPrintAdapter with Arabic Shaping', () {
    test('Kitchen ticket sends properly encoded ESC/POS sequence with codepage', () async {
      final fakeTransport = _FakeSocketTransport();
      final settings = const FacilitySettings(
        networkPrintingEnabled: true,
        printerIp: '192.168.1.50',
        printerPort: 9100,
        printerCodepage: 'CP864',
      );

      final adapter = NetworkEscPosPrintAdapter(
        settingsProvider: () async => settings,
        transport: fakeTransport,
      );

      final ticket = KitchenTicketModel(
        id: 'T-101',
        orderRef: 'ORD-101',
        station: 'سخن',
        items: const ['بيتزا مشكل جبن'],
        state: TicketState.queued,
        createdAt: DateTime.now(),
      );

      await adapter.printKitchenTicket(ticket);

      expect(fakeTransport.host, '192.168.1.50');
      expect(fakeTransport.port, 9100);
      expect(fakeTransport.sentBytes, isNotNull);

      // Verify ESC @ (0x1B, 0x40)
      expect(fakeTransport.sentBytes!.sublist(0, 2), [0x1B, 0x40]);
      // Verify ESC t 28 (0x1B, 0x74, 28) for CP864
      expect(fakeTransport.sentBytes!.sublist(2, 5), [0x1B, 0x74, 28]);
    });
  });
}
