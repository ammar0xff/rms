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
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';

/// The developer's home: is the device healthy.
///
/// Sync state, outbox totals, build identity, backend state, and the live log
/// tail — everything a developer checks first, on one screen, with actions
/// that work locally (sync now). No navigation links: screens cannot switch
/// tabs, so this board reports and triggers rather than routing.
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

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final monitor = SyncMonitor.instance;
    return RefreshIndicator(
      onRefresh: () => SyncMonitor.instance.refresh(),
      child: PageBody(
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(
                        title: 'حالة النظام',
                        subtitle: 'نبض الجهاز الحي',
                      ),
                    ),
                    RmsButton(
                      label: _syncing ? 'جارٍ المزامنة…' : 'مزامنة الآن',
                      icon: Icons.sync,
                      onPressed: _syncing ? null : _syncNow,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: monitor,
                  builder: (context, _) => GridRow(children: [
                    StatCard(
                        label: 'معلّق',
                        value: '${monitor.pending}',
                        tone: monitor.pending > 0
                            ? AppColors.warning
                            : null),
                    StatCard(
                        label: 'فاشل',
                        value: '${monitor.failed}',
                        tone: monitor.failed > 0
                            ? AppColors.negative
                            : null),
                    StatCard(
                        label: 'تعارضات',
                        value: '${monitor.conflicts}',
                        tone: monitor.conflicts > 0
                            ? AppColors.warning
                            : null),
                  ]),
                ),
              ],
            ),
          ),
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
                        'لا توجد أحداث مسجلة في هذه الجلسة.',
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
