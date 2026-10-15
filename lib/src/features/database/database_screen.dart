import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sembast/sembast.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/local/local_database.dart';
import '../../data/local/local_stores.dart';
import '../../data/local/outbox/outbox_status.dart';

/// Developer tools for inspecting and maintaining both databases.
///
/// Local section counts rows per store; backend section counts mirror
/// collections on Firestore. The prune action deletes acknowledged outbox
/// rows, which otherwise accumulate forever — only `synced` rows go, so it
/// can never lose work, only history.
///
/// Developer-only: the shell never links here for any other role.
class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  Map<String, int> _local = const {};
  Map<String, StoreRef<String, Map<String, Object?>>> _stores = const {};
  Map<String, int> _remote = const {};
  String? _remoteError;
  bool _loading = false;
  bool _pruning = false;

  static const _mirrorCollections = [
    'orders',
    'payments',
    'collections',
    'deliveries',
    'purchases',
    'suppliers',
    'kitchenTickets',
    'stockMovements',
    'inventoryItems',
    'cashSessions',
    'approvals',
    'customers',
    'menu',
    'sync_operations',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<int> _count(
    LocalDatabase db,
    StoreRef<String, Map<String, Object?>> store,
  ) async {
    try {
      return (await store.find(db.db)).length;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final db = services.database;
    if (db == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final refs = <String, StoreRef<String, Map<String, Object?>>>{
        'الطلبات': LocalStores.orders,
        'المدفوعات': LocalStores.payments,
        'التوصيل': LocalStores.deliveries,
        'التحصيلات': LocalStores.collections,
        'المشتريات': LocalStores.purchases,
        'الموردون': LocalStores.suppliers,
        'المخزون': LocalStores.inventory,
        'حركات المخزون': LocalStores.stockMovements,
        'القائمة': LocalStores.menu,
        'تذاكر المطبخ': LocalStores.kitchenTickets,
        'العملاء': LocalStores.customers,
        'الجلسات النقدية': LocalStores.cashSessions,
        'الموافقات': LocalStores.approvals,
        'التدقيق': LocalStores.audit,
      };
      final local = <String, int>{
        for (final e in refs.entries) e.key: await _count(db, e.value),
      };
      final outbox = services.outbox;
      var pending = 0;
      var synced = 0;
      if (outbox != null) {
        for (final e in await outbox.all()) {
          if (e.syncStatus == OutboxStatus.synced) {
            synced++;
          } else {
            pending++;
          }
        }
      }
      local['الصادر (مستني)'] = pending;
      local['الصادر (اتزامن)'] = synced;
      if (!mounted) return;
      setState(() {
        _local = local;
        _stores = refs;
      });

      if (services.firebaseReady) await _loadRemote();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRemote() async {
    try {
      final db = FirebaseFirestore.instance;
      final remote = <String, int>{};
      for (final collection in _mirrorCollections) {
        final snapshot =
            await db.collection(collection).count().get().timeout(
                  const Duration(seconds: 10),
                );
        remote[collection] = snapshot.count ?? -1;
      }
      if (!mounted) return;
      setState(() {
        _remote = remote;
        _remoteError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _remoteError = '$error');
    }
  }

  /// Shows the first five records of a local store: the answer to
  /// "the numbers look wrong" starts with seeing actual rows.
  Future<void> _drill(String label) async {
    final services = AppScope.of(context);
    final db = services.database;
    final store = _stores[label];
    if (db == null || store == null || !mounted) return;
    final records =
        await store.find(db.db, finder: Finder(limit: 5));
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: AppText.h1),
            const SizedBox(height: 4),
            Text(
              records.isEmpty
                  ? 'المخزن فاضي'
                  : 'أول ${records.length} صفوف',
              style: AppText.caption,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in records)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('${r.key}',
                                style: AppText.mono),
                            Text(
                              _summarize(r.value),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            RmsButton(
              label: 'اقفل',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  static String _summarize(Map<String, Object?> value) {
    final s = value.entries
        .take(3)
        .map((e) => '${e.key}=${e.value}')
        .join(' · ');
    return s.length <= 120 ? s : '${s.substring(0, 120)}…';
  }

  Future<void> _prune() async {
    final outbox = AppScope.of(context).outbox;
    if (outbox == null || _pruning) return;
    setState(() => _pruning = true);
    try {
      final removed = await outbox.pruneSynced();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('اتمسح $removed صف اتزامن')),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _pruning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        const SectionHeader(
          title: 'قاعدة البيانات',
          subtitle: 'أدوات المطوّر · على الجهاز والسيرفر',
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'المخزن المحلي'),
              const SizedBox(height: 8),
              if (_local.isEmpty)
                const Text('بنعدّ…', style: AppText.caption)
              else
                for (final e in _local.entries)
                  _StoreRow(
                    label: e.key,
                    count: e.value,
                    drillable: _stores.containsKey(e.key),
                    onDrill: () => _drill(e.key),
                  ),
              const SizedBox(height: 12),
              RmsButton(
                label: _pruning ? 'بنمسح…' : 'امسح صفوف الصادر اللي اتزامنت',
                icon: Icons.cleaning_services_outlined,
                onPressed: _pruning ? null : _prune,
              ),
            ],
          ),
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(
                title: 'الخادم',
                subtitle: 'مرايا Firestore',
              ),
              const SizedBox(height: 8),
              if (_remoteError != null)
                Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: AppColors.negative),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'القراءة فشلت: $_remoteError',
                        style: AppText.caption,
                      ),
                    ),
                  ],
                )
              else if (_remote.isEmpty)
                const Text('بنعدّ…', style: AppText.caption)
              else
                for (final e in _remote.entries)
                  KeyValue(
                    label: e.key,
                    value: e.value < 0 ? '—' : '${e.value}',
                    mono: true,
                  ),
            ],
          ),
        ),
        if (_loading)
          const SurfaceCard(
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text('بنحدّث العدّادات…', style: AppText.caption),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One local store row: label, count, and a drill chevron when the store
/// behind it can show sample rows.
class _StoreRow extends StatelessWidget {
  const _StoreRow({
    required this.label,
    required this.count,
    required this.drillable,
    required this.onDrill,
  });

  final String label;
  final int count;
  final bool drillable;
  final VoidCallback onDrill;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: drillable ? onDrill : null,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: AppText.tableCellPrimary),
            ),
            Text(
              count < 0 ? '—' : '$count',
              style: AppText.mono,
            ),
            if (drillable) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_left,
                  size: 16, color: AppColors.fgGhost),
            ],
          ],
        ),
      ),
    );
  }
}
