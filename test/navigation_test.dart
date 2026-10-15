import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/navigation/delivery_navigation.dart';

void main() {
  group('delivery navigation links', () {
    test('coordinates win over the address when both exist', () {
      final uri = deliveryNavigationUri(
        lat: 30.0444,
        lng: 31.2357,
        address: 'ميدان التحرير',
      );

      expect(
        uri.toString(),
        'https://www.google.com/maps/dir/?api=1&destination='
        '30.0444%2C31.2357',
      );
    });

    test('falls back to the encoded Arabic address', () {
      final uri = deliveryNavigationUri(address: 'شارع الجمهورية، عمارة ١٢');

      expect(uri.toString(), contains('destination='));
      expect(
        uri.queryParameters['destination'],
        'شارع الجمهورية، عمارة ١٢',
      );
    });

    test('trims a padded address', () {
      final uri =
          deliveryNavigationUri(address: '  ميدان التحرير  ');

      expect(uri.queryParameters['destination'], 'ميدان التحرير');
    });
  });
}
