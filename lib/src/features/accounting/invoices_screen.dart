import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_type.dart';

/// Screen 8: Invoices Archive (أرشيف الفواتير وإعادة الطباعة والإلغاء)
///
/// Functional contract:
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

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        appBar: AppBar(
          title: Text('أرشيف الفواتير والمبيعات', style: PieTypography.heading),
        ),
        body: FutureBuilder<List<Order>>(
          future: services.orders?.listOrders(),
          builder: (context, snapshot) {
            final allOrders = snapshot.data ?? [];

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

            if (isDesktop) {
              return Row(
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
              );
            }

            return _buildListSection(filtered);
          },
        ),
      ),
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
              TextField(
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
              ? const PieEmptyState(
                  title: 'مفيش فواتير مطابقة',
                  description: 'كل الفواتير المسجلة في السيستم هتظهر هنا.',
                  icon: Icons.receipt_outlined,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final isSelected = _selectedOrder?.localId == order.localId;

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
                              Row(
                                children: [
                                  Text(
                                    'أوردر #${order.canonicalOrderNumber ?? order.provisionalOrderNumber}',
                                    style: PieTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 8),
                                  PieBadge.channel(order.orderType),
                                ],
                              ),
                              if (order.voided)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: PieColors.stateErrorBg,
                                    borderRadius: BorderRadius.circular(4),
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
                            order.items.map((i) => '${i.quantity}x ${i.name}').join(', '),
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
                                order.total,
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('تفاصيل الفاتورة', style: PieTypography.heading),
              PieBadge.channel(order.orderType),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'رقم الفاتورة: #${order.canonicalOrderNumber ?? order.provisionalOrderNumber}',
            style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            'تاريخ الإنشاء: ${order.createdAt.toIso8601String().substring(0, 16)}',
            style: PieTypography.monoCaption,
          ),
          const Divider(color: PieColors.border, height: 24),
          // Line items
          Expanded(
            child: ListView.separated(
              itemCount: order.items.length,
              separatorBuilder: (_, __) => const Divider(color: PieColors.border, height: 1),
              itemBuilder: (context, index) {
                final item = order.items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${item.quantity}x ${item.name}', style: PieTypography.bodyStrong),
                          PieNumeral.money(item.unitPrice * item.quantity),
                        ],
                      ),
                      if (item.modifiers.isNotEmpty)
                        Text(
                          item.modifiers.join(' • '),
                          style: PieTypography.caption.copyWith(color: PieColors.cashierAccent),
                        ),
                      if (item.note != null)
                        Text('ملاحظة: ${item.note}', style: PieTypography.caption),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(color: PieColors.border, height: 20),
          // Breakdown
          _buildReceiptRow('المجموع الجزئي', order.subtotal),
          if (order.serviceAmount > 0)
            _buildReceiptRow('خدمة الصالة', order.serviceAmount),
          if (order.taxAmount > 0)
            _buildReceiptRow('ضريبة القيمة المضافة', order.taxAmount),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي النهائي', style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700)),
              PieNumeral.money(
                order.total,
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
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: PieColors.surface2,
                        content: Text('جاري إرسال أمر الطباعة للطابعة المحلية...'),
                      ),
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

  void _showMobileReceiptSheet(Order order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PieColors.surfaceOverlay,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: _buildReceiptViewer(order),
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
