import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/delivery.dart';
import '../../domain/navigation/delivery_geocoding.dart';
import '../../domain/navigation/driver_location_service.dart';
import '../../core/widgets/pie_toast.dart';
import 'driver_custody_collection_dialog.dart';
import 'driver_fail_dialog.dart';
import 'widgets/driver_nav_map_canvas.dart';
import 'widgets/real_map_tile_widget.dart';

/// Screen: Driver In-App Navigation Cockpit (شاشة الملاحة المباشرة بالخريطة الحقيقية)
///
/// Provides a high-fidelity, real-time in-app GPS navigation HUD with:
/// - Real Geographic Slippy Map Tile engine with 3D/2D perspective toggle
/// - Dynamic context-aware Turn-by-Turn instructions based on real address
/// - Telemetry HUD (speedometer, real ETA, real distance countdown, GPS lock)
/// - Trip simulation & interactive progress controls
/// - One-tap direct Google Maps Turn-by-Turn GPS & Waze live navigation
/// - Quick customer dialing & WhatsApp
/// - Direct Cash-on-Delivery collection settlement & delivery confirmation
class DriverCockpitNavScreen extends StatefulWidget {
  const DriverCockpitNavScreen({
    super.key,
    required this.delivery,
    this.initialVehicle = 'موتوسيكل 🛵',
  });

  final DeliveryModel delivery;
  final String initialVehicle;

  static Future<void> push(
    BuildContext context, {
    required DeliveryModel delivery,
    String initialVehicle = 'موتوسيكل 🛵',
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverCockpitNavScreen(
          delivery: delivery,
          initialVehicle: initialVehicle,
        ),
      ),
    );
  }

  @override
  State<DriverCockpitNavScreen> createState() => _DriverCockpitNavScreenState();
}

class _DriverCockpitNavScreenState extends State<DriverCockpitNavScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _simController;
  bool _isSimulating = false;
  bool _is3D = false;
  RealMapLayer _activeLayer = RealMapLayer.dark;
  bool _soundEnabled = true;
  bool _hasArrived = false;
  bool _isCompleting = false;
  int _lastManeuverIndex = 0;

  late GeoCoord _driverCoord;
  late GeoCoord _destCoord;
  late double _totalRoadDistanceKm;
  late int _totalMeters;
  late int _totalEtaMinutes;
  late List<NavManeuver> _maneuvers;

  @override
  void initState() {
    super.initState();
    _driverCoord = DriverLocationService.instance.effectiveCoord;
    _destCoord = DeliveryGeocoding.resolveDestination(widget.delivery);
    _recalculateRoute();

    // Query hardware GPS location
    DriverLocationService.instance.getCurrentLocation().then((loc) {
      if (mounted) {
        setState(() {
          _driverCoord = loc.coord;
          _recalculateRoute();
        });
      }
    });

    // Start live tracking updates
    DriverLocationService.instance.startTracking();
    DriverLocationService.instance.locationNotifier.addListener(_onLocationUpdate);

    _simController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    );

    _simController.addListener(() {
      setState(() {});
      _checkManeuverChime(_simController.value);
    });

    _simController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isSimulating = false;
          _hasArrived = true;
        });
        if (_soundEnabled) {
          PieSoundService.instance.chime();
        }
      }
    });
  }

  void _recalculateRoute() {
    _totalRoadDistanceKm = DeliveryGeocoding.estimateRoadDistanceKm(_driverCoord, _destCoord);
    _totalMeters = (_totalRoadDistanceKm * 1000).round();
    _totalEtaMinutes = DeliveryGeocoding.estimateEtaMinutes(
      _totalRoadDistanceKm,
      vehicle: widget.initialVehicle,
    );
    _maneuvers = DeliveryGeocoding.buildTripManeuvers(
      delivery: widget.delivery,
      origin: _driverCoord,
      destination: _destCoord,
    );
  }

  void _onLocationUpdate() {
    if (!_isSimulating && mounted) {
      final loc = DriverLocationService.instance.lastKnownLocation;
      if (loc != null) {
        if ((loc.coord.lat - _driverCoord.lat).abs() > 0.00005 ||
            (loc.coord.lng - _driverCoord.lng).abs() > 0.00005) {
          setState(() {
            _driverCoord = loc.coord;
            _recalculateRoute();
          });
        } else {
          setState(() {});
        }
      }
    }
  }

  @override
  void dispose() {
    DriverLocationService.instance.locationNotifier.removeListener(_onLocationUpdate);
    DriverLocationService.instance.stopTracking();
    _simController.dispose();
    super.dispose();
  }

  void _checkManeuverChime(double progress) {
    final idx = (progress * 5).floor().clamp(0, 5);
    if (idx != _lastManeuverIndex) {
      _lastManeuverIndex = idx;
      if (_soundEnabled) {
        PieSoundService.instance.click();
      }
    }
  }

  void _toggleSimulation() {
    setState(() {
      _isSimulating = !_isSimulating;
      if (_isSimulating) {
        if (_simController.value >= 1.0) _simController.reset();
        _simController.forward();
      } else {
        _simController.stop();
      }
    });
  }

  void _resetSimulation() {
    setState(() {
      _isSimulating = false;
      _hasArrived = false;
      _simController.reset();
    });
  }

  Future<void> _callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      _copyToClipboard(phone, 'رقم العميل');
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    var rawDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (rawDigits.startsWith('0')) {
      rawDigits = '20${rawDigits.substring(1)}';
    } else if (!rawDigits.startsWith('20')) {
      rawDigits = '20$rawDigits';
    }
    final message = Uri.encodeComponent(
      'مرحباً يا فندم، أنا كابتن التوصيل ومعايا أوردر رقم #${widget.delivery.orderRef}. أنا في طريقي لحضرتك الآن.',
    );
    final uri = Uri.parse('https://wa.me/$rawDigits?text=$message');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      _copyToClipboard(phone, 'رقم الواتساب');
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      PieToast.show(
        context,
        'تم نسخ $label إلى الحافظة بنجاح',
        icon: Icons.copy_rounded,
      );
    }
  }

  Future<void> _completeDelivery(AppServices services) async {
    final confirmed = await DriverCustodyCollectionDialog.show(
      context,
      delivery: widget.delivery,
    );
    if (confirmed != true) return;

    setState(() => _isCompleting = true);
    try {
      await services.deliveries?.updateState(widget.delivery.id, DeliveryState.delivered);
      await services.deliveries?.recordCollection(
        deliveryId: widget.delivery.id,
        amount: widget.delivery.amount,
        createdOffline: services.sync?.isOnline != true,
      );
      PieSoundService.instance.chime();
      if (mounted) {
        Navigator.of(context).pop();
        PieToast.show(
          context,
          'تم تأكيد تسليم الأوردر وإيداع مبلغ ${PieTypography.formatEgp(widget.delivery.amount)} في عهدتك بنجاح ✅',
          isSuccess: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCompleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final progress = _simController.value;

    // Dynamic Turn-by-Turn Instruction Calculation based on Progress and Real Geocoding
    final IconData turnIcon;
    final String instruction;
    final String nextTurn;
    final int metersRemaining;
    final int minutesRemaining;
    final int currentSpeed;
    final liveSpeed = DriverLocationService.instance.lastKnownLocation?.speed.round() ?? 0;

    if (progress < 0.12) {
      final m = _maneuvers.first;
      turnIcon = m.icon;
      instruction = m.instruction;
      nextTurn = _maneuvers.length > 1 ? _maneuvers[1].instruction : 'واصل السير نحو الوجهة';
      metersRemaining = _totalMeters;
      minutesRemaining = _totalEtaMinutes;
      currentSpeed = _isSimulating ? 36 : liveSpeed;
    } else if (progress < 0.45) {
      final m = _maneuvers.length > 1 ? _maneuvers[1] : _maneuvers.first;
      turnIcon = m.icon;
      instruction = m.instruction;
      nextTurn = _maneuvers.length > 2 ? _maneuvers[2].instruction : 'واصل السير نحو الوجهة';
      metersRemaining = (_totalMeters * (1.0 - progress)).round();
      minutesRemaining = math.max(1, (_totalEtaMinutes * (1.0 - progress)).round());
      currentSpeed = _isSimulating ? 38 : liveSpeed;
    } else if (progress < 0.75) {
      final m = _maneuvers.length > 2 ? _maneuvers[2] : _maneuvers.first;
      turnIcon = m.icon;
      instruction = m.instruction;
      nextTurn = _maneuvers.length > 3 ? _maneuvers[3].instruction : 'اقتربت من الوجهة';
      metersRemaining = (_totalMeters * (1.0 - progress)).round();
      minutesRemaining = math.max(1, (_totalEtaMinutes * (1.0 - progress)).round());
      currentSpeed = _isSimulating ? 34 : liveSpeed;
    } else if (progress < 0.95) {
      final m = _maneuvers.length > 3 ? _maneuvers[3] : _maneuvers.first;
      turnIcon = m.icon;
      instruction = m.instruction;
      nextTurn = _maneuvers.last.instruction;
      metersRemaining = (_totalMeters * (1.0 - progress)).round();
      minutesRemaining = math.max(1, (_totalEtaMinutes * (1.0 - progress)).round());
      currentSpeed = _isSimulating ? 22 : liveSpeed;
    } else {
      final m = _maneuvers.last;
      turnIcon = m.icon;
      instruction = 'وصلت إلى موقع العميل بالسلامة!';
      nextTurn = widget.delivery.landmark?.isNotEmpty == true
          ? 'علامة: ${widget.delivery.landmark}'
          : widget.delivery.address;
      metersRemaining = 0;
      minutesRemaining = 0;
      currentSpeed = 0;
    }

    final vehicleEmoji = widget.initialVehicle.contains('سكوتر')
        ? '🛴'
        : widget.initialVehicle.contains('دراجة')
            ? '🚲'
            : widget.initialVehicle.contains('سيارة')
                ? '🚗'
                : '🛵';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF090D16),
        body: SafeArea(
          child: Stack(
            children: [
              // 1. Full-screen Real Geographic Interactive Map Tile View
              Positioned.fill(
                child: DriverNavMapCanvas(
                  delivery: widget.delivery,
                  driverCoord: _driverCoord,
                  vehicleEmoji: vehicleEmoji,
                  progress: progress,
                  is3D: _is3D,
                  interactive: true,
                  showOverlays: false,
                  activeLayer: _activeLayer,
                  onLayerChanged: (l) => setState(() => _activeLayer = l),
                ),
              ),

              // 2. Top Turn-by-Turn Maneuver HUD Banner
              Positioned(
                top: 12,
                left: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                    borderRadius: PieRadius.borderLg,
                    border: Border.all(color: PieColors.driverBorder, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          // Large Animated Maneuver Icon
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: PieColors.driverSurface,
                              borderRadius: PieRadius.borderMd,
                              border: Border.all(color: PieColors.driverAccent, width: 1.5),
                            ),
                            child: Icon(turnIcon, size: 28, color: PieColors.driverAccent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  instruction,
                                  style: PieTypography.bodyStrong.copyWith(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: (DriverLocationService.instance.hasLiveGps
                                                ? const Color(0xFF0284C7)
                                                : const Color(0xFFD97706))
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: DriverLocationService.instance.hasLiveGps
                                              ? const Color(0xFF38BDF8)
                                              : const Color(0xFFF59E0B),
                                          width: 0.6,
                                        ),
                                      ),
                                      child: Text(
                                        DriverLocationService.instance.hasLiveGps ? '🛰️ GPS متصل' : '📡 جاري التحديد',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: DriverLocationService.instance.hasLiveGps
                                              ? const Color(0xFF38BDF8)
                                              : const Color(0xFFF59E0B),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        nextTurn,
                                        style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Sound Toggle Button
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: _soundEnabled ? 'كتم الصوت' : 'تشغيل الصوت',
                            icon: Icon(
                              _soundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                              color: _soundEnabled ? PieColors.driverAccent : PieColors.inkMuted,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _soundEnabled = !_soundEnabled),
                          ),
                          // Exit Button
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'إغلاق الملاحة',
                            icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Linear Trip Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          backgroundColor: const Color(0xFF1E293B),
                          valueColor: const AlwaysStoppedAnimation<Color>(PieColors.driverAccent),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Floating Speedometer & Telemetry Badges (Right side)
              Positioned(
                top: 110,
                right: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Speedometer Dial
                    Container(
                      width: 74,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                        borderRadius: PieRadius.borderMd,
                        border: Border.all(color: PieColors.driverBorder),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$currentSpeed',
                            style: PieTypography.monoDisplay.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: currentSpeed > 45 ? const Color(0xFFEF4444) : PieColors.driverAccent,
                            ),
                          ),
                          const Text(
                            'كم/س',
                            style: TextStyle(
                              fontFamily: 'IBMPlexSansArabic',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: PieColors.inkSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.redAccent, width: 0.8),
                            ),
                            child: const Text(
                              'حد 60',
                              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ETA & Distance Remaining
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                        borderRadius: PieRadius.borderMd,
                        border: Border.all(color: PieColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF38BDF8)),
                              const SizedBox(width: 4),
                              Text(
                                '$minutesRemaining دقيقة',
                                style: const TextStyle(
                                  fontFamily: 'IBMPlexSansArabic',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.straighten_rounded, size: 12, color: PieColors.driverAccent),
                              const SizedBox(width: 4),
                              Text(
                                metersRemaining >= 1000
                                    ? '${(metersRemaining / 1000).toStringAsFixed(1)} كم'
                                    : '$metersRemaining م',
                                style: const TextStyle(
                                  fontFamily: 'IBMPlexSansArabic',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: PieColors.inkSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 4. Cockpit Toolset Controls (Left Side)
              Positioned(
                top: 110,
                left: 14,
                child: Column(
                  children: [
                    // 3D / 2D Perspective Toggle Button
                    InkWell(
                      onTap: () => setState(() => _is3D = !_is3D),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _is3D
                              ? PieColors.driverSurface
                              : const Color(0xFF0F172A).withValues(alpha: 0.92),
                          borderRadius: PieRadius.borderMd,
                          border: Border.all(
                            color: _is3D ? PieColors.driverAccent : PieColors.border,
                          ),
                        ),
                        child: Text(
                          _is3D ? '🗺️ 2D' : '📐 3D',
                          style: TextStyle(
                            fontFamily: 'IBMPlexSansArabic',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _is3D ? PieColors.driverAccent : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Map Style Layer Selector Button
                    Tooltip(
                      message: 'نمط الخريطة (${_activeLayer.label})',
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            final nextIdx = (_activeLayer.index + 1) % RealMapLayer.values.length;
                            _activeLayer = RealMapLayer.values[nextIdx];
                          });
                          PieToast.show(context, 'تم تفعيل نمط: ${_activeLayer.label}', isSuccess: true);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                            borderRadius: PieRadius.borderMd,
                            border: Border.all(color: PieColors.border),
                          ),
                          child: Text(
                            _activeLayer.label.split(' ').first,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Simulation Play / Pause / Reset Control
                    InkWell(
                      onTap: _toggleSimulation,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _isSimulating
                              ? const Color(0xFF16A34A).withValues(alpha: 0.25)
                              : const Color(0xFF0F172A).withValues(alpha: 0.92),
                          borderRadius: PieRadius.borderMd,
                          border: Border.all(
                            color: _isSimulating ? const Color(0xFF16A34A) : PieColors.border,
                          ),
                        ),
                        child: Icon(
                          _isSimulating ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 20,
                          color: _isSimulating ? const Color(0xFF16A34A) : Colors.white,
                        ),
                      ),
                    ),
                    if (progress > 0) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _resetSimulation,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                            borderRadius: PieRadius.borderMd,
                            border: Border.all(color: PieColors.border),
                          ),
                          child: const Icon(Icons.restart_alt_rounded, size: 18, color: PieColors.inkSecondary),
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),
                    // Snap to Driver / Current Location
                    Tooltip(
                      message: 'إعادة التمركز على موقعي 🛵',
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _driverCoord = DriverLocationService.instance.effectiveCoord;
                            _recalculateRoute();
                          });
                          PieToast.show(context, 'تم إعادة التمركز على موقعك 🛰️', isSuccess: true);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                            borderRadius: PieRadius.borderMd,
                            border: Border.all(color: PieColors.border),
                          ),
                          child: const Icon(Icons.near_me_rounded, size: 18, color: Color(0xFF38BDF8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 5. Bottom Delivery Controller & Floating Action Tray
              Positioned(
                bottom: 12,
                left: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.96),
                    borderRadius: PieRadius.borderLg,
                    border: Border.all(color: PieColors.driverBorder, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Customer Info & Communication Row
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: PieColors.driverSurface,
                              shape: BoxShape.circle,
                              border: Border.all(color: PieColors.driverAccent),
                            ),
                            child: const Center(
                              child: Icon(Icons.person_pin_rounded, color: PieColors.driverAccent, size: 22),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.delivery.customerName?.isNotEmpty == true
                                      ? widget.delivery.customerName!
                                      : 'عميل أوردر #${widget.delivery.orderRef}',
                                  style: PieTypography.bodyStrong.copyWith(color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.delivery.address,
                                  style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Direct Communication Actions
                          if (widget.delivery.customerPhone != null &&
                              widget.delivery.customerPhone!.isNotEmpty) ...[
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'اتصال هاتفي',
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                foregroundColor: const Color(0xFF10B981),
                              ),
                              icon: const Icon(Icons.call_rounded, size: 18),
                              onPressed: () => _callPhone(widget.delivery.customerPhone!),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'واتساب',
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                foregroundColor: const Color(0xFF25D366),
                              ),
                              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                              onPressed: () => _openWhatsApp(widget.delivery.customerPhone!),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),

                      // High-contrast COD Cash Collection Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: PieColors.driverSurface,
                          borderRadius: PieRadius.borderMd,
                          border: Border.all(color: PieColors.driverBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Row(
                                children: [
                                  Icon(Icons.payments_rounded, color: PieColors.driverAccent, size: 18),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'المطلوب تحصيله كاش عند الباب:',
                                      style: TextStyle(
                                        fontFamily: 'IBMPlexSansArabic',
                                        fontSize: 12,
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
                            PieNumeral.money(
                              widget.delivery.amount,
                              style: PieTypography.monoBody.copyWith(
                                color: PieColors.driverAccent,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Main Delivery Actions
                      Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: PieButton.primary(
                              onPressed: _isCompleting ? null : () => _completeDelivery(services),
                              label: _hasArrived
                                  ? 'تأكيد التسليم'
                                  : 'وصلت للعميل',
                              icon: Icons.check_circle_rounded,
                              accentColor: const Color(0xFF16A34A),
                              height: 46,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: PieButton.secondary(
                              onPressed: () async {
                                final failed = await DriverFailDialog.show(
                                  context,
                                  delivery: widget.delivery,
                                );
                                if (failed == true && context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                              label: 'تعثر ⚠️',
                              height: 46,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
