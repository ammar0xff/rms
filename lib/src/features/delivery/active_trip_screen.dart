import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/di/app_services.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/delivery.dart';
import '../../domain/navigation/delivery_navigation.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/widgets/pie_toast.dart';
import 'driver_cockpit_nav_screen.dart';
import 'driver_custody_collection_dialog.dart';
import 'driver_fail_dialog.dart';
import 'driver_identity_service.dart';
import 'driver_nav_sheet.dart';
import 'driver_receipt_sheet.dart';

/// Screen 9: Active Trip Screen (قائمة الأوردرات ومسار الطلعة النشطة)
///
/// Functional contract:
/// - Trip header (courier name, total cash custody, active stops)
/// - Four-phase progress indicator
/// - Numbered stops with the current stop expanded
/// - Start-route call to action
/// - Per-stop actions (Call customer, navigate, receipt, deliver, fail)
class ActiveTripScreen extends StatefulWidget {
  const ActiveTripScreen({super.key});

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  String? _expandedStopId;
  bool _initializedActiveDeliveries = false;
  final Set<String> _notifiedDeliveryIds = {};

  @override
  void initState() {
    super.initState();
    SyncMonitor.instance.addListener(_onSyncRefresh);
  }

  @override
  void dispose() {
    SyncMonitor.instance.removeListener(_onSyncRefresh);
    super.dispose();
  }

  void _onSyncRefresh() {
    if (mounted) setState(() {});
  }

  void _showIncomingOrderAlert(BuildContext context, DeliveryModel delivery) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: const RoundedRectangleBorder(
            borderRadius: PieRadius.borderLg,
            side: BorderSide(color: PieColors.driverAccent, width: 2),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.two_wheeler_rounded, color: PieColors.driverAccent, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '🔔 طلب دليفري جديد للمتابعة!',
                  style: TextStyle(
                    fontFamily: 'IBMPlexSansArabic',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: PieColors.driverSurface,
                  borderRadius: PieRadius.borderMd,
                  border: Border.all(color: PieColors.driverBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'أوردر رقم #${delivery.orderRef}',
                        style: const TextStyle(
                          fontFamily: 'IBMPlexSansArabic',
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PieNumeral.money(
                      delivery.amount,
                      style: PieTypography.monoBody.copyWith(
                        color: PieColors.driverAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (delivery.customerName?.isNotEmpty == true) ...[
                Row(
                  children: [
                    const Icon(Icons.person_rounded, size: 16, color: PieColors.inkSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        delivery.customerName!,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFEF4444)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      delivery.address,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('إغلاق', style: TextStyle(color: PieColors.inkSecondary)),
            ),
            PieButton.primary(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                DriverCockpitNavScreen.push(context, delivery: delivery);
              },
              label: 'بدء الملاحة الحية 🧭',
              icon: Icons.navigation_rounded,
              accentColor: PieColors.driverAccent,
              height: 42,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    var cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '20${cleanPhone.substring(1)}';
    } else if (!cleanPhone.startsWith('20') && cleanPhone.length == 10) {
      cleanPhone = '20$cleanPhone';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final deliveryRepo = services.deliveries;

    if (deliveryRepo == null) {
      return const PieEmptyState(
        title: 'نظام الدليفري غير متاح',
        description: 'اتأكد من تهيئة قاعدة البيانات المحلية على الجهاز.',
        icon: Icons.error_outline_rounded,
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<List<dynamic>>(
        future: Future.wait([
          deliveryRepo.listDrivers(),
          deliveryRepo.listDeliveries(),
        ]),
        builder: (context, snapshot) {
          final drivers = (snapshot.data?[0] as List<DriverModel>?) ?? [];
          final allDeliveries = (snapshot.data?[1] as List<DeliveryModel>?) ?? [];
          final myDriverName = DriverSession.instance.resolveCurrentDriverName(
            user: services.auth.currentUser,
            drivers: drivers,
          );

          final myDeliveries = allDeliveries
              .where((d) => DriverSession.instance.isDeliveryAssignedToCurrentDriver(
                    delivery: d,
                    user: services.auth.currentUser,
                    drivers: drivers,
                  ))
              .toList();
          final activeDeliveries = myDeliveries
              .where((d) =>
                  d.state != DeliveryState.delivered &&
                  d.state != DeliveryState.failed)
              .toList();

          if (snapshot.hasData) {
            if (!_initializedActiveDeliveries) {
              _initializedActiveDeliveries = true;
              for (final d in activeDeliveries) {
                _notifiedDeliveryIds.add(d.id);
              }
            } else {
              for (final d in activeDeliveries) {
                if (!_notifiedDeliveryIds.contains(d.id)) {
                  _notifiedDeliveryIds.add(d.id);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      PieSoundService.instance.chime();
                      HapticFeedback.heavyImpact();
                      _showIncomingOrderAlert(context, d);
                    }
                  });
                  break;
                }
              }
            }
          }

          final totalCustody = myDeliveries
              .where((d) =>
                  d.state == DeliveryState.delivered &&
                  d.settlementStatus != SettlementStatus.settled)
              .fold(0.0, (sum, d) => sum + d.amount);

          final refreshWrap = (Widget child) => RefreshIndicator(
            color: PieColors.driverAccent,
            backgroundColor: PieColors.surfaceOverlay,
            onRefresh: () async {
              PieSoundService.instance.click();
              await services.sync?.requestSync();
              if (mounted) setState(() {});
            },
            child: child,
          );

          if (activeDeliveries.isEmpty) {
            return refreshWrap(
              ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _buildTripHeader(myDriverName, activeDeliveries.length, totalCustody),
                  const SizedBox(height: 20),
                  const PieCard(
                    padding: EdgeInsets.all(32),
                    child: PieEmptyState(
                      title: 'مفيش طلعات نشطة دلوقتي',
                      description: 'كل الأوردرات المسندة ليك هتظهر هنا بمجرد تجهيزها من الفرع.',
                      icon: Icons.two_wheeler_outlined,
                    ),
                  ),
                ],
              ),
            );
          }

          // Auto-expand first open stop if none expanded
          _expandedStopId ??= activeDeliveries.first.id;

          final isOnRoute = activeDeliveries.any((d) => d.state == DeliveryState.onRoute);

          return refreshWrap(
            ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                // Trip Header
                _buildTripHeader(myDriverName, activeDeliveries.length, totalCustody),
                const SizedBox(height: 16),

              // Four-phase progress indicator
              _buildFourPhaseProgress(isOnRoute),
              const SizedBox(height: 16),

              // Start Route CTA if not yet on route
              if (!isOnRoute) ...[
                PieButton.primary(
                  onPressed: () async {
                    for (final d in activeDeliveries) {
                      await deliveryRepo.updateState(d.id, DeliveryState.onRoute);
                    }
                    if (mounted) {
                      PieToast.show(
                        context,
                        'بدأت الطلعة! تم تحديث حالة الأوردرات إلى "في الطريق"',
                        isSuccess: true,
                        icon: Icons.two_wheeler_rounded,
                      );
                      setState(() {});
                    }
                  },
                  label: 'بدء خط السير والتحرك بالطلعة',
                  icon: Icons.play_arrow_rounded,
                  accentColor: PieColors.driverAccent,
                  height: 52,
                ),
                const SizedBox(height: 16),
              ],

              // Numbered Stops
              Text(
                'محطات التوصيل (${activeDeliveries.length})',
                style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),

              for (var i = 0; i < activeDeliveries.length; i++) ...[
                _buildStopCard(
                  delivery: activeDeliveries[i],
                  stopNumber: i + 1,
                  isExpanded: activeDeliveries[i].id == _expandedStopId,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
      ),
    );
  }

  Widget _buildTripHeader(String driverName, int stopsCount, double custody) {
    return PieCard(
      padding: const EdgeInsets.all(18),
      surfaceColor: PieColors.surface2,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
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
                  child: const Icon(
                    Icons.two_wheeler_rounded,
                    color: PieColors.driverAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الطيار: $driverName',
                        style: PieTypography.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$stopsCount محطات توصيل متبقية',
                        style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('العهدة المحصلة:', style: PieTypography.caption),
              const SizedBox(height: 2),
              PieNumeral.money(
                custody,
                style: PieTypography.monoHeading.copyWith(
                  color: PieColors.driverAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFourPhaseProgress(bool isOnRoute) {
    final phases = [
      ('بالفرع', true),
      ('استلام', true),
      ('في الطريق', isOnRoute),
      ('تسليم', false),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: PieColors.surface1,
        borderRadius: PieRadius.borderMd,
        border: Border.all(color: PieColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(phases.length, (index) {
            final phase = phases[index];
            final isPassed = phase.$2;

            return Padding(
              padding: EdgeInsets.only(left: index < phases.length - 1 ? 14 : 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: isPassed ? PieColors.driverAccent : PieColors.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isPassed ? PieColors.driverAccent : PieColors.border,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isPassed ? Colors.black : PieColors.inkMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    phase.$1,
                    style: PieTypography.caption.copyWith(
                      color: isPassed ? PieColors.ink : PieColors.inkMuted,
                      fontWeight: isPassed ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildStopCard({
    required DeliveryModel delivery,
    required int stopNumber,
    required bool isExpanded,
  }) {
    final services = AppScope.of(context);

    return PieCard(
      padding: const EdgeInsets.all(16),
      isActive: isExpanded,
      activeColor: PieColors.driverAccent,
      onTap: () => setState(() => _expandedStopId = delivery.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stop Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isExpanded ? PieColors.driverAccent : PieColors.surface2,
                        shape: BoxShape.circle,
                        border: Border.all(color: PieColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$stopNumber',
                        style: PieTypography.monoBody.copyWith(
                          color: isExpanded ? Colors.black : PieColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'أوردر #${delivery.orderRef}',
                        style: PieTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PieBadge.deliveryState(delivery.state),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: PieColors.inkSecondary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Address & Amount preview
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  delivery.address,
                  style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
                  maxLines: isExpanded ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              PieNumeral.money(
                delivery.amount,
                style: PieTypography.monoHeading.copyWith(
                  color: PieColors.driverAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          // Expanded Content
          if (isExpanded) ...[
            const Divider(color: PieColors.border, height: 24),

            // Landmark Banner if present
            if (delivery.landmark != null && delivery.landmark!.trim().isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: PieColors.surface2,
                  borderRadius: PieRadius.borderMd,
                  border: Border.all(color: PieColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: PieColors.driverAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'علامة مميزة: ${delivery.landmark}',
                        style: PieTypography.caption.copyWith(color: PieColors.ink),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Customer Info & Quick Communication Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: PieColors.surface1,
                borderRadius: PieRadius.borderMd,
                border: Border.all(color: PieColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_pin_circle_outlined, size: 18, color: PieColors.driverAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          delivery.customerName?.isNotEmpty == true
                              ? delivery.customerName!
                              : 'عميل الدليفري',
                          style: PieTypography.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (delivery.customerPhone != null && delivery.customerPhone!.isNotEmpty)
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              delivery.customerPhone!,
                              style: PieTypography.monoCaption.copyWith(color: PieColors.inkSecondary),
                            ),
                          )
                        else
                          Text(
                            'الرقم غير مسجل',
                            style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
                          ),
                      ],
                    ),
                  ),
                  if (delivery.customerPhone != null && delivery.customerPhone!.isNotEmpty) ...[
                    // Call Button
                    PieButton.ghost(
                      onPressed: () => _callPhone(delivery.customerPhone!),
                      label: 'اتصال',
                      icon: Icons.phone_rounded,
                      height: 36,
                    ),
                    const SizedBox(width: 4),
                    // WhatsApp Button
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: 'مراسلة عبر واتساب',
                      icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF25D366), size: 20),
                      onPressed: () => _openWhatsApp(delivery.customerPhone!),
                    ),
                    // Copy Phone
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'نسخ رقم الهاتف',
                      icon: const Icon(Icons.copy_rounded, color: PieColors.inkSecondary, size: 16),
                      onPressed: () => _copyToClipboard(delivery.customerPhone!, 'رقم العميل'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Per-Stop Action Buttons (Ergonomic layout)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // In-App Cockpit Navigation Primary Action
                PieButton.primary(
                  onPressed: () => DriverCockpitNavScreen.push(context, delivery: delivery),
                  label: 'بدء الملاحة المباشرة (Cockpit HUD) 🧭',
                  icon: Icons.explore_rounded,
                  accentColor: const Color(0xFF0284C7),
                  height: 42,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: PieButton.primary(
                        onPressed: () async {
                          final uri = deliveryNavigationUri(address: delivery.address);
                          final launched = await openDeliveryNavigation(uri);
                          if (!launched && context.mounted) {
                            PieToast.show(context, 'تعذر فتح تطبيق خرائط Google تلقائياً', isError: true);
                          }
                        },
                        label: 'Google (GPS) 🗺️',
                        icon: Icons.map_rounded,
                        accentColor: PieColors.driverAccent,
                        height: 40,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: PieButton.secondary(
                        onPressed: () => DriverNavSheet.show(context, delivery: delivery),
                        label: 'خريطة السير',
                        icon: Icons.navigation_rounded,
                        height: 40,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: PieButton.secondary(
                        onPressed: () => DriverReceiptSheet.show(context, delivery: delivery),
                        label: 'عرض البون',
                        icon: Icons.receipt_long_rounded,
                        height: 40,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: PieButton.primary(
                        onPressed: () async {
                          final confirmed = await DriverCustodyCollectionDialog.show(context, delivery: delivery);
                          if (confirmed != true) return;

                          await services.deliveries?.updateState(delivery.id, DeliveryState.delivered);
                          await services.deliveries?.recordCollection(
                            deliveryId: delivery.id,
                            amount: delivery.amount,
                            createdOffline: services.sync?.isOnline != true,
                          );
                          PieSoundService.instance.chime();
                          if (mounted) {
                            PieToast.show(
                              context,
                              'تم تسليم الأوردر وإيداع مبلغ ${PieTypography.formatEgp(delivery.amount)} نقداً بالعهدة بنجاح ✅',
                              isSuccess: true,
                            );
                            setState(() {});
                          }
                        },
                        label: 'تم التسليم واستلام العهدة ✅',
                        icon: Icons.check_circle_outline_rounded,
                        accentColor: const Color(0xFF10B981),
                        height: 42,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: PieButton.destructive(
                        onPressed: () async {
                          final failed = await DriverFailDialog.show(context, delivery: delivery);
                          if (failed == true && mounted) {
                            setState(() {});
                          }
                        },
                        label: 'تعذر التسليم',
                        icon: Icons.cancel_outlined,
                        height: 42,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
