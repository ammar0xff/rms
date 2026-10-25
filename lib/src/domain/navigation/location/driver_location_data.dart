import '../delivery_geocoding.dart';

/// Represents a geographic location snapshot for a driver/courier.
class DriverLocationData {
  const DriverLocationData({
    required this.coord,
    this.heading = 0.0,
    this.speed = 0.0,
    this.accuracy = 10.0,
    this.timestamp,
    this.isLiveGps = true,
  });

  /// Geographic coordinate (Latitude, Longitude)
  final GeoCoord coord;

  /// Heading in degrees clockwise from true north (0° to 360°)
  final double heading;

  /// Instantaneous speed in km/h
  final double speed;

  /// Horizontal accuracy in meters
  final double accuracy;

  /// Timestamp when the position was fixed
  final DateTime? timestamp;

  /// Whether this position was captured from real device hardware GPS
  final bool isLiveGps;

  DriverLocationData copyWith({
    GeoCoord? coord,
    double? heading,
    double? speed,
    double? accuracy,
    DateTime? timestamp,
    bool? isLiveGps,
  }) {
    return DriverLocationData(
      coord: coord ?? this.coord,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
      accuracy: accuracy ?? this.accuracy,
      timestamp: timestamp ?? this.timestamp,
      isLiveGps: isLiveGps ?? this.isLiveGps,
    );
  }

  @override
  String toString() =>
      'DriverLocationData(coord: $coord, speed: ${speed.toStringAsFixed(1)} km/h, heading: ${heading.toStringAsFixed(0)}°, accuracy: ${accuracy.toStringAsFixed(1)}m, live: $isLiveGps)';
}
