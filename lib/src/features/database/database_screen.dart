import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sembast/sembast.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
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
      final local = <String, int>{
        'الطلبات': await _count(db, LocalStores.orders),
        'المدفوعات': await _count(db, LocalStores.payments),
        'التوصيل': await _count(db, LocalStores.deliveries),
        'التحصيلات': await _count(db, LocalStores.collections),
        'المشتريات': await _count(db, LocalStores.purchases),
        'الموردون': await _count(db, LocalStores.suppliers),
        'المخزون': await _count(db, LocalStores.inventory),
        'حركات المخزون': await _count(db, LocalStores.stockMovements),
        'القائمة': await _count(db, LocalStores.menu),
        'تذاكر المطبخ': await _count(db, LocalStores.kitchenTickets),
        'العملاء': await _count(db, LocalStores.customers),
        'الجلسات النقدية': await _count(db, LocalStores.cashSessions),
        'الموافقات': await _count(db, LocalStores.approvals),
        'التدقيق': await _count(db, LocalStores.audit),
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
      local['الصادر (معلّق)'] = pending;
      local['الصادر (مُزامَن)'] = synced;
      if (!mounted) return;
      setState(() => _local = local);

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

  Future<void> _prune() async {
    final outbox = AppScope.of(context).outbox;
    if (outbox == null || _pruning) return;
    setState(() => _pruning = true);
    try {
      final removed = await outbox.pruneSynced();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حُذف $removed صفًا مُزامَنًا')),
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
          subtitle: 'أدوات المطوّر · المحلي والخادم',
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'المخزن المحلي'),
              const SizedBox(height: 8),
              if (_local.isEmpty)
                const Text('جارٍ العد…', style: AppText.caption)
              else
                for (final e in _local.entries)
                  KeyValue(
                    label: e.key,
                    value: e.value < 0 ? '—' : '${e.value}',
                    mono: true,
                  ),
              const SizedBox(height: 12),
              RmsButton(
                label: _pruning ? 'جارٍ الحذف…' : 'حذف صفوف الصادر المُزامَنة',
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
                        'تعذّرت القراءة: $_remoteError',
                        style: AppText.caption,
                      ),
                    ),
                  ],
                )
              else if (_remote.isEmpty)
                const Text('جارٍ العد…', style: AppText.caption)
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
                  child: Text('تحديث العدّادات…', style: AppText.caption),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
