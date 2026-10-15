import 'package:flutter/material.dart';

import '../../core/config/app_version.dart';
import '../../core/di/app_services.dart';
import '../../core/logging/app_logger.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/role_ui.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/models/app_role.dart';
import '../conflicts/conflicts_screen.dart';
import '../database/database_screen.dart';
import '../settings/settings_screen.dart';
import '../team/team_screen.dart';

/// The developer's home: is the device healthy.
///
/// Sync state, outbox totals, build identity, backend state, the tool grid
/// (database, conflicts, team, settings as focused pushed screens), and the
/// live log tail — everything a developer checks first, on one screen.
class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  bool _syncing = false;

  Future<void> _syncNow() async {
    final sync = AppScope.of(context).sync;
    if (sync == null || _syncing) return;
    setState(() => _syncing = true);
    try {
      await sync.requestSync();
      await SyncMonitor.instance.refresh();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final monitor = SyncMonitor.instance;
    final accent = AppColors.developerAccent;
    return RefreshIndicator(
      onRefresh: () => SyncMonitor.instance.refresh(),
      child: PageBody(
        children: [
          AnimatedBuilder(
            animation: monitor,
            builder: (context, _) => RoleHero(
              role: AppRole.developer,
              kicker: 'حالة النظام',
              title:
                  monitor.online ? 'متصل وشغال' : 'شغال من غير نت',
              subtitle: monitor.pending > 0
                  ? '${monitor.pending} عملية مستنية في الطابور'
                  : 'الطابور فاضي · النبض الحي شغال',
              value: AppVersion.string,
              valueLabel: 'إصدار البناء',
              action: RmsButton(
                label: _syncing ? 'جارٍ المزامنة…' : 'مزامنة دلوقتي',
                icon: Icons.sync,
                variant: BtnVariant.primary,
                onPressed: _syncing ? null : _syncNow,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: monitor,
            builder: (context, _) => GridRow(children: [
              KpiCard(
                label: 'معلّق',
                value: '${monitor.pending}',
                icon: Icons.pending_outlined,
                accent: accent,
              ),
              KpiCard(
                label: 'فاشل',
                value: '${monitor.failed}',
                icon: Icons.error_outline,
                accent: accent,
              ),
              KpiCard(
                label: 'تعارضات',
                value: '${monitor.conflicts}',
                icon: Icons.merge_type_outlined,
                accent: accent,
              ),
            ]),
          ),
          GridRow(children: [
            QuickActionTile(
              icon: Icons.storage_outlined,
              label: 'قاعدة البيانات',
              accent: accent,
              onTap: () => _open(const DatabaseScreen()),
            ),
            QuickActionTile(
              icon: Icons.device_hub_outlined,
              label: 'التعارضات',
              accent: accent,
              onTap: () => _open(const ConflictsScreen()),
            ),
          ]),
          GridRow(children: [
            QuickActionTile(
              icon: Icons.group_outlined,
              label: 'الفريق والأدوار',
              accent: accent,
              onTap: () => _open(const TeamScreen()),
            ),
            QuickActionTile(
              icon: Icons.settings_outlined,
              label: 'الإعدادات',
              accent: accent,
              onTap: () => _open(const SettingsScreen()),
            ),
          ]),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'البناء والخلفية'),
                const SizedBox(height: 8),
                KeyValue(label: 'الإصدار', value: AppVersion.string, mono: true),
                KeyValue(
                    label: 'القناة', value: AppVersion.channel, mono: true),
                KeyValue(
                  label: 'المخزن المحلي',
                  value: services.hasLocalStore ? 'متاح' : 'غير متاح',
                  mono: true,
                ),
                KeyValue(
                  label: 'المزامنة',
                  value: services.sync == null ? 'معطّلة' : 'نشطة',
                  mono: true,
                ),
                KeyValue(
                  label: 'الاتصال',
                  value: monitor.online ? 'متصل' : 'دون اتصال',
                  mono: true,
                ),
                KeyValue(
                  label: 'Firebase',
                  value: !services.config.isConfigured
                      ? 'غير مهيأة'
                      : services.firebaseReady
                          ? 'متصلة'
                          : 'فشل الاتصال',
                  mono: true,
                ),
              ],
            ),
          ),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: 'سجل الأحداث',
                  subtitle: 'آخر ما رآه الجهاز',
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final lines = AppLogger.recentLines(limit: 12);
                    if (lines.isEmpty) {
                      return const Text(
                        'مفيش أحداث مسجلة في هذه الجلسة.',
                        style: AppText.caption,
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSunken,
                        border:
                            Border.all(color: AppColors.borderSubtle),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        lines.join('\n'),
                        style: AppText.mono
                            .copyWith(fontSize: 10, height: 1.5),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
