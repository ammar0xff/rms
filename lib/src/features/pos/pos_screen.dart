import 'package:flutter/material.dart';

import '../../core/state/sync_monitor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
import '../../data/mock/mock_data.dart';
import '../common/format.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _cart = <CartLine>[];
  String _category = 'All';
  int _orderType = 0;
  static const _orderTypes = ['Dine-in', 'Takeaway', 'Delivery'];

  List<String> get _categories =>
      ['All', ...{for (final m in MockData.menu) m.category}];

  List<MenuItem> get _visible => _category == 'All'
      ? MockData.menu
      : MockData.menu.where((m) => m.category == _category).toList();

  double get _subtotal => _cart.fold(0, (s, l) => s + l.total);
  double get _tax => _subtotal * 0.08;
  double get _total => _subtotal + _tax;

  void _add(MenuItem item) {
    setState(() {
      final existing = _cart.where((l) => l.item.name == item.name).firstOrNull;
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
          onType: (i) => setState(() => _orderType = i),
          onAdd: _add,
          onDec: _dec,
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
  final List<MenuItem> items;
  final ValueChanged<String> onCategory;
  final ValueChanged<MenuItem> onAdd;

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
                      Text('Search menu or scan barcode',
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

  final MenuItem item;
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
    required this.onType,
    required this.onAdd,
    required this.onDec,
  });

  final List<CartLine> cart;
  final int orderType;
  final List<String> orderTypes;
  final double subtotal;
  final double tax;
  final double total;
  final ValueChanged<int> onType;
  final ValueChanged<MenuItem> onAdd;
  final ValueChanged<CartLine> onDec;

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
                    Text('New order', style: AppText.h2),
                    const Spacer(),
                    const Tag(label: 'PROVISIONAL', tone: StatusTone.neutral),
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
                    title: 'No items yet',
                    message: 'Tap a product to add it to the order.',
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
                KeyValue(label: 'Subtotal', value: money(subtotal)),
                KeyValue(label: 'Tax (8%)', value: money(tax)),
                const Divider(height: 16, color: AppColors.borderSubtle),
                Row(
                  children: [
                    Text('Total', style: AppText.bodyStrong),
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
                      child: Text('Saves locally first, syncs on reconnect',
                          style: TextStyle(fontSize: 10, color: AppColors.fgDim)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: RmsButton(
                        label: 'Hold',
                        icon: Icons.pause_rounded,
                        onPressed: null,
                        dense: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: RmsButton(
                        label: 'Send to kitchen',
                        icon: Icons.send_rounded,
                        variant: BtnVariant.secondary,
                        onPressed: cart.isEmpty ? null : () {},
                        dense: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                RmsButton(
                  label: 'Charge ${money(total)}',
                  icon: Icons.payments_outlined,
                  variant: BtnVariant.primary,
                  onPressed: cart.isEmpty ? null : () {},
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
                  'Offline mode — using cached menu (synced 2m ago). Orders save locally and sync automatically.',
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
