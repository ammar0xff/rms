import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
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
import '../common/format.dart';

/// A line in the POS cart, keyed by the cached menu item identity.
class CartLine {
  CartLine(this.item, {this.quantity = 1, this.note});

  final MenuItemModel item;
  int quantity;
  String? note;

  double get total => item.price * quantity;
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _cart = <CartLine>[];
  String _category = 'الكل';
  int _orderType = 0;
  bool _submitting = false;
  List<MenuItemModel> _items = const [];
  static const _orderTypes = ['داخل الصالة', 'الاستلام', 'توصيل'];

  @override
  void initState() {
    super.initState();
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

  List<MenuItemModel> get _visible => _category == 'الكل'
      ? _items
      : _items.where((m) => m.category == _category).toList();

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

  Future<void> _submitOrder() async {
    final services = AppScope.of(context);
    final orders = services.orders;
    final messenger = ScaffoldMessenger.of(context);
    if (orders == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر الحفظ: التخزين المحلي غير متاح')),
      );
      return;
    }
    final items = [
      for (final line in _cart)
        OrderItem(
          productId: line.item.id,
          name: line.item.name,
          unitPrice: line.item.price,
          quantity: line.quantity,
        ),
    ];
    setState(() => _submitting = true);
    try {
      final order = await orders.createOrder(
        OrderDraft(
          items: items,
          createdOffline: services.sync?.isOnline == false,
        ),
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _submitting = false;
      });
      services.sync?.requestSync();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'تم إنشاء الطلب ${order.provisionalOrderNumber} · يُزامَن عند الاتصال',
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 820;
        final menu = _MenuPane(
          categories: _categories,
          selected: _category,
          items: _visible,
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
          onSubmit: _submitOrder,
        );

        if (narrow) {
          return Column(
            children: [
              Expanded(child: menu),
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.42,
                child: cart,
              ),
            ],
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

class _MenuPane extends StatelessWidget {
  const _MenuPane({
    required this.categories,
    required this.selected,
    required this.items,
    required this.onCategory,
    required this.onAdd,
  });

  final List<String> categories;
  final String selected;
  final List<MenuItemModel> items;
  final ValueChanged<String> onCategory;
  final ValueChanged<MenuItemModel> onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OfflineBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.borderStrong),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 14, color: AppColors.fgGhost),
                      const SizedBox(width: 8),
                      Text('ابحث في القائمة أو امسح الباركود',
                          style: AppText.caption.copyWith(color: AppColors.fgDim)),
                      const Spacer(),
                      Text('F2', style: AppText.caption.copyWith(fontSize: 9)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
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
              mainAxisExtent: 92,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
            fontSize: 11,
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
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong.copyWith(fontSize: 12),
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
                    Text(item.station, style: AppText.caption.copyWith(fontSize: 9)),
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
    required this.onSubmit,
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
  final VoidCallback onSubmit;

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
                  children: const [
                    StatusDot(tone: StatusTone.warning),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text('يُحفظ محليًا أولاً ثم تتم المزامنة عند الاتصال',
                          style: TextStyle(fontSize: 10, color: AppColors.fgDim)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: RmsButton(
                        label: 'إيقاف مؤقت',
                        icon: Icons.pause_rounded,
                        onPressed: null,
                        dense: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: RmsButton(
                        label: 'إرسال للمطبخ',
                        icon: Icons.send_rounded,
                        variant: BtnVariant.secondary,
                        onPressed: (cart.isEmpty || submitting) ? null : onSubmit,
                        dense: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                RmsButton(
                  label: 'تحصيل ${money(total)}',
                  icon: Icons.payments_outlined,
                  variant: BtnVariant.primary,
                  onPressed: (cart.isEmpty || submitting) ? null : onSubmit,
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
                Text(line.item.name, style: AppText.tableCellPrimary),
                const SizedBox(height: 2),
                Text('${money(line.item.price)} · ${line.item.station}',
                    style: AppText.caption.copyWith(fontSize: 10)),
              ],
            ),
          ),
          _QtyButton(icon: Icons.remove, onTap: onDec),
          SizedBox(
            width: 28,
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
            width: 58,
            child: Text(money(line.total),
                textAlign: TextAlign.right,
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
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 13, color: AppColors.fgSecondary),
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
