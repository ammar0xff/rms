import 'package:flutter/material.dart';

import '../../core/config/app_version.dart';
import '../../core/config/device_update_context.dart';
import '../../core/di/app_services.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/local/migrations/local_migration_runner.dart';
import '../../domain/models/release_manifest.dart';
import '../../domain/update/device_update_status.dart';
import '../../domain/update/release_audit_event.dart';
import '../../domain/update/update_acknowledgement.dart';
import '../../domain/update/update_decision.dart';
import '../../domain/update/update_readiness.dart';
import '../../data/local/outbox/outbox_snapshot.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ReleaseManifest? _manifest;
  UpdateDecision? _decision;
  UpdateReadiness? _readiness;
  DeviceUpdateStatus? _lastStatus;
  List<ReleaseAuditEvent> _auditTrail = const [];
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
    final features = services.features;
    final manifest = features == null ? null : await features.manifest();
    final updates = services.updates;
    final release = updates == null ? null : await updates.cached();
    final branches = services.branches;
    final branch = branches == null ? null : await branches.activeBranch();
    final decision = UpdateDecisionEngine.decide(
      manifest: release,
      context: buildUpdateContext(
        now: DateTime.now(),
        branchId: branch?.id ?? '',
        cohortSeed: branch?.id ?? '',
      ),
    );
    final work = await loadLocalWorkSnapshot(
      services.outbox,
      online: SyncMonitor.instance.online,
    );
    final acknowledgement = await services.updateAcknowledgement?.load();
    final readiness = UpdateReadinessEngine.classify(
      decision: decision,
      work: work,
      acknowledgement: acknowledgement,
    );
    final lastStatus = await services.updateStatus?.load();
    final trail = await services.updateAudit?.list(limit: 5) ?? const [];
    if (!mounted) return;
    setState(() {
      _manifest = manifest;
      _decision = decision;
      _readiness = readiness;
      _lastStatus = lastStatus;
      _auditTrail = trail;
    });
  }

  /// Records an operator acknowledgement of the stuck work on hand, then
  /// re-evaluates the gate against it.
  Future<void> _acknowledgeStuckWork() async {
    final services = AppScope.of(context);
    final readiness = _readiness;
    if (readiness == null) return;
    final actor = services.auth.currentUser;
    await services.updateAcknowledgement?.save(
          UpdateAcknowledgement(
            stuckCount: readiness.work.stuck,
            acknowledgedAt: DateTime.now(),
            acknowledgedBy: actor?.email ?? '',
            note: 'تم الإقرار من شاشة الإعدادات',
          ),
        );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return PageBody(
      children: [
        const SectionHeader(
          title: 'الإعدادات والنظام',
          subtitle: 'إظهار الإصدار والترحيلات والمؤشرات وسياسة العمل دون اتصال',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _VersionCard(migration: services.migration)),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: _UpdateCard(
                decision: _decision,
                readiness: _readiness,
                lastStatus: _lastStatus,
                trail: _auditTrail,
                onAcknowledge: _acknowledgeStuckWork,
              ),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _MigrationCard(outcome: services.migration)),
            const SizedBox(width: AppSpacing.lg),
            const Expanded(child: _OfflinePolicyCard()),
          ],
        ),
        _FlagsCard(manifest: _manifest),
        const _DiagnosticsCard(),
      ],
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.migration});

  final MigrationOutcome? migration;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'إظهار الإصدار', subtitle: 'المسؤولون المصرحون فقط'),
          const SizedBox(height: 12),
          for (final (k, v) in [
            ('إصدار التطبيق', AppVersion.string),
            ('مخطط البيانات المحلي', AppVersion.localSchema),
            (
              'المخطط المطبق',
              migration == null ? 'غير معروف' : 'v${migration!.toVersion}',
            ),
            ('عقد الـ API', AppVersion.apiContract),
            ('الإعدادات', services.config.environment),
            ('الخلفية', services.firebaseReady ? 'Firebase' : 'محلي (وضع العرض)'),
            ('حالة Firebase', services.isDemo ? 'غير مهيأة' : 'متصلة'),
          ])
            KeyValue(label: k, value: v, mono: true),
        ],
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.decision,
    this.readiness,
    this.lastStatus,
    this.trail = const [],
    this.onAcknowledge,
  });

  final UpdateDecision? decision;
  final UpdateReadiness? readiness;

  /// The last update lifecycle this device recorded, so an attempt that
  /// survived a reboot is still visible.
  final DeviceUpdateStatus? lastStatus;

  /// The most recent audit events, newest first.
  final List<ReleaseAuditEvent> trail;

  /// Called when the operator acknowledges the stuck work on hand.
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final current = decision;
    final release = current?.release;
    final (headline, body, tone, icon) = _presentUpdate(current, readiness);
    final color = toneColor(tone);
    final needsAck =
        readiness?.status == UpdateReadinessStatus.needsAcknowledgement;
    final canInstall = readiness?.allowsInstall ?? false;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'التحديثات',
            trailing: Tag(
              label: _updateTagLabel(current),
              tone: tone,
              icon: icon,
            ),
          ),
          const SizedBox(height: 12),
          for (final (k, v) in [
            ('قناة الإصدار', release?.channel.label ?? '—'),
            ('الإصدار المعلن', release?.version ?? '—'),
            ('الإصدار الحالي', AppVersion.string),
            ('حالة الإصدار', release?.status.label ?? '—'),
            ('نسبة النشر', release == null ? '—' : '${release.rolloutPercent}%'),
            ('الحد الأدنى المدعوم', release?.minSupportedVersion ?? '—'),
            if (current?.bucket != null) ('شريحة النشر', '${current!.bucket} / 100'),
            if (current?.blockReason != null)
              ('سبب عدم الإتاحة', current!.blockReason!.label),
            if (current?.requiresMigration ?? false) ('ترحيل محلي مطلوب', 'نعم'),
            if (readiness != null && current?.isUpdate == true)
              ('جاهزية التثبيت', readiness!.status.label),
            if (lastStatus != null && lastStatus!.releaseId.isNotEmpty)
              ('آخر محاولة تحديث', lastStatus!.state.label),
            if (lastStatus?.failureReason != null &&
                lastStatus!.failureReason != UpdateFailureReason.none)
              ('سبب الفشل', lastStatus!.failureReason.label),
            if (lastStatus != null && lastStatus!.requiresRollback)
              ('إجراء مطلوب', 'تراجع إلى ${lastStatus!.rollbackTargetVersion}'),
            for (final event in trail.take(3))
              ('سجل التحديث', event.eventType.label),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              border: Border.all(color: color.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: AppText.tableCellPrimary.copyWith(color: color),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: AppText.caption.copyWith(fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                RmsButton(
                  label: needsAck ? 'إقرار' : 'تحديث',
                  variant: BtnVariant.primary,
                  onPressed: needsAck
                      ? onAcknowledge
                      : canInstall
                          ? () => ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'التحديث مؤهَّل وجاهز، لكن تنزيل الحزمة وتثبيتها غير مفعّلين على هذه المنصة بعد.',
                                  ),
                                ),
                              )
                          : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The headline, detail, tone and icon for a decision, so the card explains the
/// outcome without leaking the gate ordering.
(String, String, StatusTone, IconData) _presentUpdate(
  UpdateDecision? decision,
  UpdateReadiness? readiness,
) {
  final version = decision?.release?.version ?? '';
  final pending = readiness?.isPending ?? false;
  if (pending) {
    final work = readiness!.work;
    return switch (readiness.status) {
      UpdateReadinessStatus.awaitingSync => (
          'بانتظار مزامنة الأعمال المحلية',
          'لا يُثبَّت التحديث قبل رفع ${work.unsynced} عملية محلية حتى لا تُفقد.',
          StatusTone.warning,
          Icons.sync,
        ),
      UpdateReadinessStatus.offlineBacklog => (
          'يلزم اتصال بالإنترنت',
          'هناك ${work.unsynced} عملية محلية غير مرفوعة؛ اتصل بالشبكة لرفعها ثم التحديث.',
          StatusTone.warning,
          Icons.cloud_off,
        ),
      UpdateReadinessStatus.needsAcknowledgement => (
          'أعمال محلية معلّقة',
          'هناك ${work.stuck} عملية رفضها الخادم؛ راجعها وأقرّها قبل التحديث.',
          StatusTone.warning,
          Icons.report_problem_outlined,
        ),
      _ => _decisionNote(decision, version),
    };
  }
  return _decisionNote(decision, version);
}

(String, String, StatusTone, IconData) _decisionNote(
  UpdateDecision? decision,
  String version,
) => switch (decision?.status) {
      UpdateDecisionStatus.optional => (
          'تحديث اختياري متاح · $version',
          'يُسمح بالتأجيل؛ تُحفظ المعاملات المحلية المعلقة ولا تُمس الترحيلات.',
          StatusTone.info,
          Icons.system_update_alt,
        ),
      UpdateDecisionStatus.recommended => (
          'تحديث مُوصى به · $version',
          'يُنصح بالتحديث قريبًا؛ لن تُفقد أي أعمال محلية غير متزامنة.',
          StatusTone.info,
          Icons.system_update_alt,
        ),
      UpdateDecisionStatus.mandatory => (
          'تحديث إلزامي · $version',
          'مطلوب لمواصلة التشغيل الآمن؛ تُحفظ الأعمال المحلية المعلقة قبل التثبيت.',
          StatusTone.warning,
          Icons.priority_high,
        ),
      UpdateDecisionStatus.ineligible => (
          'لا يتوفر تحديث لهذا الجهاز',
          'الإصدار غير متاح لهذا الجهاز؛ السبب موضّح في التفاصيل أعلاه.',
          StatusTone.neutral,
          Icons.block,
        ),
      UpdateDecisionStatus.upToDate => (
          'أنت على أحدث إصدار',
          'لا يوجد تحديث معلن لهذا الجهاز حاليًا.',
          StatusTone.positive,
          Icons.check_circle_outline,
        ),
      null => (
          'جارٍ التحقق من الإصدار…',
          'يُقرأ آخر بيان إصدار مخزّن على هذا الجهاز.',
          StatusTone.neutral,
          Icons.system_update_alt,
        ),
    };

String _updateTagLabel(UpdateDecision? decision) =>
    switch (decision?.status) {
      UpdateDecisionStatus.optional => 'اختياري',
      UpdateDecisionStatus.recommended => 'مُوصى به',
      UpdateDecisionStatus.mandatory => 'إلزامي',
      UpdateDecisionStatus.ineligible => 'غير متاح',
      UpdateDecisionStatus.upToDate => 'محدّث',
      null => 'جارٍ التحقق',
    };

class _MigrationCard extends StatelessWidget {
  const _MigrationCard({required this.outcome});

  final MigrationOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final migration = outcome;
    final succeeded = migration?.succeeded ?? false;
    final tone = migration == null
        ? StatusTone.neutral
        : succeeded
            ? StatusTone.positive
            : StatusTone.negative;
    final label = migration == null
        ? 'غير معروفة'
        : succeeded
            ? 'مكتمل'
            : 'فشل';
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'الترحيل المحلي',
            trailing: StatusText(label: label, tone: tone),
          ),
          const SizedBox(height: 12),
          for (final (k, v) in [
            (
              'الإصدار',
              migration == null
                  ? 'غير معروف'
                  : 'v${migration.fromVersion} ← v${migration.toVersion}',
            ),
            (
              'الخطوات المطبقة',
              migration == null || migration.applied.isEmpty
                  ? 'لا شيء'
                  : migration.applied.join(' · '),
            ),
            ('صندوق الصادر محفوظ', 'نعم — لا تُمس إدخالاته'),
            ('نسخة التراجع', 'محفوظة'),
            if (migration?.error != null) ('الخطأ', migration!.error!),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          Text(
            'تُجرى الترحيلات قبل الوصول إلى المخطط الجديد، وتحافظ على إدخالات صندوق الصادر ومفاتيح التكرار، ولا تتقدم بالإصدار إلا عند النجاح.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _OfflinePolicyCard extends StatelessWidget {
  const _OfflinePolicyCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'سياسة العمل دون اتصال'),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('المدة المسموحة دون اتصال', '24 ساعة'),
            ('أقصى عمر لنسخة القائمة', '12 ساعة'),
            ('سلوك النسخة القديمة', 'تحذير الكاشير'),
            ('العمليات عالية الخطورة دون اتصال', 'محظورة'),
            ('إعادة الطباعة عند الاتصال', 'يدوية فقط'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              border: Border.all(color: AppColors.borderStrong),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              'لا يمكن للجهاز المنفصل معرفة وجود تحديث إلزامي. تُخزَّن سياسة آخر إصدار صالح، ويتتبع التطبيق عمرها، ولا تُهمل السجلات غير المتزامنة أبدًا.',
              style: AppText.caption.copyWith(fontSize: 10.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagsCard extends StatelessWidget {
  const _FlagsCard({required this.manifest});

  final ReleaseManifest? manifest;

  @override
  Widget build(BuildContext context) {
    final flags = manifest?.flags ?? const <FeatureFlag>[];
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: SectionHeader(
              title: 'مؤشرات الميزات',
              subtitle: 'تُدار من الخادم · ليست بديلاً عن صلاحية الواجهة الخلفية',
            ),
          ),
          const SizedBox(height: 8),
          if (flags.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('لا يوجد بيان إصدار مخزّن على هذا الجهاز.',
                  style: AppText.caption),
            ),
          for (var i = 0; i < flags.length; i++) ...[
            _FlagRow(
              name: flags[i].label,
              scope: flags[i].scope,
              on: flags[i].enabled,
            ),
            if (i != flags.length - 1)
              const Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.borderFaint),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.name, required this.scope, required this.on});

  final String name;
  final String scope;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.tableCellPrimary),
                if (scope.isNotEmpty)
                  Text(scope, style: AppText.caption.copyWith(fontSize: 10)),
              ],
            ),
          ),
          Container(
            width: 34,
            height: 18,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: on ? AppColors.brandSoft : AppColors.surfaceSunken,
              border: Border.all(color: on ? AppColors.brandLine : AppColors.borderStrong),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Align(
              alignment: on ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: on ? AppColors.brand : AppColors.fgGhost,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live, device-local diagnostics: store availability, outbox depth and the
/// print queue. Unlike the server-driven flags, everything here is real.
class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard();

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'تشخيص النظام',
            subtitle: 'حالة حية من هذا الجهاز · لا تعتمد على الخادم',
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: SyncMonitor.instance,
            builder: (context, _) {
              final m = SyncMonitor.instance;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyValue(
                    label: 'التخزين المحلي',
                    value: services.hasLocalStore ? 'متاح' : 'غير متاح',
                    mono: true,
                  ),
                  KeyValue(
                    label: 'صندوق الصادر',
                    value: services.outbox == null ? 'معطل' : 'نشط',
                    mono: true,
                  ),
                  KeyValue(
                    label: 'الاتصال',
                    value: m.online ? 'متصل' : 'دون اتصال',
                    mono: true,
                  ),
                  KeyValue(
                    label: 'إجمالي عمليات الصادر',
                    value: '${m.total}',
                    mono: true,
                  ),
                  KeyValue(label: 'قيد الانتظار', value: '${m.pending}', mono: true),
                  KeyValue(label: 'فشل دائم', value: '${m.failed}', mono: true),
                  KeyValue(label: 'تعارضات', value: '${m.conflicts}', mono: true),
                  KeyValue(label: 'تمت مزامنتها', value: '${m.synced}', mono: true),
                  KeyValue(
                    label: 'مهام الطباعة في الطابور',
                    value: '${services.print?.jobs.length ?? 0}',
                    mono: true,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
