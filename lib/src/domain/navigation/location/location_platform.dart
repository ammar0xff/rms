import 'geolocator_location_transport.dart';
import 'location_platform_interface.dart';

export 'driver_location_data.dart';
export 'geolocator_location_transport.dart';
export 'location_platform_interface.dart';

LocationPlatformTransport createLocationPlatformTransport() =>
    GeolocatorLocationPlatformTransport();
