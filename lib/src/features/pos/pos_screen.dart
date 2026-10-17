import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/dining_table.dart';
import '../../domain/models/menu_item.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_draft.dart';
import '../../domain/models/order_type.dart';
import '../../domain/models/payment.dart';
import 'pos_checkout_dialog.dart';
import 'pos_customise_sheet.dart';

/// Screen 1: Point of Sale (نقطة البيع وبناء الطلب)
///
/// Designed for high-speed terminal operations:
/// - Service mode switcher: Hall / Table / Takeaway / Delivery
/// - Category rail with live item availability counts
/// - Touch-first product matrix
/// - Desktop (>= 900px): Docked receipt panel on the LEFT
/// - Mobile (< 900px): Sticky running total bar & fast tender path
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  OrderType _selectedChannel = OrderType.dineIn;
  String? _selectedTableCode;
  String _selectedCategory = 'الكل';
  final List<OrderItem> _cartItems = [];

  // Service charge and tax configuration (standard Cairo rates)
  double get _serviceRate => _selectedChannel == OrderType.dineIn ? 0.12 : 0.0;
  double get _taxRate => 0.14;

  double get _subtotal =>
      _cartItems.fold(0, (sum, item) => sum + (item.unitPrice * item.quantity));

  double get _serviceAmount => _subtotal * _serviceRate;
  double get _taxAmount => (_subtotal + _serviceAmount) * _taxRate;
  double get _totalAmount => _subtotal + _serviceAmount + _taxAmount;

  void _addItem(MenuItemModel item) {
    if (item.modifierGroups.isNotEmpty) {
      PosCustomiseSheet.show(
        context,
        item: item,
        onAdd: (customizedItem) {
          setState(() => _cartItems.add(customizedItem));
        },
      );
    } else {
      setState(() {
        final existingIndex = _cartItems.indexWhere(
          (i) => i.productId == item.id && i.modifiers.isEmpty && i.note == null,
        );
        if (existingIndex >= 0) {
          final existing = _cartItems[existingIndex];
          _cartItems[existingIndex] = OrderItem(
            productId: existing.productId,
            name: existing.name,
            unitPrice: existing.unitPrice,
            quantity: existing.quantity + 1,
            station: existing.station,
          );
        } else {
          _cartItems.add(
            OrderItem(
              productId: item.id,
              name: item.name,
              unitPrice: item.price,
              quantity: 1,
              station: item.station,
            ),
          );
        }
      });
    }
  }

  void _incrementItem(int index) {
    final item = _cartItems[index];
    setState(() {
      _cartItems[index] = OrderItem(
        productId: item.productId,
        name: item.name,
        unitPrice: item.unitPrice,
        quantity: item.quantity + 1,
        station: item.station,
        note: item.note,
        modifiers: item.modifiers,
      );
    });
  }

  void _decrementItem(int index) {
    final item = _cartItems[index];
    setState(() {
      if (item.quantity > 1) {
        _cartItems[index] = OrderItem(
          productId: item.productId,
          name: item.name,
          unitPrice: item.unitPrice,
          quantity: item.quantity - 1,
          station: item.station,
          note: item.note,
          modifiers: item.modifiers,
        );
      } else {
        _cartItems.removeAt(index);
      }
    });
  }

  int get _cartItemCount =>
      _cartItems.fold(0, (sum, item) => sum + item.quantity);

  void _decrementItemByProductId(String productId) {
    final index = _cartItems.lastIndexWhere(
      (i) => i.productId == productId && i.modifiers.isEmpty && i.note == null,
    );
    if (index >= 0) {
      _decrementItem(index);
    }
  }

  Future<void> _startCheckout() async {
    if (_cartItems.isEmpty) return;

    final services = AppScope.of(context);

    await PosCheckoutDialog.show(
      context,
      totalAmount: _totalAmount,
      subtotal: _subtotal,
      taxAmount: _taxAmount,
      serviceAmount: _serviceAmount,
      discountAmount: 0.0,
      onComplete: (paymentMethod) async {
        // Write order locally first
        final draft = OrderDraft(
          items: List.of(_cartItems),
          orderType: _selectedChannel,
          taxAmount: _taxAmount,
          serviceAmount: _serviceAmount,
          discountAmount: 0.0,
          createdOffline: services.sync?.isOnline != true,
        );

        final createdOrder = await services.orders?.createOrder(draft);

        // Record payment
        if (createdOrder != null) {
          await services.payments?.recordPayment(
            PaymentDraft(
              orderLocalId: createdOrder.localId,
              orderRef: createdOrder.canonicalOrderNumber ?? createdOrder.provisionalOrderNumber,
              amount: _totalAmount,
              method: paymentMethod,
              createdOffline: services.sync?.isOnline != true,
            ),
          );
        }

        if (mounted) {
          setState(() {
            _cartItems.clear();
            _selectedTableCode = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: PieColors.surface2,
              content: Text(
                'اتعمل الأوردر تمام وتم تسجيل الدفع',
                style: PieTypography.body.copyWith(color: PieColors.stateSynced),
              ),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final services = AppScope.of(context);

    return FutureBuilder<List<MenuItemModel>>(
      future: services.menu?.listMenu(),
      builder: (context, snapshot) {
        final menuItems = snapshot.data ?? [];
        final categories = ['الكل', ...{for (final item in menuItems) item.category}];

        final filteredItems = _selectedCategory == 'الكل'
            ? menuItems
            : menuItems.where((i) => i.category == _selectedCategory).toList();

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              // Service Channel Header
              _buildChannelBar(),

              // Main Canvas
              Expanded(
                child: isDesktop
                    ? Row(
                        children: [
                          // Right side: Category Rail & Product Matrix
                          Expanded(
                            flex: 7,
                            child: _buildCatalogSection(categories, filteredItems),
                          ),
                          // Left side: Docked Receipt Panel (RTL layout)
                          Container(
                            width: 380,
                            decoration: const BoxDecoration(
                              color: PieColors.surface1,
                              border: Border(
                                right: BorderSide(color: PieColors.border, width: 1),
                              ),
                            ),
                            child: _buildReceiptPanel(),
                          ),
                        ],
                      )
                    : Stack(
                        children: [
                          _buildCatalogSection(categories, filteredItems),
                          if (_cartItems.isNotEmpty)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _buildMobileStickyCartBar(),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChannelBar() {
    return Container(
      decoration: const BoxDecoration(
        color: PieColors.surface1,
        border: Border(bottom: BorderSide(color: PieColors.border, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'نوع الطلب:',
              style: PieTypography.label.copyWith(color: PieColors.inkSecondary),
            ),
            const SizedBox(width: 10),
            _buildChannelChip(OrderType.dineIn, 'صالة', Icons.table_restaurant_rounded),
            const SizedBox(width: 8),
            _buildChannelChip(OrderType.takeaway, 'تيك أواي', Icons.shopping_bag_outlined),
            const SizedBox(width: 8),
            _buildChannelChip(OrderType.delivery, 'دليفري', Icons.two_wheeler_rounded),
            if (_selectedChannel == OrderType.dineIn) ...[
              const SizedBox(width: 12),
              Container(
                height: 24,
                width: 1,
                color: PieColors.border,
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () => _showTableSelectDialog(),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _selectedTableCode != null ? PieColors.cashierSurface : PieColors.surface2,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _selectedTableCode != null ? PieColors.cashierAccent : PieColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.table_bar_outlined,
                        size: 16,
                        color: _selectedTableCode != null ? PieColors.cashierAccent : PieColors.inkSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _selectedTableCode == null ? 'اختار الطاولة' : 'طاولة: $_selectedTableCode',
                        style: PieTypography.label.copyWith(
                          color: _selectedTableCode != null ? PieColors.cashierAccent : PieColors.ink,
                          fontWeight: _selectedTableCode != null ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 18,
                        color: _selectedTableCode != null ? PieColors.cashierAccent : PieColors.inkSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChannelChip(OrderType type, String label, IconData icon) {
    final isSelected = _selectedChannel == type;

    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 15,
        color: isSelected ? const Color(0xFF0F1117) : PieColors.inkSecondary,
      ),
      label: Text(
        label,
        style: PieTypography.label.copyWith(
          color: isSelected ? const Color(0xFF0F1117) : PieColors.ink,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: isSelected,
      selectedColor: PieColors.cashierAccent,
      backgroundColor: PieColors.surface2,
      side: BorderSide(
        color: isSelected ? PieColors.cashierAccent : PieColors.border,
      ),
      onSelected: (selected) {
        if (selected) setState(() => _selectedChannel = type);
      },
    );
  }

  Widget _buildCatalogSection(List<String> categories, List<MenuItemModel> items) {
    return Column(
      children: [
        // Category Horizontal Rail
        Container(
          height: 48,
          decoration: const BoxDecoration(
            color: PieColors.canvas,
            border: Border(bottom: BorderSide(color: PieColors.border, width: 1)),
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = _selectedCategory == cat;

              return ActionChip(
                label: Text(
                  cat,
                  style: PieTypography.caption.copyWith(
                    color: isSelected ? PieColors.cashierAccent : PieColors.inkSecondary,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                backgroundColor: isSelected ? PieColors.cashierSurface : PieColors.surface1,
                side: BorderSide(
                  color: isSelected ? PieColors.cashierAccent : PieColors.border,
                ),
                onPressed: () => setState(() => _selectedCategory = cat),
              );
            },
          ),
        ),

        // Product Matrix Grid
        Expanded(
          child: items.isEmpty
              ? const PieEmptyState(
                  title: 'مفيش أصناف في القسم ده',
                  description: 'الأصناف المتاحة هتظهر هنا بمجرد إضافتها للمنيو.',
                  icon: Icons.restaurant_menu_rounded,
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, _cartItems.isNotEmpty ? 100 : 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 148,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildProductCard(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProductCard(MenuItemModel item) {
    final inCartCount = _cartItems
        .where((i) => i.productId == item.id)
        .fold<int>(0, (sum, i) => sum + i.quantity);
    final isSelected = inCartCount > 0;

    return Opacity(
      opacity: item.available ? 1.0 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? PieColors.cashierSurface : PieColors.surface1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? PieColors.cashierAccent : PieColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: PieColors.cashierAccent.withOpacity(0.08),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: item.available ? () => _addItem(item) : null,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Station badge & In-Cart / Unavailable badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: PieColors.surface2,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: PieColors.border),
                        ),
                        child: Text(
                          item.station,
                          style: PieTypography.caption.copyWith(
                            color: PieColors.inkSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      if (!item.available)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: PieColors.stateErrorBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'نفد',
                            style: PieTypography.caption.copyWith(
                              color: PieColors.stateError,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: PieColors.cashierAccent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$inCartCount×',
                            style: PieTypography.caption.copyWith(
                              color: const Color(0xFF0F1117),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Middle: Product Name
                  Expanded(
                    child: Text(
                      item.name,
                      style: PieTypography.bodyStrong.copyWith(
                        color: item.available ? PieColors.ink : PieColors.inkMuted,
                        fontSize: 13,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Bottom Row: Price & Quick Stepper / Action
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PieNumeral.money(
                            item.price,
                            style: PieTypography.monoBody.copyWith(
                              color: isSelected ? PieColors.cashierAccent : PieColors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      if (item.available) ...[
                        if (item.modifierGroups.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: PieColors.surface2,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected ? PieColors.cashierAccent : PieColors.border,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  size: 12,
                                  color: isSelected ? PieColors.cashierAccent : PieColors.inkSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'تخصيص',
                                  style: PieTypography.caption.copyWith(
                                    color: isSelected ? PieColors.cashierAccent : PieColors.inkSecondary,
                                    fontSize: 10,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (isSelected)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => _decrementItemByProductId(item.id),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: PieColors.surface2,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: PieColors.border),
                                  ),
                                  child: const Icon(Icons.remove, size: 14, color: PieColors.ink),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: PieNumeral.count(
                                  inCartCount,
                                  style: PieTypography.monoBody.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: PieColors.cashierAccent,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _addItem(item),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: PieColors.cashierAccent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(Icons.add, size: 14, color: Color(0xFF0F1117)),
                                ),
                              ),
                            ],
                          )
                        else
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: PieColors.surface2,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: PieColors.border),
                            ),
                            child: const Icon(Icons.add_rounded, size: 18, color: PieColors.cashierAccent),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptPanel() {
    return Column(
      children: [
        // Receipt Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: PieColors.border, width: 1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, size: 18, color: PieColors.cashierAccent),
                  const SizedBox(width: 8),
                  Text(
                    'الفاتورة الحالية',
                    style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (_cartItems.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _cartItems.clear()),
                  child: Text(
                    'مسح الكل',
                    style: PieTypography.caption.copyWith(color: PieColors.stateError),
                  ),
                ),
            ],
          ),
        ),

        // Cart items list
        Expanded(
          child: _cartItems.isEmpty
              ? const PieEmptyState(
                  title: 'الفاتورة فاضية',
                  description: 'اضغط على أي صنف من القائمة لإضافته هنا مباشرة.',
                  icon: Icons.add_shopping_cart_rounded,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _cartItems.length,
                  separatorBuilder: (_, __) => const Divider(color: PieColors.border, height: 1),
                  itemBuilder: (context, index) {
                    final item = _cartItems[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: PieTypography.bodyStrong,
                                ),
                              ),
                              PieNumeral.money(
                                item.unitPrice * item.quantity,
                                style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (item.modifiers.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.modifiers.join(' • '),
                              style: PieTypography.caption.copyWith(color: PieColors.cashierAccent),
                            ),
                          ],
                          if (item.note != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'ملاحظة: ${item.note}',
                              style: PieTypography.caption.copyWith(fontStyle: FontStyle.italic),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              PieNumeral.money(
                                item.unitPrice,
                                prefix: 'سعر الوحدة: ',
                                style: PieTypography.monoCaption,
                              ),
                              const Spacer(),
                              // Stepper
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 16),
                                    onPressed: () => _decrementItem(index),
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    padding: EdgeInsets.zero,
                                  ),
                                  PieNumeral.count(
                                    item.quantity,
                                    style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 16),
                                    onPressed: () => _incrementItem(index),
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    padding: EdgeInsets.zero,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),

        // Subtotals & Fast Tender Call-to-action
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: PieColors.surface2,
            border: Border(top: BorderSide(color: PieColors.border, width: 1)),
          ),
          child: Column(
            children: [
              _buildBillLine('المجموع الجزئي', _subtotal),
              if (_serviceAmount > 0)
                _buildBillLine('خدمة صالة (12%)', _serviceAmount),
              _buildBillLine('ضريبة القيمة المضافة (14%)', _taxAmount),
              const Divider(color: PieColors.border, height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الإجمالي',
                    style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                  ),
                  PieNumeral.money(
                    _totalAmount,
                    style: PieTypography.monoHeading.copyWith(
                      color: PieColors.cashierAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              PieButton.primary(
                onPressed: _cartItems.isEmpty ? null : _startCheckout,
                label: 'المحاسبة والدفع • ${PieTypography.formatEgp(_totalAmount)}',
                accentColor: PieColors.cashierAccent,
                isFullWidth: true,
                height: 50,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileStickyCartBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: PieColors.surfaceOverlay,
        border: const Border(top: BorderSide(color: PieColors.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Order summary tap to open review sheet
            InkWell(
              onTap: _showMobileReceiptSheet,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: PieColors.surface2,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: PieColors.border),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            size: 20,
                            color: PieColors.cashierAccent,
                          ),
                        ),
                        Positioned(
                          top: -4,
                          left: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: PieColors.cashierAccent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_cartItemCount',
                              style: PieTypography.caption.copyWith(
                                color: const Color(0xFF0F1117),
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              'مراجعة الطلب',
                              style: PieTypography.caption.copyWith(
                                color: PieColors.inkSecondary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.keyboard_arrow_up_rounded,
                              size: 14,
                              color: PieColors.inkSecondary,
                            ),
                          ],
                        ),
                        PieNumeral.money(
                          _totalAmount,
                          style: PieTypography.monoBody.copyWith(
                            color: PieColors.cashierAccent,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            PieButton.primary(
              onPressed: _startCheckout,
              label: 'المحاسبة',
              icon: Icons.payments_outlined,
              accentColor: PieColors.cashierAccent,
              height: 44,
            ),
          ],
        ),
      ),
    );
  }

  void _showMobileReceiptSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PieColors.surfaceOverlay,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 10, bottom: 8),
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: PieColors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.receipt_long_rounded,
                                  size: 20,
                                  color: PieColors.cashierAccent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'تفاصيل الفاتورة ($_cartItemCount)',
                                  style: PieTypography.heading.copyWith(fontSize: 16),
                                ),
                              ],
                            ),
                            if (_cartItems.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  setState(() => _cartItems.clear());
                                  setSheetState(() {});
                                  Navigator.of(bottomSheetContext).pop();
                                },
                                child: Text(
                                  'مسح الكل',
                                  style: PieTypography.caption.copyWith(
                                    color: PieColors.stateError,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(color: PieColors.border, height: 1),

                      // Cart items list
                      Flexible(
                        child: _cartItems.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(32),
                                child: PieEmptyState(
                                  title: 'الفاتورة فاضية',
                                  description: 'اضغط على الأصناف لإضافتها.',
                                  icon: Icons.add_shopping_cart_rounded,
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.all(16),
                                itemCount: _cartItems.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(color: PieColors.border, height: 16),
                                itemBuilder: (context, index) {
                                  final item = _cartItems[index];
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item.name, style: PieTypography.bodyStrong),
                                            if (item.modifiers.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                item.modifiers.join(' • '),
                                                style: PieTypography.caption.copyWith(
                                                  color: PieColors.cashierAccent,
                                                ),
                                              ),
                                            ],
                                            if (item.note != null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'ملاحظة: ${item.note}',
                                                style: PieTypography.caption.copyWith(
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 4),
                                            PieNumeral.money(
                                              item.unitPrice,
                                              prefix: 'سعر الوحدة: ',
                                              style: PieTypography.monoCaption,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          PieNumeral.money(
                                            item.unitPrice * item.quantity,
                                            style: PieTypography.monoBody.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              InkWell(
                                                onTap: () {
                                                  _decrementItem(index);
                                                  setSheetState(() {});
                                                  if (_cartItems.isEmpty) {
                                                    Navigator.of(bottomSheetContext).pop();
                                                  }
                                                },
                                                borderRadius: BorderRadius.circular(4),
                                                child: Container(
                                                  width: 28,
                                                  height: 28,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: PieColors.surface2,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: PieColors.border),
                                                  ),
                                                  child: const Icon(Icons.remove, size: 14, color: PieColors.ink),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                                child: PieNumeral.count(
                                                  item.quantity,
                                                  style: PieTypography.monoBody.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              InkWell(
                                                onTap: () {
                                                  _incrementItem(index);
                                                  setSheetState(() {});
                                                },
                                                borderRadius: BorderRadius.circular(4),
                                                child: Container(
                                                  width: 28,
                                                  height: 28,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: PieColors.cashierAccent,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Icon(Icons.add, size: 14, color: Color(0xFF0F1117)),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),

                      // Totals breakdown & checkout
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: PieColors.surface2,
                          border: Border(top: BorderSide(color: PieColors.border, width: 1)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildBillLine('المجموع الجزئي', _subtotal),
                            if (_serviceAmount > 0)
                              _buildBillLine('خدمة صالة (12%)', _serviceAmount),
                            _buildBillLine('ضريبة القيمة المضافة (14%)', _taxAmount),
                            const Divider(color: PieColors.border, height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'الإجمالي',
                                  style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                                ),
                                PieNumeral.money(
                                  _totalAmount,
                                  style: PieTypography.monoHeading.copyWith(
                                    color: PieColors.cashierAccent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            PieButton.primary(
                              onPressed: _cartItems.isEmpty
                                  ? null
                                  : () {
                                      Navigator.of(bottomSheetContext).pop();
                                      _startCheckout();
                                    },
                              label: 'المحاسبة والدفع • ${PieTypography.formatEgp(_totalAmount)}',
                              accentColor: PieColors.cashierAccent,
                              isFullWidth: true,
                              height: 50,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBillLine(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: PieTypography.caption),
          PieNumeral.money(amount, style: PieTypography.monoCaption),
        ],
      ),
    );
  }

  void _showTableSelectDialog() {
    final tablesRepo = AppScope.of(context).tables;
    if (tablesRepo == null) return;

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: PieColors.surfaceOverlay,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('اختار الطاولة', style: PieTypography.heading),
                const SizedBox(height: 16),
                FutureBuilder<List<DiningTable>>(
                  future: tablesRepo.listTables(),
                  builder: (context, snapshot) {
                    final tables = snapshot.data ?? [];
                    if (tables.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('مفيش طاولات متسجلة'),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tables.map((t) {
                        return ActionChip(
                          label: Text(t.code),
                          backgroundColor: _selectedTableCode == t.code
                              ? PieColors.cashierAccent
                              : PieColors.surface2,
                          labelStyle: PieTypography.bodyStrong.copyWith(
                            color: _selectedTableCode == t.code ? Colors.black : PieColors.ink,
                          ),
                          onPressed: () {
                            setState(() => _selectedTableCode = t.code);
                            Navigator.of(context).pop();
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
