import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/logging/app_logger.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/blocks.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
import '../../domain/models/menu_item.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_draft.dart';
import '../../domain/models/order_type.dart';
import '../../domain/models/payment.dart';
import '../../domain/services/kitchen_ticket_factory.dart';
import '../common/format.dart';

/// A line in the POS cart, keyed by the cached menu item identity.
class CartLine {
  CartLine(this.item,
      {this.quantity = 1, this.note, this.selected = const []});

  final MenuItemModel item;
  int quantity;
  String? note;

  /// Chosen modifier options. Part of the line identity: the same item
  /// with different options is a different line, never merged.
  List<ModifierOption> selected;

  /// Item id plus sorted option ids — the merge key.
  String get key {
    final ids = selected.map((o) => o.id).toList()..sort();
    return '${item.id}|${ids.join(',')}';
  }

  double get unitPrice =>
      item.price + selected.fold(0.0, (sum, o) => sum + o.deltaPrice);

  double get total => unitPrice * quantity;
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

class _PosScreenState extends State<PosScreen>
    with SingleTickerProviderStateMixin {
  /// Owned here, not rebuilt in build(): a DefaultTabController constructed
  /// during build resets to the menu tab on every setState — yanking the
  /// cashier off the cart tab on each quantity tap or search keystroke.
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

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
    setState(() => _items = loaded);
  }


  List<String> get _categories =>
      ['الكل', ...{for (final m in _items) m.category}];

  Map<String, int> get _categoryCounts => {
        for (final c in _categories)
          c: c == 'الكل'
              ? _items.length
              : _items.where((m) => m.category == c).length,
      };

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

  void _add(MenuItemModel item, {List<ModifierOption> options = const []}) {
    final probe = CartLine(item, selected: options);
    setState(() {
      final existing = _cart.where((l) => l.key == probe.key).firstOrNull;
      if (existing != null) {
        existing.quantity++;
      } else {
        _cart.add(probe);
      }
    });
  }

  /// Customization sheet for items with modifier groups. Returns the
  /// selection, or null when dismissed. Required groups must be satisfied
  /// before confirm enables.
  Future<void> _customize(MenuItemModel item, {CartLine? line}) async {
    final selected = await showDialog<List<ModifierOption>>(
      context: context,
      builder: (_) => _CustomizeSheet(
        item: item,
        initial: line?.selected ?? const [],
      ),
    );
    if (selected == null) return;
    if (line != null) {
      setState(() => line.selected = selected);
    } else {
      _add(item, options: selected);
    }
  }

  void _dec(CartLine line) {
    setState(() {
      line.quantity--;
      if (line.quantity <= 0) _cart.remove(line);
    });
  }

  /// Free-text kitchen note per line; prints on the ticket, syncs with the
  /// order. Empty clears it.
  Future<void> _editNote(CartLine line) async {
    final controller = TextEditingController(text: line.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (_) => DialogShell(
        title: 'ملاحظة للشيف',
        subtitle: line.item.name,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in ['بدون حار', 'محمص كويس', 'نصّين'])
                  GestureDetector(
                    onTap: () {
                      final current = controller.text;
                      controller.text = current.isEmpty
                          ? chip
                          : '$current، $chip';
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: AppColors.borderStrong),
                        borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm),
                      ),
                      child: Text(chip, style: AppText.bodyStrong),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'اكتب تعليمات المطبخ…',
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
            label: 'احفظ الملاحظة',
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;
    setState(() => line.note = note.isEmpty ? null : note);
  }

  Future<void> _collect() async {
    if (_cart.isEmpty || _submitting) return;
    final input = await showDialog<_PaymentInput>(
      context: context,
      builder: (_) => PosPaymentDialog(
          total: _total, subtotal: _subtotal, tax: _tax),
    );
    if (input == null) return;
    await _submitOrder(payment: input);
  }

  Future<void> _submitOrder({_PaymentInput? payment}) async {
    // Re-entrancy guard first, synchronously: the buttons disable from the
    // last build's snapshot, so two taps before the rebuild (or send + collect
    // in quick succession) would otherwise persist two orders for one cart.
    if (_submitting) return;
    _submitting = true;
    final services = AppScope.of(context);
    final orders = services.orders;
    final messenger = ScaffoldMessenger.of(context);
    if (orders == null) {
      _submitting = false;
      messenger.showSnackBar(
        const SnackBar(content: Text('الحفظ فشل: التخزين على الجهاز مش متاح')),
      );
      return;
    }
    final orderType = OrderType.values[_orderType];
    // Unknown counts as offline: without a sync service these orders are
    // local-only, and the delivery screen already reads it this way. (The two
    // disagreed; POS claimed online, delivery claimed offline.)
    final offline = services.sync?.isOnline != true;
    final items = [
      for (final line in _cart)
        OrderItem(
          productId: line.item.id,
          name: line.item.name,
          unitPrice: line.unitPrice,
          quantity: line.quantity,
          station: line.item.station,
          note: line.note?.trim().isEmpty ?? true ? null : line.note!.trim(),
          modifiers: line.selected.map((o) => o.name).toList(),
        ),
    ];
    // Cents-rounded here so the stored tax is exact; the cart keeps showing
    // the unrounded breakdown until save.
    final taxAmount = (_tax * 100).round() / 100;
    setState(() {});
    try {
      final order = await orders.createOrder(
        OrderDraft(
          items: items,
          createdOffline: offline,
          orderType: orderType,
          taxAmount: taxAmount,
        ),
      );
      if (!mounted) return;
      if (payment != null) {
        // The order's total, not the cart's: one taxed figure everywhere, so
        // the payment matches the order, the delivery and the receipt.
        await _recordPayment(services, order, payment, order.total, offline);
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
                ? 'اتعمل الأوردر ${order.provisionalOrderNumber} · هيتزامن عند الاتصال'
                : 'تم تحصيل ${money(order.total)} (${payment.method.label}) · ${order.provisionalOrderNumber}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('الأوردر ما اتعملش، جرّب تاني')),
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
        final canPay = _cart.isNotEmpty && !_submitting;
        final menu = _MenuPane(
          categories: _categories,
          selected: _category,
          items: _visible,
          query: _query,
          chipsVisible: narrow,
          onQuery: (v) => setState(() => _query = v),
          onCategory: (v) => setState(() => _category = v),
          onAdd: _add,
          onCustomize: (item) => _customize(item),
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
          onNote: _editNote,
          onCustomizeLine: (line) => _customize(line.item, line: line),
          onSend: () => _submitOrder(),
          onCollect: _collect,
          onQuickCash: () => _submitOrder(
            payment: _PaymentInput(
                method: PaymentMethod.cash, tendered: _total),
          ),
          onQuickCard: () => _submitOrder(
            payment:
                _PaymentInput(method: PaymentMethod.card, tendered: null),
          ),
          canPay: canPay,
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: AppColors.surface,
                child: TabBar(
                  controller: _tabs,
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
                  controller: _tabs,
                  children: [
                    Stack(
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
                              onViewCart: () => _tabs.animateTo(1),
                              onCollect: _collect,
                            ),
                          ),
                      ],
                    ),
                    cart,
                  ],
                ),
              ),
            ],
          );
        }
        // The counter layout: category rail, product grid, docked cart.
        // Phones keep chips plus tabs instead (see the narrow branch).
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CategoryRail(
              categories: _categories,
              counts: _categoryCounts,
              selected: _category,
              onCategory: (v) => setState(() => _category = v),
            ),
            Container(width: 1, color: AppColors.borderStrong),
            Expanded(child: menu),
            Container(width: 1, color: AppColors.borderStrong),
            SizedBox(width: 360, child: cart),
          ],
        );
      },
    );
  }
}

/// Item customization: required single-choice groups, optional
/// multi-choice groups with priced options, and directives. Returns the
/// selection; required groups gate confirm.
class _CustomizeSheet extends StatefulWidget {
  const _CustomizeSheet({required this.item, this.initial = const []});

  final MenuItemModel item;
  final List<ModifierOption> initial;

  @override
  State<_CustomizeSheet> createState() => _CustomizeSheetState();
}

class _CustomizeSheetState extends State<_CustomizeSheet> {
  late Set<String> _picked = widget.initial.map((o) => o.id).toSet();

  List<ModifierOption> get _selected => [
        for (final g in widget.item.modifierGroups)
          for (final o in g.options)
            if (_picked.contains(o.id)) o,
      ];

  bool get _valid {
    for (final g in widget.item.modifierGroups) {
      if (!g.required) continue;
      if (!g.options.any((o) => _picked.contains(o.id))) return false;
    }
    return true;
  }

  double get _delta =>
      _selected.fold(0.0, (sum, o) => sum + o.deltaPrice);

  void _toggle(ModifierGroup group, ModifierOption option) {
    setState(() {
      if (group.multi) {
        if (_picked.contains(option.id)) {
          _picked.remove(option.id);
        } else {
          _picked.add(option.id);
        }
      } else {
        _picked.removeWhere(
            (id) => group.options.any((o) => o.id == id));
        _picked.add(option.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DialogShell(
      title: 'تخصيص ${widget.item.name}',
      subtitle: _delta > 0
          ? 'زيادة ${money(widget.item.price + _delta)}'
          : money(widget.item.price),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final group in widget.item.modifierGroups) ...[
            Row(
              children: [
                Expanded(
                  child: Text(group.name, style: AppText.bodyStrong),
                ),
                Tag(
                  label: group.required ? 'إلزامي' : 'اختياري',
                  tone: group.required
                      ? StatusTone.warning
                      : StatusTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final option in group.options)
              GestureDetector(
                onTap: () => _toggle(group, option),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Icon(
                        _picked.contains(option.id)
                            ? (group.multi
                                ? Icons.check_box
                                : Icons.radio_button_checked)
                            : (group.multi
                                ? Icons.check_box_outline_blank
                                : Icons.radio_button_unchecked),
                        size: 20,
                        color: _picked.contains(option.id)
                            ? AppColors.brand
                            : AppColors.fgGhost,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(option.name,
                            style: AppText.tableCellPrimary),
                      ),
                      if (option.deltaPrice > 0)
                        Text('+${money(option.deltaPrice)}',
                            style: AppText.caption),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
        ],
      ),
      actions: [
        RmsButton(
          label: 'إلغاء',
          variant: BtnVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RmsButton(
          label: 'أكّد التخصيص',
          onPressed:
              _valid ? () => Navigator.of(context).pop(_selected) : null,
        ),
      ],
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
    required this.onCustomize,
    this.chipsVisible = true,
  });

  final List<String> categories;
  final String selected;
  final List<MenuItemModel> items;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onCategory;
  final ValueChanged<MenuItemModel> onAdd;
  final ValueChanged<MenuItemModel> onCustomize;

  /// False on wide screens, where the category rail replaces the chips.
  final bool chipsVisible;

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
    final onCustomize = widget.onCustomize;
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
                            hintText: 'دوّر في القائمة أو امسح الباركود',
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
        if (widget.chipsVisible)
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
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.restaurant_menu_outlined,
                  title: 'مفيش أصناف',
                  message: 'ضيف أصناف من شاشة القائمة عشان تبدأ البيع.',
                )
              : GridView.builder(
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
              onCustomize: items[i].modifierGroups.isEmpty
                  ? null
                  : () => onCustomize(items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

/// The counter's category rail: every category with its count, always
/// visible beside the grid. Replaces the scrolling chip strip on wide
/// screens; phones never mount it.
class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.categories,
    required this.counts,
    required this.selected,
    required this.onCategory,
  });

  final List<String> categories;
  final Map<String, int> counts;
  final String selected;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (final c in categories)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: GestureDetector(
                onTap: () => onCategory(c),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: c == selected
                        ? AppColors.brandSoft
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStrong.copyWith(
                            color: c == selected
                                ? AppColors.brand
                                : AppColors.fgSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${counts[c] ?? 0}',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
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
  const _ProductTile(
      {required this.item, required this.onTap, this.onCustomize});

  final MenuItemModel item;
  final VoidCallback onTap;

  /// Null when the item has no modifier groups.
  final VoidCallback? onCustomize;

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
                    if (widget.onCustomize != null)
                      GestureDetector(
                        onTap: widget.onCustomize,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.tune,
                              size: 16, color: AppColors.brand),
                        ),
                      ),
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
    required this.onNote,
    required this.onCustomizeLine,
    required this.onSend,
    required this.onCollect,
    required this.onQuickCash,
    required this.onQuickCard,
    required this.canPay,
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
  final ValueChanged<CartLine> onNote;
  final ValueChanged<CartLine> onCustomizeLine;
  final VoidCallback onSend;
  final VoidCallback onCollect;
  final VoidCallback onQuickCash;
  final VoidCallback onQuickCard;

  /// False while the cart is empty or a submit is in flight; the tender
  /// buttons disable with everything else.
  final bool canPay;

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
                    title: 'مفيش أصناف بعد',
                    message: 'اضغط على أي منتج عشان تضيفه للأوردر.',
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
                      onNote: () => onNote(cart[i]),
                      onCustomizeLine: () => onCustomizeLine(cart[i]),
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
                      child: Text('يتحفظ على الجهاز الأول وبعدين بيتزامن عند الاتصال',
                          style: AppText.caption.copyWith(color: AppColors.fgDim)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Exact-cash and card skip the amount dialog: the two taps
                // a rush-hour cashier makes hundreds of times a shift.
                Row(
                  children: [
                    Expanded(
                      child: RmsButton(
                        label: 'كاش بالظبط',
                        icon: Icons.payments_outlined,
                        onPressed: canPay ? onQuickCash : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RmsButton(
                        label: 'فيزا',
                        icon: Icons.credit_card_outlined,
                        onPressed: canPay ? onQuickCard : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
  const _CartRow(
      {required this.line,
      required this.onAdd,
      required this.onDec,
      required this.onNote,
      required this.onCustomizeLine});

  final CartLine line;
  final VoidCallback onAdd;
  final VoidCallback onDec;
  final VoidCallback onNote;
  final VoidCallback onCustomizeLine;

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
                GestureDetector(
                  onTap: onNote,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(line.item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.tableCellPrimary),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit_note_outlined,
                            size: 15,
                            color: line.note == null
                                ? AppColors.fgGhost
                                : AppColors.brand,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${money(line.item.price)} · ${line.item.station}',
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption),
                      if (line.selected.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: onCustomizeLine,
                          child: Text(
                              line.selected
                                  .map((o) => o.name)
                                  .join('، '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(
                                  color: AppColors.brand)),
                        ),
                      ],
                      if (line.note != null) ...[
                        const SizedBox(height: 2),
                        Text('ملاحظة: ${line.note!}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                                color: AppColors.brand)),
                      ],
                    ],
                  ),
                ),
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
                  'شغال من غير نت — القائمة متخزنة على الجهاز. الأوردرات بتتحفظ على الجهاز وبتتزامن لوحدها لما النت يرجع.',
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
class PosPaymentDialog extends StatefulWidget {
  const PosPaymentDialog({
    required this.total,
    required this.subtotal,
    required this.tax,
  });

  final double total;
  final double subtotal;
  final double tax;

  @override
  State<PosPaymentDialog> createState() => _PaymentDialogState();
}

/// Next round bills above [total]: exact handled by بالضبط, so chips
/// start at the first round figure that covers it (100/200/500 steps).
List<int> _quickBills(double total) {
  const steps = [100, 200, 500, 1000];
  final out = <int>[];
  for (final step in steps) {
    final bill = ((total / step).ceil()) * step;
    if (bill > total && !out.contains(bill)) out.add(bill);
    if (out.length == 3) break;
  }
  return out;
}

/// Rush-hour tender pad: digits plus backspace write straight into the
/// tendered field, so gloves never hunt the system keyboard.
class _TenderPad extends StatelessWidget {
  const _TenderPad({required this.onKey});

  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'back'];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 2.2,
      ),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final key = keys[i];
        return GestureDetector(
          onTap: () => onKey(key),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              border: Border.all(color: AppColors.borderStrong),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: key == 'back'
                ? const Icon(Icons.backspace_outlined, size: 18)
                : Text(key, style: AppText.h1.copyWith(fontSize: 18)),
          ),
        );
      },
    );
  }
}

class _TenderChip extends StatelessWidget {
  const _TenderChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderStrong),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Text(label, style: AppText.bodyStrong),
        ),
      ),
    );
  }
}

class _PaymentDialogState extends State<PosPaymentDialog> {
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
            KeyValue(label: 'المجموع الفرعي', value: money(widget.subtotal)),
            KeyValue(label: 'الضريبة (8%)', value: money(widget.tax)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(
                    child:
                        Text('الإجمالي', style: AppText.bodyStrong)),
                Text(money(widget.total),
                    style: AppText.h1.copyWith(fontSize: 18)),
              ],
            ),
            const SizedBox(height: 16),
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
              // Rush-hour tender: exact or the next round bill up.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _TenderChip(
                      label: 'بالضبط',
                      onTap: () => setState(() => _tendered.text =
                          widget.total.toStringAsFixed(2)),
                    ),
                    for (final bill in _quickBills(widget.total))
                      _TenderChip(
                        label: '$bill',
                        onTap: () => setState(
                            () => _tendered.text = '$bill'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _TenderPad(
                onKey: (key) => setState(() {
                  if (key == 'back') {
                    if (_tendered.text.isNotEmpty) {
                      _tendered.text = _tendered.text
                          .substring(0, _tendered.text.length - 1);
                    }
                  } else if (key == '.') {
                    if (!_tendered.text.contains('.')) {
                      _tendered.text += '.';
                    }
                  } else {
                    _tendered.text += key;
                  }
                }),
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
                'الدفعة هتتسجل على الكاشير.',
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
          label: 'أكّد التحصيل',
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
