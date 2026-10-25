import 'package:flutter/material.dart';
import '../../../domain/models/delivery.dart';
import 'real_map_tile_widget.dart';

/// Backward-compatible wrapper exposing the authentic geographic Slippy Map Tile engine.
class DriverNavMapCanvas extends StatelessWidget {
  const DriverNavMapCanvas({
    super.key,
    required this.delivery,
    this.vehicleEmoji = '🛵',
    this.progress = 0.35,
    this.is3D = false,
    this.interactive = true,
    this.showFollowMarker = true,
    this.onProgressChanged,
    this.height,
  });

  final DeliveryModel delivery;
  final String vehicleEmoji;
  final double progress;
  final bool is3D;
  final bool interactive;
  final bool showFollowMarker;
  final ValueChanged<double>? onProgressChanged;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return RealMapTileWidget(
      delivery: delivery,
      vehicleEmoji: vehicleEmoji,
      progress: progress,
      is3D: is3D,
      interactive: interactive,
      showFollowMarker: showFollowMarker,
      onProgressChanged: onProgressChanged,
      height: height,
    );
  }
}
