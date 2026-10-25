import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../delivery_geocoding.dart';
import 'driver_location_data.dart';
import 'location_platform_interface.dart';

/// Real Hardware GPS Transport powered by package:geolocator.
/// Handles runtime permissions, GPS satellite fixes, and continuous position tracking.
class GeolocatorLocationPlatformTransport implements LocationPlatformTransport {
  StreamSubscription<Position>? _positionSub;
  final StreamController<DriverLocationData> _controller =
      StreamController<DriverLocationData>.broadcast();

  @override
  Future<DriverLocationData?> getCurrentLocation() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return null;

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      return _mapPosition(position);
    } catch (e) {
      debugPrint('[GPS] getCurrentLocation error: $e');
      return null;
    }
  }

  @override
  Stream<DriverLocationData> watchLocation() {
    _startWatching();
    return _controller.stream;
  }

  Future<void> _startWatching() async {
    await _positionSub?.cancel();

    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return;

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      );

      _positionSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position pos) {
          final data = _mapPosition(pos);
          _controller.add(data);
        },
        onError: (err) {
          debugPrint('[GPS] Stream error: $err');
        },
      );
    } catch (e) {
      debugPrint('[GPS] Start watching error: $e');
    }
  }

  @override
  void stopWatching() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  /// Checks and prompts user for location permissions if necessary.
  static Future<bool> checkAndRequestPermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  static DriverLocationData _mapPosition(Position p) {
    final speedKmh = (p.speed * 3.6).clamp(0.0, 160.0);
    return DriverLocationData(
      coord: GeoCoord(p.latitude, p.longitude),
      heading: p.heading.clamp(0.0, 360.0),
      speed: speedKmh,
      accuracy: p.accuracy,
      timestamp: p.timestamp,
      isLiveGps: true,
    );
  }
}
