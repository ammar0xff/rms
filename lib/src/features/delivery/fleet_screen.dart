import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/delivery.dart';

/// Screen: Fleet & Delivery Dispatch (طيارين الفرع وإدارة التوصيل)
///
/// Designed for Cashier and Manager:
/// - Real-time branch courier fleet oversight and availability
/// - Active orders in transit with destinations and elapsed time
/// - Waiting delivery orders with auto-dispatch & manual courier assignment
/// - Driver cash custody tracking with one-tap receipt into cash drawer
class FleetScreen extends StatefulWidget {
  const FleetScreen({super.key});

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {
  bool _isProcessing = false;

  Future<void> _showAddDriverDialog(AppServices services) async {
    final nameCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final added = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          shape: const RoundedRectangleBorder(
            borderRadius: PieRadius.borderLg,
            side: BorderSide(color: PieColors.border),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: PieColors.driverSurface,
                  borderRadius: PieRadius.borderMd,
                ),
                child: const Icon(Icons.person_add_alt_1_outlined,
                    color: PieColors.driverAccent, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('إضافة كابتن توصيل بالفرع', style: PieTypography.heading),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('اسم الكابتن / الطيار', style: PieTypography.caption),
                const SizedBox(height: 6),
                TextFormField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: PieTypography.body,
                  decoration: const InputDecoration(
                    hintText: 'مثال: كابتن حسام مصطفى',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'اكتب اسم الكابتن' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(
                'إلغاء',
                style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
              ),
            ),
            PieButton.primary(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogCtx).pop(true);
                }
              },
              label: 'حفظ وإضافة',
              accentColor: PieColors.driverAccent,
              height: 40,
            ),
          ],
        ),
      ),
    );

    if (added == true && mounted) {
      final deliveryRepo = services.deliveries;
      if (deliveryRepo == null) return;

      final existing = await deliveryRepo.listDrivers();
      final newDriver = DriverModel(
        id: 'driver-${DateTime.now().millisecondsSinceEpoch}',
        name: nameCtrl.text.trim(),
        available: true,
      );

      await deliveryRepo.cacheDrivers([...existing, newDriver], replace: true);
      PieSoundService.playOrderPlaced();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: PieColors.surface2,
            content: Text(
              'تمت إضافة الكابتن ${newDriver.name} بنجاح إلى أسطول الفرع',
              style: PieTypography.body.copyWith(color: const Color(0xFF4ADE80)),
            ),
          ),
        );
      }
    }
  }

  Future<void> _assignOrderToDriver({
    required DeliveryModel delivery,
    required List<DriverModel> drivers,
    required AppServices services,
  }) async {
    final deliveryRepo = services.deliveries;
    if (deliveryRepo == null) return;

    final selectedDriver = await showDialog<DriverModel>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          shape: const RoundedRectangleBorder(
            borderRadius: PieRadius.borderLg,
            side: BorderSide(color: PieColors.border),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تسكين الأوردر ${delivery.orderRef}', style: PieTypography.heading),
              const SizedBox(height: 4),
              Text(
                'العنوان: ${delivery.address} · ${PieTypography.formatEgp(delivery.amount)}',
                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: drivers.isEmpty
                ? const Text('لا يوجد طيارين مسجلين', style: PieTypography.body)
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: drivers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final d = drivers[idx];
                      return InkWell(
                        onTap: () => Navigator.of(dialogCtx).pop(d),
                        borderRadius: PieRadius.borderMd,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: d.available
                                ? PieColors.surface2
                                : PieColors.surface3,
                            borderRadius: PieRadius.borderMd,
                            border: Border.all(
                              color: d.available
                                  ? PieColors.driverAccent.withValues(alpha: 0.3)
                                  : PieColors.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.two_wheeler_rounded,
                                color: d.available
                                    ? PieColors.driverAccent
                                    : PieColors.inkMuted,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(d.name, style: PieTypography.bodyStrong),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: d.available
                                      ? const Color(0xFF052E16)
                                      : PieColors.surface2,
                                  borderRadius: PieRadius.borderSm,
                                  border: Border.all(
                                    color: d.available
                                        ? const Color(0xFF4ADE80)
                                        : PieColors.border,
                                  ),
                                ),
                                child: Text(
                                  d.available ? 'متاح' : 'غير متاح',
                                  style: PieTypography.caption.copyWith(
                                    color: d.available
                                        ? const Color(0xFF4ADE80)
                                        : PieColors.inkMuted,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(null),
              child: Text(
                'إلغاء',
                style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
              ),
            ),
          ],
        ),
      ),
    );

    if (selectedDriver != null && mounted) {
      await deliveryRepo.assignDriver(delivery.id, selectedDriver.name);
      PieSoundService.playOrderPlaced();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: PieColors.surface2,
            content: Text(
              'تم تسكين الأوردر ${delivery.orderRef} على الكابتن ${selectedDriver.name}',
              style: PieTypography.body.copyWith(color: const Color(0xFF4ADE80)),
            ),
          ),
        );
      }
    }
  }

  Future<void> _settleDriverCustody({
    required DriverModel driver,
    required double custodyAmount,
    required List<DeliveryModel> driverDeliveredJobs,
    required AppServices services,
  }) async {
    final deliveryRepo = services.deliveries;
    final branchRepo = services.branches;
    final currentUser = services.auth.currentUser;
    if (deliveryRepo == null) return;

    final activeBranch = await branchRepo?.activeBranch();
    final branchId = activeBranch?.id ?? 'main-branch';
    final cashierName = currentUser?.displayName ??
        currentUser?.email?.split('@').first ??
        'الكاشير';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          shape: const RoundedRectangleBorder(
            borderRadius: PieRadius.borderLg,
            side: BorderSide(color: PieColors.border),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: PieColors.cashierSurface,
                  borderRadius: PieRadius.borderMd,
                ),
                child: const Icon(Icons.point_of_sale_rounded,
                    color: PieColors.cashierAccent, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('استلام عهدة الكاش للخزينة', style: PieTypography.heading),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل استلمت النقدية كاملة من الكابتن ${driver.name}؟',
                style: PieTypography.body,
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: PieColors.surface2,
                  borderRadius: PieRadius.borderMd,
                  border: Border.all(color: PieColors.cashierAccent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('المبلغ المطلوب توريده للخزينة:',
                        style: PieTypography.caption),
                    const SizedBox(height: 4),
                    PieNumeral.money(
                      custodyAmount,
                      style: PieTypography.monoDisplay.copyWith(
                        color: PieColors.cashierAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'المستلم: $cashierName · الفرع: ${activeBranch?.name ?? 'الفرع الرئيسي'}',
                      style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(
                'إلغاء',
                style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
              ),
            ),
            PieButton.primary(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              label: 'تأكيد الاستلام والتوريد',
              accentColor: PieColors.cashierAccent,
              height: 40,
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isProcessing = true);
      try {
        await deliveryRepo.recordBatchSettlement(
          driver: driver.name,
          branchId: branchId,
          amount: custodyAmount,
          receiver: cashierName,
        );

        for (final job in driverDeliveredJobs) {
          if (job.settlementStatus != SettlementStatus.settled) {
            await deliveryRepo.finalizeSettlement(job.id);
          }
        }

        PieSoundService.playCashDrawer();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: PieColors.surface2,
              content: Text(
                'تم استلام عهدة ${driver.name} بقيمة ${PieTypography.formatEgp(custodyAmount)} وتوريدها للخزينة بنجاح',
                style: PieTypography.body.copyWith(color: const Color(0xFF4ADE80)),
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _toggleDriverAvailability({
    required DriverModel driver,
    required List<DriverModel> allDrivers,
    required AppServices services,
  }) async {
    final deliveryRepo = services.deliveries;
    if (deliveryRepo == null) return;

    final updated = allDrivers.map((d) {
      if (d.id == driver.id) {
        return DriverModel(id: d.id, name: d.name, available: !d.available);
      }
      return d;
    }).toList();

    await deliveryRepo.cacheDrivers(updated, replace: true);
    PieSoundService.playOrderPlaced();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final deliveryRepo = services.deliveries;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<List<DriverModel>>(
        future: deliveryRepo?.listDrivers(),
          builder: (context, driverSnapshot) {
            final drivers = driverSnapshot.data ?? [];

            return FutureBuilder<List<DeliveryModel>>(
              future: deliveryRepo?.listDeliveries(),
              builder: (context, deliverySnapshot) {
                final deliveries = deliverySnapshot.data ?? [];
                final waitingDeliveries = deliveries
                    .where((d) => d.state == DeliveryState.waiting)
                    .toList();

                // Compute KPI metrics
                final availableDrivers =
                    drivers.where((d) => d.available).toList();

                var driversOnRouteCount = 0;
                var totalCustodyInTransit = 0.0;

                for (final driver in drivers) {
                  final activeJobs = deliveries.where((d) =>
                      d.driver == driver.name &&
                      (d.state == DeliveryState.assigned ||
                          d.state == DeliveryState.onRoute));
                  if (activeJobs.isNotEmpty) {
                    driversOnRouteCount++;
                  }

                  final unsettledDelivered = deliveries.where((d) =>
                      d.driver == driver.name &&
                      d.state == DeliveryState.delivered &&
                      d.settlementStatus != SettlementStatus.settled);
                  for (final job in unsettledDelivered) {
                    totalCustodyInTransit += job.amount;
                  }
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Action Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'كباتن الأسطول والتوصيل',
                          style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'تحديث البيانات',
                              icon: const Icon(Icons.refresh_rounded, color: PieColors.inkSecondary),
                              onPressed: () => setState(() {}),
                            ),
                            const SizedBox(width: 8),
                            PieButton.primary(
                              icon: Icons.person_add_alt_1_outlined,
                              label: 'إضافة كابتن توصيل',
                              onPressed: () => _showAddDriverDialog(services),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Overview KPI Grid
                    LayoutBuilder(
                      builder: (context, kpiConstraints) {
                        final cardTotal = PieCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('إجمالي الطيارين',
                                  style: PieTypography.caption),
                              const SizedBox(height: 6),
                              PieNumeral.count(
                                drivers.length,
                                style: PieTypography.monoHeading.copyWith(
                                  color: PieColors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                        final cardAvailable = PieCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('متاحين بالفرع',
                                  style: PieTypography.caption),
                              const SizedBox(height: 6),
                              PieNumeral.count(
                                availableDrivers.length,
                                style: PieTypography.monoHeading.copyWith(
                                  color: const Color(0xFF4ADE80),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                        final cardInTransit = PieCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('في مشاوير',
                                  style: PieTypography.caption),
                              const SizedBox(height: 6),
                              PieNumeral.count(
                                driversOnRouteCount,
                                style: PieTypography.monoHeading.copyWith(
                                  color: PieColors.driverAccent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                        final cardCustody = PieCard(
                          padding: const EdgeInsets.all(14),
                          surfaceColor: totalCustodyInTransit > 0
                              ? const Color(0xFF1E1B18)
                              : PieColors.surface1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('عهدة في الطريق',
                                  style: PieTypography.caption),
                              const SizedBox(height: 6),
                              PieNumeral.money(
                                totalCustodyInTransit,
                                style: PieTypography.monoHeading.copyWith(
                                  color: totalCustodyInTransit > 0
                                      ? PieColors.cashierAccent
                                      : PieColors.inkMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );

                        if (kpiConstraints.maxWidth < 650) {
                          return Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: cardTotal),
                                  const SizedBox(width: 10),
                                  Expanded(child: cardAvailable),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: cardInTransit),
                                  const SizedBox(width: 10),
                                  Expanded(child: cardCustody),
                                ],
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: cardTotal),
                            const SizedBox(width: 10),
                            Expanded(child: cardAvailable),
                            const SizedBox(width: 10),
                            Expanded(child: cardInTransit),
                            const SizedBox(width: 10),
                            Expanded(child: cardCustody),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // Waiting Deliveries Dispatch Section
                    PieCard(
                      padding: const EdgeInsets.all(16),
                      surfaceColor: waitingDeliveries.isNotEmpty
                          ? PieColors.surface2
                          : PieColors.surface1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, headerConstraints) {
                              final isCompact = headerConstraints.maxWidth < 460;
                              final titleWidget = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.pending_actions_rounded,
                                      color: PieColors.driverAccent, size: 20),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'أوردرات في انتظار التسكين (${waitingDeliveries.length})',
                                      style: PieTypography.subheading.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: PieColors.ink,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              );
                              final buttonWidget = PieButton.primary(
                                label: 'تسكين ذكي آلي',
                                icon: Icons.auto_mode_rounded,
                                onPressed: (_isProcessing ||
                                        waitingDeliveries.isEmpty ||
                                        availableDrivers.isEmpty)
                                    ? null
                                    : () async {
                                        setState(() => _isProcessing = true);
                                        try {
                                          final results = await deliveryRepo
                                              ?.autoAssignWaiting();
                                          PieSoundService.playOrderPlaced();
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                backgroundColor:
                                                    PieColors.surface2,
                                                content: Text(
                                                  'تم تسكين ${results?.length ?? 0} أوردر آلياً على كباتن الفرع',
                                                  style: PieTypography.body
                                                      .copyWith(
                                                          color: const Color(
                                                              0xFF4ADE80)),
                                                ),
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _isProcessing = false);
                                          }
                                        }
                                      },
                              );

                              if (isCompact) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    titleWidget,
                                    const SizedBox(height: 12),
                                    buttonWidget,
                                  ],
                                );
                              }

                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: titleWidget),
                                  const SizedBox(width: 12),
                                  buttonWidget,
                                ],
                              );
                            },
                          ),
                          if (waitingDeliveries.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Divider(color: PieColors.border, height: 1),
                            const SizedBox(height: 12),
                            for (final d in waitingDeliveries) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: PieColors.surface1,
                                  borderRadius: PieRadius.borderMd,
                                  border: Border.all(color: PieColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: PieColors.driverSurface,
                                        borderRadius: PieRadius.borderSm,
                                      ),
                                      child: Text(
                                        d.orderRef,
                                        style: PieTypography.monoCaption.copyWith(
                                          color: PieColors.driverAccent,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(d.address,
                                              style: PieTypography.body),
                                          const SizedBox(height: 2),
                                          PieNumeral.money(
                                            d.amount,
                                            style: PieTypography.monoCaption
                                                .copyWith(
                                                    color:
                                                        PieColors.cashierAccent),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PieButton.secondary(
                                      onPressed: () => _assignOrderToDriver(
                                        delivery: d,
                                        drivers: drivers,
                                        services: services,
                                      ),
                                      label: 'تسكين على كابتن',
                                      height: 34,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ] else ...[
                            const SizedBox(height: 8),
                            Text(
                              'لا توجد أوردرات دليفري معلقة في انتظار التسكين حالياً.',
                              style: PieTypography.caption
                                  .copyWith(color: PieColors.inkSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Couriers Roster Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'كباتن الفرع والحالة التشغيلية (${drivers.length})',
                          style: PieTypography.heading
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                        TextButton.icon(
                          onPressed: () => _showAddDriverDialog(services),
                          icon: const Icon(Icons.add,
                              size: 18, color: PieColors.driverAccent),
                          label: Text(
                            'إضافة كابتن',
                            style: PieTypography.body
                                .copyWith(color: PieColors.driverAccent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (drivers.isEmpty)
                      const PieCard(
                        padding: EdgeInsets.all(32),
                        child: PieEmptyState(
                          title: 'مفيش طيارين متسجلين في الفرع',
                          description:
                              'اضغط على زر إضافة كابتن لتسجيل طياري الفرع.',
                          icon: Icons.two_wheeler_outlined,
                        ),
                      )
                    else
                      for (final driver in drivers) ...[
                        _buildDriverCard(
                          driver: driver,
                          allDrivers: drivers,
                          allDeliveries: deliveries,
                          services: services,
                        ),
                        const SizedBox(height: 12),
                      ],
                  ],
                );
              },
            );
          },
        ),
    );
  }

  Widget _buildDriverCard({
    required DriverModel driver,
    required List<DriverModel> allDrivers,
    required List<DeliveryModel> allDeliveries,
    required AppServices services,
  }) {
    final activeOrders = allDeliveries
        .where((d) =>
            d.driver == driver.name &&
            (d.state == DeliveryState.assigned ||
                d.state == DeliveryState.onRoute))
        .toList();

    final unsettledDelivered = allDeliveries
        .where((d) =>
            d.driver == driver.name &&
            d.state == DeliveryState.delivered &&
            d.settlementStatus != SettlementStatus.settled)
        .toList();

    final custodyAmount =
        unsettledDelivered.fold(0.0, (sum, d) => sum + d.amount);

    final isOnRoute = activeOrders.isNotEmpty;

    return PieCard(
      padding: const EdgeInsets.all(16),
      surfaceColor: PieColors.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isOnRoute
                      ? PieColors.driverSurface
                      : (driver.available
                          ? const Color(0xFF052E16)
                          : PieColors.surface2),
                  borderRadius: PieRadius.borderMd,
                  border: Border.all(
                    color: isOnRoute
                        ? PieColors.driverAccent
                        : (driver.available
                            ? const Color(0xFF4ADE80)
                            : PieColors.border),
                  ),
                ),
                child: Icon(
                  Icons.two_wheeler_rounded,
                  color: isOnRoute
                      ? PieColors.driverAccent
                      : (driver.available
                          ? const Color(0xFF4ADE80)
                          : PieColors.inkMuted),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(driver.name, style: PieTypography.bodyStrong),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isOnRoute
                                ? PieColors.driverSurface
                                : (driver.available
                                    ? const Color(0xFF052E16)
                                    : PieColors.surface3),
                            borderRadius: PieRadius.borderSm,
                            border: Border.all(
                              color: isOnRoute
                                  ? PieColors.driverAccent
                                  : (driver.available
                                      ? const Color(0xFF4ADE80)
                                      : PieColors.border),
                            ),
                          ),
                          child: Text(
                            isOnRoute
                                ? 'في مشوار (${activeOrders.length} أوردر)'
                                : (driver.available ? 'متاح بالفرع' : 'في استراحة'),
                            style: PieTypography.caption.copyWith(
                              color: isOnRoute
                                  ? PieColors.driverAccent
                                  : (driver.available
                                      ? const Color(0xFF4ADE80)
                                      : PieColors.inkMuted),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isOnRoute
                          ? 'أوردرات جارية: ${activeOrders.map((e) => e.orderRef).join(', ')}'
                          : (driver.available
                              ? 'جاهز لاستلام طلعات جديدة فور تجهيزها'
                              : 'غير متاح للتسكين التلقائي حالياً'),
                      style: PieTypography.caption.copyWith(
                        color: PieColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: PieColors.inkSecondary),
                color: PieColors.surfaceOverlay,
                onSelected: (val) {
                  if (val == 'toggle') {
                    _toggleDriverAvailability(
                      driver: driver,
                      allDrivers: allDrivers,
                      services: services,
                    );
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      driver.available
                          ? 'تحويل لوضع الاستراحة'
                          : 'تحويل إلى متاح بالفرع',
                      style: PieTypography.body,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Active Orders Detail
          if (activeOrders.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: PieColors.surface2,
                borderRadius: PieRadius.borderMd,
                border: Border.all(color: PieColors.border),
              ),
              child: Column(
                children: [
                  for (final job in activeOrders)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: PieColors.surface3,
                              borderRadius: PieRadius.borderSm,
                            ),
                            child: Text(
                              job.orderRef,
                              style: PieTypography.monoCaption.copyWith(
                                color: PieColors.driverAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              job.address,
                              style: PieTypography.caption
                                  .copyWith(color: PieColors.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          PieNumeral.money(
                            job.amount,
                            style: PieTypography.monoCaption
                                .copyWith(color: PieColors.cashierAccent),
                          ),
                          const SizedBox(width: 6),
                          PieBadge(
                            label: job.state.label,
                            variant: PieBadgeVariant.pending,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(color: PieColors.border, height: 1),
          const SizedBox(height: 12),

          // Custody Handover Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 16, color: PieColors.inkSecondary),
                  const SizedBox(width: 6),
                  Text('العهدة النقدية الحالية:', style: PieTypography.caption),
                  const SizedBox(width: 6),
                  PieNumeral.money(
                    custodyAmount,
                    style: PieTypography.monoHeading.copyWith(
                      color: custodyAmount > 0
                          ? PieColors.cashierAccent
                          : PieColors.inkMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              PieButton.primary(
                onPressed: custodyAmount <= 0
                    ? null
                    : () => _settleDriverCustody(
                          driver: driver,
                          custodyAmount: custodyAmount,
                          driverDeliveredJobs: unsettledDelivered,
                          services: services,
                        ),
                label: 'استلام وتوريد العهدة للخزينة',
                accentColor: PieColors.cashierAccent,
                height: 36,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
