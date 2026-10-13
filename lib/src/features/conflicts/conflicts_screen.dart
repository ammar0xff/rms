import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/local/outbox/outbox_entry.dart';
import '../../data/local/outbox/outbox_status.dart';

class ConflictsScreen extends StatefulWidget {
  const ConflictsScreen({super.key});

  @override
  State<ConflictsScreen> createState() => _ConflictsScreenState();
}

class _ConflictsScreenState extends State<ConflictsScreen> {
  List<OutboxEntry> _conflicts = const [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final outbox = services.outbox;
    final conflicts = outbox == null
        ? const <OutboxEntry>[]
        : (await outbox.all())
            .where((e) =>
                e.syncStatus == OutboxStatus.conflict ||
                e.syncStatus == OutboxStatus.requiresUserAction ||
                e.syncStatus == OutboxStatus.permanentlyRejected)
            .toList();
    if (!mounted) return;
    setState(() => _conflicts = conflicts);
  }

  /// Re-queues a stalled entry so the next sync pass retries it.
  Future<void> _resolve(OutboxEntry entry) async {
    final services = AppScope.of(context);
    final outbox = services.outbox;
    final messenger = ScaffoldMessenger.of(context);
    if (outbox == null) return;
    await outbox.save(entry.copyWith(
      syncStatus: OutboxStatus.pending,
      attemptCount: 0,
      clearLastError: true,
    ));
    await _load();
    unawaited(SyncMonitor.instance.refresh());
    services.sync?.requestSync();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('أُعيد إدراج العملية ${entry.entityType}/${entry.entityId} للمزامنة')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        Row(
          children: [
            const SectionHeader(
              title: 'التعارضات',
              subtitle: 'تُكتشف عند المزامنة · التعارضات المالية تتطلب مراجعة',
            ),
            const Spacer(),
            Tag(
              label: '${_conflicts.length} غير محلولة',
              tone: _conflicts.isEmpty ? StatusTone.positive : StatusTone.negative,
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _conflictList()),
            const SizedBox(width: AppSpacing.lg),
            const Expanded(child: _StrategyCard()),
          ],
        ),
        const SurfaceCard(
          level: SurfaceLevel.secondary,
          child: Row(
            children: [
              Icon(Icons.gavel_outlined, size: 16, color: AppColors.warning),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'لا تُحل التعارضات ذات الأهمية المالية تلقائيًا بقاعدة آخر كاتب يفوز. تُحفظ نسختا الحالة للتحقيق حتى يقوم مستخدم مصرح به بالحل.',
                  style: AppText.body,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _conflictList() {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: SectionHeader(title: 'غير محلولة'),
          ),
          if (_conflicts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Text('لا توجد تعارضات بانتظار الحل.', style: AppText.caption),
            ),
          for (var i = 0; i < _conflicts.length; i++) ...[
            _ConflictTile(entry: _conflicts[i], onResolve: () => _resolve(_conflicts[i])),
            if (i != _conflicts.length - 1)
              const Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.borderFaint),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({required this.entry, required this.onResolve});

  final OutboxEntry entry;
  final VoidCallback onResolve;

  StatusTone get _tone {
    switch (entry.entityType) {
      case 'payment':
      case 'order':
      case 'settlement':
        return StatusTone.negative;
      case 'delivery':
      case 'inventory':
      case 'supplier':
      case 'purchase':
        return StatusTone.warning;
      default:
        return StatusTone.neutral;
    }
  }

  String get _severity => switch (_tone) {
        StatusTone.negative => 'مالي',
        StatusTone.warning => 'تشغيلي',
        _ => 'عام',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          StatusDot(tone: _tone, size: 6),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(entry.entityId, style: AppText.mono.copyWith(fontSize: 10.5)),
                    const SizedBox(width: 8),
                    Tag(label: _severity, tone: _tone),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${entry.entityType} · ${entry.operationType}',
                    style: AppText.tableCellPrimary),
                Text(
                  '${entry.lastError ?? 'بانتظار المراجعة'} · ${entry.attemptCount} محاولات',
                  style: AppText.caption.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
          RmsButton(label: 'حل', variant: BtnVariant.primary, onPressed: onResolve),
        ],
      ),
    );
  }
}

class _StrategyCard extends StatelessWidget {
  const _StrategyCard();

  static const _strategies = [
    ('إعدادات القائمة', 'مرجعها الخادم؛ تحديث اللقطات القديمة'),
    ('إنشاء الطلب', 'إنشاء آمن بمفتاح مستقر'),
    ('أصناف الطلب', 'فحوصات النسخة والتعامل الصريح'),
    ('حالة المطبخ', 'التحقق من الانتقالات القانونية؛ الاحتفاظ بالسجل'),
    ('المدفوعات النقدية', 'إضافة فقط مع إزالة التكرار'),
    ('تحصيلات السائقين', 'إضافة فقط + مطابقة'),
    ('التسويات', 'تحقق موثوق؛ لا قاعدة آخر كاتب يفوز'),
    ('المخزون', 'حركات إضافة فقط؛ حل التعارضات'),
    ('الأدوار والصلاحيات', 'مرجعها الخادم؛ لا تعديل دون اتصال'),
  ];

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'استراتيجية الحل', subtitle: 'حسب نوع الكيان'),
          const SizedBox(height: 12),
          RmsTable(
            columns: const [
              RmsColumn('الكيان', flex: 3),
              RmsColumn('الاستراتيجية', flex: 5),
            ],
            rows: [
              for (final (entity, strategy) in _strategies)
                [
                  Text(entity, style: AppText.tableCellPrimary.copyWith(fontSize: 11)),
                  Text(strategy, style: AppText.tableCell.copyWith(fontSize: 11)),
                ],
            ],
          ),
        ],
      ),
    );
  }
}
