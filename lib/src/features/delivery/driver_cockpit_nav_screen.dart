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
import '../../core/state/sync_monitor.dart';
import '../../core/widgets/pie_toast.dart';
import 'driver_custody_collection_dialog.dart';
import 'driver_fail_dialog.dart';
import 'driver_identity_service.dart';
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

class _DriverCockpitNavScreenState extends State<DriverCockpitNavScreen> {
  bool _is3D = false;
  RealMapLayer _activeLayer = RealMapLayer.dark;
  bool _soundEnabled = true;
  bool _hasArrived = false;
  bool _isCompleting = false;
  bool _dismissedDueToStatusChange = false;
  int _lastManeuverIndex = 0;
  final GlobalKey<RealMapTileWidgetState> _mapKey = GlobalKey<RealMapTileWidgetState>();
  bool _hasInitialGpsFix = false;
  GeoCoord? _lastRoutedCoord;

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
    _lastRoutedCoord = _driverCoord;
    _recalculateRoute();

    // Request location permissions and query hardware GPS
    DriverLocationService.instance.checkAndRequestPermission().then((status) {
      if (status == LocationServiceStatus.active || status == LocationServiceStatus.acquiring) {
        DriverLocationService.instance.getCurrentLocation().then((loc) {
          if (mounted) {
            setState(() {
              _driverCoord = loc.coord;
              _lastRoutedCoord = loc.coord;
              _recalculateRoute();
            });
            _mapKey.currentState?.snapToDriver();
          }
        });
      }
    });

    // Start live tracking updates
    DriverLocationService.instance.startTracking();
    DriverLocationService.instance.locationNotifier.addListener(_onLocationUpdate);

    // Listen to real-time changes to handle mid-trip cancellation or driver reassignment
    SyncMonitor.instance.addListener(_onSyncRefresh);
  }

  void _onSyncRefresh() async {
    if (!mounted || _dismissedDueToStatusChange) return;
    final services = AppScope.of(context);
    final deliveryRepo = services.deliveries;
    if (deliveryRepo == null) return;

    final updated = await deliveryRepo.getDelivery(widget.delivery.id);
    if (!mounted || _dismissedDueToStatusChange) return;

    if (updated == null) {
      _dismissedDueToStatusChange = true;
      PieSoundService.instance.beep();
      PieToast.show(context, 'تم حذف الطلب من قائمة الدليفري', isError: true);
      Navigator.of(context).pop();
      return;
    }

    if (updated.state == DeliveryState.failed || updated.state == DeliveryState.returned) {
      _dismissedDueToStatusChange = true;
      PieSoundService.instance.beep();
      final reason = updated.failedReason?.label ?? 'تم إلغاء الطلب من الإدارة';
      PieToast.show(context, 'تنبيه: تم إلغاء مسار الطلب ($reason)', isError: true);
      Navigator.of(context).pop();
      return;
    }

    final drivers = await deliveryRepo.listDrivers();
    if (!mounted || _dismissedDueToStatusChange) return;
    final isStillMine = DriverSession.instance.isDeliveryAssignedToCurrentDriver(
      delivery: updated,
      user: services.auth.currentUser,
      drivers: drivers,
    );
    if (!isStillMine) {
      _dismissedDueToStatusChange = true;
      PieSoundService.instance.beep();
      PieToast.show(context, 'تنبيه: تمت إعادة إسناد الطلب لكابتن آخر (${updated.driver})', isError: true);
      Navigator.of(context).pop();
      return;
    }
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
    if (mounted) {
      final loc = DriverLocationService.instance.lastKnownLocation;
      if (loc != null) {
        // Auto-center map upon receiving first live GPS lock
        if (!_hasInitialGpsFix && loc.isLiveGps) {
          _hasInitialGpsFix = true;
          _mapKey.currentState?.snapToDriver();
        }

        final distFromLastMeters = _lastRoutedCoord != null
            ? DeliveryGeocoding.haversineDistanceKm(_lastRoutedCoord!, loc.coord) * 1000.0
            : 999.0;

        final distToDestMeters = (DeliveryGeocoding.haversineDistanceKm(loc.coord, _destCoord) * 1000.0).round();
        if (!_hasArrived && distToDestMeters <= 45) {
          _hasArrived = true;
          if (_soundEnabled) {
            PieSoundService.instance.chime();
          }
          PieToast.show(context, '🎉 وصلت إلى موقع العميل بالسلامة!', isSuccess: true);
        }

        // Dynamic rerouting: recalculate route when courier moves > 60 meters
        if (distFromLastMeters > 60.0 ||
            ((loc.coord.lat - _driverCoord.lat).abs() > 0.0001 ||
             (loc.coord.lng - _driverCoord.lng).abs() > 0.0001)) {
          _lastRoutedCoord = loc.coord;
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
    SyncMonitor.instance.removeListener(_onSyncRefresh);
    DriverLocationService.instance.locationNotifier.removeListener(_onLocationUpdate);
    DriverLocationService.instance.stopTracking();
    super.dispose();
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
    final loc = DriverLocationService.instance.lastKnownLocation;
    final int currentSpeed = loc != null && loc.speed > 0 ? loc.speed.round() : 0;
    final distToDestMeters = (DeliveryGeocoding.haversineDistanceKm(_driverCoord, _destCoord) * 1000.0).round();

    // Real progress and telemetry
    final initialTripMeters = math.max(1, _totalMeters);
    final metersRemaining = _hasArrived ? 0 : distToDestMeters;
    final minutesRemaining = _hasArrived
        ? 0
        : (_totalMeters > 0 && metersRemaining > 0
            ? math.max(1, ((metersRemaining / _totalMeters) * _totalEtaMinutes).round())
            : DeliveryGeocoding.estimateEtaMinutes(
                metersRemaining / 1000.0,
                vehicle: widget.initialVehicle,
              ));
    final realProgress = (1.0 - (metersRemaining / initialTripMeters)).clamp(0.0, 1.0);

    // Dynamic Turn-by-Turn Instruction based on live GPS and road maneuvers
    final IconData turnIcon;
    final String instruction;
    final String nextTurn;

    if (_hasArrived || distToDestMeters <= 45) {
      final m = _maneuvers.isNotEmpty ? _maneuvers.last : null;
      turnIcon = m?.icon ?? Icons.check_circle_rounded;
      instruction = 'وصلت إلى موقع العميل بالسلامة! 🏁';
      nextTurn = widget.delivery.landmark?.isNotEmpty == true
          ? 'علامة: ${widget.delivery.landmark}'
          : widget.delivery.address;
    } else if (_maneuvers.isEmpty) {
      turnIcon = Icons.navigation_rounded;
      instruction = 'واصل السير نحو ${DeliveryGeocoding.extractStreetName(widget.delivery.address)}';
      nextTurn = widget.delivery.address;
    } else {
      // Find the closest upcoming maneuver along the route
      int bestIdx = 0;
      double minManeuverDist = double.infinity;
      for (int i = 0; i < _maneuvers.length; i++) {
        final d = DeliveryGeocoding.haversineDistanceKm(_driverCoord, _maneuvers[i].coord) * 1000.0;
        if (d < minManeuverDist) {
          minManeuverDist = d;
          bestIdx = i;
        }
      }

      if (bestIdx != _lastManeuverIndex) {
        _lastManeuverIndex = bestIdx;
        if (_soundEnabled) {
          PieSoundService.instance.click();
        }
      }

      final m = _maneuvers[bestIdx];
      turnIcon = m.icon;
      instruction = m.instruction;
      if (bestIdx + 1 < _maneuvers.length) {
        nextTurn = _maneuvers[bestIdx + 1].instruction;
      } else {
        nextTurn = 'اقتربت من الوجهة: ${DeliveryGeocoding.extractStreetName(widget.delivery.address)}';
      }
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
                  mapKey: _mapKey,
                  delivery: widget.delivery,
                  driverCoord: _driverCoord,
                  vehicleEmoji: vehicleEmoji,
                  progress: realProgress,
                  is3D: _is3D,
                  interactive: true,
                  showOverlays: false,
                  activeLayer: _activeLayer,
                  onLayerChanged: (l) => setState(() => _activeLayer = l),
                  onRouteCalculated: (route) {
                    if (mounted && route.points.isNotEmpty) {
                      setState(() {
                        _totalMeters = route.distanceMeters;
                        _totalRoadDistanceKm = route.distanceKm;
                        _totalEtaMinutes = route.durationMinutes;
                        if (route.maneuvers.isNotEmpty) {
                          _maneuvers = route.maneuvers;
                        }
                      });
                    }
                  },
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
                                    ValueListenableBuilder<LocationServiceStatus>(
                                      valueListenable: DriverLocationService.instance.statusNotifier,
                                      builder: (context, status, _) {
                                        final bool isLive = status == LocationServiceStatus.active &&
                                            DriverLocationService.instance.hasLiveGps;
                                        final bool isDenied = status == LocationServiceStatus.permissionDenied ||
                                            status == LocationServiceStatus.permissionDeniedForever;
                                        final bool isDisabled = status == LocationServiceStatus.serviceDisabled;

                                        final Color badgeBg = isLive
                                            ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                                            : (isDenied || isDisabled)
                                                ? const Color(0xFFDC2626).withValues(alpha: 0.2)
                                                : const Color(0xFFD97706).withValues(alpha: 0.2);

                                        final Color badgeBorder = isLive
                                            ? const Color(0xFF38BDF8)
                                            : (isDenied || isDisabled)
                                                ? const Color(0xFFEF4444)
                                                : const Color(0xFFF59E0B);

                                        final String badgeText = isLive
                                            ? '🛰️ GPS متصل'
                                            : isDisabled
                                                ? '⚠️ GPS مغلق'
                                                : isDenied
                                                    ? '⚠️ إذن الموقع مطلوب'
                                                    : '📡 جاري التحديد';

                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: badgeBg,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: badgeBorder, width: 0.6),
                                          ),
                                          child: Text(
                                            badgeText,
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: badgeBorder,
                                            ),
                                          ),
                                        );
                                      },
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
                          value: realProgress.clamp(0.0, 1.0),
                          backgroundColor: const Color(0xFF1E293B),
                          valueColor: const AlwaysStoppedAnimation<Color>(PieColors.driverAccent),
                          minHeight: 4,
                        ),
                      ),

                      // Interactive Location Permission & GPS Diagnostics Banner
                      ValueListenableBuilder<LocationServiceStatus>(
                        valueListenable: DriverLocationService.instance.statusNotifier,
                        builder: (context, status, _) {
                          if (status == LocationServiceStatus.active ||
                              status == LocationServiceStatus.unknown) {
                            return const SizedBox.shrink();
                          }

                          final String bannerTitle;
                          final String bannerBtn;
                          final IconData bannerIcon;
                          final Color bannerBg;
                          final Color bannerBorderColor;
                          final VoidCallback onBannerAction;

                          if (status == LocationServiceStatus.serviceDisabled) {
                            bannerTitle = 'خدمة الموقع (GPS) مغلقة على الهاتف';
                            bannerBtn = 'تفعيل GPS 🧭';
                            bannerIcon = Icons.location_off_rounded;
                            bannerBg = const Color(0xFF7F1D1D).withValues(alpha: 0.95);
                            bannerBorderColor = const Color(0xFFEF4444);
                            onBannerAction = () async {
                              await DriverLocationService.instance.openLocationSettings();
                              await DriverLocationService.instance.checkAndRequestPermission();
                            };
                          } else if (status == LocationServiceStatus.permissionDenied) {
                            bannerTitle = 'التطبيق بحاجة لإذن الموقع لتتبع المسار';
                            bannerBtn = 'منح الإذن 📍';
                            bannerIcon = Icons.security_rounded;
                            bannerBg = const Color(0xFF78350F).withValues(alpha: 0.95);
                            bannerBorderColor = const Color(0xFFF59E0B);
                            onBannerAction = () async {
                              final res = await DriverLocationService.instance
                                  .checkAndRequestPermission(requestIfNotGranted: true);
                              if (res == LocationServiceStatus.active ||
                                  res == LocationServiceStatus.acquiring) {
                                final loc = await DriverLocationService.instance.getCurrentLocation();
                                if (mounted) {
                                  setState(() {
                                    _driverCoord = loc.coord;
                                    _lastRoutedCoord = loc.coord;
                                    _recalculateRoute();
                                  });
                                  _mapKey.currentState?.snapToDriver();
                                }
                              }
                            };
                          } else if (status == LocationServiceStatus.permissionDeniedForever) {
                            bannerTitle = 'إذن الموقع مرفوض دائماً بالنظام';
                            bannerBtn = 'إعدادات التطبيق ⚙️';
                            bannerIcon = Icons.settings_suggest_rounded;
                            bannerBg = const Color(0xFF7F1D1D).withValues(alpha: 0.95);
                            bannerBorderColor = const Color(0xFFEF4444);
                            onBannerAction = () async {
                              await DriverLocationService.instance.openAppSettings();
                            };
                          } else {
                            // acquiring
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF38BDF8),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'جاري التقاط إشارة الأقمار الصناعية (GPS)... 🛰️',
                                    style: TextStyle(
                                      fontFamily: 'IBMPlexSansArabic',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF38BDF8).withValues(alpha: 0.95),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: bannerBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: bannerBorderColor, width: 1),
                            ),
                            child: Row(
                              children: [
                                Icon(bannerIcon, color: Colors.white, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    bannerTitle,
                                    style: const TextStyle(
                                      fontFamily: 'IBMPlexSansArabic',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: onBannerAction,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      bannerBtn,
                                      style: const TextStyle(
                                        fontFamily: 'IBMPlexSansArabic',
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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

                    // Snap to Driver / Current Location
                    Tooltip(
                      message: 'إعادة التمركز على موقعي 🛵',
                      child: InkWell(
                        onTap: () {
                          _mapKey.currentState?.snapToDriver();
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
                            border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
                          ),
                          child: const Icon(Icons.my_location_rounded, size: 18, color: Color(0xFF38BDF8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Recenter Full Route
                    Tooltip(
                      message: 'كامل المسار (السائق والوجهة) 🗺️',
                      child: InkWell(
                        onTap: () {
                          _mapKey.currentState?.recenter();
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                            borderRadius: PieRadius.borderMd,
                            border: Border.all(color: PieColors.border),
                          ),
                          child: const Icon(Icons.fit_screen_rounded, size: 18, color: Colors.white70),
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
