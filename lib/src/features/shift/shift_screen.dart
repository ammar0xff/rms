import 'dart:async';
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
import '../../domain/models/cash_session.dart';
import '../../domain/models/facility_settings.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_type.dart';
import '../../domain/services/receipt_print_service.dart';
import '../accounting/z_report_screen.dart';
import 'open_shift_dialog.dart';

/// Screen 5: Shift Board (الوردية ولوحة المبيعات اللحظية)
///
/// Functional contract:
/// - Shift state (open / closed) & live elapsed duration
/// - Drawer float vs opening float
/// - Live ticket rail filterable by channel (hall / takeaway / delivery)
/// - Fast path to Cash Count and Z-Close
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  static bool enableTicker = true;

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  OrderType? _selectedChannelFilter;
  Timer? _ticker;
  CashSession? _session;
  double _expectedCash = 0;
  List<Order> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Live elapsed timer ticker (1 second) - disabled in test environments
    if (ShiftScreen.enableTicker) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && (_session?.isOpen ?? false)) {
          if (timer.tick % 3 == 0) {
            _loadData(silent: true);
          } else {
            setState(() {});
          }
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final services = AppScope.of(context);
      final cashSessionsRepo = services.cashSessions;
      final ordersRepo = services.orders;

      var session = await cashSessionsRepo?.currentSession();
      if (session == null && services.firebaseReady && services.inboundSync != null && !silent) {
        try {
          await services.inboundSync!.waitForInitialCollection(
            'cashSessions',
            timeout: const Duration(milliseconds: 1800),
          );
          session = await cashSessionsRepo?.currentSession();
        } catch (_) {}
      }
      double expected = session?.openingFloat ?? 0.0;
      if (session != null && cashSessionsRepo != null) {
        try {
          expected = await cashSessionsRepo.expectedCash(session);
        } catch (_) {
          expected = session.expectedCash ?? session.openingFloat;
        }
      }
      final orders = await ordersRepo?.listOrders() ?? [];
      final currentSession = session;
      final scopedOrders = currentSession == null
          ? <Order>[]
          : orders
              .where((o) =>
                  !o.createdAt.toUtc().isBefore(currentSession.openedAt.toUtc()) &&
                  (currentSession.closedAt == null || !o.createdAt.toUtc().isAfter(currentSession.closedAt!.toUtc())))
              .toList();

      if (mounted) {
        setState(() {
          _session = session;
          _expectedCash = expected;
          _orders = scopedOrders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatElapsed(DateTime openedAt) {
    try {
      final diff = DateTime.now().difference(openedAt);
      if (diff.isNegative) return '00:00:00';
      final hours = diff.inHours.toString().padLeft(2, '0');
      final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
      final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    } catch (_) {
      return '00:00:00';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedChannelFilter == null
        ? _orders
        : _orders.where((o) => o.orderType == _selectedChannelFilter).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Shift State Hero Card
            _buildShiftHeaderCard(_session, _expectedCash),
            const SizedBox(height: 20),

            // Live Ticket Rail Header
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 480;
                final chips = SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildChannelFilterChip(null, 'الكل'),
                      const SizedBox(width: 6),
                      _buildChannelFilterChip(OrderType.takeaway, 'تيك أواي'),
                      const SizedBox(width: 6),
                      _buildChannelFilterChip(OrderType.delivery, 'دليفري'),
                    ],
                  ),
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'تذاكر الأوردرات اللحظية',
                        style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      chips,
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'تذاكر الأوردرات اللحظية',
                      style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 12),
                    Flexible(child: chips),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

            // Live Ticket Rail
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: PieColors.cashierAccent),
                ),
              )
            else if (filtered.isEmpty)
              const PieCard(
                padding: EdgeInsets.all(32),
                child: PieEmptyState(
                  title: 'مفيش أوردرات في الشيفت ده لسه',
                  description: 'كل أوردر يتعمل من شاشة الكاشير هيظهر هنا مباشرة مع حالته.',
                  icon: Icons.receipt_long_outlined,
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final order = filtered[index];
                  return _buildTicketCard(order);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftHeaderCard(CashSession? session, double expectedCashAmount) {
    final isOpen = session?.isOpen ?? false;
    final openedAt = session?.openedAt ?? DateTime.now();
    final rawFloat = session?.openingFloat ?? 0.0;
    final openingFloat = rawFloat.isFinite ? rawFloat : 0.0;
    final rawExpected = session != null ? expectedCashAmount : openingFloat;
    final expectedCash = rawExpected.isFinite ? rawExpected : openingFloat;

    return PieCard(
      padding: const EdgeInsets.all(20),
      surfaceColor: PieColors.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isOpen ? const Color(0xFF4ADE80) : PieColors.stateError,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isOpen ? 'الوردية مفتوحة ومباشرة' : 'الوردية مقفولة',
                        style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (isOpen)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: PieColors.well,
                    borderRadius: PieRadius.borderSm,
                    border: Border.all(color: PieColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 14, color: PieColors.cashierAccent),
                      const SizedBox(width: 6),
                      PieNumeral.time(
                        _formatElapsed(openedAt),
                        style: PieTypography.monoBody.copyWith(
                          color: PieColors.cashierAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (isOpen && session != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (session.cashierName != null && session.cashierName!.isNotEmpty) ...[
                  const Icon(Icons.person_outline_rounded, size: 16, color: PieColors.inkSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'الكاشير المسؤول: ${session.cashierName}',
                    style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                  ),
                  const SizedBox(width: 14),
                ],
                if (session.branchName != null && session.branchName!.isNotEmpty) ...[
                  const Icon(Icons.storefront_outlined, size: 16, color: PieColors.inkSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'الفرع: ${session.branchName}',
                    style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(color: PieColors.border, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('عهدة الافتتاح (Float)', style: PieTypography.caption),
                    const SizedBox(height: 4),
                    PieNumeral.money(
                      openingFloat,
                      style: PieTypography.monoHeading.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: PieColors.border),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الرصيد المحسوب بالدرج', style: PieTypography.caption),
                    const SizedBox(height: 4),
                    PieNumeral.money(
                      expectedCash,
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
          const SizedBox(height: 18),
          if (isOpen)
            PieButton.primary(
              onPressed: () {
                PieSoundService.instance.click();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ZReportScreen(),
                  ),
                ).then((_) => _loadData());
              },
              label: 'جرد الكاش وتقفيل الوردية (Z-Report)',
              icon: Icons.point_of_sale_rounded,
              accentColor: PieColors.cashierAccent,
            )
          else
            PieButton.primary(
              onPressed: _showOpenShiftDialog,
              label: 'فتح وردية جديدة وتعيين العهدة',
              icon: Icons.lock_open_rounded,
              accentColor: PieColors.stateSynced,
            ),
          const SizedBox(height: 10),
          PieButton.secondary(
            onPressed: _showShiftHistorySheet,
            label: 'سجل الورديات السابقة وتقارير Z',
            icon: Icons.history_rounded,
            height: 44,
          ),
        ],
      ),
    );
  }

  Future<void> _showOpenShiftDialog() async {
    final session = await OpenShiftDialog.show(context);
    if (session != null && mounted) {
      await _loadData();
    }
  }

  Future<void> _showShiftHistorySheet() async {
    final services = AppScope.of(context);
    final repo = services.cashSessions;
    final facility = await services.facility?.load() ?? const FacilitySettings();
    if (repo == null) return;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PieColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PieRadius.lg)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return FutureBuilder<List<CashSession>>(
              future: repo.listSessions(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: PieColors.cashierAccent),
                  );
                }

                final sessions = (snapshot.data ?? [])
                  ..sort((a, b) => b.openedAt.compareTo(a.openedAt));

                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: PieColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.history_rounded, color: PieColors.cashierAccent),
                              const SizedBox(width: 8),
                              Text('سجل الورديات السابقة', style: PieTypography.heading),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: PieColors.border, height: 1),
                    if (sessions.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text('لا توجد ورديات مسجلة حتى الآن'),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: sessions.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final s = sessions[index];
                            final isItemOpen = s.isOpen;
                            final openedStr =
                                '${s.openedAt.year}-${s.openedAt.month.toString().padLeft(2, '0')}-${s.openedAt.day.toString().padLeft(2, '0')} ${s.openedAt.hour.toString().padLeft(2, '0')}:${s.openedAt.minute.toString().padLeft(2, '0')}';
                            final closedStr = s.closedAt != null
                                ? '${s.closedAt!.year}-${s.closedAt!.month.toString().padLeft(2, '0')}-${s.closedAt!.day.toString().padLeft(2, '0')} ${s.closedAt!.hour.toString().padLeft(2, '0')}:${s.closedAt!.minute.toString().padLeft(2, '0')}'
                                : 'مفتوحة حالياً';

                            final exp = s.expectedCash ?? s.openingFloat;
                            final cnt = s.countedCash ?? exp;
                            final vr = s.variance ?? (cnt - exp);

                            return PieCard(
                              padding: const EdgeInsets.all(14),
                              surfaceColor: PieColors.surface2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'وردية #${s.id}',
                                        style: PieTypography.bodyStrong.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isItemOpen
                                              ? const Color(0xFF14532D)
                                              : PieColors.surfaceOverlay,
                                          borderRadius: PieRadius.borderSm,
                                        ),
                                        child: Text(
                                          isItemOpen ? 'نشطة الآن' : 'مقفلة',
                                          style: PieTypography.caption.copyWith(
                                            color: isItemOpen
                                                ? const Color(0xFF4ADE80)
                                                : PieColors.inkSecondary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      if (s.cashierName != null && s.cashierName!.isNotEmpty) ...[
                                        Text('الكاشير: ${s.cashierName} • ', style: PieTypography.caption),
                                      ],
                                      if (s.branchName != null && s.branchName!.isNotEmpty) ...[
                                        Text('فرع: ${s.branchName} • ', style: PieTypography.caption),
                                      ],
                                      Expanded(
                                        child: Text(
                                          'من: $openedStr إلى: $closedStr',
                                          style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const Divider(color: PieColors.border, height: 1),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('عهدة الافتتاح', style: PieTypography.caption),
                                          PieNumeral.money(s.openingFloat, style: PieTypography.monoBody),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('المجرود فعلياً', style: PieTypography.caption),
                                          PieNumeral.money(cnt, style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('الفارق', style: PieTypography.caption),
                                          Text(
                                            vr == 0
                                                ? 'مطابق (0.00)'
                                                : (vr > 0 ? '+${vr.toStringAsFixed(2)}' : vr.toStringAsFixed(2)),
                                            style: PieTypography.monoBody.copyWith(
                                              color: vr == 0
                                                  ? const Color(0xFF4ADE80)
                                                  : (vr > 0 ? const Color(0xFF4ADE80) : PieColors.stateError),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: PieButton.secondary(
                                          onPressed: () {
                                            ReceiptPrintService.printZReport(
                                              session: s,
                                              facility: facility,
                                              expectedCash: exp,
                                              countedCash: cnt,
                                              variance: vr,
                                              cashierName: s.cashierName,
                                              isXReport: isItemOpen,
                                            );
                                          },
                                          label: isItemOpen ? 'طباعة تقرير X' : 'طباعة تقرير Z',
                                          icon: Icons.print_rounded,
                                          height: 38,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        height: 38,
                                        width: 38,
                                        decoration: BoxDecoration(
                                          color: PieColors.surface1,
                                          borderRadius: PieRadius.borderMd,
                                          border: Border.all(color: PieColors.border),
                                        ),
                                        child: IconButton(
                                          icon: const Icon(Icons.open_in_new_rounded, size: 18, color: PieColors.inkSecondary),
                                          tooltip: 'فتح في نافذة مستقلة',
                                          onPressed: () {
                                            ReceiptPrintService.openZReportInTab(
                                              session: s,
                                              facility: facility,
                                              expectedCash: exp,
                                              countedCash: cnt,
                                              variance: vr,
                                              cashierName: s.cashierName,
                                              isXReport: isItemOpen,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildChannelFilterChip(OrderType? type, String label) {
    final isSelected = _selectedChannelFilter == type;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      backgroundColor: PieColors.surface1,
      selectedColor: PieColors.cashierSurface,
      side: BorderSide(
        color: isSelected ? PieColors.cashierAccent : PieColors.border,
      ),
      labelStyle: PieTypography.caption.copyWith(
        color: isSelected ? PieColors.cashierAccent : PieColors.inkSecondary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      onSelected: (_) => setState(() => _selectedChannelFilter = type),
    );
  }

  Widget _buildTicketCard(Order order) {
    final ref = (order.canonicalOrderNumber?.isNotEmpty == true)
        ? order.canonicalOrderNumber!
        : (order.provisionalOrderNumber.isNotEmpty ? order.provisionalOrderNumber : order.localId);
    final safeTotal = order.total.isFinite ? order.total : 0.0;
    final hour = order.createdAt.hour.toString().padLeft(2, '0');
    final minute = order.createdAt.minute.toString().padLeft(2, '0');
    final itemsText = order.items.isEmpty
        ? 'أوردر بدون أصناف'
        : order.items.map((i) => '${i.quantity}x ${i.name}').join(', ');

    return PieCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'أوردر #$ref',
                        style: PieTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    PieBadge.channel(order.orderType),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PieBadge.syncStatus(
                isSynced: order.syncStatus.name == 'synced',
                isPending: order.syncStatus.name == 'pendingSync' || order.syncStatus.name == 'localOnly',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            itemsText,
            style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$hour:$minute',
                style: PieTypography.monoCaption,
              ),
              PieNumeral.money(
                safeTotal,
                style: PieTypography.monoBody.copyWith(
                  fontWeight: FontWeight.w700,
                  color: PieColors.cashierAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
