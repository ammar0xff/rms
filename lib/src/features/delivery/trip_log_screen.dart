import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/blocks.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/role_ui.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/delivery.dart';
import '../common/format.dart';

/// The driver's day: totals strip, filter chips, and trip groups with
/// numbered stops and payment tags. Everything computed from deliveries
/// plus collections — distance and tips are not tracked, so they are not
/// shown (no stub figures).
class TripLogScreen extends StatefulWidget {
  const TripLogScreen({super.key});

  @override
  State<TripLogScreen> createState() => _TripLogScreenState();
}

class _TripLogScreenState extends State<TripLogScreen> {
  List<DeliveryModel> _deliveries = const [];
  List<CollectionModel> _collections = const [];
  bool _loaded = false;

  /// 0 النهاردة · 1 امبارح · 2 المرتجعات.
  int _filter = 0;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).deliveries;
    if (repo == null) return;
    final deliveries = await repo.listDeliveries();
    final collections = await repo.listCollections();
    if (!mounted) return;
    setState(() {
      _deliveries = deliveries;
      _collections = collections;
    });
  }

  bool _isToday(DateTime at) {
    final now = DateTime.now();
    return at.year == now.year && at.month == now.month && at.day == now.day;
  }

  bool _isYesterday(DateTime at) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return at.year == yesterday.year &&
        at.month == yesterday.month &&
        at.day == yesterday.day;
  }

  List<DeliveryModel> get _visible {
    List<DeliveryModel> list;
    switch (_filter) {
      case 1:
        list =
            _deliveries.where((d) => _isYesterday(d.createdAt)).toList();
        break;
      case 2:
        list = _deliveries
            .where((d) => d.isFailed || d.state == DeliveryState.returned)
            .toList();
        break;
      default:
        list = _deliveries.where((d) => _isToday(d.createdAt)).toList();
    }
    final q = _query.trim();
    if (q.isEmpty) return list;
    return list
        .where((d) =>
            d.orderRef.contains(q) || d.address.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final today = _deliveries.where((d) => _isToday(d.createdAt)).toList();
    final done = today.where((d) => d.state == DeliveryState.delivered).length;
    final failed = today.where((d) => d.isFailed).length;
    final cash = _collections
        .where((c) => _isToday(c.collectedAt))
        .fold(0.0, (sum, c) => sum + c.amount);
    final visible = _visible;
    return PageBody(
      maxWidth: 720,
      children: [
        GridRow(children: [
          KpiCard(
              label: 'أوردرات خلصانة',
              value: '$done',
              icon: Icons.check_circle_outline,
              accent: AppColors.driverAccent),
          KpiCard(
              label: 'كاش اليوم',
              value: money(cash),
              icon: Icons.payments_outlined,
              accent: AppColors.driverAccent),
          KpiCard(
              label: 'مرتجعات',
              value: '$failed',
              icon: Icons.undo_outlined,
              accent: AppColors.driverAccent),
        ]),
        ListToolbar(
          hint: 'دوّر برقم الأوردر…',
          onQuery: (v) => setState(() => _query = v),
          filters: const ['النهاردة', 'امبارح', 'المرتجعات'],
          selected: _filter,
          onFilter: (i) => setState(() => _filter = i),
        ),
        if (visible.isEmpty)
          const SurfaceCard(
            child: Text('مفيش رحلات بالفلتر ده.',
                style: AppText.caption),
          )
        else
          SurfaceCard(
            child: TimelineList(entries: [
              for (var i = 0; i < visible.length; i++)
                TimelineEntry(
                  tone: _tone(visible[i].state),
                  title:
                      'المحطة ${i + 1} · ${visible[i].orderRef}',
                  subtitle:
                      '${visible[i].address} · ${visible[i].state.label}',
                  trailing: Text(money(visible[i].amount),
                      style: AppText.tableCellPrimary),
                ),
            ]),
          ),
      ],
    );
  }

  StatusTone _tone(DeliveryState state) => switch (state) {
        DeliveryState.delivered => StatusTone.positive,
        DeliveryState.failed => StatusTone.negative,
        DeliveryState.returned => StatusTone.neutral,
        DeliveryState.onRoute => StatusTone.warning,
        _ => StatusTone.info,
      };
}
