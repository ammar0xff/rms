import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/pwa/pwa_cache_service.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../core/widgets/pie_toast.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/delivery.dart';
import 'driver_identity_service.dart';

/// Screen: Driver Profile & Duty Status (ملف وحالة كابتن التوصيل)
///
/// Features:
/// - Current courier identity and active branch
/// - Real-time availability toggle: "متاح للاستلام" vs "في استراحة"
/// - Personal shift KPIs: Delivered stops, cash in hand, active trips
/// - Driver persona selector for quick terminal handovers
/// - Vehicle selector & Driver Settings (PWA updates, Sound effects)
class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  bool _isUpdating = false;
  bool _isClearingCache = false;
  String _selectedVehicle = 'موتوسيكل';

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

  Future<void> _clearBrowserCache() async {
    setState(() => _isClearingCache = true);
    PieSoundService.instance.click();

    PieToast.show(
      context,
      'جاري مسح كاش المتصفح وتحديث تطبيق الكابتن...',
      icon: Icons.refresh_rounded,
      duration: const Duration(seconds: 4),
    );

    await Future.delayed(const Duration(milliseconds: 300));
    PwaCacheService.instance.clearCacheAndReload();

    if (mounted) {
      setState(() => _isClearingCache = false);
    }
  }

  Future<void> _toggleAvailability(
    DriverModel? currentDriver,
    String driverName,
    AppServices services,
  ) async {
    final deliveryRepo = services.deliveries;
    if (deliveryRepo == null) return;

    setState(() => _isUpdating = true);

    try {
      final currentList = await deliveryRepo.listDrivers();
      final targetAvailable = !(currentDriver?.available ?? true);

      final updatedList = <DriverModel>[];
      var found = false;

      for (final d in currentList) {
        if (d.name == driverName || (currentDriver != null && d.id == currentDriver.id)) {
          updatedList.add(DriverModel(
            id: d.id,
            name: d.name,
            available: targetAvailable,
          ));
          found = true;
        } else {
          updatedList.add(d);
        }
      }

      if (!found) {
        updatedList.add(DriverModel(
          id: 'driver-${DateTime.now().millisecondsSinceEpoch}',
          name: driverName,
          available: targetAvailable,
        ));
      }

      await deliveryRepo.cacheDrivers(updatedList, replace: true);
      PieSoundService.playOrderPlaced();

      if (mounted) {
        PieToast.show(
          context,
          targetAvailable
              ? 'أنت الآن متاح بالفرع وجاهز لاستلام طلعات جديدة'
              : 'تم تفعيل وضع الاستراحة. لن يتم إسناد طلعات جديدة لك تلقائياً',
          isSuccess: targetAvailable,
          icon: targetAvailable ? Icons.check_circle_outline : Icons.pause_circle_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final user = services.auth.currentUser;
    final deliveryRepo = services.deliveries;
    final branchRepo = services.branches;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<List<DriverModel>>(
          future: deliveryRepo?.listDrivers(),
          builder: (context, driverSnap) {
            final allDrivers = driverSnap.data ?? [];
            final myDriverName = DriverSession.instance.resolveCurrentDriverName(
              user: user,
              drivers: allDrivers,
            );

            DriverModel? currentDriver;
            for (final d in allDrivers) {
              if (d.name == myDriverName ||
                  (user != null && d.id == user.uid) ||
                  (user?.email != null && d.email.isNotEmpty && d.email.toLowerCase() == user!.email!.toLowerCase())) {
                currentDriver = d;
                break;
              }
            }

            final isAvailable = currentDriver?.available ?? true;

            return FutureBuilder<List<DeliveryModel>>(
              future: deliveryRepo?.listDeliveries(),
              builder: (context, deliverySnap) {
                final allDeliveries = deliverySnap.data ?? [];
                final myDeliveries = allDeliveries
                    .where((d) => DriverSession.instance.isDeliveryAssignedToCurrentDriver(
                          delivery: d,
                          user: user,
                          drivers: allDrivers,
                        ))
                    .toList();

                final activeStops = myDeliveries
                    .where((d) =>
                        d.state == DeliveryState.assigned ||
                        d.state == DeliveryState.onRoute)
                    .toList();

                final deliveredStops = myDeliveries
                    .where((d) => d.state == DeliveryState.delivered)
                    .toList();

                final failedStops = myDeliveries
                    .where((d) =>
                        d.state == DeliveryState.failed ||
                        d.state == DeliveryState.returned)
                    .toList();

                final totalCustodyInHand = myDeliveries
                    .where((d) =>
                        d.state == DeliveryState.delivered &&
                        d.settlementStatus != SettlementStatus.settled)
                    .fold(0.0, (sum, d) => sum + d.amount);

                return FutureBuilder(
                  future: branchRepo?.activeBranch(),
                  builder: (context, branchSnap) {
                    final branch = branchSnap.data;
                    final branchName =
                        branch?.name.isNotEmpty == true ? branch!.name : 'الفرع الرئيسي';

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Courier Profile Card
                        PieCard(
                          padding: const EdgeInsets.all(20),
                          surfaceColor: PieColors.surface2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: PieColors.driverSurface,
                                      borderRadius: PieRadius.borderLg,
                                      border: Border.all(
                                        color: PieColors.driverAccent,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.two_wheeler_rounded,
                                      color: PieColors.driverAccent,
                                      size: 30,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                myDriverName,
                                                style: PieTypography.heading.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: PieColors.ink,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isAvailable
                                                    ? const Color(0xFF052E16)
                                                    : PieColors.surface3,
                                                borderRadius: PieRadius.borderSm,
                                                border: Border.all(
                                                  color: isAvailable
                                                      ? const Color(0xFF4ADE80)
                                                      : PieColors.border,
                                                ),
                                              ),
                                              child: Text(
                                                isAvailable ? 'متاح للاستلام' : 'في استراحة',
                                                style: PieTypography.caption.copyWith(
                                                  color: isAvailable
                                                      ? const Color(0xFF4ADE80)
                                                      : PieColors.inkMuted,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.storefront_outlined,
                                              size: 14,
                                              color: PieColors.inkSecondary,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              branchName,
                                              style: PieTypography.caption.copyWith(
                                                color: PieColors.inkSecondary,
                                              ),
                                            ),
                                            if (user?.email != null &&
                                                user!.email!.isNotEmpty) ...[
                                              const SizedBox(width: 10),
                                              Text(
                                                '•',
                                                style: PieTypography.caption.copyWith(
                                                  color: PieColors.border,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  user.email!,
                                                  style: PieTypography.caption.copyWith(
                                                    color: PieColors.inkMuted,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              const Divider(color: PieColors.border, height: 1),
                              const SizedBox(height: 16),

                              // Quick Availability Switch Action
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'حالة التواجد في الفرع',
                                          style: PieTypography.subheading,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isAvailable
                                              ? 'الكاشير يقدر يسندلك أوردرات دلوقتي'
                                              : 'تم إيقاف تسكين الأوردرات مؤقتاً',
                                          style: PieTypography.caption.copyWith(
                                            color: PieColors.inkSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  PieButton.primary(
                                    onPressed: _isUpdating
                                        ? null
                                        : () => _toggleAvailability(
                                              currentDriver,
                                              myDriverName,
                                              services,
                                            ),
                                    label: isAvailable ? 'أخذ استراحة' : 'تسجيل جاهزية',
                                    accentColor: isAvailable
                                        ? PieColors.surface3
                                        : const Color(0xFF16A34A),
                                    height: 38,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Shift KPIs Section
                        Text(
                          'ملخص ورديتي اليوم',
                          style: PieTypography.subheading.copyWith(
                            color: PieColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: PieCard(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('أوردرات اتسلّمت', style: PieTypography.caption),
                                    const SizedBox(height: 6),
                                    PieNumeral.count(
                                      deliveredStops.length,
                                      style: PieTypography.monoHeading.copyWith(
                                        color: const Color(0xFF4ADE80),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: PieCard(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('طلعات جارية', style: PieTypography.caption),
                                    const SizedBox(height: 6),
                                    PieNumeral.count(
                                      activeStops.length,
                                      style: PieTypography.monoHeading.copyWith(
                                        color: PieColors.driverAccent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: PieCard(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('تعذر / مرتجع', style: PieTypography.caption),
                                    const SizedBox(height: 6),
                                    PieNumeral.count(
                                      failedStops.length,
                                      style: PieTypography.monoHeading.copyWith(
                                        color: failedStops.isEmpty
                                            ? PieColors.inkMuted
                                            : PieColors.stateError,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Cash in Custody Hero Card
                        PieCard(
                          padding: const EdgeInsets.all(16),
                          surfaceColor: totalCustodyInHand > 0
                              ? const Color(0xFF1E1B18)
                              : PieColors.surface1,
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: totalCustodyInHand > 0
                                      ? PieColors.cashierSurface
                                      : PieColors.surface2,
                                  borderRadius: PieRadius.borderMd,
                                  border: Border.all(
                                    color: totalCustodyInHand > 0
                                        ? PieColors.cashierAccent
                                        : PieColors.border,
                                  ),
                                ),
                                child: Icon(
                                  Icons.account_balance_wallet_outlined,
                                  color: totalCustodyInHand > 0
                                      ? PieColors.cashierAccent
                                      : PieColors.inkSecondary,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('إجمالي نقدية العهدة في حوزتي',
                                        style: PieTypography.caption),
                                    const SizedBox(height: 2),
                                    PieNumeral.money(
                                      totalCustodyInHand,
                                      style: PieTypography.monoHeading.copyWith(
                                        color: totalCustodyInHand > 0
                                            ? PieColors.cashierAccent
                                            : PieColors.inkMuted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Vehicle Selector
                        Text(
                          'وسيلة التوصيل',
                          style: PieTypography.subheading.copyWith(
                            color: PieColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ('موتوسيكل 🛵', 'موتوسيكل'),
                            ('سكوتر 🛴', 'سكوتر'),
                            ('دراجة 🚲', 'دراجة'),
                            ('سيارة 🚗', 'سيارة'),
                          ].map((v) {
                            final isSel = _selectedVehicle == v.$2;
                            return ChoiceChip(
                              label: Text(
                                v.$1,
                                style: PieTypography.body.copyWith(
                                  color: isSel ? PieColors.driverAccent : PieColors.inkSecondary,
                                  fontWeight: isSel ? FontWeight.w700 : FontWeight.normal,
                                ),
                              ),
                              selected: isSel,
                              selectedColor: PieColors.driverSurface,
                              backgroundColor: PieColors.surface2,
                              side: BorderSide(
                                color: isSel ? PieColors.driverAccent : PieColors.border,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _selectedVehicle = v.$2);
                                  PieSoundService.instance.click();
                                }
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),

                        // Courier Persona Switcher (For testing and shared handsets)
                        if (allDrivers.isNotEmpty) ...[
                          Text(
                            'تحديد الكابتن النشط على هذا الجهاز',
                            style: PieTypography.subheading.copyWith(
                              color: PieColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'اختر حسابك التشغيلي في حالة استخدام جهاز لوحي مشترك بالفرع:',
                            style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: allDrivers.map((d) {
                              final isSelected = d.name == myDriverName;
                              return ChoiceChip(
                                label: Text(
                                  d.name,
                                  style: PieTypography.body.copyWith(
                                    color: isSelected
                                        ? PieColors.driverAccent
                                        : PieColors.inkSecondary,
                                    fontWeight:
                                        isSelected ? FontWeight.w700 : FontWeight.normal,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: PieColors.driverSurface,
                                backgroundColor: PieColors.surface2,
                                side: BorderSide(
                                  color: isSelected
                                      ? PieColors.driverAccent
                                      : PieColors.border,
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      DriverSession.instance.activeDriverName = d.name;
                                    });
                                    PieSoundService.playRoleSwitch();
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Driver App & Device Settings Card
                        Text(
                          'إعدادات وتحديثات التطبيق (PWA)',
                          style: PieTypography.subheading.copyWith(
                            color: PieColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        PieCard(
                          padding: const EdgeInsets.all(16),
                          surfaceColor: PieColors.surface2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Sound effects toggle
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.volume_up_rounded, color: PieColors.driverAccent, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('المؤثرات والتنبيهات الصوتية', style: PieTypography.bodyStrong),
                                              const SizedBox(height: 2),
                                              Text(
                                                'أصوات استلام الطلعات، الأوردرات والتسليم',
                                                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: PieSoundService.instance.enabled,
                                    activeThumbColor: PieColors.driverAccent,
                                    onChanged: (val) {
                                      setState(() {
                                        PieSoundService.instance.enabled = val;
                                      });
                                      if (val) PieSoundService.instance.click();
                                    },
                                  ),
                                ],
                              ),
                              const Divider(color: PieColors.border, height: 24),
                              // PWA Cache Buster Button
                              Row(
                                children: [
                                  const Icon(Icons.cached_rounded, color: PieColors.driverAccent, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('تحديث كاش المتصفح (PWA)', style: PieTypography.bodyStrong),
                                        const SizedBox(height: 2),
                                        Text(
                                          'يجلب أحدث نسخة مرفوعة على السيرفر ويمسح التخزين القديم فوراً',
                                          style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  PieButton.primary(
                                    onPressed: _isClearingCache ? null : _clearBrowserCache,
                                    label: _isClearingCache ? 'جاري التحديث...' : 'تحديث الآن',
                                    icon: Icons.refresh_rounded,
                                    accentColor: PieColors.driverAccent,
                                    height: 38,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
    );
  }
}
