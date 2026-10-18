import 'package:flutter/material.dart';
import '../../domain/models/dining_table.dart';
import '../../domain/models/order_type.dart';
import '../../domain/models/delivery.dart';
import '../theme/pie_colors.dart';
import '../theme/pie_typography.dart';

enum PieBadgeVariant {
  synced,
  pending,
  conflict,
  error,
  localOnly,
  neutral,
}

/// Semantic Badges & Chips
///
/// Ensures operational state is unmistakable at a glance:
/// - Sync status (reconciled vs on-device vs conflict)
/// - Service channel (hall vs takeaway vs delivery)
/// - Table occupancy state
/// - Delivery trip phase
class PieBadge extends StatelessWidget {
  const PieBadge({
    super.key,
    required this.label,
    this.color,
    this.backgroundColor,
    this.variant,
    this.icon,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  final String label;
  final Color? color;
  final Color? backgroundColor;
  final PieBadgeVariant? variant;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  Color get effectiveColor {
    if (color != null) return color!;
    return switch (variant ?? PieBadgeVariant.neutral) {
      PieBadgeVariant.synced => PieColors.stateSynced,
      PieBadgeVariant.pending => PieColors.statePending,
      PieBadgeVariant.conflict => PieColors.stateConflict,
      PieBadgeVariant.error => PieColors.stateError,
      PieBadgeVariant.localOnly => PieColors.inkSecondary,
      PieBadgeVariant.neutral => PieColors.inkSecondary,
    };
  }

  Color get effectiveBackgroundColor {
    if (backgroundColor != null) return backgroundColor!;
    return switch (variant ?? PieBadgeVariant.neutral) {
      PieBadgeVariant.synced => PieColors.stateSyncedBg,
      PieBadgeVariant.pending => PieColors.statePendingBg,
      PieBadgeVariant.conflict => PieColors.stateConflictBg,
      PieBadgeVariant.error => PieColors.stateErrorBg,
      PieBadgeVariant.localOnly => PieColors.well,
      PieBadgeVariant.neutral => PieColors.well,
    };
  }

  /// Sync state badge: Is this synced, local on-device, or conflicted?
  factory PieBadge.syncStatus({
    required bool isSynced,
    bool isPending = false,
    bool isConflict = false,
    bool isOffline = false,
    int pendingCount = 0,
  }) {
    if (isConflict) {
      return const PieBadge(
        label: 'تعارض في البيانات',
        color: PieColors.stateConflict,
        backgroundColor: PieColors.stateConflictBg,
        icon: Icons.warning_amber_rounded,
      );
    }
    if (isOffline) {
      return PieBadge(
        label: pendingCount > 0 ? 'أوفلاين ($pendingCount معلق)' : 'أوفلاين',
        color: PieColors.stateOffline,
        backgroundColor: PieColors.stateOfflineBg,
        icon: Icons.cloud_off_rounded,
      );
    }
    if (isPending) {
      return PieBadge(
        label: pendingCount > 0 ? 'على الجهاز ($pendingCount)' : 'على الجهاز',
        color: PieColors.statePending,
        backgroundColor: PieColors.statePendingBg,
        icon: Icons.cloud_upload_outlined,
      );
    }
    return const PieBadge(
      label: 'متزامن',
      color: PieColors.stateSynced,
      backgroundColor: PieColors.stateSyncedBg,
      icon: Icons.check_circle_outline_rounded,
    );
  }

  /// Channel badge: Hall, Takeaway, Delivery
  factory PieBadge.channel(OrderType channel) {
    return switch (channel) {
      OrderType.dineIn => const PieBadge(
          label: 'صالة',
          color: Color(0xFF60A5FA),
          backgroundColor: Color(0xFF172554),
          icon: Icons.table_restaurant_rounded,
        ),
      OrderType.takeaway => const PieBadge(
          label: 'تيك أواي',
          color: Color(0xFFFBBF24),
          backgroundColor: Color(0xFF451A03),
          icon: Icons.shopping_bag_outlined,
        ),
      OrderType.delivery => const PieBadge(
          label: 'دليفري',
          color: PieColors.driverAccent,
          backgroundColor: Color(0xFF082F49),
          icon: Icons.two_wheeler_rounded,
        ),
    };
  }

  /// Table occupancy state badge
  factory PieBadge.tableState(TableStatus status) {
    return switch (status) {
      TableStatus.vacant => const PieBadge(
          label: 'فاضية',
          color: Color(0xFF4ADE80),
          backgroundColor: Color(0xFF052E16),
          icon: Icons.check_rounded,
        ),
      TableStatus.occupied => const PieBadge(
          label: 'مشغولة',
          color: PieColors.cashierAccent,
          backgroundColor: Color(0xFF451A03),
          icon: Icons.people_outline_rounded,
        ),
      TableStatus.billRequested => const PieBadge(
          label: 'طلب الحساب',
          color: Color(0xFFF87171),
          backgroundColor: Color(0xFF450A0A),
          icon: Icons.receipt_long_rounded,
        ),
    };
  }

  /// Delivery state badge
  factory PieBadge.deliveryState(DeliveryState state) {
    return switch (state) {
      DeliveryState.waiting => const PieBadge(
          label: 'مستني طيار',
          color: PieColors.statePending,
          backgroundColor: PieColors.statePendingBg,
          icon: Icons.hourglass_top_rounded,
        ),
      DeliveryState.assigned => const PieBadge(
          label: 'اتسند لطيار',
          color: PieColors.driverAccent,
          backgroundColor: PieColors.driverSurface,
          icon: Icons.person_pin_circle_outlined,
        ),
      DeliveryState.onRoute => const PieBadge(
          label: 'في الطريق',
          color: Color(0xFF38BDF8),
          backgroundColor: Color(0xFF0C4A6E),
          icon: Icons.navigation_rounded,
        ),
      DeliveryState.delivered => const PieBadge(
          label: 'اتسلّم',
          color: PieColors.stateSynced,
          backgroundColor: PieColors.stateSyncedBg,
          icon: Icons.done_all_rounded,
        ),
      DeliveryState.failed => const PieBadge(
          label: 'فشل التسليم',
          color: PieColors.stateError,
          backgroundColor: PieColors.stateErrorBg,
          icon: Icons.cancel_outlined,
        ),
      DeliveryState.returned => const PieBadge(
          label: 'مرتجع للمطعم',
          color: Color(0xFFA78BFA),
          backgroundColor: Color(0xFF2E1065),
          icon: Icons.assignment_return_outlined,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final fg = effectiveColor;
    final bg = effectiveBackgroundColor;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: PieTypography.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
