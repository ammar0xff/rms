import 'package:flutter/material.dart';

import '../../core/state/sync_monitor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../core/di/app_services.dart';
import '../../data/services/print_service.dart';
import '../../domain/services/print_adapter.dart';
import '../../data/mock/mock_data.dart';

(String, StatusTone) _opStatus(String s) => switch (s) {
      'pending' => ('قيد الانتظار', StatusTone.warning),
      'in_progress' => ('قيد الإرسال', StatusTone.info),
      'synced' => ('تمت المزامنة', StatusTone.positive),
      'conflict' => ('تعارض', StatusTone.negative),
      'retryable_failure' => ('قابل لإعادة المحاولة', StatusTone.warning),
      'requires_user_action' => ('يتطلب إجراء', StatusTone.negative),
      _ => (s, StatusTone.neutral),
    };

class SyncCenterScreen extends StatelessWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        Row(
          children: [
            const SectionHeader(
              title: 'مركز المزامنة',
              subtitle: 'صندوق الصادر · ترتيب بالاعتماديات · إعادة محاولات آمنة',
            ),
            const Spacer(),
            RmsButton(label: 'إعادة الاتصال والمزامنة الآن', icon: Icons.sync, onPressed: () {
              final svc = AppScope.of(context).sync;
              if (svc != null) svc.requestSync();
              SyncMonitor.instance.refresh();
            }, dense: false),
          ],
        ),
        AnimatedBuilder(
          animation: SyncMonitor.instance,
          builder: (context, _) {
            final m = SyncMonitor.instance;
            return GridRow(children: [
              StatCard(label: 'قيد الانتظار', value: '${m.pending}', tone: AppColors.fgBright),
              const StatCard(label: 'قيد الإرسال', value: '1', delta: 'جارٍ الإرسال'),
              StatCard(
                label: 'فشل',
                value: '${m.failed}',
                delta: 'قابل لإعادة المحاولة',
                deltaTone: DeltaTone.negative,
                tone: m.failed > 0 ? AppColors.negative : null,
              ),
              StatCard(
                label: 'تعارضات',
                value: '${m.conflicts}',
                delta: 'مراجعة',
                deltaTone: DeltaTone.negative,
                tone: m.conflicts > 0 ? AppColors.warning : null,
              ),
            ]);
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        const _PrintQueueSection(),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _OutboxTable()),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: _SequenceCard()),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const _PrintQueueSection(),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _PolicyCard(
              title: 'التكرار الآمن',
              icon: Icons.fingerprint,
              body: 'يحمل كل أمر مفتاح تكرار آمن ثابت. يحتفظ الخادم بإيصالات العمليات ويعيد النتيجة القائمة للطلبات المكررة — يطبَّق على الطلبات والمدفوعات والاستردادات والتذاكر والإسنادات والتحصيلات والمخزون.',
            )),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: _PolicyCard(
              title: 'سياسة إعادة المحاولة',
              icon: Icons.replay,
              body: 'الفشل العابر يُعاد بمهلة تصاعدية مع تشتيت. الأخطاء الدائمة لا تُعاد إلى ما لا نهاية، وتبقى العمليات المحظورة مرئية مع أسباب قابلة للتنفيذ بدلاً من إهمالها.',
            )),
          ],
        ),
      ],
    );
  }
}

class _OutboxTable extends StatelessWidget {
  const _OutboxTable();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: SectionHeader(
              title: 'عمليات صندوق الصادر',
              trailing: const StatusText(label: 'قيد المعالجة', tone: StatusTone.info),
            ),
          ),
          RmsTable(
            columns: [
              RmsColumn('العملية', flex: 2),
              RmsColumn('الكيان', flex: 3),
              RmsColumn('النوع', flex: 3),
              RmsColumn('المحاولات', flex: 2, align: TextAlign.right),
              RmsColumn('الحالة', flex: 3),
            ],
            rows: [
              for (final op in MockData.syncOperations)
                [
                  Text(op.operationId, style: AppText.mono.copyWith(fontSize: 10.5)),
                  Text(op.entity, style: AppText.tableCell),
                  Text(op.type, style: AppText.tableCell),
                  Text('${op.attempts}', style: AppText.tableCell),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusText(label: _opStatus(op.status).$1, tone: _opStatus(op.status).$2),
                      if (op.lastError != null)
                        Text(op.lastError!, style: AppText.caption.copyWith(fontSize: 9.5, color: AppColors.fgGhost)),
                    ],
                  ),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SequenceCard extends StatelessWidget {
  const _SequenceCard();

  static const _steps = [
    'إنشاء العميل عند الحاجة',
    'إرسال الطلب',
    'مزامنة سجلات الدفع',
    'مزامنة أحداث المطبخ',
    'مزامنة إسناد / حالة التوصيل',
    'مزامنة سجلات التحصيل المؤهلة',
    'تحديث الملخصات المؤكدة من الخادم',
  ];

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'ترتيب المزامنة', subtitle: 'يحترم الاعتماديات'),
          const SizedBox(height: 14),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSunken,
                      border: Border.all(color: AppColors.borderStrong),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('${i + 1}', style: AppText.caption.copyWith(fontSize: 9)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_steps[i], style: AppText.tableCell.copyWith(color: AppColors.fgSecondary))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.title, required this.icon, required this.body});

  final String title;
  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.fgMuted),
              const SizedBox(width: 8),
              Text(title, style: AppText.sectionHeading),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: AppText.body),
        ],
      ),
    );
  }
}


class _PrintQueueSection extends StatelessWidget {
  const _PrintQueueSection();

  @override
  Widget build(BuildContext context) {
    final printSvc = AppScope.of(context).print ?? PrintService();
    return StreamBuilder<List<PrintJob>>(
      stream: printSvc.jobsStream,
      initialData: printSvc.jobs,
      builder: (context, snapshot) {
        final jobs = snapshot.data ?? const [];
        return SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.print_rounded, size: 16, color: AppColors.fgMuted),
                  const SizedBox(width: 6),
                  Text('طابور الطباعة (محلي)', style: AppText.sectionHeading),
                  const Spacer(),
                  Text('${jobs.length}', style: AppText.caption),
                ],
              ),
              const SizedBox(height: 8),
              if (jobs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('لا توجد مهام طباعة', style: AppText.caption)),
                )
              else
                RmsTable(
                  columns: [
                    RmsColumn('المعرف'),
                    RmsColumn('النوع'),
                    RmsColumn('المرجع'),
                    RmsColumn('الوقت'),
                  ],
                  rows: jobs.reversed.take(10).map((j) {
                    final payload = j.payload;
                    final ref = payload['orderRef'] ?? payload['id'] ?? '-';
                    return [
                      Text(j.id),
                      Text(j.type),
                      Text('$ref'),
                      Text(j.createdAt?.toIso8601String().substring(11, 16) ?? '-'),
                    ];
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }
}