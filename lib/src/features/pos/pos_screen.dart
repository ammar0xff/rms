import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_grab_handle.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../data/repositories/cash_session_repository.dart';
import '../../domain/models/cash_session.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/menu_item.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_draft.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/order_type.dart';
import '../../domain/models/cashier_user_settings.dart';
import '../../domain/models/facility_settings.dart';
import '../../domain/models/payment.dart';
import '../../domain/services/kitchen_ticket_factory.dart';
import '../../domain/services/receipt_print_service.dart';
import '../shift/open_shift_dialog.dart';
import 'pos_checkout_dialog.dart';
import 'pos_customise_sheet.dart';
import 'pos_receipt_success_dialog.dart';

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
  OrderType _selectedChannel = OrderType.takeaway;
  String _selectedCategory = 'الكل';
  final List<OrderItem> _cartItems = [];

  CashSession? _currentSession;
  double _expectedCash = 0.0;
  bool _isLoadingSession = true;
  StreamSubscription<CashSession?>? _sessionSubscription;
  Timer? _sessionRefreshTimer;

  FacilitySettings? _facility;
  CashierUserSettings _userSettings = const CashierUserSettings();
  bool _preferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    _sessionRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _isShiftOpen) {
        _refreshExpectedCash();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeToSession();
    if (!_preferencesLoaded) {
      _preferencesLoaded = true;
      _loadPreferences();
    }
  }

  Future<void> _loadPreferences() async {
    final services = AppScope.of(context);
    final user = services.auth.currentUser;
    final f = await services.facility?.load();
    final u = await CashierUserSettings.load(services.database, user?.uid);
    if (mounted) {
      setState(() {
        _facility = f;
        _userSettings = u;
        if (_cartItems.isEmpty) {
          _selectedChannel = u.defaultOrderType;
        }
      });
    }
  }

  void _subscribeToSession() {
    final services = AppScope.of(context);
    final repo = services.cashSessions;
    if (repo == null) {
      if (_isLoadingSession || _currentSession != null) {
        setState(() {
          _currentSession = null;
          _isLoadingSession = false;
          _expectedCash = 0.0;
        });
      }
      return;
    }

    _sessionSubscription?.cancel();
    _sessionSubscription = repo.watchCurrentSession().listen((session) {
      if (mounted) {
        setState(() {
          _currentSession = session;
          if (session != null) {
            _isLoadingSession = false;
          }
        });
        _refreshExpectedCash();
      }
    });

    _resolveInitialSession(services, repo);
  }

  Future<void> _resolveInitialSession(
    AppServices services,
    CashSessionRepository repo,
  ) async {
    try {
      final local = await repo.currentSession();
      if (local != null) {
        if (mounted) {
          setState(() {
            _currentSession = local;
            _isLoadingSession = false;
          });
          _refreshExpectedCash();
        }
        return;
      }
    } catch (_) {}

    if (services.firebaseReady && services.inboundSync != null) {
      try {
        await services.inboundSync!.waitForInitialCollection(
          'cashSessions',
          timeout: const Duration(milliseconds: 1800),
        );
        final synced = await repo.currentSession();
        if (mounted) {
          setState(() {
            _currentSession = synced;
            _isLoadingSession = false;
          });
          _refreshExpectedCash();
          return;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isLoadingSession = false;
      });
    }
  }

  Future<void> _refreshExpectedCash() async {
    final repo = AppScope.of(context).cashSessions;
    final session = _currentSession;
    if (repo == null || session == null || !session.isOpen) {
      if (mounted && _expectedCash != 0.0) {
        setState(() => _expectedCash = 0.0);
      }
      return;
    }
    try {
      final expected = await repo.expectedCash(session);
      if (mounted) {
        setState(() => _expectedCash = expected);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _sessionRefreshTimer?.cancel();
    _sessionSubscription?.cancel();
    super.dispose();
  }

  bool get _isShiftOpen => _currentSession != null && _currentSession!.isOpen;

  Future<void> _promptOpenShift() async {
    PieSoundService.instance.beep();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: PieColors.statePendingBg,
        duration: const Duration(seconds: 4),
        content: Text(
          'الوردية الحالية مغلقة — يرجى فتح الوردية للبدء بعمليات البيع',
          style: PieTypography.body.copyWith(color: PieColors.statePending),
        ),
        action: SnackBarAction(
          label: 'فتح الوردية',
          textColor: PieColors.cashierAccent,
          onPressed: () async {
            final session = await OpenShiftDialog.show(context);
            if (session != null && mounted) {
              setState(() {
                _currentSession = session;
                _isLoadingSession = false;
              });
              _refreshExpectedCash();
            }
          },
        ),
      ),
    );
  }

  // Tax configuration (dynamically linked to FacilitySettings, falling back to Egyptian standard rates)
  double get _taxRate => _facility?.vatRate ?? 0.14;

  double get _subtotal =>
      _cartItems.fold(0, (sum, item) => sum + (item.unitPrice * item.quantity));

  double get _serviceAmount => 0.0;
  double get _taxAmount => _subtotal * _taxRate;
  double get _totalAmount => _subtotal + _taxAmount;

  void _addItem(MenuItemModel item) {
    if (!_isShiftOpen) {
      _promptOpenShift();
      return;
    }
    if (_userSettings.hapticFeedback) {
      HapticFeedback.selectionClick();
    }
    PieSoundService.instance.beep();
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
    PieSoundService.instance.click();
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
    PieSoundService.instance.click();
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
    if (!_isShiftOpen) {
      _promptOpenShift();
      return;
    }
    if (_cartItems.isEmpty) return;

    final services = AppScope.of(context);
    Order? createdOrderResult;
    String? resolvedPaymentMethod;
    double? resolvedTendered;
    double? resolvedChange;
    String? resolvedCustomerName;
    String? resolvedCustomerPhone;
    String? resolvedDeliveryAddress;

    final didCheckout = await PosCheckoutDialog.show(
      context,
      totalAmount: _totalAmount,
      subtotal: _subtotal,
      taxAmount: _taxAmount,
      serviceAmount: _serviceAmount,
      discountAmount: 0.0,
      orderType: _selectedChannel,
      onComplete: (
        paymentMethod, {
        customerName,
        customerPhone,
        deliveryAddress,
        tenderedAmount,
        zoneName,
        zoneFee,
      }) async {
        if (services.orders == null) {
          throw StateError('قاعدة البيانات غير متاحة حالياً، تعذر حفظ الفاتورة');
        }

        // Write order locally first
        final draft = OrderDraft(
          items: List.of(_cartItems),
          orderType: _selectedChannel,
          taxAmount: _taxAmount,
          serviceAmount: _serviceAmount,
          discountAmount: 0.0,
          deliveryFee: zoneFee ?? 0.0,
          createdOffline: services.sync?.isOnline != true,
        );

        final createdOrder = await services.orders!.createOrder(draft);
        createdOrderResult = createdOrder;
        resolvedPaymentMethod = paymentMethod == PaymentMethod.card ? 'فيزا / بطاقة' : 'نقدي';
        resolvedTendered = tenderedAmount ?? createdOrder.total;
        resolvedChange = (paymentMethod == PaymentMethod.cash && (tenderedAmount ?? createdOrder.total) > createdOrder.total)
            ? ((tenderedAmount ?? createdOrder.total) - createdOrder.total)
            : 0.0;
        resolvedCustomerName = customerName;
        resolvedCustomerPhone = customerPhone;
        resolvedDeliveryAddress = deliveryAddress;

        final orderRef = createdOrder.canonicalOrderNumber ?? createdOrder.provisionalOrderNumber;

        // Record payment for in-store orders (takeaway) or prepaid cards.
        // For cash delivery orders, payment is Cash On Delivery (COD) collected
        // on the road by the courier and ONLY enters the cashier drawer upon settlement.
        final isCashDelivery = _selectedChannel == OrderType.delivery && paymentMethod == PaymentMethod.cash;
        if (services.payments != null && !isCashDelivery) {
          try {
            await services.payments!.recordPayment(
              PaymentDraft(
                orderLocalId: createdOrder.localId,
                orderRef: orderRef,
                amount: createdOrder.total,
                method: paymentMethod,
                tendered: tenderedAmount,
                createdOffline: services.sync?.isOnline != true,
              ),
            );
            _refreshExpectedCash();
          } catch (e) {
            AppLogger.warn('Payment record warning: $e');
          }
        }

        // Save customer info if provided
        if (customerName != null || customerPhone != null) {
          try {
            await services.customers?.createCustomer(
              name: customerName?.isNotEmpty == true ? customerName! : 'عميل',
              phone: customerPhone ?? '',
              notes: deliveryAddress ?? '',
              createdOffline: services.sync?.isOnline != true,
            );
          } catch (_) {}
        }

        // Handle delivery channel: create job and auto-dispatch or manual assign
        if (_selectedChannel == OrderType.delivery) {
          final delivery = await services.deliveries?.createDelivery(
            orderRef: orderRef,
            address: deliveryAddress?.isNotEmpty == true ? deliveryAddress! : 'العنوان غير محدد',
            amount: createdOrder.total,
            customerName: customerName,
            customerPhone: customerPhone,
            landmark: deliveryAddress,
            zoneName: zoneName,
            zoneFee: zoneFee,
            createdOffline: services.sync?.isOnline != true,
          );

          final facility = await services.facility?.load();
          final autoDispatch = facility?.autoAssignDelivery ?? true;

          if (autoDispatch) {
            final assignedList = await services.deliveries?.autoAssignWaiting();
            final wasAssigned = assignedList?.any((d) => d.deliveryId == delivery?.id) ?? false;
            if (!wasAssigned && delivery != null && mounted) {
              await _showManualDriverAssignDialog(context, delivery.id, orderRef);
            }
          } else if (delivery != null && mounted) {
            await _showManualDriverAssignDialog(context, delivery.id, orderRef);
          }
        }
      },
    );

    if (didCheckout == true) {
      _refreshExpectedCash();
    }

    if (didCheckout == true && createdOrderResult != null && mounted) {
      final createdOrder = createdOrderResult!;
      final orderRef = createdOrder.canonicalOrderNumber ?? createdOrder.provisionalOrderNumber;
      final facility = await services.facility?.load();

      // Clear the cart on successful checkout (if fastCheckoutAutoClear enabled)
      if (_userSettings.fastCheckoutAutoClear) {
        setState(() {
          _cartItems.clear();
          _selectedChannel = _userSettings.defaultOrderType;
        });
      }

      // Immediate print trigger on checkout
      ReceiptPrintService.printOrder(
        order: createdOrder,
        facility: facility,
        printService: services.print,
        paymentMethod: resolvedPaymentMethod,
        paidAmount: resolvedTendered,
        changeDue: resolvedChange,
        customerName: resolvedCustomerName,
        customerPhone: resolvedCustomerPhone,
        deliveryAddress: resolvedDeliveryAddress,
      );

      // Kitchen Ticket dispatch to KDS store and thermal printer
      try {
        final kitchenTickets = KitchenTicketFactory().fromOrder(createdOrder);
        for (final ticket in kitchenTickets) {
          services.kitchen?.upsertTicket(ticket);
          services.print?.printKitchenTicket(ticket);
        }
      } catch (e) {
        AppLogger.warn('Kitchen ticket dispatch error: $e');
      }

      // Show immediate confirmation & print dialog if enabled in user preferences
      if (mounted && _userSettings.autoOpenReceipt) {
        await PosReceiptSuccessDialog.show(
          context,
          order: createdOrder,
          facility: facility,
          paymentMethod: resolvedPaymentMethod,
          paidAmount: resolvedTendered,
          changeDue: resolvedChange,
          onPrint: () async {
            await ReceiptPrintService.printOrder(
              order: createdOrder,
              facility: facility,
              printService: services.print,
              paymentMethod: resolvedPaymentMethod,
              paidAmount: resolvedTendered,
              changeDue: resolvedChange,
            );
          },
          onOpenTab: () {
            ReceiptPrintService.openOrderInTab(
              order: createdOrder,
              facility: facility,
              paymentMethod: resolvedPaymentMethod,
              paidAmount: resolvedTendered,
              changeDue: resolvedChange,
            );
          },
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: PieColors.surface2,
            duration: const Duration(seconds: 4),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: PieColors.stateSynced, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم إنشاء الفاتورة #$orderRef بنجاح',
                    style: PieTypography.body.copyWith(color: PieColors.stateSynced),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'إعادة طباعة',
              textColor: PieColors.cashierAccent,
              onPressed: () async {
                final fac = await services.facility?.load();
                await ReceiptPrintService.printOrder(
                  order: createdOrder,
                  facility: fac,
                  printService: services.print,
                  paymentMethod: resolvedPaymentMethod,
                  paidAmount: resolvedTendered,
                  changeDue: resolvedChange,
                );
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final services = AppScope.of(context);

    if (_isLoadingSession) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: CircularProgressIndicator(color: PieColors.cashierAccent),
        ),
      );
    }

    if (!_isShiftOpen) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: _buildShiftRequiredGate(isDesktop),
      );
    }

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
              // Mobile-only Channel Header (on desktop it is docked above the cart)
              if (!isDesktop) _buildChannelBar(),

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

  Widget _buildShiftRequiredGate(bool isDesktop) {
    return Container(
      color: PieColors.canvas,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 580),
            padding: EdgeInsets.all(isDesktop ? 36 : 24),
            decoration: BoxDecoration(
              color: PieColors.surface1,
              borderRadius: PieRadius.borderLg,
              border: Border.all(color: PieColors.cashierAccent.withValues(alpha: 0.35), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Glowing Icon Header
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: PieColors.cashierSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: PieColors.cashierAccent.withValues(alpha: 0.5), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: PieColors.cashierAccent.withValues(alpha: 0.2),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.lock_clock_rounded,
                    color: PieColors.cashierAccent,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                const Text(
                  'الوردية مغلقة — يرجى فتح الوردية للبدء',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PieColors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  'نظام نقطة البيع مقفل ومحمي. لا يمكن إنشاء أي طلبات جديدة، أو إضافة أصناف إلى السلة، أو محاسبة العملاء حتى يتم افتتاح وردية كاشير وتعيين مبلغ العهدة النقدية في الدرج.',
                  textAlign: TextAlign.center,
                  style: PieTypography.body.copyWith(
                    color: PieColors.inkSecondary,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 28),

                // Status info box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: PieColors.surface2,
                    borderRadius: PieRadius.borderMd,
                    border: Border.all(color: PieColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: PieColors.statePending, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'حالة درج النقدية: مقفل ومؤمّن | حماية المبيعات: مفعلة',
                          style: PieTypography.caption.copyWith(
                            color: PieColors.statePending,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PieColors.cashierAccent,
                      foregroundColor: const Color(0xFF0F1117),
                      shape: const RoundedRectangleBorder(borderRadius: PieRadius.borderMd),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.lock_open_rounded, size: 22),
                    label: const Text(
                      'افتتاح الوردية وتعيين العهدة الآن',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () async {
                      final session = await OpenShiftDialog.show(context);
                      if (session != null && mounted) {
                        setState(() {
                          _currentSession = session;
                          _isLoadingSession = false;
                        });
                        _refreshExpectedCash();
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Footer note
                Text(
                  'سيتم تسجيل وقت فتح الوردية واسم الكاشير ومبلغ العهدة النقدية تلقائياً في سجلات التدقيق.',
                  textAlign: TextAlign.center,
                  style: PieTypography.caption.copyWith(
                    color: PieColors.inkMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: PieColors.surface1,
        border: Border(bottom: BorderSide(color: PieColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            'نوع الطلب:',
            style: PieTypography.caption.copyWith(
              color: PieColors.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildChannelChip(
              OrderType.takeaway,
              'تيك أواي (استلام)',
              Icons.shopping_bag_outlined,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildChannelChip(
              OrderType.delivery,
              'دليفري (توصيل)',
              Icons.two_wheeler_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelChip(OrderType type, String label, IconData icon) {
    final isSelected = _selectedChannel == type;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          PieSoundService.instance.click();
          setState(() => _selectedChannel = type);
        },
        borderRadius: PieRadius.borderMd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? PieColors.cashierAccent : PieColors.surface2,
            borderRadius: PieRadius.borderMd,
            border: Border.all(
              color: isSelected ? PieColors.cashierAccent : PieColors.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? PieColors.canvas : PieColors.inkSecondary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PieTypography.caption.copyWith(
                    color: isSelected ? PieColors.canvas : PieColors.ink,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    PieSoundService.instance.click();
                    setState(() => _selectedCategory = cat);
                  },
                  borderRadius: PieRadius.borderSm,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? PieColors.cashierSurface : PieColors.surface1,
                      borderRadius: PieRadius.borderSm,
                      border: Border.all(
                        color: isSelected ? PieColors.cashierAccent : PieColors.border,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        cat,
                        style: PieTypography.caption.copyWith(
                          color: isSelected ? PieColors.cashierAccent : PieColors.inkSecondary,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
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
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: _userSettings.compactGridView ? 175 : 220,
                    mainAxisExtent: _userSettings.compactGridView ? 118 : 148,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isSelected ? PieColors.cashierSurface : PieColors.surface1,
          borderRadius: PieRadius.borderLg,
          border: Border.all(
            color: isSelected ? PieColors.cashierAccent : PieColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: PieColors.cashierAccent.withOpacity(0.12),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: PieRadius.borderLg,
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
                          borderRadius: PieRadius.borderSm,
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
                            borderRadius: PieRadius.borderSm,
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
                            borderRadius: PieRadius.borderSm,
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
                      Flexible(
                        child: Column(
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
                      ),
                      if (item.available) ...[
                        if (item.modifierGroups.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: PieColors.surface2,
                              borderRadius: PieRadius.borderSm,
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
                                borderRadius: PieRadius.borderSm,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: PieColors.surface2,
                                    borderRadius: PieRadius.borderSm,
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
                                borderRadius: PieRadius.borderSm,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: PieColors.cashierAccent,
                                    borderRadius: PieRadius.borderSm,
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
                              borderRadius: PieRadius.borderSm,
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
        // Order Type Selector Header (Placed directly above the cart)
        _buildChannelBar(),

        // Receipt Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: PieColors.border, width: 1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, size: 18, color: PieColors.cashierAccent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'الفاتورة الحالية',
                        style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
              _buildBillLine('ضريبة القيمة المضافة (${(_taxRate * 100).toStringAsFixed(0)}%)', _taxAmount),
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
              borderRadius: PieRadius.borderMd,
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
                            borderRadius: PieRadius.borderMd,
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
                              borderRadius: PieRadius.borderSm,
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
      shape: RoundedRectangleBorder(
        borderRadius: PieRadius.topLg,
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
                      const PieGrabHandle(),
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
                                                borderRadius: PieRadius.borderSm,
                                                child: Container(
                                                  width: 28,
                                                  height: 28,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: PieColors.surface2,
                                                    borderRadius: PieRadius.borderSm,
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
                                                borderRadius: PieRadius.borderSm,
                                                child: Container(
                                                  width: 28,
                                                  height: 28,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: PieColors.cashierAccent,
                                                    borderRadius: PieRadius.borderSm,
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
                            _buildBillLine('ضريبة القيمة المضافة (${(_taxRate * 100).toStringAsFixed(0)}%)', _taxAmount),
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
          Expanded(
            child: Text(
              label,
              style: PieTypography.caption,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          PieNumeral.money(amount, style: PieTypography.monoCaption),
        ],
      ),
    );
  }

  Future<void> _showManualDriverAssignDialog(
    BuildContext context,
    String deliveryId,
    String orderRef,
  ) async {
    final services = AppScope.of(context);
    final driversRepo = services.deliveries;
    if (driversRepo == null) return;

    var drivers = await driversRepo.listDrivers();
    if (drivers.isEmpty) {
      if (services.inboundSync != null) {
        await services.inboundSync!.waitForInitialCollection('drivers', timeout: const Duration(milliseconds: 1500));
        drivers = await driversRepo.listDrivers();
      }
      if (drivers.isEmpty) {
        try {
          final snap = await FirebaseFirestore.instance.collection('drivers').get();
          if (snap.docs.isNotEmpty) {
            final fetched = snap.docs.map<DriverModel>((doc) {
              final data = doc.data();
              return DriverModel(
                id: doc.id,
                name: data['name']?.toString() ?? 'كابتن',
                available: data['available'] == true || data['status'] == 'available',
                phone: data['phone']?.toString(),
                email: data['email']?.toString() ?? '',
              );
            }).toList();
            await driversRepo.cacheDrivers(fetched);
            drivers = fetched;
          }
        } catch (_) {}
      }
    }
    final allDeliveries = await driversRepo.listDeliveries();

    if (!mounted) return;

    // Calculate active assigned/onRoute counts for each driver
    final activeCounts = <String, int>{};
    for (final d in allDeliveries) {
      if (d.state == DeliveryState.assigned || d.state == DeliveryState.onRoute) {
        activeCounts[d.driver] = (activeCounts[d.driver] ?? 0) + 1;
      }
    }

    String? selectedDriverName;
    if (drivers.isNotEmpty) {
      final available = drivers.where((d) => d.available).toList();
      if (available.isNotEmpty) {
        available.sort((a, b) => (activeCounts[a.name] ?? 0).compareTo(activeCounts[b.name] ?? 0));
        selectedDriverName = available.first.name;
      } else {
        selectedDriverName = drivers.first.name;
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Dialog(
                backgroundColor: PieColors.surfaceOverlay,
                insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Container(
                  width: 480,
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: PieColors.driverSurface,
                              borderRadius: PieRadius.borderMd,
                            ),
                            child: const Icon(Icons.two_wheeler_rounded, color: PieColors.driverAccent, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'إسناد يدوي لسائق التوصيل',
                                  style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'طلب: $orderRef • تم إيقاف التوزيع التلقائي من الإعدادات',
                                  style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'اختر أحد السائقين المتاحين للرحلة:',
                        style: PieTypography.label.copyWith(color: PieColors.inkSecondary),
                      ),
                      const SizedBox(height: 10),

                      if (drivers.isEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: PieColors.surface2,
                            borderRadius: PieRadius.borderMd,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.two_wheeler_outlined, color: PieColors.inkMuted, size: 28),
                                const SizedBox(height: 8),
                                Text(
                                  'لا يوجد كباتن مسجلين بالنظام حالياً',
                                  style: PieTypography.bodyStrong.copyWith(color: PieColors.inkMuted),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'يرجى مراجعة مدير الفرع لتسجيل طيارين وتعيينهم',
                                  style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: drivers.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final driver = drivers[index];
                              final isSelected = selectedDriverName == driver.name;
                              final count = activeCounts[driver.name] ?? 0;

                              return InkWell(
                                onTap: () {
                                  PieSoundService.instance.click();
                                  setDialogState(() => selectedDriverName = driver.name);
                                },
                                borderRadius: PieRadius.borderMd,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? PieColors.driverSurface : PieColors.surface2,
                                    borderRadius: PieRadius.borderMd,
                                    border: Border.all(
                                      color: isSelected ? PieColors.driverAccent : PieColors.border,
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                        color: isSelected ? PieColors.driverAccent : PieColors.inkMuted,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          driver.name,
                                          style: PieTypography.bodyStrong.copyWith(
                                            color: isSelected ? PieColors.driverAccent : PieColors.ink,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: driver.available ? PieColors.managerSurface : PieColors.surface3,
                                          borderRadius: PieRadius.borderSm,
                                        ),
                                        child: Text(
                                          driver.available ? 'متاح ($count جارية)' : 'غير متاح',
                                          style: PieTypography.caption.copyWith(
                                            color: driver.available ? PieColors.managerAccent : PieColors.inkMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                PieSoundService.instance.click();
                                Navigator.of(dialogCtx).pop();
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: PieColors.border),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: PieRadius.borderMd),
                              ),
                              child: Text(
                                'تخطي والإسناد لاحقاً',
                                style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: PieButton.primary(
                              onPressed: selectedDriverName == null
                                  ? null
                                  : () async {
                                      PieSoundService.instance.chime();
                                      await driversRepo.assignDriver(deliveryId, selectedDriverName!);
                                      if (dialogCtx.mounted) {
                                        Navigator.of(dialogCtx).pop();
                                      }
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            backgroundColor: PieColors.surface2,
                                            content: Text(
                                              'تم إسناد الطلب للكابتن $selectedDriverName بنجاح',
                                              style: PieTypography.body.copyWith(color: PieColors.driverAccent),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              label: selectedDriverName != null
                                  ? 'إسناد للكابتن $selectedDriverName'
                                  : 'اختار سائق',
                              accentColor: PieColors.driverAccent,
                              height: 48,
                            ),
                          ),
                        ],
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
}
