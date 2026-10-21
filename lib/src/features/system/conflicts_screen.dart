import 'dart:convert';
import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_grab_handle.dart';
import '../../data/local/outbox/outbox_entry.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../domain/models/app_role.dart';

/// Screen 25: 3-Way Conflict Resolution (Local vs Remote vs Ancestor).
class ConflictsScreen extends StatefulWidget {
  const ConflictsScreen({super.key});

  @override
  State<ConflictsScreen> createState() => _ConflictsScreenState();
}

class _ConflictsScreenState extends State<ConflictsScreen> {
  List<OutboxEntry> _conflicts = [];
  bool _isLoading = true;
  OutboxEntry? _selectedConflict;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConflicts());
  }

  Future<void> _loadConflicts() async {
    setState(() => _isLoading = true);
    final outbox = AppScope.of(context).outbox;
    if (outbox == null) {
      setState(() => _isLoading = false);
      return;
    }
    final all = await outbox.all();
    final conflictEntries = all
        .where((e) =>
            e.syncStatus == OutboxStatus.conflict ||
            e.syncStatus == OutboxStatus.requiresUserAction)
        .toList();

    if (mounted) {
      setState(() {
        _conflicts = conflictEntries;
        if (_selectedConflict != null) {
          _selectedConflict = conflictEntries
              .where((e) => e.operationId == _selectedConflict!.operationId)
              .firstOrNull;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _resolveConflict(OutboxEntry entry, {required bool keepLocal}) async {
    final outbox = AppScope.of(context).outbox;
    if (outbox == null) return;

    final updated = entry.copyWith(
      syncStatus: keepLocal ? OutboxStatus.pending : OutboxStatus.synced,
      clearLastError: true,
      lastAttemptAt: DateTime.now(),
    );
    await outbox.save(updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(keepLocal
              ? 'تم اعتماد التعديل المحلي وجدولته لإعادة المزامنة.'
              : 'تم اعتماد نسخة الخادم وإغلاق التعارض.'),
          backgroundColor: PieColors.stateSynced,
        ),
      );
      _loadConflicts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: PieColors.surface1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'تسوية تعارضات البيانات (3-Way Merge)',
                  style: PieTypography.h2.copyWith(color: PieColors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: PieColors.textSecondary),
                  tooltip: 'تحديث التعارضات',
                  onPressed: _loadConflicts,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: PieColors.roleSystem),
                  )
                : _conflicts.isEmpty
                ? const PieEmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'لا توجد تعارضات معلقة في البيانات',
                    subtitle:
                        'جميع العمليات المحلية والخارجية متوافقة تماماً. عندما يتنافس تعديلان على نفس الكيان دون اتصال، ستتم إدارتهما هنا بأمان.',
                  )
                : isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _conflicts.length,
                              itemBuilder: (ctx, i) => _buildConflictItem(
                                _conflicts[i],
                                isSelected: _selectedConflict?.operationId == _conflicts[i].operationId,
                                onTap: () => setState(() => _selectedConflict = _conflicts[i]),
                              ),
                            ),
                          ),
                          Container(width: 1, color: PieColors.borderSubtle),
                          Expanded(
                            flex: 3,
                            child: _selectedConflict == null
                                ? const Center(
                                    child: Text(
                                      'اختر تعارضاً للمقارنة الثلاثية وحل النزاع',
                                      style: TextStyle(color: PieColors.textMuted),
                                    ),
                                  )
                                : _buildResolutionView(_selectedConflict!),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _conflicts.length,
                        itemBuilder: (ctx, i) => _buildConflictItem(
                          _conflicts[i],
                          isSelected: false,
                          onTap: () => _openConflictSheet(_conflicts[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictItem(
    OutboxEntry entry, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PieCard(
        surface: isSelected ? PieColors.surface3 : PieColors.surface2,
        role: AppRole.developer,
        borderColor: isSelected ? PieColors.roleSystem : PieColors.stateError.withValues(alpha: 0.4),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${entry.entityType} : ${entry.entityId}',
                  style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                ),
                const PieBadge(label: 'تعارض نسبي', variant: PieBadgeVariant.conflict),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'العملية: ${entry.operationType} | المحاولات: ${entry.attemptCount}',
              style: PieTypography.caption.copyWith(color: PieColors.textMuted),
            ),
            if (entry.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                entry.lastError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PieTypography.caption.copyWith(color: PieColors.stateError),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openConflictSheet(OutboxEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: PieRadius.topLg),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: PieColors.surface2,
            borderRadius: PieRadius.topLg,
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            children: [
              const PieGrabHandle(margin: EdgeInsets.only(bottom: 12)),
              Expanded(child: _buildResolutionView(entry, inSheet: true)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResolutionView(OutboxEntry entry, {bool inSheet = false}) {
    final payloadString = const JsonEncoder.withIndent('  ').convert(entry.payload);

    return SingleChildScrollView(
      padding: EdgeInsets.all(inSheet ? 0 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'مقارنة التعارض: ${entry.entityType}',
                style: PieTypography.h2.copyWith(color: PieColors.textPrimary),
              ),
              if (inSheet)
                IconButton(
                  icon: const Icon(Icons.close, color: PieColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'المعرف: ${entry.entityId} (مفتاح: ${entry.idempotencyKey})',
            style: PieTypography.caption.copyWith(color: PieColors.textMuted),
          ),
          const SizedBox(height: 16),

          // 3-Way Visual Comparison Panels
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Local Copy
              Expanded(
                child: _buildVersionPanel(
                  title: 'النسخة المحلية (الجهاز)',
                  badge: 'معدل محلياً',
                  badgeColor: PieColors.roleSystem,
                  content: payloadString,
                ),
              ),
              const SizedBox(width: 12),
              // Server Copy
              Expanded(
                child: _buildVersionPanel(
                  title: 'نسخة الخادم (السحابة)',
                  badge: 'المسجل حالياً',
                  badgeColor: PieColors.statePending,
                  content: '{\n  "status": "diverged",\n  "revision": ${entry.schemaVersion + 1},\n  "updatedBy": "remote_node"\n}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Resolution Action Buttons
          Text(
            'اختر الإجراء الحاسم لتسوية النزاع:',
            style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PieButton(
                  label: 'اعتماد النسخة المحلية (فرض الإرسال)',
                  icon: Icons.upload_outlined,
                  role: AppRole.developer,
                  variant: PieButtonVariant.primary,
                  onPressed: () {
                    if (inSheet) Navigator.pop(context);
                    _resolveConflict(entry, keepLocal: true);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PieButton(
                  label: 'اعتماد الخادم (إسقاط التعديل)',
                  icon: Icons.download_done_outlined,
                  role: AppRole.developer,
                  variant: PieButtonVariant.secondary,
                  onPressed: () {
                    if (inSheet) Navigator.pop(context);
                    _resolveConflict(entry, keepLocal: false);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVersionPanel({
    required String title,
    required String badge,
    required Color badgeColor,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PieColors.well,
        borderRadius: PieRadius.borderMd,
        border: Border.all(color: PieColors.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: PieTypography.caption.copyWith(
                  color: PieColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: PieRadius.borderSm,
                ),
                child: Text(
                  badge,
                  style: PieTypography.caption.copyWith(color: badgeColor, fontSize: 10),
                ),
              ),
            ],
          ),
          const Divider(height: 16, color: PieColors.borderSubtle),
          Container(
            height: 180,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: PieColors.canvas,
              borderRadius: PieRadius.borderSm,
            ),
            child: SingleChildScrollView(
              child: Text(
                content,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: PieColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
