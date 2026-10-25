import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/pie_colors.dart';
import '../../../core/theme/pie_radius.dart';
import '../../../domain/models/delivery.dart';
import '../../../domain/navigation/delivery_geocoding.dart';
import '../../../domain/navigation/driver_location_service.dart';

/// Available map imagery layers
enum RealMapLayer {
  dark('🌙 ليلي', 'خريطة ليلية حقيقية عالية التباين'),
  street('☀️ شوارع', 'خريطة شوارع تفصيلية باللغة العربية'),
  satellite('🛰️ قمر صناعي', 'صور أقمار صناعية حقيقية ملتقطة من الفضاء');

  const RealMapLayer(this.label, this.description);
  final String label;
  final String description;
}

/// Real interactive Geographic Slippy Map Tile engine with dynamic route polyline,
/// authentic tile rendering from CartoDB & OpenStreetMap & ESRI Satellite,
/// real destination geocoding, courier beacon, and ergonomic gesture controls.
class RealMapTileWidget extends StatefulWidget {
  const RealMapTileWidget({
    super.key,
    required this.delivery,
    this.driverCoord,
    this.vehicleEmoji = '🛵',
    this.progress = 0.35,
    this.is3D = false,
    this.interactive = true,
    this.showFollowMarker = true,
    this.showOverlays = true,
    this.initialZoom = 15,
    this.onProgressChanged,
    this.height,
  });

  final DeliveryModel delivery;
  final GeoCoord? driverCoord;
  final String vehicleEmoji;
  final double progress;
  final bool is3D;
  final bool interactive;
  final bool showFollowMarker;
  final bool showOverlays;
  final int initialZoom;
  final ValueChanged<double>? onProgressChanged;
  final double? height;

  @override
  State<RealMapTileWidget> createState() => _RealMapTileWidgetState();
}

class _RealMapTileWidgetState extends State<RealMapTileWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late int _zoom;
  Offset _panOffset = Offset.zero;
  RealMapLayer _activeLayer = RealMapLayer.dark;

  late GeoCoord _destinationCoord;
  late GeoCoord _driverCoord;
  late List<NavManeuver> _maneuvers;
  bool _isLiveGps = false;

  @override
  void initState() {
    super.initState();
    _resolveCoordinates();
    _zoom = _calculateFittingZoom(_driverCoord, _destinationCoord);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    DriverLocationService.instance.locationNotifier.addListener(_onDriverLocationUpdated);
  }

  int _calculateFittingZoom(GeoCoord c1, GeoCoord c2) {
    final distKm = DeliveryGeocoding.haversineDistanceKm(c1, c2);
    if (distKm <= 0.8) return 16;
    if (distKm <= 2.2) return 15;
    if (distKm <= 5.5) return 14;
    if (distKm <= 12.0) return 13;
    if (distKm <= 26.0) return 12;
    if (distKm <= 55.0) return 11;
    return 10;
  }

  void _onDriverLocationUpdated() {
    if (widget.driverCoord == null && mounted) {
      final updated = DriverLocationService.instance.effectiveCoord;
      if ((updated.lat - _driverCoord.lat).abs() > 0.00005 ||
          (updated.lng - _driverCoord.lng).abs() > 0.00005 ||
          _isLiveGps != DriverLocationService.instance.hasLiveGps) {
        setState(() {
          _resolveCoordinates();
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant RealMapTileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delivery.id != widget.delivery.id ||
        oldWidget.delivery.address != widget.delivery.address ||
        oldWidget.driverCoord?.lat != widget.driverCoord?.lat ||
        oldWidget.driverCoord?.lng != widget.driverCoord?.lng) {
      _resolveCoordinates();
    }
  }

  void _resolveCoordinates() {
    _driverCoord = widget.driverCoord ?? DriverLocationService.instance.effectiveCoord;
    _isLiveGps = widget.driverCoord != null || DriverLocationService.instance.hasLiveGps;
    _destinationCoord = DeliveryGeocoding.resolveDestination(widget.delivery);
    _maneuvers = DeliveryGeocoding.buildTripManeuvers(
      delivery: widget.delivery,
      origin: _driverCoord,
      destination: _destinationCoord,
    );
  }

  @override
  void dispose() {
    DriverLocationService.instance.locationNotifier.removeListener(_onDriverLocationUpdated);
    _pulseController.dispose();
    super.dispose();
  }

  // Slippy Map Math: convert (lat, lng) to world pixel point at zoom z
  Offset _coordToWorldPixels(GeoCoord coord, int zoom) {
    final n = math.pow(2.0, zoom).toDouble();
    final worldSize = n * 256.0;

    final x = (coord.lng + 180.0) / 360.0 * worldSize;
    final latRad = coord.lat * math.pi / 180.0;
    final y = (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
        2.0 *
        worldSize;

    return Offset(x, y);
  }

  String _getTileUrl(int z, int x, int y, RealMapLayer layer) {
    switch (layer) {
      case RealMapLayer.dark:
        return 'https://a.basemaps.cartocdn.com/rastertiles/dark_all/$z/$x/$y.png';
      case RealMapLayer.street:
        return 'https://a.basemaps.cartocdn.com/rastertiles/voyager/$z/$x/$y.png';
      case RealMapLayer.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$z/$y/$x';
    }
  }

  void _recenter() {
    setState(() {
      _zoom = _calculateFittingZoom(_driverCoord, _destinationCoord);
      _panOffset = Offset.zero;
    });
  }

  void _snapToDriver() {
    final centerCoord = GeoCoord(
      (_driverCoord.lat + _destinationCoord.lat) / 2.0,
      (_driverCoord.lng + _destinationCoord.lng) / 2.0,
    );
    setState(() {
      _zoom = 15;
      final centerPixels = _coordToWorldPixels(centerCoord, 15);
      final driverPixels = _coordToWorldPixels(_driverCoord, 15);
      _panOffset = Offset(centerPixels.dx - driverPixels.dx, centerPixels.dy - driverPixels.dy);
    });
  }

  void _snapToDestination() {
    final centerCoord = GeoCoord(
      (_driverCoord.lat + _destinationCoord.lat) / 2.0,
      (_driverCoord.lng + _destinationCoord.lng) / 2.0,
    );
    setState(() {
      _zoom = 15;
      final centerPixels = _coordToWorldPixels(centerCoord, 15);
      final destPixels = _coordToWorldPixels(_destinationCoord, 15);
      _panOffset = Offset(centerPixels.dx - destPixels.dx, centerPixels.dy - destPixels.dy);
    });
  }

  void _zoomIn() {
    if (_zoom < 17) {
      setState(() => _zoom++);
    }
  }

  void _zoomOut() {
    if (_zoom > 12) {
      setState(() => _zoom--);
    }
  }

  void _cycleLayer() {
    setState(() {
      final nextIdx = (_activeLayer.index + 1) % RealMapLayer.values.length;
      _activeLayer = RealMapLayer.values[nextIdx];
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        final viewportHeight = widget.height ??
            (constraints.maxHeight.isFinite ? constraints.maxHeight : 320.0);

        final viewportSize = Size(viewportWidth, viewportHeight);

        // Center map midway between driver and destination
        final centerLat = (_driverCoord.lat + _destinationCoord.lat) / 2.0;
        final centerLng = (_driverCoord.lng + _destinationCoord.lng) / 2.0;
        final centerCoord = GeoCoord(centerLat, centerLng);

        final centerPixels = _coordToWorldPixels(centerCoord, _zoom);

        final minWorldX = centerPixels.dx - (viewportSize.width / 2) - _panOffset.dx;
        final minWorldY = centerPixels.dy - (viewportSize.height / 2) - _panOffset.dy;

        final numTiles = 1 << _zoom;
        final startTileX = (minWorldX / 256.0).floor();
        final endTileX = ((minWorldX + viewportSize.width) / 256.0).floor();
        final startTileY = (minWorldY / 256.0).floor().clamp(0, numTiles - 1);
        final endTileY = ((minWorldY + viewportSize.height) / 256.0).floor().clamp(0, numTiles - 1);

        final tiles = <Widget>[];
        for (int ty = startTileY; ty <= endTileY; ty++) {
          for (int tx = startTileX; tx <= endTileX; tx++) {
            final wrappedTx = ((tx % numTiles) + numTiles) % numTiles;
            final tileUrl = _getTileUrl(_zoom, wrappedTx, ty, _activeLayer);
            final left = tx * 256.0 - minWorldX;
            final top = ty * 256.0 - minWorldY;

            Widget tileWidget = Image.network(
              tileUrl,
              fit: BoxFit.cover,
              headers: const {'User-Agent': 'PIE-Restaurant-POS/1.0'},
              errorBuilder: (context, error, stackTrace) {
                // Safe offline / test fallback grid
                return Container(
                  decoration: BoxDecoration(
                    color: _activeLayer == RealMapLayer.street
                        ? const Color(0xFFF1F5F9)
                        : const Color(0xFF0A0F1D),
                    border: Border.all(
                      color: _activeLayer == RealMapLayer.street
                          ? const Color(0xFFCBD5E1).withValues(alpha: 0.3)
                          : const Color(0xFF1E293B).withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                );
              },
            );

            tiles.add(
              Positioned(
                left: left,
                top: top,
                width: 256,
                height: 256,
                child: tileWidget,
              ),
            );
          }
        }

        // Project route maneuvers into screen space
        final screenPoints = _maneuvers.map((m) {
          final wp = _coordToWorldPixels(m.coord, _zoom);
          return Offset(wp.dx - minWorldX, wp.dy - minWorldY);
        }).toList();

        // Calculate Courier screen position based on progress
        final t = widget.progress.clamp(0.0, 1.0);
        Offset courierScreenPos = screenPoints.first;
        double headingAngle = 0.0;
        if (screenPoints.length >= 2) {
          final totalSegs = screenPoints.length - 1;
          final scaledT = t * totalSegs;
          final curIdx = scaledT.floor().clamp(0, totalSegs - 1);
          final segT = (scaledT - curIdx).clamp(0.0, 1.0);

          final pA = screenPoints[curIdx];
          final pB = screenPoints[curIdx + 1];
          courierScreenPos = Offset.lerp(pA, pB, segT)!;
          headingAngle = math.atan2(pB.dy - pA.dy, pB.dx - pA.dx);
        }

        final mapContent = Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // 1. Real Map Tiles Background
            ...tiles,

            // 2. Real Route & Markers Vector Overlay
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final isFromBranch = (_driverCoord.lat - DeliveryGeocoding.defaultBranch.lat).abs() < 0.0001 &&
                    (_driverCoord.lng - DeliveryGeocoding.defaultBranch.lng).abs() < 0.0001;

                return CustomPaint(
                  size: viewportSize,
                  painter: _RealMapOverlayPainter(
                    screenPoints: screenPoints,
                    courierPos: courierScreenPos,
                    headingAngle: headingAngle,
                    pulseValue: _pulseController.value,
                    vehicleEmoji: widget.vehicleEmoji,
                    orderRef: widget.delivery.orderRef,
                    clientAddress: widget.delivery.address,
                    isDark: _activeLayer != RealMapLayer.street,
                    isFromBranch: isFromBranch,
                  ),
                );
              },
            ),
          ],
        );

        Widget interactiveMap = mapContent;
        if (widget.is3D) {
          interactiveMap = Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(-0.42),
            alignment: Alignment.bottomCenter,
            child: mapContent,
          );
        }

        if (widget.interactive) {
          interactiveMap = GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _panOffset += details.delta;
              });
            },
            onDoubleTap: _zoomIn,
            child: interactiveMap,
          );
        }

        return Container(
          height: widget.height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF090D16),
            borderRadius: PieRadius.borderLg,
            border: Border.all(color: PieColors.border, width: 1.2),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: interactiveMap),

              // Top Map Layer & Status Badge
              if (widget.showOverlays)
                Positioned(
                  top: 10,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: PieColors.surfaceOverlay.withValues(alpha: 0.9),
                      borderRadius: PieRadius.borderSm,
                      border: Border.all(color: PieColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isLiveGps ? Icons.satellite_alt_rounded : Icons.public_rounded,
                          size: 14,
                          color: _isLiveGps ? const Color(0xFF38BDF8) : const Color(0xFF4ADE80),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isLiveGps
                              ? '🛰️ موقع السائق المباشر • ${_activeLayer.label}'
                              : 'خريطة جغرافية حقيقية • ${_activeLayer.label}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: PieColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Interactive Floating Controls (Left Bar)
              if (widget.interactive && widget.showOverlays)
                Positioned(
                  top: 10,
                  left: 12,
                  child: Column(
                    children: [
                      // Layer Switcher Button
                      _buildMapCircleBtn(
                        icon: Icons.layers_rounded,
                        tooltip: 'تغيير نوع الخريطة (${_activeLayer.label})',
                        onTap: _cycleLayer,
                        color: PieColors.driverAccent,
                      ),
                      const SizedBox(height: 8),
                      // Snap to Driver Button (موقعي)
                      _buildMapCircleBtn(
                        icon: Icons.near_me_rounded,
                        tooltip: 'موقعي الحالي 🛵',
                        onTap: _snapToDriver,
                        color: const Color(0xFF38BDF8),
                      ),
                      const SizedBox(height: 8),
                      // Snap to Destination Button (العميل)
                      _buildMapCircleBtn(
                        icon: Icons.location_on_rounded,
                        tooltip: 'موقع العميل 📍',
                        onTap: _snapToDestination,
                        color: const Color(0xFFEF4444),
                      ),
                      const SizedBox(height: 8),
                      // Recenter Button (كامل المسار)
                      _buildMapCircleBtn(
                        icon: Icons.fit_screen_rounded,
                        tooltip: 'كامل المسار (السائق والعميل)',
                        onTap: _recenter,
                      ),
                      const SizedBox(height: 8),
                      // Zoom In
                      _buildMapCircleBtn(
                        icon: Icons.add_rounded,
                        tooltip: 'تكبير (+)',
                        onTap: _zoomIn,
                      ),
                      const SizedBox(height: 6),
                      // Zoom Out
                      _buildMapCircleBtn(
                        icon: Icons.remove_rounded,
                        tooltip: 'تصغير (-)',
                        onTap: _zoomOut,
                      ),
                    ],
                  ),
                ),

              // Destination Chip Badge (Bottom Right)
              if (widget.showOverlays)
                Positioned(
                bottom: 10,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                    borderRadius: PieRadius.borderMd,
                    border: Border.all(color: PieColors.driverBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFFEF4444)),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          widget.delivery.address,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapCircleBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: PieColors.surfaceOverlay.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: PieColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, size: 18, color: color ?? PieColors.ink),
        ),
      ),
    );
  }
}

/// Custom painter for the route line, courier beacon, and pins overlaying real map tiles
class _RealMapOverlayPainter extends CustomPainter {
  _RealMapOverlayPainter({
    required this.screenPoints,
    required this.courierPos,
    required this.headingAngle,
    required this.pulseValue,
    required this.vehicleEmoji,
    required this.orderRef,
    required this.clientAddress,
    required this.isDark,
    required this.isFromBranch,
  });

  final List<Offset> screenPoints;
  final Offset courierPos;
  final double headingAngle;
  final double pulseValue;
  final String vehicleEmoji;
  final String orderRef;
  final String clientAddress;
  final bool isDark;
  final bool isFromBranch;

  @override
  void paint(Canvas canvas, Size size) {
    if (screenPoints.length < 2) return;

    // 1. Draw glowing Route Polyline
    final routePath = Path();
    routePath.moveTo(screenPoints.first.dx, screenPoints.first.dy);
    for (int i = 1; i < screenPoints.length; i++) {
      routePath.lineTo(screenPoints[i].dx, screenPoints[i].dy);
    }

    // Outer neon glow
    final glowPaint = Paint()
      ..color = PieColors.driverAccent.withValues(alpha: isDark ? 0.45 : 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(routePath, glowPaint);

    // Core route line
    final corePaint = Paint()
      ..color = PieColors.driverAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(routePath, corePaint);

    // 2. Draw Origin Pin (🏬 or 🏁)
    final originPos = screenPoints.first;
    if (isFromBranch) {
      canvas.drawCircle(originPos, 10, Paint()..color = const Color(0xFF0284C7));
      canvas.drawCircle(originPos, 4, Paint()..color = Colors.white);
      _drawBadge(canvas, 'الفرع 🏬', originPos + const Offset(-20, -22), const Color(0xFF0369A1));
    } else {
      canvas.drawCircle(originPos, 10, Paint()..color = const Color(0xFF0284C7));
      canvas.drawCircle(originPos, 4, Paint()..color = Colors.white);
      _drawBadge(canvas, 'نقطة الانطلاق 🏁', originPos + const Offset(-25, -22), const Color(0xFF0284C7));
    }

    // 3. Draw Destination Pin (📍)
    final destPos = screenPoints.last;
    canvas.drawCircle(destPos, 12, Paint()..color = const Color(0xFFEF4444));
    canvas.drawCircle(destPos, 5, Paint()..color = Colors.white);
    final street = DeliveryGeocoding.extractStreetName(clientAddress);
    _drawBadge(canvas, 'موقع العميل: $street 📍', destPos + const Offset(-45, -24), const Color(0xFFDC2626));

    // 4. Draw Waypoint nodes along the route
    for (int i = 1; i < screenPoints.length - 1; i++) {
      canvas.drawCircle(screenPoints[i], 4, Paint()..color = PieColors.driverAccent);
      canvas.drawCircle(screenPoints[i], 2, Paint()..color = Colors.white);
    }

    // 5. Draw Animated Radar Pulse around Courier
    final radarPaint = Paint()
      ..color = PieColors.driverAccent.withValues(alpha: (1.0 - pulseValue) * 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(courierPos, 14 + (pulseValue * 22), radarPaint);

    // 6. Draw Directional Courier Chevron & Vehicle
    canvas.save();
    canvas.translate(courierPos.dx, courierPos.dy);
    canvas.rotate(headingAngle);

    final chevronPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final chevronPath = Path()
      ..moveTo(16, 0)
      ..lineTo(7, -6)
      ..lineTo(10, 0)
      ..lineTo(7, 6)
      ..close();
    canvas.drawPath(chevronPath, chevronPaint);

    // Vehicle background disc
    canvas.drawCircle(Offset.zero, 15, Paint()..color = const Color(0xFF0F172A));
    canvas.drawCircle(
      Offset.zero,
      15,
      Paint()
        ..color = PieColors.driverAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    canvas.restore();

    // Draw Vehicle Emoji unrotated for legibility
    _drawEmoji(canvas, vehicleEmoji, courierPos);
  }

  void _drawBadge(Canvas canvas, String text, Offset position, Color bgColor) {
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        fontFamily: 'IBMPlexSansArabic',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.rtl,
    )..layout();

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(position.dx - 6, position.dy - 3, textPainter.width + 12, textPainter.height + 6),
      const Radius.circular(6),
    );
    canvas.drawRRect(badgeRect, Paint()..color = bgColor);
    textPainter.paint(canvas, position);
  }

  void _drawEmoji(Canvas canvas, String emoji, Offset position) {
    final textSpan = TextSpan(
      text: emoji,
      style: const TextStyle(fontSize: 15),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, position - Offset(textPainter.width / 2, textPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RealMapOverlayPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
        oldDelegate.headingAngle != headingAngle ||
        oldDelegate.courierPos != courierPos ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isFromBranch != isFromBranch ||
        oldDelegate.clientAddress != clientAddress;
  }
}
