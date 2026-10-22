import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/cash_session.dart';
import '../../domain/models/facility_settings.dart';
import '../../domain/services/receipt_print_service.dart';

/// Screen 6: Cash Count & Z-Close Report (جرد الكاش وتقفيل الوردية)
///
/// Functional contract:
/// - Egyptian banknote denomination steppers (200, 100, 50, 20, 10, 5, coins)
/// - Counted vs Expected cash comparison
/// - Plain surplus or shortage calculation
/// - Explicit Z-Close confirmation
class ZReportScreen extends StatefulWidget {
  const ZReportScreen({super.key});

  @override
  State<ZReportScreen> createState() => _ZReportScreenState();
}

class _ZReportScreenState extends State<ZReportScreen> {
  // Egyptian denominations count
  final Map<int, int> _counts = {
    200: 0,
    100: 0,
    50: 0,
    20: 0,
    10: 0,
    5: 0,
    1: 0, // coins
  };

  double get _totalCounted {
    double sum = 0;
    _counts.forEach((denom, count) {
      sum += denom * count;
    });
    return sum;
  }

  void _increment(int denom) {
    setState(() => _counts[denom] = (_counts[denom] ?? 0) + 1);
  }

  void _decrement(int denom) {
    if ((_counts[denom] ?? 0) > 0) {
      setState(() => _counts[denom] = _counts[denom]! - 1);
    }
  }

  Future<void> _printZReport(
    CashSession session,
    double expectedCash,
    double countedCash,
    double variance, {
    bool inTab = false,
  }) async {
    final services = AppScope.of(context);
    final facility = await services.facility?.load() ?? const FacilitySettings();
    final user = services.auth?.currentUser;
    final cashierName = user?.displayName ?? user?.email ?? 'الكاشير';

    if (inTab) {
      ReceiptPrintService.openZReportInTab(
        session: session,
        facility: facility,
        expectedCash: expectedCash,
        countedCash: countedCash,
        variance: variance,
        counts: _counts,
        cashierName: cashierName,
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: PieColors.surface2,
            content: Text('جاري إرسال أمر طباعة تقرير تقفيل الوردية Z...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      await ReceiptPrintService.printZReport(
        session: session,
        facility: facility,
        expectedCash: expectedCash,
        countedCash: countedCash,
        variance: variance,
        counts: _counts,
        cashierName: cashierName,
      );
    }
  }

  Future<void> _performZClose(CashSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          title: Text('تأكيد تقفيل الوردية (Z-Close)', style: PieTypography.heading),
          content: Text(
            'هل أنت متأكد من إنهاء الوردية وتقفيل الدرج؟ العملية دي نهائية ومفيش رجوع فيها.',
            style: PieTypography.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('إلغاء', style: PieTypography.body.copyWith(color: PieColors.inkSecondary)),
            ),
            PieButton.primary(
              onPressed: () => Navigator.of(context).pop(true),
              label: 'أكّد التقفيل',
              accentColor: PieColors.cashierAccent,
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      final services = AppScope.of(context);
      final countedCash = _totalCounted;
      final expectedCash = session.expectedCash ?? 500.0;
      final variance = countedCash - expectedCash;

      await services.cashSessions?.closeSession(
        session.id,
        countedCash: countedCash,
      );

      // Print Z-report slip immediately
      await _printZReport(session, expectedCash, countedCash, variance);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: PieColors.surface2,
            content: Text('تم تقفيل الوردية وتسجيل تقرير Z وطباعته بنجاح'),
          ),
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          setState(() {});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<CashSession?>(
        future: services.cashSessions?.currentSession(),
        builder: (context, snapshot) {
          final session = snapshot.data;
          final expectedCash = session?.expectedCash ?? 500.0;
          final countedCash = _totalCounted;
          final variance = countedCash - expectedCash;

          if (isDesktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Denomination Steppers List (Right side)
                Expanded(
                  flex: 6,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: _buildDenominationsList(),
                  ),
                ),
                // Summary & Z-Report Panel (Left side)
                Container(
                  width: 420,
                  decoration: const BoxDecoration(
                    color: PieColors.surface1,
                    border: Border(right: BorderSide(color: PieColors.border, width: 1)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildSummaryColumn(session, expectedCash, countedCash, variance),
                  ),
                ),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSummaryColumn(session, expectedCash, countedCash, variance),
              const SizedBox(height: 20),
              Text(
                'فئات النقدية بالدرج',
                style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _buildDenominationsList(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryColumn(
    CashSession? session,
    double expectedCash,
    double countedCash,
    double variance,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PieCard(
          padding: const EdgeInsets.all(18),
          surfaceColor: PieColors.surface2,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'الرصيد المحسوب بالدفتر:',
                      style: PieTypography.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  PieNumeral.money(
                    expectedCash,
                    style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'الرصيد الفعلي المجرود:',
                      style: PieTypography.bodyStrong,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  PieNumeral.money(
                    countedCash,
                    style: PieTypography.monoHeading.copyWith(
                      color: PieColors.cashierAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Divider(color: PieColors.border, height: 20),
              // Variance Callout
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'الفارق (العجز / الزيادة):',
                      style: PieTypography.bodyStrong,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: variance == 0
                        ? Text(
                            'مطابق تماماً (0.00)',
                            style: PieTypography.monoBody.copyWith(
                              color: const Color(0xFF4ADE80),
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          )
                        : (variance > 0
                            ? PieNumeral.money(
                                variance,
                                prefix: 'زيادة: +',
                                style: PieTypography.monoBody.copyWith(
                                  color: const Color(0xFF4ADE80),
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : PieNumeral.money(
                                variance.abs(),
                                prefix: 'عجز: -',
                                style: PieTypography.monoBody.copyWith(
                                  color: PieColors.stateError,
                                  fontWeight: FontWeight.w700,
                                ),
                              )),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: PieButton.secondary(
                onPressed: session == null
                    ? null
                    : () => _printZReport(session, expectedCash, countedCash, variance),
                label: 'طباعة تقرير Z',
                icon: Icons.print_rounded,
                height: 48,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: PieColors.surface2,
                borderRadius: PieRadius.borderMd,
                border: Border.all(color: PieColors.border),
              ),
              child: IconButton(
                icon: const Icon(Icons.open_in_new_rounded, color: PieColors.inkSecondary),
                tooltip: 'فتح تقرير Z في نافذة مستقلة للطباعة',
                onPressed: session == null
                    ? null
                    : () => _printZReport(session, expectedCash, countedCash, variance, inTab: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        PieButton.primary(
          onPressed: session == null ? null : () => _performZClose(session),
          label: 'إتمام تقفيل الوردية Z-Close',
          icon: Icons.lock_clock_rounded,
          accentColor: PieColors.cashierAccent,
          height: 52,
        ),
      ],
    );
  }

  Widget _buildDenominationsList() {
    final denoms = [200, 100, 50, 20, 10, 5, 1];

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: denoms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final denom = denoms[index];
        final count = _counts[denom] ?? 0;
        final subtotal = denom * count;
        final label = denom == 1 ? 'فكة / عملات معدنية' : 'ورقة $denom ج.م';

        return PieCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: PieColors.surface2,
                  borderRadius: PieRadius.borderMd,
                  border: Border.all(color: PieColors.border),
                ),
                alignment: Alignment.center,
                child: Text(
                  denom == 1 ? '1' : '$denom',
                  style: PieTypography.monoHeading.copyWith(
                    color: PieColors.cashierAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: PieTypography.bodyStrong),
                    const SizedBox(height: 2),
                    PieNumeral.money(
                      subtotal,
                      style: PieTypography.monoCaption.copyWith(color: PieColors.cashierAccent),
                    ),
                  ],
                ),
              ),
              // Stepper Capsule
              Container(
                decoration: BoxDecoration(
                  color: PieColors.surface2,
                  borderRadius: PieRadius.borderMd,
                  border: Border.all(color: PieColors.border, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      color: count > 0 ? PieColors.inkSecondary : PieColors.inkMuted,
                      onPressed: count > 0 ? () => _decrement(denom) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    Container(
                      width: 36,
                      alignment: Alignment.center,
                      child: PieNumeral.count(
                        count,
                        style: PieTypography.monoHeading.copyWith(
                          fontWeight: FontWeight.w700,
                          color: count > 0 ? PieColors.cashierAccent : PieColors.inkSecondary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      color: PieColors.cashierAccent,
                      onPressed: () => _increment(denom),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
