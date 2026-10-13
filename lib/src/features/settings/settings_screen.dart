import 'package:flutter/material.dart';

import '../../core/config/app_version.dart';
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ReleaseManifest? _manifest;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final features = AppScope.of(context).features;
    final manifest = features == null ? null : await features.manifest();
    if (!mounted) return;
    setState(() => _manifest = manifest);
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
            Expanded(child: _UpdateCard(manifest: _manifest)),
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
  const _UpdateCard({required this.manifest});

  final ReleaseManifest? manifest;

  @override
  Widget build(BuildContext context) {
    final channel = manifest?.channel ?? 'stable';
    final version = manifest?.version ?? AppVersion.number;
    final minSupported = manifest?.minSupportedVersion ?? '—';
    final rollout = manifest?.rolloutPercent;
    final mandatory = manifest?.mandatory ?? false;
    final hasNewer = manifest != null && manifest!.version != AppVersion.number;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'التحديثات',
            trailing: Tag(
              label: mandatory ? 'إلزامي' : 'مستقر',
              tone: mandatory ? StatusTone.warning : StatusTone.positive,
            ),
          ),
          const SizedBox(height: 12),
          for (final (k, v) in [
            ('قناة الإصدار', channel),
            ('الإصدار المعلن', version),
            ('الحد الأدنى المدعوم', minSupported),
            ('نسبة النشر', rollout == null ? '—' : '$rollout%'),
            ('الإصدار الحالي', AppVersion.number),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.06),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.system_update_alt, size: 15, color: AppColors.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasNewer ? 'تحديث اختياري متاح · $version' : 'أنت على الإصدار المعلن',
                        style: AppText.tableCellPrimary.copyWith(color: AppColors.info),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'يُسمح بالتأجيل. تُحفظ المعاملات المحلية المعلقة وتُجرى الترحيلات بشكل متصل.',
                        style: AppText.caption.copyWith(fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                RmsButton(
                  label: 'تحديث',
                  variant: BtnVariant.primary,
                  onPressed: hasNewer ? () {} : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
