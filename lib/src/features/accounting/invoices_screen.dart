import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_grab_handle.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_type.dart';
import '../../domain/services/receipt_print_service.dart';

/// Screen 8: Invoices Archive (أرشيف الفواتير وإعادة الطباعة والإلغاء)
///
/// Functional contract:
/// - Real-time reactive order list synchronized across the terminal
/// - Filterable invoice list by channel and search query
/// - Full receipt detail viewer
/// - Reprint trigger
/// - Void via approval request workflow
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  String _searchQuery = '';
  OrderType? _selectedChannelFilter;
  Order? _selectedOrder;
  List<Order>? _orders;
  bool _isLoading = true;
  Object? _loadError;
  StreamSubscription<List<Order>>? _orderSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeOrders();
  }

  void _subscribeOrders() {
    _orderSub?.cancel();
    final services = AppScope.of(context);

    // Immediate initial fetch
    _refreshOrders();

    final stream = services.orders?.watchOrders();
    if (stream != null) {
      _orderSub = stream.listen(
        (updated) {
          if (mounted) {
            setState(() {
              _orders = updated;
              _isLoading = false;
              _loadError = null;
              if (_selectedOrder != null) {
                final matchIndex = updated.indexWhere((o) => o.localId == _selectedOrder!.localId);
                if (matchIndex >= 0) {
                  _selectedOrder = updated[matchIndex];
                }
              }
            });
          }
        },
        onError: (e) {
          if (mounted && _orders == null) {
            setState(() {
              _loadError = e;
              _isLoading = false;
            });
          }
        },
      );
    }
  }

  Future<void> _refreshOrders() async {
    final services = AppScope.of(context);
    try {
      final orders = await services.orders?.listOrders() ?? <Order>[];
      if (mounted) {
        setState(() {
          _orders = orders;
          _isLoading = false;
          _loadError = null;
          if (_selectedOrder != null) {
            final matchIndex = orders.indexWhere((o) => o.localId == _selectedOrder!.localId);
            if (matchIndex >= 0) {
              _selectedOrder = orders[matchIndex];
            }
          }
        });
      }
    } catch (e) {
      if (mounted && _orders == null) {
        setState(() {
          _loadError = e;
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    if (_isLoading && _orders == null) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: PieColors.cashierAccent),
          ),
        ),
      );
    }

    if (_loadError != null && _orders == null) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: PieColors.stateError, size: 40),
                const SizedBox(height: 12),
                Text('تعذر تحميل سجل الفواتير', style: PieTypography.heading),
                const SizedBox(height: 8),
                Text('$_loadError', style: PieTypography.caption, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                PieButton.secondary(
                  onPressed: () {
                    PieSoundService.instance.click();
                    _refreshOrders();
                  },
                  label: 'إعادة المحاولة',
                  icon: Icons.refresh_rounded,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final allOrders = _orders ?? [];

    var filtered = allOrders;
    if (_selectedChannelFilter != null) {
      filtered = filtered.where((o) => o.orderType == _selectedChannelFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((o) {
        final ref = o.canonicalOrderNumber ?? o.provisionalOrderNumber;
        return ref.contains(_searchQuery);
      }).toList();
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // List (Right side)
                Expanded(
                  flex: 6,
                  child: _buildListSection(filtered),
                ),
                // Receipt Detail Viewer (Left side)
                Container(
                  width: 420,
                  decoration: const BoxDecoration(
                    color: PieColors.surface1,
                    border: Border(right: BorderSide(color: PieColors.border, width: 1)),
                  ),
                  child: _selectedOrder == null
                      ? const PieEmptyState(
                          title: 'اختار فاتورة لعرض التفاصيل',
                          description: 'اضغط على أي فاتورة من القائمة علشان تشوف البون وتعيد طباعته.',
                          icon: Icons.receipt_long_outlined,
                        )
                      : _buildReceiptViewer(_selectedOrder!),
                ),
              ],
            )
          : _buildListSection(filtered),
    );
  }

  Widget _buildListSection(List<Order> orders) {
    return Column(
      children: [
        // Filter and Search Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: PieColors.surface1,
            border: Border(bottom: BorderSide(color: PieColors.border, width: 1)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      decoration: InputDecoration(
                        hintText: 'ابحث برقم الأوردر...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () => setState(() => _searchQuery = ''),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 22, color: PieColors.inkSecondary),
                    tooltip: 'تحديث السجل',
                    onPressed: () {
                      PieSoundService.instance.click();
                      _refreshOrders();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildChannelFilterChip(null, 'الكل'),
                    const SizedBox(width: 6),
                    _buildChannelFilterChip(OrderType.dineIn, 'صالة'),
                    const SizedBox(width: 6),
                    _buildChannelFilterChip(OrderType.takeaway, 'تيك أواي'),
                    const SizedBox(width: 6),
                    _buildChannelFilterChip(OrderType.delivery, 'دليفري'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: orders.isEmpty
              ? PieEmptyState(
                  title: 'مفيش فواتير مطابقة',
                  description: 'كل الفواتير المسجلة في السيستم هتظهر هنا.',
                  icon: Icons.receipt_outlined,
                  actionLabel: 'تحديث السجل',
                  onAction: () {
                    PieSoundService.instance.click();
                    _refreshOrders();
                  },
                )
              : RefreshIndicator(
                  color: PieColors.cashierAccent,
                  backgroundColor: PieColors.surfaceOverlay,
                  onRefresh: _refreshOrders,
                  child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final isSelected = _selectedOrder?.localId == order.localId;

                    final ref = (order.canonicalOrderNumber?.isNotEmpty == true)
                        ? order.canonicalOrderNumber!
                        : (order.provisionalOrderNumber.isNotEmpty ? order.provisionalOrderNumber : order.localId);
                    final safeTotal = order.total.isFinite ? order.total : 0.0;
                    final itemsText = order.items.isEmpty
                        ? 'أوردر بدون أصناف'
                        : order.items.map((i) => '${i.quantity}x ${i.name}').join(', ');

                    return PieCard(
                      padding: const EdgeInsets.all(14),
                      isActive: isSelected,
                      activeColor: PieColors.cashierAccent,
                      onTap: () {
                        setState(() => _selectedOrder = order);
                        final isCompact = MediaQuery.of(context).size.width < 900;
                        if (isCompact) {
                          _showMobileReceiptSheet(order);
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        'أوردر #$ref',
                                        style: PieTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    PieBadge.channel(order.orderType),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (order.voided)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: PieColors.stateErrorBg,
                                    borderRadius: PieRadius.borderSm,
                                    border: Border.all(color: PieColors.stateError),
                                  ),
                                  child: Text(
                                    'ملغى',
                                    style: PieTypography.caption.copyWith(color: PieColors.stateError),
                                  ),
                                )
                              else
                                PieBadge.syncStatus(
                                  isSynced: order.syncStatus.name == 'synced',
                                  isPending: order.syncStatus.name == 'pendingSync' ||
                                      order.syncStatus.name == 'localOnly',
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            itemsText,
                            style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${order.createdAt.year}-${order.createdAt.month.toString().padLeft(2, '0')}-${order.createdAt.day.toString().padLeft(2, '0')} • ${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}',
                                style: PieTypography.monoCaption,
                              ),
                              PieNumeral.money(
                                safeTotal,
                                style: PieTypography.monoBody.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: order.voided ? PieColors.inkMuted : PieColors.cashierAccent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildChannelFilterChip(OrderType? type, String label) {
    final isSelected = _selectedChannelFilter == type;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      backgroundColor: PieColors.surface1,
      selectedColor: PieColors.cashierSurface,
      side: BorderSide(
        color: isSelected ? PieColors.cashierAccent : PieColors.border,
      ),
      labelStyle: PieTypography.caption.copyWith(
        color: isSelected ? PieColors.cashierAccent : PieColors.inkSecondary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      onSelected: (_) => setState(() => _selectedChannelFilter = type),
    );
  }

  Widget _buildReceiptViewer(Order order) {
    final ref = (order.canonicalOrderNumber?.isNotEmpty == true)
        ? order.canonicalOrderNumber!
        : (order.provisionalOrderNumber.isNotEmpty ? order.provisionalOrderNumber : order.localId);
    final safeTotal = order.total.isFinite ? order.total : 0.0;
    final safeSubtotal = order.subtotal.isFinite ? order.subtotal : 0.0;
    final safeService = order.serviceAmount.isFinite ? order.serviceAmount : 0.0;
    final safeTax = order.taxAmount.isFinite ? order.taxAmount : 0.0;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'تفاصيل الفاتورة',
                  style: PieTypography.heading,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              PieBadge.channel(order.orderType),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'رقم الفاتورة: #$ref',
            style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            'تاريخ الإنشاء: ${order.createdAt.year}-${order.createdAt.month.toString().padLeft(2, '0')}-${order.createdAt.day.toString().padLeft(2, '0')} • ${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}',
            style: PieTypography.monoCaption,
          ),
          const Divider(color: PieColors.border, height: 24),
          // Line items
          Expanded(
            child: order.items.isEmpty
                ? const Center(
                    child: Text('لا توجد أصناف في هذه الفاتورة', style: PieTypography.caption),
                  )
                : ListView.separated(
                    itemCount: order.items.length,
                    separatorBuilder: (_, __) => const Divider(color: PieColors.border, height: 1),
                    itemBuilder: (context, index) {
                      final item = order.items[index];
                      final lineTotal = (item.unitPrice * item.quantity).isFinite
                          ? (item.unitPrice * item.quantity)
                          : 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.quantity}x ${item.name}',
                                    style: PieTypography.bodyStrong,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PieNumeral.money(lineTotal),
                              ],
                            ),
                            if (item.modifiers.isNotEmpty)
                              Text(
                                item.modifiers.join(' • '),
                                style: PieTypography.caption.copyWith(color: PieColors.cashierAccent),
                              ),
                            if (item.note != null && item.note!.isNotEmpty)
                              Text('ملاحظة: ${item.note}', style: PieTypography.caption),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(color: PieColors.border, height: 20),
          // Breakdown
          _buildReceiptRow('المجموع الجزئي', safeSubtotal),
          if (safeService > 0)
            _buildReceiptRow('خدمة الصالة', safeService),
          if (safeTax > 0)
            _buildReceiptRow('ضريبة القيمة المضافة', safeTax),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'الإجمالي النهائي',
                  style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              PieNumeral.money(
                safeTotal,
                style: PieTypography.monoHeading.copyWith(
                  fontWeight: FontWeight.w700,
                  color: PieColors.cashierAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Action Buttons: Reprint & Void
          Row(
            children: [
              Expanded(
                child: PieButton.secondary(
                  onPressed: () async {
                    final services = AppScope.of(context);
                    final facility = await services.facility?.load();
                    final ref = (order.canonicalOrderNumber?.isNotEmpty == true)
                        ? order.canonicalOrderNumber!
                        : (order.provisionalOrderNumber.isNotEmpty ? order.provisionalOrderNumber : order.localId);

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: PieColors.surface2,
                          content: Text('جاري إرسال أمر طباعة الفاتورة #$ref...'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }

                    await ReceiptPrintService.printOrder(
                      order: order,
                      facility: facility,
                      printService: services.print,
                    );
                  },
                  label: 'إعادة طباعة',
                  icon: Icons.print_rounded,
                ),
              ),
              const SizedBox(width: 10),
              if (!order.voided)
                Expanded(
                  child: PieButton.destructive(
                    onPressed: () => _requestVoidApproval(order),
                    label: 'طلب إلغاء',
                    icon: Icons.cancel_outlined,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, double amount) {
    final safeAmount = amount.isFinite ? amount : 0.0;
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
          PieNumeral.money(safeAmount, style: PieTypography.monoCaption),
        ],
      ),
    );
  }

  void _showMobileReceiptSheet(Order order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PieColors.surfaceOverlay,
      shape: const RoundedRectangleBorder(borderRadius: PieRadius.topLg),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              const PieGrabHandle(),
              Expanded(child: _buildReceiptViewer(order)),
            ],
          ),
        ),
      ),
    );
  }

  void _requestVoidApproval(Order order) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          title: Text('طلب إلغاء فاتورة', style: PieTypography.heading),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إلغاء الفواتير يتطلب موافقة المدير. اكتب سبب الإلغاء ليتم إرساله لمركز الموافقات:',
                style: PieTypography.body,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'سبب الإلغاء',
                  hintText: 'مثلاً: خطأ في الأصناف، طلب العميل...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إلغاء', style: PieTypography.body.copyWith(color: PieColors.inkSecondary)),
            ),
            PieButton.destructive(
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) return;

                final services = AppScope.of(context);
                final ref = order.canonicalOrderNumber ?? order.provisionalOrderNumber;

                await services.approvals?.requestVoid(
                  orderLocalId: order.localId,
                  orderRef: ref,
                  amount: order.total,
                  reason: reason,
                  requestedBy: 'الكاشير',
                  createdOffline: services.sync?.isOnline != true,
                );

                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: PieColors.surface2,
                      content: Text('اتبعت طلب الإلغاء لمركز موافقات المدير'),
                    ),
                  );
                }
              },
              label: 'إرسال للمدير',
            ),
          ],
        ),
      ),
    );
  }
}
