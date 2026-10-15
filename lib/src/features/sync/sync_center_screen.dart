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
import '../../data/local/outbox/outbox_entry.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../data/services/print_service.dart';
import '../../domain/services/print_adapter.dart';

(String, StatusTone) _opStatus(OutboxStatus status) => switch (status) {
      OutboxStatus.pending => ('قيد الانتظار', StatusTone.warning),
      OutboxStatus.inProgress => ('قيد الإرسال', StatusTone.info),
      OutboxStatus.synced => ('تمت المزامنة', StatusTone.positive),
      OutboxStatus.conflict => ('تعارض', StatusTone.negative),
      OutboxStatus.retryableFailure => ('قابل لإعادة المحاولة', StatusTone.warning),
      OutboxStatus.requiresUserAction => ('يتطلب إجراء', StatusTone.negative),
      OutboxStatus.permanentlyRejected => ('مرفوض نهائيًا', StatusTone.negative),
    };

class SyncCenterScreen extends StatelessWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final action = RmsButton(label: 'إعادة الاتصال والمزامنة الآن', icon: Icons.sync, onPressed: () {
              final svc = AppScope.of(context).sync;
              if (svc != null) svc.requestSync();
              SyncMonitor.instance.refresh();
            }, dense: false);
            if (c.maxWidth >= 600) {
              return Row(
                children: [
                  const Expanded(
                    child: SectionHeader(
                      title: 'مركز المزامنة',
                      subtitle: 'صندوق الصادر · ترتيب بالاعتماديات · إعادة محاولات آمنة',
                    ),
                  ),
                  action,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: 'مركز المزامنة',
                  subtitle: 'صندوق الصادر · ترتيب بالاعتماديات · إعادة محاولات آمنة',
                ),
                const SizedBox(height: 8),
                action,
              ],
            );
          },
        ),
        AnimatedBuilder(
          animation: SyncMonitor.instance,
          builder: (context, _) {
            final m = SyncMonitor.instance;
            return GridRow(children: [
              StatCard(label: 'قيد الانتظار', value: '${m.pending}', tone: AppColors.fgBright),
              StatCard(label: 'تمت المزامنة', value: '${m.synced}', tone: AppColors.fgBright),
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
        _PrintQueueSection(),
        const ResponsiveRow(
          gap: AppSpacing.lg,
          children: [
            _OutboxTable(),
            _SequenceCard(),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const ResponsiveRow(
          gap: AppSpacing.lg,
          children: [
            _PolicyCard(
              title: 'التكرار الآمن',
              icon: Icons.fingerprint,
              body: 'يحمل كل أمر مفتاح تكرار آمن ثابت. يحتفظ الخادم بإيصالات العمليات ويعيد النتيجة القائمة للطلبات المكررة — يطبَّق على الطلبات والمدفوعات والاستردادات والتذاكر والإسنادات والتحصيلات والمخزون.',
            ),
            _PolicyCard(
              title: 'سياسة إعادة المحاولة',
              icon: Icons.replay,
              body: 'الفشل العابر يُعاد بمهلة تصاعدية مع تشتيت. الأخطاء الدائمة لا تُعاد إلى ما لا نهاية، وتبقى العمليات المحظورة مرئية مع أسباب قابلة للتنفيذ بدلاً من إهمالها.',
            ),
          ],
        ),
      ],
    );
  }
}

class _OutboxTable extends StatefulWidget {
  const _OutboxTable();

  @override
  State<_OutboxTable> createState() => _OutboxTableState();
}

class _OutboxTableState extends State<_OutboxTable> {
  List<OutboxEntry> _entries = const [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SyncMonitor.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SyncMonitor.instance.removeListener(_load);
    super.dispose();
  }

  // The screen whose job is showing what is stuck must read the real outbox,
  // not fixtures: genuine pending and conflicted operations were invisible
  // here while the header claimed to be processing them.
  Future<void> _load() async {
    final outbox = AppScope.of(context).outbox;
    if (outbox == null) return;
    final entries = await outbox.all();
    if (!mounted) return;
    setState(() {
      _entries = entries
          .where((e) => e.syncStatus != OutboxStatus.synced)
          .toList();
      _loaded = true;
    });
  }

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
              trailing: StatusText(
                label: _loaded
                    ? (_entries.isEmpty ? 'فارغ' : '${_entries.length} معلّقة')
                    : 'قيد المعالجة',
                tone: _entries.isEmpty ? StatusTone.positive : StatusTone.info,
              ),
            ),
          ),
          if (_loaded && _entries.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'لا توجد عمليات معلّقة. كل الأعمال المحلية مرفوعة.',
                style: AppText.caption,
              ),
            )
          else
            RmsTable(
              columns: const [
                RmsColumn('العملية', flex: 2),
                RmsColumn('الكيان', flex: 3),
                RmsColumn('النوع', flex: 3),
                RmsColumn('المحاولات', flex: 2, align: TextAlign.right),
                RmsColumn('الحالة', flex: 3),
              ],
              rows: [
                for (final op in _entries)
                  [
                    Text(op.operationId, style: AppText.mono),
                    Text(op.entityType, style: AppText.tableCell),
                    Text(op.operationType, style: AppText.tableCell),
                    Text('${op.attemptCount}', style: AppText.tableCell),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusText(label: _opStatus(op.syncStatus).$1, tone: _opStatus(op.syncStatus).$2),
                        if (op.lastError != null)
                          Text(op.lastError!, style: AppText.caption.copyWith(color: AppColors.fgGhost)),
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
                    child: Text('${i + 1}', style: AppText.caption),
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
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(child: Text('لا توجد مهام طباعة', style: AppText.caption)),
                )
              else
                RmsTable(
                  columns: const [
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