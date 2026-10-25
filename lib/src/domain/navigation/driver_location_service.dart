import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'delivery_geocoding.dart';
import 'location/location_platform.dart';

export 'location/driver_location_data.dart';

/// Operational status of the device GPS and location permissions.
enum LocationServiceStatus {
  unknown,
  serviceDisabled,         // Device location services / GPS toggle is off
  permissionDenied,        // User denied permission, can be requested again
  permissionDeniedForever, // User denied forever, requires opening app settings
  acquiring,               // Permission granted, actively acquiring GPS fix
  active,                  // Live hardware GPS signal acquired and streaming
}

/// Real-time Driver GPS Geolocation Service.
///
/// Bridges device hardware GPS via package:geolocator.
/// Provides live position, heading, velocity, accuracy, permission diagnostics,
/// and smooth fallbacks.
class DriverLocationService {
  DriverLocationService._internal() {
    _transport = createLocationPlatformTransport();
  }

  static final DriverLocationService instance = DriverLocationService._internal();

  late final LocationPlatformTransport _transport;
  StreamSubscription<DriverLocationData>? _trackingSub;
  DriverLocationData? _mockLocation;

  /// Notifier exposing the latest acquired driver location.
  final ValueNotifier<DriverLocationData?> locationNotifier =
      ValueNotifier<DriverLocationData?>(null);

  /// Reactive status of GPS hardware and permissions.
  final ValueNotifier<LocationServiceStatus> statusNotifier =
      ValueNotifier<LocationServiceStatus>(LocationServiceStatus.unknown);

  /// Current effective geographic coordinate for the driver.
  /// Falls back to Suez/Cairo branch anchor if GPS is not yet acquired.
  GeoCoord get effectiveCoord =>
      locationNotifier.value?.coord ?? DeliveryGeocoding.activeBranchCoord;

  /// Last known location data snapshot.
  DriverLocationData? get lastKnownLocation => locationNotifier.value;

  /// Whether current location is backed by live hardware GPS.
  bool get hasLiveGps => locationNotifier.value?.isLiveGps ?? false;

  /// Diagnostic check and prompt for location services and permissions.
  Future<LocationServiceStatus> checkAndRequestPermission({bool requestIfNotGranted = true}) async {
    if (_mockLocation != null) {
      statusNotifier.value = LocationServiceStatus.active;
      return LocationServiceStatus.active;
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        statusNotifier.value = LocationServiceStatus.serviceDisabled;
        return LocationServiceStatus.serviceDisabled;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestIfNotGranted) {
        statusNotifier.value = LocationServiceStatus.acquiring;
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        statusNotifier.value = LocationServiceStatus.permissionDenied;
        return LocationServiceStatus.permissionDenied;
      }

      if (permission == LocationPermission.deniedForever) {
        statusNotifier.value = LocationServiceStatus.permissionDeniedForever;
        return LocationServiceStatus.permissionDeniedForever;
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        statusNotifier.value = locationNotifier.value != null
            ? LocationServiceStatus.active
            : LocationServiceStatus.acquiring;
        return statusNotifier.value;
      }
    } catch (e) {
      debugPrint('[DriverLocationService] checkAndRequestPermission error: $e');
    }

    return statusNotifier.value;
  }

  /// Opens the device app settings screen so user can grant permanently denied permissions.
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Opens the device system location settings screen so user can enable GPS toggle.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Requests the driver's current position from device hardware GPS.
  Future<DriverLocationData> getCurrentLocation({bool requestPermission = true}) async {
    if (_mockLocation != null) {
      locationNotifier.value = _mockLocation;
      statusNotifier.value = LocationServiceStatus.active;
      return _mockLocation!;
    }

    if (requestPermission) {
      await checkAndRequestPermission(requestIfNotGranted: true);
    }

    try {
      final loc = await _transport.getCurrentLocation();
      if (loc != null) {
        locationNotifier.value = loc;
        statusNotifier.value = LocationServiceStatus.active;
        return loc;
      }
    } catch (e) {
      debugPrint('[DriverLocationService] getCurrentLocation error: $e');
    }

    // Fallback if hardware GPS unavailable
    final fallback = locationNotifier.value ??
        DriverLocationData(
          coord: DeliveryGeocoding.activeBranchCoord,
          isLiveGps: false,
          accuracy: 50.0,
        );
    locationNotifier.value = fallback;
    return fallback;
  }

  /// Begins streaming live continuous GPS updates from device hardware.
  Stream<DriverLocationData> startTracking() {
    if (_mockLocation != null) {
      statusNotifier.value = LocationServiceStatus.active;
      return Stream.value(_mockLocation!);
    }

    _trackingSub?.cancel();
    final stream = _transport.watchLocation();
    _trackingSub = stream.listen(
      (data) {
        locationNotifier.value = data;
        statusNotifier.value = LocationServiceStatus.active;
      },
      onError: (err) {
        debugPrint('[DriverLocationService] Tracking stream error: $err');
      },
    );
    return stream;
  }

  /// Stops continuous GPS tracking.
  void stopTracking() {
    _trackingSub?.cancel();
    _trackingSub = null;
    _transport.stopWatching();
  }

  /// Injects a mock location for automated tests and simulators.
  void setMockLocation(DriverLocationData? mock) {
    _mockLocation = mock;
    locationNotifier.value = mock;
    if (mock != null) {
      statusNotifier.value = LocationServiceStatus.active;
    }
  }

  /// Resets state and cancels active subscriptions.
  void reset() {
    stopTracking();
    _mockLocation = null;
    locationNotifier.value = null;
    statusNotifier.value = LocationServiceStatus.unknown;
  }
}
