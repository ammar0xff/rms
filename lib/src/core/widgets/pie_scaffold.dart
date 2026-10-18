import 'package:flutter/material.dart';
import '../../domain/models/app_role.dart';
import '../../domain/models/branch.dart';
import '../di/app_services.dart';
import '../sound/pie_sound_service.dart';
import '../state/sync_monitor.dart';
import '../theme/pie_colors.dart';
import '../theme/pie_typography.dart';
import 'pie_badge.dart';

class PieNavItem {
  const PieNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Unified PIE Application Scaffold
///
/// Features:
/// - RTL-native: pins navigation and identity properly.
/// - Unmistakable role uniform: top role bar and accents immediately identify which app is active.
/// - Honest sync indicator: live outbox and connectivity state always visible in the chrome.
/// - Responsive: Bottom bar on mobile (< 900px) and docked vertical rail on desktop (>= 900px).
class PieScaffold extends StatelessWidget {
  const PieScaffold({
    super.key,
    required this.role,
    required this.items,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.body,
    this.title,
    this.actions,
    this.onRoleSwitch,
    this.floatingActionButton,
  });

  final AppRole role;
  final List<PieNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final String? title;
  final List<Widget>? actions;
  /// Switching roles is a demo affordance only. Null means no switcher is
  /// rendered — the control does not exist outside demo mode.
  final ValueChanged<AppRole>? onRoleSwitch;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final roleAccent = PieColors.accentFor(role);
    final services = AppScope.of(context);

    // Watch sync monitor for honest sync status
    final monitor = SyncMonitor.instance;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        floatingActionButton: floatingActionButton,
        appBar: AppBar(
          backgroundColor: PieColors.canvas,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 56,
          automaticallyImplyLeading: false,
          centerTitle: false,
          titleSpacing: isDesktop ? 16 : 8,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: PieColors.border, height: 1, thickness: 1),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Role Identity Badge
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: PieColors.surfaceFor(role),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: PieColors.borderFor(role), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: roleAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          role.label,
                          style: PieTypography.label.copyWith(
                            color: roleAccent,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (isDesktop) ...[
                const SizedBox(width: 10),
                FutureBuilder<BranchModel?>(
                  future: services.branches?.activeBranch(),
                  builder: (context, branchSnap) {
                    final branch = branchSnap.data;
                    final branchName = branch?.name ?? 'فرع المعادي';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: PieColors.surface2,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: PieColors.borderMuted),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.storefront_outlined,
                            size: 14,
                            color: PieColors.inkSecondary,
                          ),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Text(
                              branchName,
                              style: PieTypography.caption.copyWith(
                                color: PieColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title ?? 'فطيرة للتشغيل',
                    style: PieTypography.subheading.copyWith(
                      fontWeight: FontWeight.w600,
                      color: PieColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            // Honest Sync Chip (Clickable for sync diagnostic / offline toggle)
            ListenableBuilder(
              listenable: monitor,
              builder: (context, _) {
                final isOffline = !monitor.online;
                return Tooltip(
                  message: 'اضغط لعرض تفاصيل المزامنة وحالة الاتصال',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _showSyncStatusModal(context, monitor, services),
                    child: PieBadge.syncStatus(
                      isSynced: monitor.pending == 0 && monitor.conflicts == 0 && !isOffline,
                      isPending: monitor.pending > 0,
                      isConflict: monitor.conflicts > 0,
                      isOffline: isOffline,
                      pendingCount: monitor.pending,
                      compact: !isDesktop,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
            // Role Switcher Button (demo)
            if (onRoleSwitch != null)
              PopupMenuButton<AppRole>(
                tooltip: 'تبديل الدور الوظيفي',
                icon: const Icon(Icons.swap_horiz_rounded, color: PieColors.inkSecondary),
                color: PieColors.surfaceOverlay,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: PieColors.border),
                ),
                onSelected: onRoleSwitch,
                itemBuilder: (context) => [
                  _buildRoleMenuItem(AppRole.cashier, role),
                  _buildRoleMenuItem(AppRole.driver, role),
                  _buildRoleMenuItem(AppRole.manager, role),
                  _buildRoleMenuItem(AppRole.developer, role),
                ],
              ),
            if (actions != null) ...actions!,
          ],
        ),
        body: isDesktop ? _buildDesktopLayout(roleAccent) : body,
        bottomNavigationBar: isDesktop ? null : _buildMobileBottomBar(roleAccent),
      ),
    );
  }

  PopupMenuItem<AppRole> _buildRoleMenuItem(AppRole targetRole, AppRole currentRole) {
    final isSelected = targetRole == currentRole;
    final accent = PieColors.accentFor(targetRole);

    return PopupMenuItem<AppRole>(
      value: targetRole,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            targetRole.label,
            style: PieTypography.bodyStrong.copyWith(
              color: isSelected ? accent : PieColors.ink,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            Icon(Icons.check_rounded, size: 16, color: accent),
          ],
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(Color roleAccent) {
    return Row(
      children: [
        // Persistent Right Navigation Rail for RTL
        Container(
          width: 220,
          decoration: const BoxDecoration(
            color: PieColors.surface1,
            border: Border(left: BorderSide(color: PieColors.border, width: 1)),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final isSelected = index == currentIndex;

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: isSelected ? roleAccent.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () {
                      PieSoundService.instance.click();
                      onDestinationSelected(index);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(color: roleAccent.withOpacity(0.4), width: 1)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? item.selectedIcon : item.icon,
                            size: 20,
                            color: isSelected ? roleAccent : PieColors.inkMuted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.label,
                              style: PieTypography.bodyStrong.copyWith(
                                color: isSelected ? roleAccent : PieColors.inkSecondary,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Main Screen Canvas
        Expanded(child: body),
      ],
    );
  }

  Widget _buildMobileBottomBar(Color roleAccent) {
    return Container(
      decoration: const BoxDecoration(
        color: PieColors.surface1,
        border: Border(top: BorderSide(color: PieColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = index == currentIndex;

              return Expanded(
                child: InkWell(
                  onTap: () {
                    PieSoundService.instance.click();
                    onDestinationSelected(index);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSelected ? roleAccent.withValues(alpha: 0.15) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isSelected ? item.selectedIcon : item.icon,
                            size: 20,
                            color: isSelected ? roleAccent : PieColors.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              item.label,
                              style: PieTypography.caption.copyWith(
                                color: isSelected ? roleAccent : PieColors.inkMuted,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 10.5,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  void _showSyncStatusModal(BuildContext context, SyncMonitor monitor, AppServices services) {
    PieSoundService.instance.click();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: PieColors.border),
          ),
          title: Row(
            children: [
              const Icon(Icons.sync_rounded, color: PieColors.stateSynced, size: 22),
              const SizedBox(width: 8),
              Text('حالة الاتصال والمزامنة', style: PieTypography.heading),
            ],
          ),
          content: StatefulBuilder(
            builder: (ctx, setModalState) {
              final isOffline = !monitor.online;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isOffline ? PieColors.stateOfflineBg : PieColors.stateSyncedBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isOffline ? PieColors.stateOffline : PieColors.stateSynced,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isOffline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                          color: isOffline ? PieColors.stateOffline : PieColors.stateSynced,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isOffline ? 'النظام في وضع العمل بدون إنترنت (أوفلاين)' : 'النظام متصل بالإنترنت ومباشر',
                                style: PieTypography.bodyStrong.copyWith(
                                  color: isOffline ? PieColors.stateOffline : PieColors.stateSynced,
                                ),
                              ),
                              Text(
                                isOffline
                                    ? 'كل العمليات تسجل محلياً على الجهاز ويتم حفظها في صندوق الصادر.'
                                    : 'تتم مزامنة العمليات تلقائياً مع السيرفر السحابي.',
                                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text('محاكاة وضع أوفلاين (اختبار)', style: PieTypography.body),
                    subtitle: Text('يفصل الاتصال برمجياً لاختبار المعاملات دون شبكة', style: PieTypography.caption),
                    value: monitor.isSimulatedOffline,
                    activeColor: PieColors.stateOffline,
                    onChanged: (val) {
                      setModalState(() {
                        monitor.setSimulatedOffline(val);
                      });
                      PieSoundService.instance.pop();
                    },
                  ),
                  const Divider(color: PieColors.border),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('عمليات معلقة على الجهاز:', style: PieTypography.body),
                      Text('${monitor.pending}', style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('عمليات متزامنة ومستقرة:', style: PieTypography.body),
                      Text('${monitor.synced}', style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (monitor.conflicts > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('تعارضات بحاجة لمراجعة:', style: PieTypography.body.copyWith(color: PieColors.stateConflict)),
                        Text('${monitor.conflicts}', style: PieTypography.monoBody.copyWith(color: PieColors.stateConflict, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: PieColors.surface2,
                foregroundColor: PieColors.stateSynced,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('مزامنة الآن'),
              onPressed: () async {
                PieSoundService.instance.pop();
                if (services.sync != null) {
                  await services.sync!.requestSync();
                }
                await monitor.refresh();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
