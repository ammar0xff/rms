import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import '../delivery_geocoding.dart';
import 'driver_location_data.dart';
import 'location_platform_interface.dart';

@JS('pieGetDriverLocationPromise')
external JSPromise<JSString>? _pieGetDriverLocationPromise();

@JS('pieWatchDriverLocation')
external JSNumber? _pieWatchDriverLocation();

@JS('pieClearWatchLocation')
external void _pieClearWatchLocation(JSNumber watchId);

@JS('pieGetLastLocationJson')
external JSString? _pieGetLastLocationJson();

LocationPlatformTransport createLocationPlatformTransport() =>
    _WebLocationPlatformTransport();

class _WebLocationPlatformTransport implements LocationPlatformTransport {
  int? _activeWatchId;
  Timer? _pollTimer;
  StreamController<DriverLocationData>? _streamController;
  String _lastJson = '';

  @override
  Future<DriverLocationData?> getCurrentLocation() async {
    try {
      final promise = _pieGetDriverLocationPromise();
      if (promise != null) {
        final jsStr = await promise.toDart;
        final jsonStr = jsStr.toDart;
        final data = _parseLocationJson(jsonStr);
        if (data != null) return data;
      }
    } catch (_) {}

    // Fallback: check if last location was cached/captured
    try {
      final lastJsStr = _pieGetLastLocationJson();
      if (lastJsStr != null) {
        final lastStr = lastJsStr.toDart;
        if (lastStr.isNotEmpty) {
          return _parseLocationJson(lastStr);
        }
      }
    } catch (_) {}

    return null;
  }

  @override
  Stream<DriverLocationData> watchLocation() {
    _streamController?.close();
    _streamController = StreamController<DriverLocationData>.broadcast(
      onCancel: stopWatching,
    );

    try {
      final num = _pieWatchDriverLocation();
      if (num != null) {
        _activeWatchId = num.toDartInt;
      }
    } catch (_) {}

    // Poll last location JSON every 1500ms to pipe new coordinates into the stream
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      try {
        final jsStr = _pieGetLastLocationJson();
        if (jsStr == null) return;
        final jsonStr = jsStr.toDart;
        if (jsonStr.isNotEmpty && jsonStr != _lastJson) {
          _lastJson = jsonStr;
          final data = _parseLocationJson(jsonStr);
          if (data != null && !(_streamController?.isClosed ?? true)) {
            _streamController?.add(data);
          }
        }
      } catch (_) {}
    });

    return _streamController!.stream;
  }

  @override
  void stopWatching() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_activeWatchId != null) {
      try {
        _pieClearWatchLocation(_activeWatchId!.toJS);
      } catch (_) {}
      _activeWatchId = null;
    }
    _streamController?.close();
    _streamController = null;
  }

  DriverLocationData? _parseLocationJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final lat = (map['lat'] as num).toDouble();
      final lng = (map['lng'] as num).toDouble();
      final heading = (map['heading'] as num?)?.toDouble() ?? 0.0;
      final speed = (map['speed'] as num?)?.toDouble() ?? 0.0;
      final accuracy = (map['accuracy'] as num?)?.toDouble() ?? 10.0;
      final ts = map['ts'] as int?;

      return DriverLocationData(
        coord: GeoCoord(lat, lng),
        heading: heading,
        speed: speed,
        accuracy: accuracy,
        timestamp: ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : DateTime.now(),
        isLiveGps: true,
      );
    } catch (_) {
      return null;
    }
  }
}
