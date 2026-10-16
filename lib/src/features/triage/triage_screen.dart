import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/blocks.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/assignment/delivery_assignment.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/order.dart';
import '../../domain/models/permissions.dart';
import '../../data/services/permission_service.dart';
import '../common/format.dart';

/// Live order triage for managers: every open order on this device branch
/// with its courier state, plus tactical actions (assign, discount request,
/// void request). Cross-branch triage needs a server feed that does not
/// exist yet — this screen is honest about covering the device branch.
class TriageScreen extends StatefulWidget {
  const TriageScreen({super.key});

  @override
  State<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends State<TriageScreen> {
  List<Order> _orders = const [];
  List<DeliveryModel> _deliveries = const [];
  List<DriverModel> _drivers = const [];
  bool _loaded = false;
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
    final services = AppScope.of(context);
    final orders = services.orders;
    final deliveries = services.deliveries;
    if (orders == null || deliveries == null) return;
    final orderList = await orders.listOrders();
    final deliveryList = await deliveries.listDeliveries();
    final driverList = await deliveries.listDrivers();
    if (!mounted) return;
    setState(() {
      _orders = orderList;
      _deliveries = deliveryList;
      _drivers = driverList;
    });
  }

  DeliveryModel? _deliveryFor(Order order) {
    for (final d in _deliveries) {
      if (d.orderRef == order.provisionalOrderNumber ||
          d.orderRef == order.localId) {
        return d;
      }
    }
    return null;
  }

  /// 0 الكل · 1 بدون طيار · 2 في الطريق · 3 اتسلّم.
  bool _matches(Order order) {
    final delivery = _deliveryFor(order);
    switch (_filter) {
      case 1:
        return delivery == null ||
            delivery.state == DeliveryState.waiting;
      case 2:
        return delivery != null &&
            (delivery.state == DeliveryState.assigned ||
                delivery.state == DeliveryState.onRoute);
      case 3:
        return delivery?.state == DeliveryState.delivered;
      default:
        return true;
    }
  }

  List<Order> get _visible {
    final q = _query.trim();
    return _orders.where((o) {
      if (o.voided) return false;
      if (!_matches(o)) return false;
      if (q.isEmpty) return true;
      return o.provisionalOrderNumber.contains(q);
    }).toList();
  }

  Future<void> _assign(Order order) async {
    final repo = AppScope.of(context).deliveries;
    if (repo == null) return;
    final existing = _deliveryFor(order);
    if (existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مفيش مهمة توصيل للأوردر ده')),
      );
      return;
    }
    if (_drivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مفيش سائقون متاحون')),
      );
      return;
    }
    final picked = await showDialog<_AssignPick>(
      context: context,
      builder: (_) => _AssignSheet(
        drivers: _drivers,
        current: existing.driver,
        suggested: DeliveryAssignmentPolicy.pickDriver(
          deliveries: _deliveries,
          drivers: _drivers,
        ),
      ),
    );
    if (picked == null) return;
    await repo.assignDriver(existing.id, picked.driver,
        baseDriver: existing.driver, reason: picked.reason);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('اتسندت المهمة ${existing.id} إلى ${picked.driver}')),
    );
  }

  Future<void> _discount(Order order) async {
    if (!await userCan(
        AppScope.of(context), Permissions.orderDiscount)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('صلاحية طلب الخصم مش متاحة لدورك')),
      );
      return;
    }
    final approvals = AppScope.of(context).approvals;
    if (approvals == null) return;
    await approvals.requestDiscount(
      orderLocalId: order.localId,
      orderRef: order.provisionalOrderNumber,
      amount: order.total,
      reason: 'خصم ترضية من شاشة المتابعة',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اتطلب خصم ترضية وهيستنى المدير')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return PageBody(
      children: [
        const SectionHeader(
          title: 'الأوردرات النشطة',
          subtitle: 'فرع الجهاز · المتابعة والتدخل',
        ),
        ListToolbar(
          hint: 'دوّر برقم الأوردر…',
          onQuery: (v) => setState(() => _query = v),
          filters: const ['الكل', 'بدون طيار', 'في الطريق', 'اتسلّم'],
          selected: _filter,
          onFilter: (i) => setState(() => _filter = i),
        ),
        if (visible.isEmpty)
          const SurfaceCard(
            child: Text('مفيش أوردرات بالفلتر ده.',
                style: AppText.caption),
          )
        else
          SurfaceCard(
            padding: EdgeInsets.zero,
            clip: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  _TriageRow(
                    order: visible[i],
                    delivery: _deliveryFor(visible[i]),
                    onAssign: () => _assign(visible[i]),
                    onDiscount: () => _discount(visible[i]),
                  ),
                  if (i != visible.length - 1)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Driver picker with reassignment reason. Returns the pick, or null.
class _AssignPick {
  _AssignPick({required this.driver, required this.reason});

  final String driver;
  final String reason;
}

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({
    required this.drivers,
    required this.current,
    required this.suggested,
  });

  final List<DriverModel> drivers;
  final String current;
  final String? suggested;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  String? _driver;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DialogShell(
      title: 'تعيين طيار',
      subtitle: widget.suggested == null
          ? null
          : 'المقترح: ${widget.suggested} (الأخف حملا)',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final d in widget.drivers)
            GestureDetector(
              onTap: () => setState(() => _driver = d.name),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Icon(
                      _driver == d.name
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: _driver == d.name
                          ? AppColors.brand
                          : AppColors.fgGhost,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(d.name,
                          style: AppText.tableCellPrimary),
                    ),
                    if (d.name == widget.current)
                      const Tag(label: 'الحالي', tone: StatusTone.neutral),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'سبب التعيين (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        RmsButton(
          label: 'إلغاء',
          variant: BtnVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RmsButton(
          label: 'أكّد التعيين',
          onPressed: _driver == null
              ? null
              : () => Navigator.of(context).pop(_AssignPick(
                    driver: _driver!,
                    reason: _reason.text.trim(),
                  )),
        ),
      ],
    );
  }
}

class _TriageRow extends StatelessWidget {
  const _TriageRow({
    required this.order,
    required this.delivery,
    required this.onAssign,
    required this.onDiscount,
  });

  final Order order;
  final DeliveryModel? delivery;
  final VoidCallback onAssign;
  final VoidCallback onDiscount;

  @override
  Widget build(BuildContext context) {
    final state = delivery?.state;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(order.provisionalOrderNumber,
                    style: AppText.tableCellPrimary),
              ),
              Tag(
                label: state == null
                    ? 'بدون طيار'
                    : state.label,
                tone: state == null
                    ? StatusTone.warning
                    : state == DeliveryState.delivered
                        ? StatusTone.positive
                        : StatusTone.info,
              ),
              const SizedBox(width: 8),
              Text(money(order.total),
                  style: AppText.tableCellPrimary),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (state == null || state == DeliveryState.waiting)
                RmsButton(
                  label: 'تعيين طيار',
                  dense: true,
                  onPressed: onAssign,
                ),
              RmsButton(
                label: 'خصم ترضية',
                dense: true,
                variant: BtnVariant.secondary,
                onPressed: onDiscount,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
