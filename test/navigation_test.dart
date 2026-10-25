import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/navigation/delivery_geocoding.dart';
import 'package:rms/src/domain/navigation/delivery_navigation.dart';
import 'package:rms/src/domain/navigation/driver_location_service.dart';

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

    test('googleMapsTurnByTurnUri includes origin when provided', () {
      const driverPos = GeoCoord(30.0500, 31.2400);
      const clientPos = GeoCoord(30.0600, 31.2500);

      final uri = googleMapsTurnByTurnUri(
        origin: driverPos,
        coord: clientPos,
        address: 'شارع المعز',
      );

      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['origin'], '30.05,31.24');
      expect(uri.queryParameters['destination'], '30.06,31.25');
      expect(uri.queryParameters['travelmode'], 'driving');
    });

    test('googleMapsTurnByTurnUri works without origin', () {
      const clientPos = GeoCoord(30.0600, 31.2500);

      final uri = googleMapsTurnByTurnUri(
        coord: clientPos,
        address: 'شارع المعز',
      );

      expect(uri.queryParameters['origin'], isNull);
      expect(uri.queryParameters['destination'], '30.06,31.25');
      expect(uri.queryParameters['travelmode'], 'driving');
    });

    test('wazeNavigationUri generates valid waze deep-link', () {
      const clientPos = GeoCoord(30.0600, 31.2500);
      final uri = wazeNavigationUri(coord: clientPos);

      expect(uri.scheme, 'https');
      expect(uri.host, 'waze.com');
      expect(uri.queryParameters['ll'], '30.06,31.25');
      expect(uri.queryParameters['navigate'], 'yes');
    });
  });

  group('DriverLocationService and Trip Maneuvers', () {
    setUp(() {
      DriverLocationService.instance.reset();
    });

    tearDown(() {
      DriverLocationService.instance.reset();
    });

    test('falls back to active branch when no GPS acquired', () {
      final effective = DriverLocationService.instance.effectiveCoord;
      expect(effective.lat, DeliveryGeocoding.activeBranchCoord.lat);
      expect(effective.lng, DeliveryGeocoding.activeBranchCoord.lng);
      expect(DriverLocationService.instance.hasLiveGps, isFalse);
    });

    test('updates position and notifies listeners when location is set', () {
      const testCoord = GeoCoord(30.0700, 31.3300);
      const mockData = DriverLocationData(
        coord: testCoord,
        heading: 90.0,
        speed: 35.0,
        accuracy: 5.0,
        isLiveGps: true,
      );

      DriverLocationData? notified;
      DriverLocationService.instance.locationNotifier.addListener(() {
        notified = DriverLocationService.instance.locationNotifier.value;
      });

      DriverLocationService.instance.setMockLocation(mockData);

      expect(DriverLocationService.instance.effectiveCoord.lat, 30.0700);
      expect(DriverLocationService.instance.effectiveCoord.lng, 31.3300);
      expect(DriverLocationService.instance.hasLiveGps, isTrue);
      expect(notified?.speed, 35.0);
      expect(notified?.heading, 90.0);
    });
  });
}
