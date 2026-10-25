import 'dart:async';
import 'package:flutter/foundation.dart';
import 'delivery_geocoding.dart';
import 'location/driver_location_data.dart';
import 'location/location_platform.dart';

export 'location/driver_location_data.dart';

/// Real-time Driver GPS Geolocation Service.
///
/// Bridges device hardware GPS via platform transport (Web HTML5 Geolocation API,
/// native platforms, or mock test harness).
///
/// Provides live position, heading, velocity, accuracy, and smooth fallbacks.
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

  /// Current effective geographic coordinate for the driver.
  /// Falls back to Cairo Central Branch if GPS is not yet acquired.
  GeoCoord get effectiveCoord =>
      locationNotifier.value?.coord ?? DeliveryGeocoding.defaultBranch;

  /// Last known location data snapshot.
  DriverLocationData? get lastKnownLocation => locationNotifier.value;

  /// Whether current location is backed by live hardware GPS.
  bool get hasLiveGps => locationNotifier.value?.isLiveGps ?? false;

  /// Requests the driver's current position from device GPS.
  Future<DriverLocationData> getCurrentLocation() async {
    if (_mockLocation != null) {
      locationNotifier.value = _mockLocation;
      return _mockLocation!;
    }

    try {
      final loc = await _transport.getCurrentLocation();
      if (loc != null) {
        locationNotifier.value = loc;
        return loc;
      }
    } catch (_) {}

    // Fallback if hardware GPS unavailable
    final fallback = locationNotifier.value ??
        const DriverLocationData(
          coord: DeliveryGeocoding.defaultBranch,
          isLiveGps: false,
          accuracy: 50.0,
        );
    locationNotifier.value = fallback;
    return fallback;
  }

  /// Begins streaming live continuous GPS updates.
  Stream<DriverLocationData> startTracking() {
    if (_mockLocation != null) {
      return Stream.value(_mockLocation!);
    }

    _trackingSub?.cancel();
    final stream = _transport.watchLocation();
    _trackingSub = stream.listen(
      (data) {
        locationNotifier.value = data;
      },
      onError: (_) {},
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
  }

  /// Resets state and cancels active subscriptions.
  void reset() {
    stopTracking();
    _mockLocation = null;
    locationNotifier.value = null;
  }
}
