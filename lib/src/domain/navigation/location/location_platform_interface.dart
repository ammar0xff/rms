import 'driver_location_data.dart';

abstract class LocationPlatformTransport {
  Future<DriverLocationData?> getCurrentLocation();
  Stream<DriverLocationData> watchLocation();
  void stopWatching();
}
