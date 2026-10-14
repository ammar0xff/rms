import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/logging/app_logger.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
import '../../data/mock/mock_data.dart';
import '../../domain/models/menu_item.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_draft.dart';
import '../../domain/models/order_type.dart';
import '../../domain/models/payment.dart';
import '../../domain/services/kitchen_ticket_factory.dart';
import '../common/format.dart';

/// A line in the POS cart, keyed by the cached menu item identity.
class CartLine {
  CartLine(this.item, {this.quantity = 1, this.note});

  final MenuItemModel item;
  int quantity;
  String? note;

  double get total => item.price * quantity;
}

/// The result of the POS payment dialog.
class _PaymentInput {
  const _PaymentInput({required this.method, this.tendered});

  final PaymentMethod method;
  final double? tendered;
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _cart = <CartLine>[];
  String _category = 'الكل';
  String _query = '';
  int _orderType = 0;
  bool _submitting = false;
  List<MenuItemModel> _items = const [];
  bool _loaded = false;
  static final _orderTypes = [for (final t in OrderType.values) t.label];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  /// Reads the cached menu (server is the source of truth) and falls back to
  /// demo data when the local store is unavailable.
  Future<void> _load() async {
    final menu = AppScope.of(context).menu;
    List<MenuItemModel> loaded = const [];
    if (menu != null) {
      try {
        loaded = await menu.listMenu();
      } catch (_) {
        loaded = const [];
      }
    }
    // Never mutate state synchronously from within initState.
    await Future<void>.value();
    if (!mounted) return;
    setState(() => _items = loaded.isEmpty ? _fallbackMenu : loaded);
  }

  List<MenuItemModel> get _fallbackMenu => [
        for (final m in MockData.menu)
          MenuItemModel(
            id: m.name,
            name: m.name,
            category: m.category,
            price: m.price,
            station: m.station,
            available: m.available,
          ),
      ];

  List<String> get _categories =>
      ['الكل', ...{for (final m in _items) m.category}];

  List<MenuItemModel> get _visible {
    final inCategory = _category == 'الكل'
        ? _items
        : _items.where((m) => m.category == _category).toList();
    final q = _query.trim();
    if (q.isEmpty) return inCategory;
    // Name matches, or an exact id scan from the barcode reader.
    return inCategory
        .where((m) => m.name.contains(q) || m.id == q)
        .toList();
  }

  double get _subtotal => _cart.fold(0, (s, l) => s + l.total);
  double get _tax => _subtotal * 0.08;
  double get _total => _subtotal + _tax;

  void _add(MenuItemModel item) {
    setState(() {
      final existing = _cart.where((l) => l.item.id == item.id).firstOrNull;
      if (existing != null) {
        existing.quantity++;
      } else {
        _cart.add(CartLine(item));
      }
    });
  }

  void _dec(CartLine line) {
    setState(() {
      line.quantity--;
      if (line.quantity <= 0) _cart.remove(line);
    });
  }

  Future<void> _collect() async {
    if (_cart.isEmpty || _submitting) return;
    final input = await showDialog<_PaymentInput>(
      context: context,
      builder: (_) => _PaymentDialog(total: _total),
    );
    if (input == null) return;
    await _submitOrder(payment: input);
  }

  Future<void> _submitOrder({_PaymentInput? payment}) async {
    final services = AppScope.of(context);
    final orders = services.orders;
    final messenger = ScaffoldMessenger.of(context);
    if (orders == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر الحفظ: التخزين المحلي غير متاح')),
      );
      return;
    }
    final total = _total;
    final orderType = OrderType.values[_orderType];
    final offline = services.sync?.isOnline == false;
    final items = [
      for (final line in _cart)
        OrderItem(
          productId: line.item.id,
          name: line.item.name,
          unitPrice: line.item.price,
          quantity: line.quantity,
          station: line.item.station,
        ),
    ];
    setState(() => _submitting = true);
    try {
      final order = await orders.createOrder(
        OrderDraft(items: items, createdOffline: offline, orderType: orderType),
      );
      if (!mounted) return;
      if (payment != null) {
        await _recordPayment(services, order, payment, total, offline);
      }
      if (orderType == OrderType.delivery) {
        await _createDelivery(services, order, offline);
      }
      if (!mounted) return;
      await _dispatchToKitchen(services, order);
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _submitting = false;
      });
      services.sync?.requestSync();
      unawaited(SyncMonitor.instance.refresh());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            payment == null
                ? 'تم إنشاء الطلب ${order.provisionalOrderNumber} · يُزامَن عند الاتصال'
                : 'تم تحصيل ${money(total)} (${payment.method.label}) · ${order.provisionalOrderNumber}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('فشل إنشاء الطلب، حاول مرة أخرى')),
      );
    }
  }

  /// Records the collected payment. Best effort: the order is already saved, so
  /// a payment failure is logged rather than surfaced as an order failure.
  Future<void> _recordPayment(
    AppServices services,
    Order order,
    _PaymentInput payment,
    double total,
    bool offline,
  ) async {
    final payments = services.payments;
    if (payments == null) return;
    try {
      await payments.recordPayment(
        PaymentDraft(
          orderLocalId: order.localId,
          orderRef: order.provisionalOrderNumber,
          amount: total,
          method: payment.method,
          tendered: payment.tendered,
          createdOffline: offline,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.error('Failed to record payment', error, stackTrace);
    }
  }

  /// Creates the delivery job for a delivery order. Best effort.
  Future<void> _createDelivery(
    AppServices services,
    Order order,
    bool offline,
  ) async {
    final deliveries = services.deliveries;
    if (deliveries == null) return;
    try {
      await deliveries.createDelivery(
        orderRef: order.provisionalOrderNumber,
        address: 'يُحدد عند التسليم',
        amount: order.total,
        createdOffline: offline,
      );
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create delivery job', error, stackTrace);
    }
  }

  /// Routes a freshly created order to the kitchen display and printer. Best
  /// effort: a failure here never invalidates the order that was already saved.
  Future<void> _dispatchToKitchen(AppServices services, Order order) async {
    final tickets = KitchenTicketFactory().fromOrder(order);
    try {
      final kitchen = services.kitchen;
      if (kitchen != null) {
        for (final ticket in tickets) {
          await kitchen.upsertTicket(ticket);
        }
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to queue kitchen tickets', error, stackTrace);
    }
    final print = services.print;
    if (print == null) return;
    for (final ticket in tickets) {
      unawaited(print.printKitchenTicket(ticket));
    }
    unawaited(print.printReceipt(
      order.provisionalOrderNumber,
      {
        'total': order.total,
        'items': [
          for (final item in order.items)
            {'name': item.name, 'qty': item.quantity, 'price': item.unitPrice},
        ],
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 820;
        final menu = _MenuPane(
          categories: _categories,
          selected: _category,
          items: _visible,
          query: _query,
          onQuery: (v) => setState(() => _query = v),
          onCategory: (v) => setState(() => _category = v),
          onAdd: _add,
        );
        final cart = _CartPane(
          cart: _cart,
          orderType: _orderType,
          orderTypes: _orderTypes,
          subtotal: _subtotal,
          tax: _tax,
          total: _total,
          submitting: _submitting,
          onType: (i) => setState(() => _orderType = i),
          onAdd: _add,
          onDec: _dec,
          onSend: () => _submitOrder(),
          onCollect: _collect,
        );

        if (narrow) {
          // Phones get tabs, not two stacked panes: squeezing the cart into a
          // fixed 42% slot overflowed its footer on every real screen height.
          // Full-height cart tab means the totals and buttons are always
          // reachable, and the badge shows the line count at a glance.
          //
          // The menu tab keeps a sticky cart bar so the total and checkout
          // stay one tap away without switching tabs.
          final showBar = _cart.isNotEmpty;
          return DefaultTabController(
            length: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: AppColors.surface,
                  child: TabBar(
                    labelStyle: AppText.bodyStrong,
                    unselectedLabelStyle: AppText.body,
                    tabs: [
                      const Tab(text: 'القائمة'),
                      Tab(
                        text: _cart.isEmpty
                            ? 'السلة'
                            : 'السلة (${_cart.length})',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      Builder(
                        builder: (tabContext) => Stack(
                          children: [
                            Padding(
                              // The bar floats over the grid; keep the last
                              // row reachable.
                              padding: EdgeInsets.only(
                                  bottom: showBar ? 84 : 0),
                              child: menu,
                            ),
                            if (showBar)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: _CartBar(
                                  total: _total,
                                  count: _cart.length,
                                  onViewCart: () =>
                                      DefaultTabController.of(tabContext)
                                          .animateTo(1),
                                  onCollect: _collect,
                                ),
                              ),
                          ],
                        ),
                      ),
                      cart,
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: menu),
            Container(width: 1, color: AppColors.borderStrong),
            SizedBox(width: 360, child: cart),
          ],
        );
      },
    );
  }
}

class _MenuPane extends StatefulWidget {
  const _MenuPane({
    required this.categories,
    required this.selected,
    required this.items,
    required this.query,
    required this.onQuery,
    required this.onCategory,
    required this.onAdd,
  });

  final List<String> categories;
  final String selected;
  final List<MenuItemModel> items;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onCategory;
  final ValueChanged<MenuItemModel> onAdd;

  @override
  State<_MenuPane> createState() => _MenuPaneState();
}

class _MenuPaneState extends State<_MenuPane> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The field owns its text; the parent owns the filter. They only meet at
    // the clear button, which empties both.
    if (_search.text != widget.query && widget.query.isEmpty) {
      _search.clear();
    }
    final categories = widget.categories;
    final selected = widget.selected;
    final items = widget.items;
    final query = widget.query;
    final onQuery = widget.onQuery;
    final onCategory = widget.onCategory;
    final onAdd = widget.onAdd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OfflineBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.borderStrong),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search,
                          size: 18, color: AppColors.fgGhost),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: onQuery,
                          textInputAction: TextInputAction.search,
                          style: AppText.body
                              .copyWith(color: AppColors.fgBright),
                          decoration: InputDecoration(
                            hintText: 'ابحث في القائمة أو امسح الباركود',
                            hintStyle: AppText.caption
                                .copyWith(color: AppColors.fgDim),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (query.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _search.clear();
                            onQuery('');
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.clear,
                                size: 18, color: AppColors.fgGhost),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final c in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _CategoryChip(
                    label: c,
                    active: c == selected,
                    onTap: () => onCategory(c),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisExtent: 100,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _ProductTile(
              item: items[i],
              onTap: () => onAdd(items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.brandSoft : Colors.transparent,
          border: Border.all(
            color: active ? AppColors.brandLine : AppColors.borderStrong,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: active ? AppColors.brand : AppColors.fgMuted,
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatefulWidget {
  const _ProductTile({required this.item, required this.onTap});

  final MenuItemModel item;
  final VoidCallback onTap;

  @override
  State<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<_ProductTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      cursor: item.available ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: item.available ? widget.onTap : null,
        child: Opacity(
          opacity: item.available ? 1 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _hover ? AppColors.hover : AppColors.surface,
              border: Border.all(color: AppColors.borderStrong),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong,
                      ),
                    ),
                    // A dimmed tile alone does not say why it cannot be tapped.
                    if (!item.available) ...[
                      const SizedBox(width: 6),
                      const Tag(label: 'نفد', tone: StatusTone.negative),
                    ],
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Text(money(item.price),
                        style: AppText.tableCellPrimary.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand,
                        )),
                    const Spacer(),
                    Flexible(
                      child: Text(item.station,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sticky checkout bar floating over the menu tab on phones.
///
/// Without it the total and التحصيل are a tab-switch away, which is where the
/// thumb already is. Tapping the total opens the cart; the button collects.
class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.total,
    required this.count,
    required this.onViewCart,
    required this.onCollect,
  });

  final double total;
  final int count;
  final VoidCallback onViewCart;
  final VoidCallback onCollect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.borderStrong)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onViewCart,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('الإجمالي · $count ${count == 1 ? 'صنف' : 'أصناف'}',
                      style: AppText.caption),
                  Text(money(total),
                      style: AppText.h1.copyWith(fontSize: 18)),
                ],
              ),
            ),
          ),
          const Spacer(),
          RmsButton(
            label: 'تحصيل',
            icon: Icons.payments_outlined,
            variant: BtnVariant.primary,
            onPressed: onCollect,
            dense: false,
          ),
        ],
      ),
    );
  }
}

class _CartPane extends StatelessWidget {
  const _CartPane({
    required this.cart,
    required this.orderType,
    required this.orderTypes,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.submitting,
    required this.onType,
    required this.onAdd,
    required this.onDec,
    required this.onSend,
    required this.onCollect,
  });

  final List<CartLine> cart;
  final int orderType;
  final List<String> orderTypes;
  final double subtotal;
  final double tax;
  final double total;
  final bool submitting;
  final ValueChanged<int> onType;
  final ValueChanged<MenuItemModel> onAdd;
  final ValueChanged<CartLine> onDec;
  final VoidCallback onSend;
  final VoidCallback onCollect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceSecondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('طلب جديد', style: AppText.h2),
                    const Spacer(),
                    const Tag(label: 'مؤقت', tone: StatusTone.neutral),
                  ],
                ),
                const SizedBox(height: 12),
                Segmented(
                  options: orderTypes,
                  index: orderType,
                  onChanged: onType,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          Expanded(
            child: cart.isEmpty
                ? const EmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: 'لا توجد أصناف بعد',
                    message: 'اضغط على أي منتج لإضافته إلى الطلب.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: cart.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.borderFaint,
                    ),
                    itemBuilder: (context, i) => _CartRow(
                      line: cart[i],
                      onAdd: () => onAdd(cart[i].item),
                      onDec: () => onDec(cart[i]),
                    ),
                  ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderSubtle)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyValue(label: 'المجموع الفرعي', value: money(subtotal)),
                KeyValue(label: 'الضريبة (8%)', value: money(tax)),
                const Divider(height: 16, color: AppColors.borderSubtle),
                Row(
                  children: [
                    Text('الإجمالي', style: AppText.bodyStrong),
                    const Spacer(),
                    Text(money(total),
                        style: AppText.h1.copyWith(fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const StatusDot(tone: StatusTone.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('يُحفظ محليًا أولاً ثم تتم المزامنة عند الاتصال',
                          style: AppText.caption.copyWith(color: AppColors.fgDim)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                RmsButton(
                  label: 'إرسال للمطبخ',
                  icon: Icons.send_rounded,
                  variant: BtnVariant.secondary,
                  onPressed: (cart.isEmpty || submitting) ? null : onSend,
                  dense: false,
                ),
                const SizedBox(height: 8),
                RmsButton(
                  label: 'تحصيل ${money(total)}',
                  icon: Icons.payments_outlined,
                  variant: BtnVariant.primary,
                  onPressed: (cart.isEmpty || submitting) ? null : onCollect,
                  dense: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({required this.line, required this.onAdd, required this.onDec});

  final CartLine line;
  final VoidCallback onAdd;
  final VoidCallback onDec;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.tableCellPrimary),
                const SizedBox(height: 2),
                Text('${money(line.item.price)} · ${line.item.station}',
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption),
              ],
            ),
          ),
          _QtyButton(icon: Icons.remove, onTap: onDec),
          SizedBox(
            width: 32,
            child: Text(
              '${line.quantity}',
              textAlign: TextAlign.center,
              style: AppText.tableCellPrimary.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _QtyButton(icon: Icons.add, onTap: onAdd),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Text(money(line.total),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 16, color: AppColors.fgSecondary),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final monitor = SyncMonitor.instance;
    return AnimatedBuilder(
      animation: monitor,
      builder: (context, _) {
        if (monitor.online) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          color: AppColors.warning.withValues(alpha: 0.06),
          child: Row(
            children: [
              const StatusDot(tone: StatusTone.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'وضع العمل دون اتصال — قائمة مخزنة محليًا. تُحفظ الطلبات محليًا وتُزامن تلقائيًا عند استعادة الاتصال.',
                  style: AppText.caption.copyWith(color: AppColors.warning.withValues(alpha: 0.9)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Collects the payment method and (for cash) the amount tendered.
///
/// Returns a [_PaymentInput] when confirmed, or null when dismissed.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total});

  final double total;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _tendered = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  static final _methods = [for (final m in PaymentMethod.values) m.label];

  @override
  void initState() {
    super.initState();
    _tendered.text = widget.total.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _tendered.dispose();
    super.dispose();
  }

  double? get _tenderedValue => double.tryParse(_tendered.text.trim());

  double? get _change {
    if (_method != PaymentMethod.cash) return null;
    final given = _tenderedValue;
    if (given == null) return null;
    final change = given - widget.total;
    return change < 0 ? null : change;
  }

  bool get _canConfirm {
    if (_method != PaymentMethod.cash) return true;
    final given = _tenderedValue;
    return given != null && given >= widget.total;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('تحصيل ${money(widget.total)}'),
      content: SizedBox(
        // Fill the dialog's available width instead of demanding 360px the
        // phone does not have.
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Segmented(
              options: _methods,
              index: PaymentMethod.values.indexOf(_method),
              onChanged: (i) => setState(() => _method = PaymentMethod.values[i]),
            ),
            const SizedBox(height: 16),
            if (_method == PaymentMethod.cash) ...[
              TextField(
                controller: _tendered,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                style: AppText.body.copyWith(color: AppColors.fgBright),
                decoration: InputDecoration(
                  labelText: 'المبلغ المستلم',
                  labelStyle: AppText.caption,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('الباقي', style: AppText.bodyStrong)),
                  Text(
                    _change == null ? '—' : money(_change!),
                    style: AppText.bodyStrong.copyWith(
                      color: _change == null ? AppColors.negative : AppColors.positive,
                    ),
                  ),
                ],
              ),
              if (_change == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'المبلغ المستلم أقل من الإجمالي',
                    style: AppText.caption.copyWith(color: AppColors.negative),
                  ),
                ),
            ] else
              Text(
                'سيتم تسجيل الدفعة على جهاز نقاط البيع.',
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ),
      actions: [
        RmsButton(
          label: 'إلغاء',
          variant: BtnVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RmsButton(
          label: 'تأكيد التحصيل',
          variant: BtnVariant.primary,
          icon: Icons.payments_outlined,
          onPressed: _canConfirm
              ? () => Navigator.of(context).pop(
                    _PaymentInput(
                      method: _method,
                      tendered: _method == PaymentMethod.cash ? _tenderedValue : null,
                    ),
                  )
              : null,
        ),
      ],
    );
  }
}
