import 'driver_location_data.dart';
import 'location_platform_interface.dart';

LocationPlatformTransport createLocationPlatformTransport() =>
    _StubLocationPlatformTransport();

class _StubLocationPlatformTransport implements LocationPlatformTransport {
  @override
  Future<DriverLocationData?> getCurrentLocation() async => null;

  @override
  Stream<DriverLocationData> watchLocation() => const Stream.empty();

  @override
  void stopWatching() {}
}
