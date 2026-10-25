import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_grab_handle.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/delivery.dart';
import '../../domain/navigation/delivery_geocoding.dart';
import '../../domain/navigation/delivery_navigation.dart';
import '../../domain/navigation/driver_location_service.dart';
import '../../core/widgets/pie_toast.dart';
import 'driver_cockpit_nav_screen.dart';
import 'driver_custody_collection_dialog.dart';
import 'driver_fail_dialog.dart';
import 'widgets/driver_nav_map_canvas.dart';

/// Screen 10: Driver Navigation Sheet (توصيل وملاحة الدليفري بالخريطة الحقيقية)
///
/// Functional contract:
/// - Real Geographic Slippy Map Tile Preview
/// - Direct Google Maps GPS launch action
/// - Direct Waze navigation launch action
/// - Context-aware next turn guidance card
/// - Huge collection reminder
/// - Arrived / Failed actions
class DriverNavSheet extends StatelessWidget {
  const DriverNavSheet({super.key, required this.delivery});

  final DeliveryModel delivery;

  static Future<void> show(BuildContext context, {required DeliveryModel delivery}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PieColors.surfaceOverlay,
      shape: const RoundedRectangleBorder(borderRadius: PieRadius.topLg),
      builder: (context) => DriverNavSheet(delivery: delivery),
    );
  }

  Future<void> _launchMaps(BuildContext context) async {
    final driverCoord = DriverLocationService.instance.effectiveCoord;
    final dest = DeliveryGeocoding.resolveDestination(delivery);
    final uri = googleMapsTurnByTurnUri(
      origin: driverCoord,
      coord: dest,
      address: delivery.address,
    );
    final launched = await openDeliveryNavigation(uri);
    if (!launched && context.mounted) {
      PieToast.show(context, 'تعذر فتح تطبيق الخرائط الخارجي تلقائياً', isError: true);
    }
  }

  Future<void> _launchWaze(BuildContext context) async {
    final dest = DeliveryGeocoding.resolveDestination(delivery);
    final uri = wazeNavigationUri(coord: dest);
    final launched = await openDeliveryNavigation(uri);
    if (!launched && context.mounted) {
      PieToast.show(context, 'تعذر فتح تطبيق Waze تلقائياً', isError: true);
    }
  }

  void _copyAddress(BuildContext context) {
    Clipboard.setData(ClipboardData(text: delivery.address));
    PieToast.show(context, 'تم نسخ العنوان إلى الحافظة بنجاح', isSuccess: true);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final origin = DriverLocationService.instance.effectiveCoord;
    final dest = DeliveryGeocoding.resolveDestination(delivery);
    final distKm = DeliveryGeocoding.estimateRoadDistanceKm(origin, dest);
    final etaMin = DeliveryGeocoding.estimateEtaMinutes(distKm);
    final maneuvers = DeliveryGeocoding.buildTripManeuvers(
      delivery: delivery,
      origin: origin,
      destination: dest,
    );
    final nextManeuver = maneuvers.length > 1 ? maneuvers[1] : maneuvers.first;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: PieColors.surfaceOverlay,
          borderRadius: PieRadius.topLg,
        ),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PieGrabHandle(margin: EdgeInsets.only(top: 8, bottom: 12)),
              // Top handle & Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.navigation_rounded, color: PieColors.driverAccent, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ملاحة خط السير • أوردر #${delivery.orderRef}',
                            style: PieTypography.heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Destination Address Card & Actions
              PieCard(
                padding: const EdgeInsets.all(14),
                surfaceColor: PieColors.surface2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: PieColors.driverAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            delivery.address,
                            style: PieTypography.bodyStrong,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          tooltip: 'نسخ العنوان',
                          icon: const Icon(Icons.copy_rounded, color: PieColors.inkSecondary, size: 16),
                          onPressed: () => _copyAddress(context),
                        ),
                      ],
                    ),
                    if (delivery.landmark != null && delivery.landmark!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'علامة مميزة: ${delivery.landmark}',
                        style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Live Telemetry row
                    Row(
                      children: [
                        const Icon(Icons.route_rounded, size: 14, color: Color(0xFF4ADE80)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'مسافة الطريق: ${distKm.toStringAsFixed(1)} كم • زمن الوصول: حوالي $etaMin دقيقة',
                            style: PieTypography.caption.copyWith(
                              color: const Color(0xFF4ADE80),
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Prominent Direct Navigation Buttons Row
                    Row(
                      children: [
                        Expanded(
                          child: PieButton.primary(
                            onPressed: () => _launchMaps(context),
                            label: 'فتح في خرائط Google (GPS مباشر)',
                            icon: Icons.map_rounded,
                            accentColor: PieColors.driverAccent,
                            height: 44,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PieButton.secondary(
                            onPressed: () => _launchWaze(context),
                            label: 'Waze مباشر 🧭',
                            icon: Icons.explore_rounded,
                            height: 44,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Real Geographic Map View & Launch Cockpit Button
              Stack(
                children: [
                  DriverNavMapCanvas(
                    delivery: delivery,
                    driverCoord: origin,
                    height: 200,
                    interactive: true,
                    is3D: false,
                  ),
                  Positioned(
                    bottom: 10,
                    right: 12,
                    left: 12,
                    child: PieButton.primary(
                      onPressed: () {
                        Navigator.of(context).pop();
                        DriverCockpitNavScreen.push(context, delivery: delivery);
                      },
                      label: 'بدء الملاحة المباشرة (Cockpit HUD) 🧭',
                      icon: Icons.explore_rounded,
                      accentColor: const Color(0xFF0284C7),
                      height: 40,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Dynamic Next Turn Guidance Card
              PieCard(
                padding: const EdgeInsets.all(14),
                surfaceColor: PieColors.surface1,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: PieColors.driverSurface,
                        borderRadius: PieRadius.borderMd,
                        border: Border.all(color: PieColors.driverBorder),
                      ),
                      child: Icon(
                        nextManeuver.icon,
                        size: 26,
                        color: PieColors.driverAccent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('انعطف يميناً بعد 250 متراً', style: PieTypography.bodyStrong),
                          const SizedBox(height: 2),
                          Text(
                            'باتجاه ${nextManeuver.streetName} - ${delivery.landmark?.isNotEmpty == true ? delivery.landmark! : delivery.address}',
                            style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Huge Collection Reminder
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: PieColors.driverSurface,
                  borderRadius: PieRadius.borderMd,
                  border: Border.all(color: PieColors.driverBorder, width: 1.5),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.payments_rounded, color: PieColors.driverAccent, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'تذكير استلام النقدية (كاش عند الباب):',
                            style: PieTypography.subheading.copyWith(
                              color: PieColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    PieNumeral.money(
                      delivery.amount,
                      style: PieTypography.monoDisplay.copyWith(
                        color: PieColors.driverAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'المبلغ يدخل عهدة الكابتن الشخصية حتى توريده لخزينة الفرع',
                      style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Arrived & Failed action buttons
              Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: PieButton.primary(
                      onPressed: () async {
                        final confirmed = await DriverCustodyCollectionDialog.show(
                          context,
                          delivery: delivery,
                        );
                        if (confirmed != true) return;

                        await services.deliveries?.updateState(delivery.id, DeliveryState.delivered);
                        await services.deliveries?.recordCollection(
                          deliveryId: delivery.id,
                          amount: delivery.amount,
                          createdOffline: services.sync?.isOnline != true,
                        );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          PieToast.show(
                            context,
                            'تم تسليم الأوردر وإيداع مبلغ ${PieTypography.formatEgp(delivery.amount)} في عهدتك بنجاح ✅',
                            isSuccess: true,
                          );
                        }
                      },
                      label: 'تم التسليم واستلام العهدة ✅',
                      accentColor: const Color(0xFF16A34A),
                      height: 48,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: PieButton.secondary(
                      onPressed: () async {
                        final failed = await DriverFailDialog.show(context, delivery: delivery);
                        if (failed == true && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      label: 'تعثر التسليم ⚠️',
                      height: 48,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Local GPS Audit Note
              Center(
                child: Text(
                  'يتم تسجيل إحداثيات وتوقيت التسليم تلقائياً في سجل تدقيق الوردية المحلي.',
                  style: PieTypography.caption.copyWith(color: PieColors.inkMuted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
