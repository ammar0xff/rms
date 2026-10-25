import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_grab_handle.dart';
import '../../data/local/outbox/outbox_entry.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../domain/models/app_role.dart';

/// Screen 23: Diagnostics, Sync Engine, Node ID, Outbox status queue, and payload inspector.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<OutboxEntry> _entries = [];
  bool _isLoading = true;
  String _selectedFilter = 'all'; // 'all', 'pending', 'error', 'synced'
  bool _allowSignUp = true;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _signUpSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEntries());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_signUpSub == null) {
      final services = AppScope.of(context);
      services.facility?.load().then((f) {
        if (mounted) {
          setState(() => _allowSignUp = f.allowSignUp);
        }
      });
      if (services.firebaseReady) {
        _signUpSub = FirebaseFirestore.instance
            .collection('public_settings')
            .doc('auth')
            .snapshots()
            .listen((snap) {
          if (mounted && snap.exists && snap.data() != null) {
            final val = snap.data()!['allowSignUp'] as bool?;
            if (val != null) {
              setState(() => _allowSignUp = val);
            }
          }
        }, onError: (_) {});
      }
    }
  }

  @override
  void dispose() {
    _signUpSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleSignUp(bool value) async {
    setState(() => _allowSignUp = value);
    PieSoundService.instance.pop();

    final services = AppScope.of(context);
    final repo = services.facility;
    if (repo != null) {
      final current = await repo.load();
      await repo.save(current.copyWith(allowSignUp: value));
    }

    if (services.firebaseReady) {
      try {
        await FirebaseFirestore.instance.collection('public_settings').doc('auth').set({
          'allowSignUp': value,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': services.auth.currentUser?.email ?? 'developer',
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error updating public_settings/auth: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: value ? PieColors.stateSynced : PieColors.stateError,
          content: Text(
            value
                ? 'تم تفعيل تسجيل الموظفين الجدد (Sign Up Enabled)'
                : 'تم إيقاف وتعطيل تسجيل الموظفين الجدد (Sign Up Disabled)',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    final outbox = AppScope.of(context).outbox;
    if (outbox == null) {
      setState(() => _isLoading = false);
      return;
    }
    final list = await outbox.all();
    if (mounted) {
      setState(() {
        _entries = list.reversed.toList(); // Newest first
        _isLoading = false;
      });
    }
  }

  Future<void> _pruneSynced() async {
    final outbox = AppScope.of(context).outbox;
    if (outbox == null) return;
    final count = await outbox.pruneSynced();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تنظيف $count عملية متزامنة بنجاح.'),
          backgroundColor: PieColors.stateSynced,
        ),
      );
      _loadEntries();
    }
  }

  List<OutboxEntry> get _filteredEntries {
    return _entries.where((e) {
      if (_selectedFilter == 'pending') {
        return e.syncStatus == OutboxStatus.pending ||
            e.syncStatus == OutboxStatus.inProgress;
      }
      if (_selectedFilter == 'error') {
        return e.syncStatus == OutboxStatus.retryableFailure ||
            e.syncStatus == OutboxStatus.conflict ||
            e.syncStatus == OutboxStatus.permanentlyRejected;
      }
      if (_selectedFilter == 'synced') {
        return e.syncStatus == OutboxStatus.synced;
      }
      return true;
    }).toList();
  }

  void _showPayloadSheet(OutboxEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: PieRadius.topLg),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: PieColors.surface2,
            borderRadius: PieRadius.topLg,
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PieGrabHandle(margin: EdgeInsets.only(bottom: 12)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'تفاصيل العملية: ${entry.entityType}',
                    style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: PieColors.textMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'المعرف: ${entry.operationId} (مفتاح التكرار: ${entry.idempotencyKey})',
                style: PieTypography.caption.copyWith(color: PieColors.textMuted),
              ),
              const SizedBox(height: 12),
              if (entry.lastError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PieColors.stateError.withValues(alpha: 0.15),
                    borderRadius: PieRadius.borderMd,
                    border: Border.all(color: PieColors.stateError.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: PieColors.stateError),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'الخطأ الأخير: ${entry.lastError}',
                          style: PieTypography.caption.copyWith(color: PieColors.stateError),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text('البيانات البرمجية (Payload):', style: PieTypography.body.copyWith(color: PieColors.textSecondary)),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PieColors.well,
                    borderRadius: PieRadius.borderMd,
                    border: Border.all(color: PieColors.borderMuted),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      const JsonEncoder.withIndent('  ').convert(entry.payload),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: PieColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    final pendingCount = _entries.where((e) =>
        e.syncStatus == OutboxStatus.pending ||
        e.syncStatus == OutboxStatus.inProgress).length;
    final errorCount = _entries.where((e) =>
        e.syncStatus == OutboxStatus.retryableFailure ||
        e.syncStatus == OutboxStatus.conflict).length;
    final syncedCount = _entries.where((e) => e.syncStatus == OutboxStatus.synced).length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // Engine Overview Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: PieColors.surface2,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'معرف الجهاز / العقدة',
                        style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        services.config.projectId.isNotEmpty
                            ? 'NODE-${services.config.projectId.substring(0, 8).toUpperCase()}'
                            : 'NODE-LOCAL-DEMO',
                        style: PieTypography.body.copyWith(
                          color: PieColors.roleSystem,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: services.firebaseReady
                        ? PieColors.stateSynced.withValues(alpha: 0.15)
                        : PieColors.statePending.withValues(alpha: 0.15),
                    borderRadius: PieRadius.borderSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        services.firebaseReady ? Icons.cloud_done : Icons.cloud_off,
                        size: 16,
                        color: services.firebaseReady ? PieColors.stateSynced : PieColors.statePending,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        services.firebaseReady ? 'متصل بالسحابة' : 'وضع محلي مستقل',
                        style: PieTypography.caption.copyWith(
                          color: services.firebaseReady ? PieColors.stateSynced : PieColors.statePending,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: _allowSignUp
                      ? 'تسجيل الموظفين مفعّل (انقر للتعطيل)'
                      : 'تسجيل الموظفين معطّل (انقر للتفعيل)',
                  child: InkWell(
                    onTap: () => _toggleSignUp(!_allowSignUp),
                    borderRadius: PieRadius.borderSm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _allowSignUp
                            ? PieColors.stateSynced.withValues(alpha: 0.15)
                            : PieColors.stateError.withValues(alpha: 0.15),
                        borderRadius: PieRadius.borderSm,
                        border: Border.all(
                          color: _allowSignUp
                              ? PieColors.stateSynced.withValues(alpha: 0.4)
                              : PieColors.stateError.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _allowSignUp ? Icons.person_add_rounded : Icons.person_off_rounded,
                            size: 16,
                            color: _allowSignUp ? PieColors.stateSynced : PieColors.stateError,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _allowSignUp ? 'تسجيل الموظفين: مفعّل' : 'تسجيل الموظفين: مغلق',
                            style: PieTypography.caption.copyWith(
                              color: _allowSignUp ? PieColors.stateSynced : PieColors.stateError,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, color: PieColors.textSecondary, size: 20),
                  tooltip: 'تحديث القائمة',
                  onPressed: _loadEntries,
                ),
                IconButton(
                  icon: const Icon(Icons.cleaning_services_outlined, color: PieColors.textSecondary, size: 20),
                  tooltip: 'تنظيف العمليات المتزامنة',
                  onPressed: _pruneSynced,
                ),
              ],
            ),
          ),

            // Filter Tabs
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: PieColors.surface1,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: Text('الكل (${_entries.length})'),
                      selected: _selectedFilter == 'all',
                      selectedColor: PieColors.roleSystem.withValues(alpha: 0.2),
                      backgroundColor: PieColors.well,
                      side: BorderSide(
                        color: _selectedFilter == 'all' ? PieColors.roleSystem : PieColors.borderMuted,
                      ),
                      onSelected: (_) => setState(() => _selectedFilter = 'all'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('قيد المزامنة ($pendingCount)'),
                      selected: _selectedFilter == 'pending',
                      selectedColor: PieColors.statePending.withValues(alpha: 0.2),
                      backgroundColor: PieColors.well,
                      side: BorderSide(
                        color: _selectedFilter == 'pending' ? PieColors.statePending : PieColors.borderMuted,
                      ),
                      onSelected: (_) => setState(() => _selectedFilter = 'pending'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('أخطاء وتعارضات ($errorCount)'),
                      selected: _selectedFilter == 'error',
                      selectedColor: PieColors.stateError.withValues(alpha: 0.2),
                      backgroundColor: PieColors.well,
                      side: BorderSide(
                        color: _selectedFilter == 'error' ? PieColors.stateError : PieColors.borderMuted,
                      ),
                      onSelected: (_) => setState(() => _selectedFilter = 'error'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('مكتمل ($syncedCount)'),
                      selected: _selectedFilter == 'synced',
                      selectedColor: PieColors.stateSynced.withValues(alpha: 0.2),
                      backgroundColor: PieColors.well,
                      side: BorderSide(
                        color: _selectedFilter == 'synced' ? PieColors.stateSynced : PieColors.borderMuted,
                      ),
                      onSelected: (_) => setState(() => _selectedFilter = 'synced'),
                    ),
                  ],
                ),
              ),
            ),

            // Outbox List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: PieColors.roleSystem),
                    )
                  : _filteredEntries.isEmpty
                      ? const PieEmptyState(
                          icon: Icons.done_all,
                          title: 'صندوق العمليات الصادرة فارغ',
                          subtitle: 'لا توجد عمليات تطابق الفلتر المختار.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredEntries.length,
                          itemBuilder: (ctx, i) => _buildEntryCard(_filteredEntries[i]),
                        ),
            ),
          ],
        ),
    );
  }

  Widget _buildEntryCard(OutboxEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PieCard(
        surface: PieColors.surface2,
        role: AppRole.developer,
        onTap: () => _showPayloadSheet(entry),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: PieColors.roleSystem.withValues(alpha: 0.15),
                          borderRadius: PieRadius.borderSm,
                        ),
                        child: Text(
                          _localizeOperation(entry.operationType),
                          style: PieTypography.caption.copyWith(
                            color: PieColors.roleSystem,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _localizeEntity(entry.entityType),
                        style: PieTypography.caption.copyWith(
                          color: PieColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _formatEntityId(entry.entityId),
                          style: PieTypography.body.copyWith(
                            color: PieColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(entry.syncStatus),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'المحاولات: ${entry.attemptCount}',
                  style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                ),
                Text(
                  _formatTimestamp(entry.createdAt),
                  style: PieTypography.caption.copyWith(color: PieColors.textMuted),
                ),
              ],
            ),
            if (entry.lastError != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: PieColors.stateError.withValues(alpha: 0.1),
                  borderRadius: PieRadius.borderSm,
                  border: Border.all(color: PieColors.stateError.withValues(alpha: 0.3)),
                ),
                child: Text(
                  entry.lastError!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PieTypography.caption.copyWith(color: PieColors.stateError),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _localizeOperation(String op) {
    final lower = op.toLowerCase();
    if (lower.contains('settledriver')) return 'تسوية عهدة طيار';
    if (lower.contains('deliverystate')) return 'تحديث حالة توصيل';
    if (lower.contains('createdelivery')) return 'إنشاء توصيل';
    if (lower.contains('recordcollection')) return 'تحصيل كاش';
    if (lower.contains('submitapproval')) return 'طلب اعتماد';
    if (lower.contains('recordbatchsettlement')) return 'توريد عهدة كاش';
    if (lower.contains('finalizesettlement')) return 'إخلاء طرف';
    return switch (lower) {
      'create' => 'إنشاء',
      'update' => 'تحديث',
      'delete' => 'حذف',
      'upsert' => 'حفظ',
      _ => op.toUpperCase(),
    };
  }

  String _localizeEntity(String entity) {
    return switch (entity.toLowerCase()) {
      'order' => 'طلب',
      'delivery' => 'توصيل',
      'collection' => 'تحصيل',
      'payment' => 'مدفوعات',
      'drawer_shift' || 'drawer' => 'درج نقدية',
      'inventory' => 'مخزون',
      'stock_movement' => 'حركة مخزون',
      'supplier' => 'مورد',
      'expense' => 'مصروفات',
      'customer' => 'عميل',
      'user' => 'مستخدم',
      'facility' => 'المنشأة',
      'branch' => 'فرع',
      _ => entity,
    };
  }

  String _formatEntityId(String id) {
    if (id.length > 18 && !id.contains(' ')) {
      return '#${id.substring(0, 8)}...';
    }
    return id.startsWith('#') ? id : '#$id';
  }

  Widget _buildStatusBadge(OutboxStatus status) {
    return switch (status) {
      OutboxStatus.synced => const PieBadge(label: 'متزامن', variant: PieBadgeVariant.synced),
      OutboxStatus.pending => const PieBadge(label: 'بالانتظار', variant: PieBadgeVariant.pending),
      OutboxStatus.inProgress => const PieBadge(label: 'جاري الإرسال', variant: PieBadgeVariant.pending),
      OutboxStatus.retryableFailure => const PieBadge(label: 'فشل مؤقت', variant: PieBadgeVariant.error),
      OutboxStatus.conflict => const PieBadge(label: 'تعارض', variant: PieBadgeVariant.conflict),
      OutboxStatus.permanentlyRejected => const PieBadge(label: 'مرفوض', variant: PieBadgeVariant.error),
      OutboxStatus.requiresUserAction => const PieBadge(label: 'يتطلب إجراء', variant: PieBadgeVariant.conflict),
    };
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}
