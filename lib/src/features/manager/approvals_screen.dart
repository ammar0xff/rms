import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/approval_request.dart';
import 'pin_delegation_dialog.dart';

/// Screen 17: Approvals Centre (مركز الموافقات والاعتمادات الإدارية)
///
/// Functional contract:
/// - Typed financial requests (refund, discount, petty cash, void, adjustment)
/// - Amount hero, age, requester, and reason
/// - PIN-gated approval action
/// - Rejection action with mandatory note
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  ApprovalKind? _selectedKind;

  Future<void> _approve(ApprovalRequest req) async {
    final verified = await PinDelegationDialog.verify(
      context,
      title: 'اعتماد ${req.kind.label}',
    );

    if (verified && mounted) {
      final services = AppScope.of(context);
      final managerName = services.isDemo
          ? 'المدير العام'
          : (services.auth.currentUser?.displayName ??
              services.auth.currentUser?.email?.split('@').first ??
              'المدير العام');
      await services.approvals?.decide(
        req.id,
        approved: true,
        decidedBy: managerName,
        note: 'تم الاعتماد بنجاح',
      );

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: PieColors.surface2,
            content: Text(
              'تم اعتماد ${req.kind.label} لمبلغ ${PieTypography.formatEgp(req.amount)}',
              style: PieTypography.body.copyWith(color: const Color(0xFF4ADE80)),
            ),
          ),
        );
      }
    }
  }

  Future<void> _reject(ApprovalRequest req) async {
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          title: Text('رفض ${req.kind.label}', style: PieTypography.heading),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'اكتب سبب رفض الطلب ليتم إبلاغ الكاشير بالسبب:',
                style: PieTypography.body,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'سبب الرفض (إلزامي)',
                  hintText: 'مثلاً: غير مطابق لسياسة الاسترجاع...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('إلغاء', style: PieTypography.body.copyWith(color: PieColors.inkSecondary)),
            ),
            PieButton.destructive(
              onPressed: () {
                if (noteController.text.trim().isNotEmpty) {
                  Navigator.of(context).pop(true);
                }
              },
              label: 'أكّد الرفض',
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      final services = AppScope.of(context);
      final managerName = services.auth.currentUser?.displayName ??
          services.auth.currentUser?.email?.split('@').first ??
          'المدير العام';
      await services.approvals?.decide(
        req.id,
        approved: false,
        decidedBy: managerName,
        note: noteController.text.trim(),
      );

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: PieColors.surface2,
            content: Text(
              'تم رفض الطلب وتسجيل السبب',
              style: PieTypography.body.copyWith(color: PieColors.stateError),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final approvalsRepo = services.approvals;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<List<ApprovalRequest>>(
          future: approvalsRepo?.listRequests(),
          builder: (context, snapshot) {
            final allRequests = snapshot.data ?? [];
            final pendingRequests = allRequests.where((r) => r.isPending).toList();

            var filtered = pendingRequests;
            if (_selectedKind != null) {
              filtered = filtered.where((r) => r.kind == _selectedKind).toList();
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Top Pending Hero Bar
                PieCard(
                  padding: const EdgeInsets.all(16),
                  surfaceColor: PieColors.surface2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('طلبات معلقة بالانتظار', style: PieTypography.subheading),
                          const SizedBox(height: 2),
                          Text(
                            'الموافقات المعلقة تتطلب تفويض الـ PIN',
                            style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: pendingRequests.isEmpty
                              ? const Color(0xFF052E16)
                              : PieColors.managerSurface,
                          borderRadius: PieRadius.borderSm,
                          border: Border.all(
                            color: pendingRequests.isEmpty
                                ? const Color(0xFF4ADE80)
                                : PieColors.managerAccent,
                          ),
                        ),
                        child: Text(
                          '${pendingRequests.length} طلبات',
                          style: PieTypography.bodyStrong.copyWith(
                            color: pendingRequests.isEmpty
                                ? PieColors.stateSynced
                                : PieColors.managerAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Filter by Kind
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildKindChip(null, 'الكل (${pendingRequests.length})'),
                      const SizedBox(width: 6),
                      _buildKindChip(ApprovalKind.voidOrder, 'إلغاء فاتورة'),
                      const SizedBox(width: 6),
                      _buildKindChip(ApprovalKind.refund, 'استرجاع'),
                      const SizedBox(width: 6),
                      _buildKindChip(ApprovalKind.discount, 'خصومات'),
                      const SizedBox(width: 6),
                      _buildKindChip(ApprovalKind.pettyCash, 'نثريات'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (filtered.isEmpty)
                  const PieCard(
                    padding: EdgeInsets.all(32),
                    child: PieEmptyState(
                      title: 'مفيش طلبات معلقة للاعتماد',
                      description: 'جميع طلبات الإلغاء والاسترجاع والخصم تم البت فيها.',
                      icon: Icons.verified_user_outlined,
                    ),
                  )
                else
                  for (final req in filtered) ...[
                    _buildApprovalCard(req),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
        ),
    );
  }

  Widget _buildKindChip(ApprovalKind? kind, String label) {
    final isSelected = _selectedKind == kind;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      backgroundColor: PieColors.surface1,
      selectedColor: PieColors.managerSurface,
      side: BorderSide(
        color: isSelected ? PieColors.managerAccent : PieColors.border,
      ),
      labelStyle: PieTypography.caption.copyWith(
        color: isSelected ? PieColors.managerAccent : PieColors.inkSecondary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      onSelected: (_) => setState(() => _selectedKind = kind),
    );
  }

  Widget _buildApprovalCard(ApprovalRequest req) {
    final ageMinutes = DateTime.now().difference(req.requestedAt).inMinutes;

    return PieCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: PieColors.surface2,
                  borderRadius: PieRadius.borderSm,
                  border: Border.all(color: PieColors.border),
                ),
                child: Text(
                  req.kind.label,
                  style: PieTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: PieColors.managerAccent,
                  ),
                ),
              ),
              Text(
                'منذ $ageMinutes دقيقة',
                style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المبلغ المطلوب:',
                    style: PieTypography.caption,
                  ),
                  const SizedBox(height: 2),
                  PieNumeral.money(
                    req.amount,
                    style: PieTypography.monoDisplay.copyWith(
                      color: PieColors.managerAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('مقدم الطلب: ${req.requestedBy}', style: PieTypography.caption),
                  const SizedBox(height: 2),
                  Text('مرجع: #${req.orderRef}', style: PieTypography.monoCaption),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: PieColors.well,
              borderRadius: PieRadius.borderSm,
              border: Border.all(color: PieColors.border),
            ),
            child: Text(
              'السبب: ${req.reason}',
              style: PieTypography.body.copyWith(fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PieButton.primary(
                  onPressed: () => _approve(req),
                  label: 'اعتماد بـ PIN',
                  icon: Icons.check_rounded,
                  accentColor: PieColors.managerAccent,
                  height: 44,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PieButton.destructive(
                  onPressed: () => _reject(req),
                  label: 'رفض الطلب',
                  icon: Icons.close_rounded,
                  height: 44,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
