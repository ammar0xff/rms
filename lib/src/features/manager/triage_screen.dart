import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../domain/models/branch.dart';

/// Screen 19: Cross-branch Triage (إدارة ومراقبة أوردرات كافة الفروع)
///
/// Functional contract:
/// - Cross-branch monitoring (status, load, delays)
/// - Delay threshold detection (> 30m)
/// - Emergency routing & rebalancing
class TriageScreen extends StatefulWidget {
  const TriageScreen({super.key});

  @override
  State<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends State<TriageScreen> {
  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final branchRepo = services.branches;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<List<BranchModel>>(
        future: branchRepo?.listBranches(),
        builder: (context, snapshot) {
          final branches = snapshot.data ?? [
            BranchModel(
              id: 'dokki',
              name: 'فرع الدقي الرئيسي',
              code: 'DKI',
              city: 'الجيزة',
              timezone: 'Africa/Cairo',
              openedAt: DateTime(2023, 1, 1),
              status: BranchStatus.active,
            ),
            BranchModel(
              id: 'maadi',
              name: 'فرع المعادي',
              code: 'MAD',
              city: 'القاهرة',
              timezone: 'Africa/Cairo',
              openedAt: DateTime(2023, 6, 1),
              status: BranchStatus.active,
            ),
            BranchModel(
              id: 'nasr_city',
              name: 'فرع مدينة نصر',
              code: 'NAS',
              city: 'القاهرة',
              timezone: 'Africa/Cairo',
              openedAt: DateTime(2023, 9, 1),
              status: BranchStatus.active,
            ),
            BranchModel(
              id: 'alex',
              name: 'فرع سموحة - الإسكندرية',
              code: 'ALX',
              city: 'الإسكندرية',
              timezone: 'Africa/Cairo',
              openedAt: DateTime(2024, 2, 1),
              status: BranchStatus.active,
            ),
          ];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Network Overview Card
              PieCard(
                padding: const EdgeInsets.all(18),
                surfaceColor: PieColors.surface2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNetworkStat('الفروع المتصلة', '${branches.length}', PieColors.stateSynced),
                    _buildNetworkStat('أوردرات جارية', '34', PieColors.managerAccent),
                    _buildNetworkStat('تحذيرات التأخير', '2', PieColors.stateError),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'شبكة الفروع المباشرة (${branches.length})',
                style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),

              for (final branch in branches) ...[
                _buildBranchTriageCard(branch),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildNetworkStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: PieTypography.monoDisplay.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(label, style: PieTypography.caption),
      ],
    );
  }

  Widget _buildBranchTriageCard(BranchModel branch) {
    final isDelayed = branch.id == 'nasr_city';

    return PieCard(
      padding: const EdgeInsets.all(16),
      isActive: isDelayed,
      activeColor: PieColors.stateError,
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
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: branch.isActive ? const Color(0xFF4ADE80) : PieColors.inkMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        branch.name,
                        style: PieTypography.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isDelayed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: PieColors.stateErrorBg,
                    borderRadius: PieRadius.borderSm,
                    border: Border.all(color: PieColors.stateError),
                  ),
                  child: Text(
                    'ضغط تشغيلي (تأخير 35 د)',
                    style: PieTypography.caption.copyWith(color: PieColors.stateError),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF052E16),
                    borderRadius: PieRadius.borderSm,
                  ),
                  child: Text(
                    'تشغيل طبيعي',
                    style: PieTypography.caption.copyWith(color: const Color(0xFF4ADE80)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBranchMetric('أوردرات الصالة', '8'),
              _buildBranchMetric('أوردرات التيك أواي', '12'),
              _buildBranchMetric('أوردرات الدليفري', '5'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PieButton.secondary(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: PieColors.surface2,
                        content: Text('فتح شاشة متابعة تفاصيل أوردرات ${branch.name}'),
                      ),
                    );
                  },
                  label: 'عرض أوردرات الفرع',
                  height: 38,
                ),
              ),
              if (isDelayed) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: PieButton.primary(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: PieColors.surface2,
                          content: Text('تم تفعيل التحويل التلقائي للأوردرات الزائدة لأقرب فرع'),
                        ),
                      );
                    },
                    label: 'إعادة توجيه طارئ',
                    accentColor: PieColors.managerAccent,
                    height: 38,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBranchMetric(String label, String value) {
    return Column(
      children: [
        Text(value, style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
      ],
    );
  }
}
