import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../core/widgets/pie_toast.dart';
import '../../domain/models/app_role.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/delivery.dart';
import 'package:url_launcher/url_launcher.dart';

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

  bool _deliveryMatchesDriver(DeliveryModel d, DriverModel driver) {
    final assigned = d.driver.trim().toLowerCase();
    if (assigned.isEmpty) return false;
    if (assigned == driver.name.trim().toLowerCase()) return true;
    if (assigned == driver.id.trim().toLowerCase()) return true;
    if (driver.email.isNotEmpty && assigned == driver.email.trim().toLowerCase()) return true;
    return false;
  }

  Future<void> _showAddDriverDialog(AppServices services) async {
    final user = services.auth.currentUser;
    final isPrivileged = user?.role == AppRole.manager || user?.role == AppRole.developer;
    if (!isPrivileged) {
      PieToast.show(
        context,
        'عفواً، تسجيل وإضافة الكباتن مقتصرة على مدير الفرع فقط.',
        isError: true,
      );
      return;
    }
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
        PieToast.show(
          context,
          'تمت إضافة الكابتن ${newDriver.name} بنجاح إلى أسطول الفرع',
          isSuccess: true,
          icon: Icons.person_add_rounded,
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
        PieToast.show(
          context,
          'تم تسكين الأوردر ${delivery.orderRef} على الكابتن ${selectedDriver.name}',
          isSuccess: true,
          icon: Icons.check_circle_outline,
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

    if (!mounted) return;
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
          PieToast.show(
            context,
            'تم استلام عهدة ${driver.name} بقيمة ${PieTypography.formatEgp(custodyAmount)} وتوريدها للخزينة بنجاح',
            isSuccess: true,
            icon: Icons.payments_rounded,
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _callPhone(String phone) async {
    final clean = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _settleSingleOrder({
    required DeliveryModel delivery,
    required DriverModel driver,
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

    if (!mounted) return;
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
              const Text('توريد عهدة أوردر للخزينة', style: PieTypography.heading),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل استلمت نقدية الأوردر ${delivery.orderRef} بقيمة ${PieTypography.formatEgp(delivery.amount)} من الكابتن ${driver.name}؟',
                style: PieTypography.body,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PieColors.surface2,
                  borderRadius: PieRadius.borderMd,
                  border: Border.all(color: PieColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الأوردر: ${delivery.orderRef}', style: PieTypography.bodyStrong),
                    const SizedBox(height: 4),
                    Text('العميل: ${delivery.customerName ?? 'عميل دليفري'} · ${delivery.customerPhone ?? ''}',
                        style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
                    const SizedBox(height: 2),
                    Text('العنوان: ${delivery.address}',
                        style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
                    const SizedBox(height: 6),
                    PieNumeral.money(
                      delivery.amount,
                      style: PieTypography.monoHeading.copyWith(
                        color: PieColors.cashierAccent,
                        fontWeight: FontWeight.w700,
                      ),
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
              label: 'تأكيد التوريد للخزينة',
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
        await deliveryRepo.finalizeSettlement(delivery.id);
        await deliveryRepo.recordBatchSettlement(
          driver: driver.name,
          branchId: branchId,
          amount: delivery.amount,
          receiver: cashierName,
        );
        PieSoundService.playCashDrawer();
        if (mounted) {
          PieToast.show(
            context,
            'تم توريد عهدة الأوردر ${delivery.orderRef} بقيمة ${PieTypography.formatEgp(delivery.amount)} للخزينة بنجاح',
            isSuccess: true,
            icon: Icons.payments_rounded,
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
    final user = services.auth.currentUser;
    final isPrivileged = user?.role == AppRole.manager || user?.role == AppRole.developer;
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
                var totalDeliveredCustody = 0.0;
                var totalInTransitCustody = 0.0;

                for (final driver in drivers) {
                  final activeJobs = deliveries.where((d) =>
                      _deliveryMatchesDriver(d, driver) &&
                      (d.state == DeliveryState.assigned ||
                          d.state == DeliveryState.onRoute));
                  if (activeJobs.isNotEmpty) {
                    driversOnRouteCount++;
                  }
                  for (final job in activeJobs) {
                    totalInTransitCustody += job.amount;
                  }

                  final unsettledDelivered = deliveries.where((d) =>
                      _deliveryMatchesDriver(d, driver) &&
                      d.state == DeliveryState.delivered &&
                      d.settlementStatus != SettlementStatus.settled);
                  for (final job in unsettledDelivered) {
                    totalDeliveredCustody += job.amount;
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
                            if (isPrivileged) ...[
                              const SizedBox(width: 8),
                              PieButton.primary(
                                icon: Icons.person_add_alt_1_outlined,
                                label: 'إضافة كابتن توصيل',
                                onPressed: () => _showAddDriverDialog(services),
                              ),
                            ],
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
                          surfaceColor: totalDeliveredCustody > 0
                              ? const Color(0xFF261D08)
                              : PieColors.surface1,
                          borderColor: totalDeliveredCustody > 0
                              ? PieColors.cashierAccent.withValues(alpha: 0.5)
                              : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_outlined,
                                    size: 14,
                                    color: totalDeliveredCustody > 0
                                        ? PieColors.cashierAccent
                                        : PieColors.inkSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  const Expanded(
                                    child: Text(
                                      'عهدة كاش مع الطيارين',
                                      style: PieTypography.caption,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              PieNumeral.money(
                                totalDeliveredCustody,
                                style: PieTypography.monoHeading.copyWith(
                                  color: totalDeliveredCustody > 0
                                      ? PieColors.cashierAccent
                                      : PieColors.inkMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                totalInTransitCustody > 0
                                    ? '+ ${PieTypography.formatEgp(totalInTransitCustody)} في الطريق'
                                    : (totalDeliveredCustody > 0
                                        ? 'جاهزة للتوريد بالخزينة'
                                        : 'لا توجد مبالغ معلقة'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PieTypography.caption.copyWith(
                                  color: totalDeliveredCustody > 0
                                      ? const Color(0xFFFBBF24)
                                      : PieColors.inkMuted,
                                  fontSize: 10,
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
                                            PieToast.show(
                                              context,
                                              'تم تسكين ${results?.length ?? 0} أوردر آلياً على كباتن الفرع',
                                              isSuccess: true,
                                              icon: Icons.auto_awesome_rounded,
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
                        if (isPrivileged)
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
                      PieCard(
                        padding: const EdgeInsets.all(32),
                        child: PieEmptyState(
                          title: 'مفيش طيارين متسجلين في الفرع',
                          description: isPrivileged
                              ? 'اضغط على زر إضافة كابتن بالأعلى لتسجيل وتعيين طياري الفرع.'
                              : 'لم يقم مدير الفرع بإضافة كباتن توصيل بعد. يرجى مراجعة إدارة الفرع لتسجيل طياري الفرع.',
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
            _deliveryMatchesDriver(d, driver) &&
            (d.state == DeliveryState.assigned ||
                d.state == DeliveryState.onRoute))
        .toList();

    final unsettledDelivered = allDeliveries
        .where((d) =>
            _deliveryMatchesDriver(d, driver) &&
            d.state == DeliveryState.delivered &&
            d.settlementStatus != SettlementStatus.settled)
        .toList();

    final deliveredCustodyAmount =
        unsettledDelivered.fold(0.0, (sum, d) => sum + d.amount);
    final inTransitAmount =
        activeOrders.fold(0.0, (sum, d) => sum + d.amount);
    final totalDriverCustody = deliveredCustodyAmount + inTransitAmount;
    final allUnreturnedOrders = [...unsettledDelivered, ...activeOrders];

    final isOnRoute = activeOrders.isNotEmpty;
    final hasDeliveredCustody = deliveredCustodyAmount > 0;

    return PieCard(
      padding: const EdgeInsets.all(16),
      surfaceColor: PieColors.surface1,
      borderColor: hasDeliveredCustody
          ? PieColors.cashierAccent
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Driver Identity & Status Row
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: hasDeliveredCustody
                      ? const Color(0xFF261D08)
                      : (isOnRoute
                          ? PieColors.driverSurface
                          : (driver.available
                              ? const Color(0xFF052E16)
                              : PieColors.surface2)),
                  borderRadius: PieRadius.borderMd,
                  border: Border.all(
                    color: hasDeliveredCustody
                        ? PieColors.cashierAccent
                        : (isOnRoute
                            ? PieColors.driverAccent
                            : (driver.available
                                ? const Color(0xFF4ADE80)
                                : PieColors.border)),
                  ),
                ),
                child: Icon(
                  Icons.two_wheeler_rounded,
                  color: hasDeliveredCustody
                      ? PieColors.cashierAccent
                      : (isOnRoute
                          ? PieColors.driverAccent
                          : (driver.available
                              ? const Color(0xFF4ADE80)
                              : PieColors.inkMuted)),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                        if (hasDeliveredCustody)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF261D08),
                              borderRadius: PieRadius.borderSm,
                              border: Border.all(color: PieColors.cashierAccent),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 12, color: PieColors.cashierAccent),
                                const SizedBox(width: 4),
                                Text(
                                  'عهدة باليد: ${PieTypography.formatEgp(deliveredCustodyAmount)}',
                                  style: PieTypography.caption.copyWith(
                                    color: PieColors.cashierAccent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      allUnreturnedOrders.isNotEmpty
                          ? 'إجمالي ما طرف الكابتن: ${PieTypography.formatEgp(totalDriverCustody)} (${allUnreturnedOrders.length} أوردر لم يُورّد)'
                          : (driver.available
                              ? 'لا توجد عهدة معلقة · جاهز لاستلام طلعات جديدة'
                              : 'لا توجد عهدة معلقة · في استراحة'),
                      style: PieTypography.caption.copyWith(
                        color: hasDeliveredCustody ? const Color(0xFFFBBF24) : PieColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: PieColors.inkSecondary),
                color: PieColors.surfaceOverlay,
                onSelected: (val) {
                  if (val == 'toggle') {
                    _toggleDriverAvailability(
                      driver: driver,
                      allDrivers: allDrivers,
                      services: services,
                    );
                  } else if (val == 'sheet') {
                    _showDriverCustodyDetailSheet(
                      driver: driver,
                      unsettledDelivered: unsettledDelivered,
                      activeOrders: activeOrders,
                      deliveredCustodyAmount: deliveredCustodyAmount,
                      inTransitAmount: inTransitAmount,
                      services: services,
                    );
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'sheet',
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded, size: 18, color: PieColors.cashierAccent),
                        const SizedBox(width: 8),
                        Text('عرض كشف حساب العهدة', style: PieTypography.body),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      driver.available ? 'تحويل لوضع الاستراحة' : 'تحويل إلى متاح بالفرع',
                      style: PieTypography.body,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: PieColors.border, height: 1),
          const SizedBox(height: 12),

          // Custody Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: PieColors.surface2,
              borderRadius: PieRadius.borderMd,
              border: Border.all(
                color: hasDeliveredCustody
                    ? PieColors.cashierAccent.withValues(alpha: 0.4)
                    : PieColors.border,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('عهدة محصلة جاهزة للتوريد', style: PieTypography.caption),
                      const SizedBox(height: 2),
                      PieNumeral.money(
                        deliveredCustodyAmount,
                        style: PieTypography.monoHeading.copyWith(
                          color: hasDeliveredCustody ? PieColors.cashierAccent : PieColors.inkMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 32, color: PieColors.border),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('قيد التحصيل في الطريق', style: PieTypography.caption),
                      const SizedBox(height: 2),
                      PieNumeral.money(
                        inTransitAmount,
                        style: PieTypography.monoHeading.copyWith(
                          color: inTransitAmount > 0 ? PieColors.driverAccent : PieColors.inkMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 32, color: PieColors.border),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('إجمالي ما بالذمة', style: PieTypography.caption),
                      const SizedBox(height: 2),
                      PieNumeral.money(
                        totalDriverCustody,
                        style: PieTypography.monoHeading.copyWith(
                          color: totalDriverCustody > 0 ? PieColors.ink : PieColors.inkMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Itemized Unreturned Orders Breakdown Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'تفاصيل الأوردرات طرف الكابتن (${allUnreturnedOrders.length}):',
                  style: PieTypography.bodyStrong.copyWith(color: PieColors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (allUnreturnedOrders.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _showDriverCustodyDetailSheet(
                    driver: driver,
                    unsettledDelivered: unsettledDelivered,
                    activeOrders: activeOrders,
                    deliveredCustodyAmount: deliveredCustodyAmount,
                    inTransitAmount: inTransitAmount,
                    services: services,
                  ),
                  icon: const Icon(Icons.fullscreen_rounded, size: 16, color: PieColors.driverAccent),
                  label: Text('كشف مفصل', style: PieTypography.caption.copyWith(color: PieColors.driverAccent)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Unsettled Delivered Orders (Delivered, cash with driver)
          if (unsettledDelivered.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF261D08),
                borderRadius: PieRadius.borderSm,
                border: Border.all(color: PieColors.cashierAccent.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 14, color: PieColors.cashierAccent),
                  const SizedBox(width: 6),
                  Text(
                    'أوردرات تم تسليمها للعميل والكاش لم يُورّد للخزينة (${unsettledDelivered.length})',
                    style: PieTypography.caption.copyWith(
                      color: PieColors.cashierAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            for (final job in unsettledDelivered)
              _buildDetailedOrderCard(
                job: job,
                driver: driver,
                isDelivered: true,
                services: services,
                onSettle: () => _settleSingleOrder(delivery: job, driver: driver, services: services),
              ),
          ],

          // Active In-Transit Orders
          if (activeOrders.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8, top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: PieColors.driverSurface,
                borderRadius: PieRadius.borderSm,
                border: Border.all(color: PieColors.driverBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler_rounded, size: 14, color: PieColors.driverAccent),
                  const SizedBox(width: 6),
                  Text(
                    'أوردرات في الطريق قيد التحصيل (${activeOrders.length})',
                    style: PieTypography.caption.copyWith(
                      color: PieColors.driverAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            for (final job in activeOrders)
              _buildDetailedOrderCard(
                job: job,
                driver: driver,
                isDelivered: false,
                services: services,
              ),
          ],

          // Empty state when driver has 0 unreturned orders
          if (allUnreturnedOrders.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PieColors.surface2,
                borderRadius: PieRadius.borderMd,
                border: Border.all(color: const Color(0xFF052E16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.task_alt_rounded, color: Color(0xFF4ADE80), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'لا توجد أوردرات معلقة طرف الكابتن · كافة المبالغ تم توريدها وتسويتها بالكامل ✅',
                      style: PieTypography.caption.copyWith(color: const Color(0xFF4ADE80)),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 14),
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
                  Text('العهدة الجاهزة للتوريد:', style: PieTypography.caption),
                  const SizedBox(width: 6),
                  PieNumeral.money(
                    deliveredCustodyAmount,
                    style: PieTypography.monoHeading.copyWith(
                      color: deliveredCustodyAmount > 0
                          ? PieColors.cashierAccent
                          : PieColors.inkMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PieButton.secondary(
                    onPressed: () => _showDriverCustodyDetailSheet(
                      driver: driver,
                      unsettledDelivered: unsettledDelivered,
                      activeOrders: activeOrders,
                      deliveredCustodyAmount: deliveredCustodyAmount,
                      inTransitAmount: inTransitAmount,
                      services: services,
                    ),
                    label: 'كشف الحساب',
                    icon: Icons.receipt_long_rounded,
                    height: 36,
                  ),
                  const SizedBox(width: 8),
                  PieButton.primary(
                    onPressed: deliveredCustodyAmount <= 0
                        ? null
                        : () => _settleDriverCustody(
                              driver: driver,
                              custodyAmount: deliveredCustodyAmount,
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
        ],
      ),
    );
  }

  Widget _buildDetailedOrderCard({
    required DeliveryModel job,
    required DriverModel driver,
    required bool isDelivered,
    required AppServices services,
    VoidCallback? onSettle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PieColors.surface2,
        borderRadius: PieRadius.borderMd,
        border: Border.all(
          color: isDelivered ? const Color(0xFFFBBF24).withValues(alpha: 0.4) : PieColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDelivered ? const Color(0xFF2E2405) : PieColors.driverSurface,
                      borderRadius: PieRadius.borderSm,
                      border: Border.all(
                        color: isDelivered ? const Color(0xFFFBBF24) : PieColors.driverBorder,
                      ),
                    ),
                    child: Text(
                      job.orderRef,
                      style: PieTypography.monoCaption.copyWith(
                        color: isDelivered ? const Color(0xFFFBBF24) : PieColors.driverAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDelivered ? const Color(0xFF261D08) : PieColors.surface3,
                      borderRadius: PieRadius.borderSm,
                    ),
                    child: Text(
                      isDelivered ? 'تم التسليم · الكاش باليد' : job.state.label,
                      style: PieTypography.caption.copyWith(
                        color: isDelivered ? const Color(0xFFFBBF24) : PieColors.inkSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              PieNumeral.money(
                job.amount,
                style: PieTypography.monoHeading.copyWith(
                  color: PieColors.cashierAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 14, color: PieColors.inkSecondary),
              const SizedBox(width: 4),
              Text(
                job.customerName?.isNotEmpty == true ? job.customerName! : 'عميل دليفري',
                style: PieTypography.caption.copyWith(color: PieColors.ink, fontWeight: FontWeight.w600),
              ),
              if (job.customerPhone != null && job.customerPhone!.isNotEmpty) ...[
                const SizedBox(width: 10),
                const Icon(Icons.phone_outlined, size: 13, color: PieColors.inkSecondary),
                const SizedBox(width: 4),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    job.customerPhone!,
                    style: PieTypography.monoCaption.copyWith(color: PieColors.inkSecondary),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  icon: const Icon(Icons.call, size: 14, color: PieColors.driverAccent),
                  onPressed: () => _callPhone(job.customerPhone!),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 14, color: PieColors.inkSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  job.address,
                  style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (job.zoneName != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: PieColors.surface3,
                    borderRadius: PieRadius.borderSm,
                  ),
                  child: Text(
                    job.zoneName!,
                    style: PieTypography.caption.copyWith(color: PieColors.inkMuted, fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
          if (isDelivered && onSettle != null) ...[
            const SizedBox(height: 8),
            const Divider(color: PieColors.border, height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'المبلغ المطلوب توريده: ${PieTypography.formatEgp(job.amount)}',
                  style: PieTypography.caption.copyWith(color: const Color(0xFFFBBF24), fontWeight: FontWeight.w600),
                ),
                PieButton.primary(
                  onPressed: onSettle,
                  label: 'توريد هذا الأوردر للخزينة',
                  accentColor: PieColors.cashierAccent,
                  height: 32,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showDriverCustodyDetailSheet({
    required DriverModel driver,
    required List<DeliveryModel> unsettledDelivered,
    required List<DeliveryModel> activeOrders,
    required double deliveredCustodyAmount,
    required double inTransitAmount,
    required AppServices services,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PieColors.surfaceOverlay,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final totalCustody = deliveredCustodyAmount + inTransitAmount;
        final totalCount = unsettledDelivered.length + activeOrders.length;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: PieColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: PieColors.driverSurface,
                              borderRadius: PieRadius.borderMd,
                              border: Border.all(color: PieColors.driverBorder),
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: PieColors.driverAccent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('كشف حساب عهدة الكابتن', style: PieTypography.heading),
                              Text(
                                'الكابتن: ${driver.name} · $totalCount أوردر طرفه',
                                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Summary Cards
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: PieColors.surface2,
                      borderRadius: PieRadius.borderLg,
                      border: Border.all(color: PieColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('عهدة كاش باليد', style: PieTypography.caption),
                              const SizedBox(height: 4),
                              PieNumeral.money(
                                deliveredCustodyAmount,
                                style: PieTypography.monoHeading.copyWith(
                                  color: deliveredCustodyAmount > 0
                                      ? PieColors.cashierAccent
                                      : PieColors.inkMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${unsettledDelivered.length} أوردر تم تسليمهم',
                                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 44, color: PieColors.border),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('في الطريق (تحصيل)', style: PieTypography.caption),
                              const SizedBox(height: 4),
                              PieNumeral.money(
                                inTransitAmount,
                                style: PieTypography.monoHeading.copyWith(
                                  color: inTransitAmount > 0
                                      ? PieColors.driverAccent
                                      : PieColors.inkMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${activeOrders.length} أوردر جاري',
                                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 44, color: PieColors.border),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('إجمالي ما بالذمة', style: PieTypography.caption),
                              const SizedBox(height: 4),
                              PieNumeral.money(
                                totalCustody,
                                style: PieTypography.monoHeading.copyWith(
                                  color: PieColors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'كل ما طرف الكابتن',
                                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Delivered Orders Section
                  if (unsettledDelivered.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 18, color: Color(0xFFFBBF24)),
                        const SizedBox(width: 8),
                        Text(
                          'أوردرات تم تسليمها والفلوس مع الكابتن (${unsettledDelivered.length}):',
                          style: PieTypography.bodyStrong.copyWith(color: const Color(0xFFFBBF24)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final job in unsettledDelivered)
                      _buildDetailedOrderCard(
                        job: job,
                        driver: driver,
                        isDelivered: true,
                        services: services,
                        onSettle: () {
                          Navigator.of(sheetCtx).pop();
                          _settleSingleOrder(delivery: job, driver: driver, services: services);
                        },
                      ),
                    const SizedBox(height: 16),
                  ],

                  // In-Transit Orders Section
                  if (activeOrders.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.two_wheeler_rounded,
                            size: 18, color: PieColors.driverAccent),
                        const SizedBox(width: 8),
                        Text(
                          'أوردرات جارية في الطريق للتسليم (${activeOrders.length}):',
                          style: PieTypography.bodyStrong.copyWith(color: PieColors.driverAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final job in activeOrders)
                      _buildDetailedOrderCard(
                        job: job,
                        driver: driver,
                        isDelivered: false,
                        services: services,
                      ),
                    const SizedBox(height: 16),
                  ],

                  if (unsettledDelivered.isEmpty && activeOrders.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          const Icon(Icons.task_alt_rounded, color: Color(0xFF4ADE80), size: 48),
                          const SizedBox(height: 12),
                          const Text('كافة الحسابات موردة بالكامل', style: PieTypography.subheading),
                          const SizedBox(height: 4),
                          Text(
                            'لا توجد أي أوردرات معلقة أو مبالغ نقدية طرف الكابتن حالياً.',
                            style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),
                  if (deliveredCustodyAmount > 0)
                    PieButton.primary(
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        _settleDriverCustody(
                          driver: driver,
                          custodyAmount: deliveredCustodyAmount,
                          driverDeliveredJobs: unsettledDelivered,
                          services: services,
                        );
                      },
                      label: 'استلام وتوريد كافة العهدة المسلمة (${PieTypography.formatEgp(deliveredCustodyAmount)}) للخزينة',
                      accentColor: PieColors.cashierAccent,
                      icon: Icons.account_balance_wallet_rounded,
                      height: 48,
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
