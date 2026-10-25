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
import '../shift/open_shift_dialog.dart';

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
  // Post-close retained state for reprint preservation
  CashSession? _lastClosedSession;
  double _lastExpectedCash = 0.0;
  double _lastCountedCash = 0.0;
  double _lastVariance = 0.0;

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
    bool isXReport = false,
  }) async {
    final services = AppScope.of(context);
    final facility = await services.facility?.load() ?? const FacilitySettings();
    final user = services.auth.currentUser;
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
        isXReport: isXReport,
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: PieColors.surface2,
            content: Text(
              isXReport
                  ? 'جاري إرسال أمر طباعة تقرير القراءة المؤقتة X...'
                  : 'جاري إرسال أمر طباعة تقرير تقفيل الوردية Z...',
            ),
            duration: const Duration(seconds: 2),
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
        isXReport: isXReport,
      );
    }
  }

  Future<({CashSession? session, double expectedCash})> _loadSessionData(AppServices services) async {
    final session = await services.cashSessions?.currentSession();
    if (session == null) {
      return (session: null, expectedCash: 0.0);
    }
    double expected = session.openingFloat;
    try {
      expected = await services.cashSessions?.expectedCash(session) ?? session.openingFloat;
    } catch (_) {
      expected = session.openingFloat;
    }
    return (session: session, expectedCash: expected);
  }

  Future<void> _performZClose(CashSession session, [double? preloadedExpectedCash]) async {
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
      double expectedCash = preloadedExpectedCash ?? session.openingFloat;
      try {
        expectedCash = await services.cashSessions?.expectedCash(session) ?? expectedCash;
      } catch (_) {
        expectedCash = preloadedExpectedCash ?? session.expectedCash ?? session.openingFloat;
      }
      final variance = countedCash - expectedCash;

      final user = services.auth.currentUser;
      final cashierName = (user?.displayName != null && user!.displayName!.isNotEmpty)
          ? user.displayName
          : (user?.email?.split('@').first ?? 'الكاشير');

      final closedSession = session.copyWith(
        status: CashSessionStatus.closed,
        closedAt: DateTime.now(),
        countedCash: countedCash,
        expectedCash: expectedCash,
        cashierUid: user?.uid,
        cashierName: cashierName,
      );

      setState(() {
        _lastClosedSession = closedSession;
        _lastExpectedCash = expectedCash;
        _lastCountedCash = countedCash;
        _lastVariance = variance;
      });

      await services.cashSessions?.closeSession(
        session.id,
        countedCash: countedCash,
        cashierUid: user?.uid,
        cashierName: cashierName,
      );

      // Print Z-report slip immediately
      await _printZReport(closedSession, expectedCash, countedCash, variance, isXReport: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: PieColors.surface2,
            content: Text('تم تقفيل الوردية وتسجيل تقرير Z وطباعته بنجاح'),
          ),
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final canPop = Navigator.of(context).canPop();

    final content = Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<({CashSession? session, double expectedCash})>(
        future: _loadSessionData(services),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: PieColors.cashierAccent),
            );
          }
          final data = snapshot.data;
          final session = data?.session;

          // If no active session, but we just closed one in this screen, show post-close view!
          if (session == null && _lastClosedSession != null) {
            return _buildPostCloseSuccessView(_lastClosedSession!);
          }

          if (session == null && snapshot.connectionState == ConnectionState.done) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: PieCard(
                  padding: const EdgeInsets.all(24),
                  surfaceColor: PieColors.surface2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 48, color: PieColors.inkSecondary),
                      const SizedBox(height: 16),
                      Text('لا توجد وردية مفتوحة حالياً', style: PieTypography.heading),
                      const SizedBox(height: 8),
                      Text(
                        'لتقفيل الوردية وجرد الدرج، يجب أولاً فتح وردية نشطة من شاشة الورديات.',
                        style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          PieButton.primary(
                            onPressed: () async {
                              final session = await OpenShiftDialog.show(context);
                              if (session != null && mounted) {
                                setState(() {});
                              }
                            },
                            label: 'فتح وردية جديدة الآن',
                            icon: Icons.lock_open_rounded,
                            accentColor: PieColors.stateSynced,
                          ),
                          if (Navigator.of(context).canPop())
                            PieButton.secondary(
                              onPressed: () => Navigator.of(context).pop(),
                              label: 'الرجوع',
                              icon: Icons.arrow_back_rounded,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final expectedCash = data?.expectedCash ?? session?.expectedCash ?? session?.openingFloat ?? 0.0;
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

    if (canPop) {
      return Scaffold(
        backgroundColor: PieColors.canvas,
        appBar: AppBar(
          backgroundColor: PieColors.surface1,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: PieColors.ink),
            tooltip: 'الرجوع',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'تقفيل الوردية وجرد الكاش (Z-Report)',
            style: PieTypography.subheading.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        body: content,
      );
    }

    return content;
  }

  Widget _buildPostCloseSuccessView(CashSession session) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: PieCard(
            padding: const EdgeInsets.all(24),
            surfaceColor: PieColors.surface2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: Icon(Icons.check_circle_rounded, size: 54, color: Color(0xFF10B981)),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text('تم تقفيل الوردية بنجاح (Z-Close)', style: PieTypography.heading),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'معرف الوردية: #${session.id}${session.branchName != null ? ' • فرع ${session.branchName}' : ''}',
                    style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: PieColors.border),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'الرصيد الافتتاحي (عهدة الدرج):',
                        style: PieTypography.body,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PieNumeral.money(session.openingFloat, style: PieTypography.monoBody),
                  ],
                ),
                const SizedBox(height: 8),
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
                    PieNumeral.money(_lastExpectedCash, style: PieTypography.monoBody),
                  ],
                ),
                const SizedBox(height: 8),
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
                      _lastCountedCash,
                      style: PieTypography.monoHeading.copyWith(
                        color: PieColors.cashierAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PieColors.surface1,
                    borderRadius: PieRadius.borderMd,
                    border: Border.all(color: PieColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'الفارق النهائي:',
                          style: PieTypography.bodyStrong,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: _lastVariance == 0
                            ? Text(
                                'مطابق تماماً (0.00)',
                                style: PieTypography.monoBody.copyWith(
                                  color: const Color(0xFF10B981),
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              )
                            : (_lastVariance > 0
                                ? PieNumeral.money(
                                    _lastVariance,
                                    prefix: 'زيادة: +',
                                    style: PieTypography.monoBody.copyWith(
                                      color: const Color(0xFF10B981),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : PieNumeral.money(
                                    _lastVariance.abs(),
                                    prefix: 'عجز: -',
                                    style: PieTypography.monoBody.copyWith(
                                      color: PieColors.stateError,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: PieButton.primary(
                        onPressed: () => _printZReport(
                          session,
                          _lastExpectedCash,
                          _lastCountedCash,
                          _lastVariance,
                          isXReport: false,
                        ),
                        label: 'إعادة طباعة تقرير Z',
                        icon: Icons.print_rounded,
                        accentColor: PieColors.cashierAccent,
                        height: 48,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: PieColors.surface1,
                        borderRadius: PieRadius.borderMd,
                        border: Border.all(color: PieColors.border),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, color: PieColors.inkSecondary),
                        tooltip: 'فتح في نافذة مستقلة',
                        onPressed: () => _printZReport(
                          session,
                          _lastExpectedCash,
                          _lastCountedCash,
                          _lastVariance,
                          inTab: true,
                          isXReport: false,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PieButton.secondary(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() {
                        _lastClosedSession = null;
                      });
                    }
                  },
                  label: 'إغلاق والعودة',
                  icon: Icons.close_rounded,
                  height: 44,
                ),
              ],
            ),
          ),
        ),
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
                    : () => _printZReport(session, expectedCash, countedCash, variance, isXReport: true),
                label: 'طباعة قراءة مؤقتة (X-Report)',
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
                tooltip: 'فتح القراءة المؤقتة X في نافذة مستقلة',
                onPressed: session == null
                    ? null
                    : () => _printZReport(session, expectedCash, countedCash, variance, inTab: true, isXReport: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        PieButton.primary(
          onPressed: session == null ? null : () => _performZClose(session, expectedCash),
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
