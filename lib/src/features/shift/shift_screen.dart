import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/cash_session.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_type.dart';
import '../accounting/z_report_screen.dart';

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
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData() async {
    final services = AppScope.of(context);
    final cashSessionsRepo = services.cashSessions;
    final ordersRepo = services.orders;

    final session = await cashSessionsRepo?.currentSession();
    double expected = session?.openingFloat ?? 500.0;
    if (session != null && cashSessionsRepo != null) {
      try {
        expected = await cashSessionsRepo.expectedCash(session);
      } catch (_) {
        expected = session.expectedCash ?? session.openingFloat;
      }
    }
    final orders = await ordersRepo?.listOrders() ?? [];

    if (mounted) {
      setState(() {
        _session = session;
        _expectedCash = expected;
        _orders = orders;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatElapsed(DateTime openedAt) {
    final diff = DateTime.now().difference(openedAt);
    final hours = diff.inHours.toString().padLeft(2, '0');
    final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
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
                    chips,
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
    final openingFloat = session?.openingFloat ?? 500.0;
    final expectedCash = session != null ? expectedCashAmount : openingFloat;

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
                    borderRadius: BorderRadius.circular(6),
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
        ],
      ),
    );
  }

  Future<void> _showOpenShiftDialog() async {
    PieSoundService.instance.click();
    final ctrl = TextEditingController(text: '500');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: PieColors.border),
          ),
          title: Row(
            children: [
              const Icon(Icons.lock_open_rounded, color: PieColors.stateSynced, size: 22),
              const SizedBox(width: 10),
              Text('افتتاح وردية جديدة', style: PieTypography.heading),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'أدخل مبلغ العهدة الافتتاحية في درج الكاشير للبدء بالبيع:',
                style: PieTypography.body,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: PieTypography.monoHeading.copyWith(color: PieColors.cashierAccent),
                decoration: const InputDecoration(
                  labelText: 'عهدة الافتتاح (Float)',
                  suffixText: 'ج.م',
                  filled: true,
                  fillColor: PieColors.well,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [200, 500, 1000].map((amt) {
                  return ActionChip(
                    label: Text('+$amt ج.م'),
                    backgroundColor: PieColors.surface2,
                    side: const BorderSide(color: PieColors.border),
                    onPressed: () {
                      ctrl.text = amt.toString();
                      PieSoundService.instance.click();
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: PieColors.cashierAccent,
                foregroundColor: const Color(0xFF0F1117),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('فتح الوردية الآن'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final float = double.tryParse(ctrl.text.trim()) ?? 500.0;
      final services = AppScope.of(context);
      await services.cashSessions?.openSession(openingFloat: float);
      PieSoundService.instance.chime();
      await _loadData();
    }
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
    return PieCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'أوردر #${order.canonicalOrderNumber ?? order.provisionalOrderNumber}',
                    style: PieTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  PieBadge.channel(order.orderType),
                ],
              ),
              PieBadge.syncStatus(
                isSynced: order.syncStatus.name == 'synced',
                isPending: order.syncStatus.name == 'pendingSync' || order.syncStatus.name == 'localOnly',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            order.items.map((i) => '${i.quantity}x ${i.name}').join(', '),
            style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}',
                style: PieTypography.monoCaption,
              ),
              PieNumeral.money(
                order.total,
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
