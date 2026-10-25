import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../../core/widgets/pie_toast.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/order.dart';
import '../../domain/navigation/delivery_geocoding.dart';

/// Screen: Cashier Customers Management & Order History (سجل العملاء والطلبات السابقة للكاشير)
///
/// Features:
/// - Real-time search across customers by name, phone, or address
/// - Customer profile cards with verified GPS coordinates badge and orders counter
/// - Modal bottom sheet inspecting complete order history with line items
/// - Fast customer profile creation and editing with Egyptian geocoding autocomplete
class CashierCustomersScreen extends StatefulWidget {
  const CashierCustomersScreen({super.key});

  @override
  State<CashierCustomersScreen> createState() => _CashierCustomersScreenState();
}

class _CashierCustomersScreenState extends State<CashierCustomersScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) {
          setState(() {
            _query = _searchCtrl.text.trim().toLowerCase();
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    var cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '20${cleanPhone.substring(1)}';
    } else if (!cleanPhone.startsWith('20') && cleanPhone.length == 10) {
      cleanPhone = '20$cleanPhone';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showOrderHistory(BuildContext context, CustomerModel customer, AppServices services) {
    PieSoundService.instance.click();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PieColors.surfaceOverlay,
      shape: const RoundedRectangleBorder(borderRadius: PieRadius.topLg),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: DraggableScrollableSheet(
            initialChildSize: 0.65,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (_, scrollCtrl) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  children: [
                    const PieGrabHandle(margin: EdgeInsets.only(bottom: 12)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.history_rounded, color: PieColors.cashierAccent, size: 24),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'سجل طلبات: ${customer.name}',
                                  style: PieTypography.heading,
                                ),
                                Text(
                                  customer.phone,
                                  style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: PieColors.border),
                    Expanded(
                      child: FutureBuilder<List<Order>>(
                        future: services.orders?.getOrdersByCustomer(customer.id) ?? Future.value(<Order>[]),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final orders = snapshot.data!;
                          if (orders.isEmpty) {
                            return const Center(
                              child: PieEmptyState(
                                title: 'لا توجد طلبات سابقة مسجلة',
                                description: 'سيتم حفظ جميع طلبات العميل تلقائياً عند إتمام عمليات الشراء.',
                                icon: Icons.receipt_long_outlined,
                              ),
                            );
                          }

                          return ListView.separated(
                            controller: scrollCtrl,
                            itemCount: orders.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, idx) {
                              final order = orders[idx];
                              return PieCard(
                                padding: const EdgeInsets.all(14),
                                surfaceColor: PieColors.surface1,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'أوردر #${order.orderNumber}',
                                          style: PieTypography.bodyStrong.copyWith(color: PieColors.cashierAccent),
                                        ),
                                        PieNumeral.money(
                                          order.total,
                                          style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'التاريخ: ${order.createdAt.toLocal().toString().split('.').first}',
                                      style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                    ),
                                    if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFFEF4444)),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              order.deliveryAddress!,
                                              style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: order.items.map((item) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: PieColors.surfaceOverlay,
                                            borderRadius: PieRadius.borderSm,
                                            border: Border.all(color: PieColors.border),
                                          ),
                                          child: Text(
                                            '${item.quantity}× ${item.name}',
                                            style: const TextStyle(fontSize: 11, color: PieColors.ink),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showAddOrEditCustomerDialog(BuildContext context, AppServices services, [CustomerModel? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    double? resolvedLat = existing?.latitude;
    double? resolvedLng = existing?.longitude;

    List<PlaceSuggestion> suggestions = [];
    bool isSearchingPlaces = false;
    Timer? placeDebounce;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void onAddressChanged(String val) {
              placeDebounce?.cancel();
              if (val.trim().length < 3) {
                setDialogState(() {
                  suggestions = [];
                  isSearchingPlaces = false;
                });
                return;
              }
              setDialogState(() => isSearchingPlaces = true);
              placeDebounce = Timer(const Duration(milliseconds: 400), () async {
                final results = await DeliveryGeocoding.searchAddressSuggestions(val);
                if (dialogCtx.mounted) {
                  setDialogState(() {
                    suggestions = results;
                    isSearchingPlaces = false;
                  });
                }
              });
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: PieColors.surfaceOverlay,
                shape: const RoundedRectangleBorder(borderRadius: PieRadius.borderLg),
                title: Row(
                  children: [
                    Icon(
                      existing == null ? Icons.person_add_alt_1_rounded : Icons.edit_rounded,
                      color: PieColors.cashierAccent,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      existing == null ? 'إضافة عميل جديد' : 'تعديل بيانات العميل',
                      style: PieTypography.heading,
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: SizedBox(
                    width: 440,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CustomerInputField(
                          controller: nameCtrl,
                          label: 'اسم العميل *',
                          hint: 'مثال: أحمد عبد الله',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                        ),
                        const SizedBox(height: 12),
                        _CustomerInputField(
                          controller: phoneCtrl,
                          label: 'رقم الموبايل *',
                          hint: '01xxxxxxxxx',
                          keyboardType: TextInputType.phone,
                          prefixIcon: const Icon(Icons.phone_outlined),
                        ),
                        const SizedBox(height: 12),
                        _CustomerInputField(
                          controller: addressCtrl,
                          label: 'العنوان ومكان التوصيل',
                          hint: 'ابحث عن الشارع أو المنطقة (مثال: الأمل، شارع الباسل بالسويس)',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          onChanged: onAddressChanged,
                        ),
                        if (isSearchingPlaces)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: LinearProgressIndicator(color: PieColors.cashierAccent),
                          ),
                        if (suggestions.isNotEmpty)
                          Container(
                            constraints: const BoxConstraints(maxHeight: 160),
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              color: PieColors.surface2,
                              borderRadius: PieRadius.borderMd,
                              border: Border.all(color: PieColors.border),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: suggestions.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: PieColors.border),
                              itemBuilder: (context, idx) {
                                final s = suggestions[idx];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.place_rounded, size: 16, color: PieColors.cashierAccent),
                                  title: Text(s.name, style: PieTypography.bodyStrong),
                                  subtitle: Text(s.city, style: PieTypography.caption),
                                  onTap: () {
                                    setDialogState(() {
                                      addressCtrl.text = s.displayName;
                                      resolvedLat = s.latitude;
                                      resolvedLng = s.longitude;
                                      suggestions = [];
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (resolvedLat != null && resolvedLng != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: PieColors.stateSyncedBg,
                              borderRadius: PieRadius.borderSm,
                              border: Border.all(color: PieColors.stateSynced),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.verified_rounded, size: 14, color: PieColors.stateSynced),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'موقع جغرافي موثق (${resolvedLat!.toStringAsFixed(4)}, ${resolvedLng!.toStringAsFixed(4)})',
                                    style: const TextStyle(fontSize: 11, color: PieColors.stateSynced, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: Text('إلغاء', style: PieTypography.body.copyWith(color: PieColors.inkSecondary)),
                  ),
                  PieButton.primary(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      final phone = phoneCtrl.text.trim();
                      final address = addressCtrl.text.trim();

                      if (name.isEmpty || phone.isEmpty) {
                        PieToast.show(context, 'يرجى إدخال اسم العميل ورقم الموبايل', isError: true);
                        return;
                      }

                      if (existing != null) {
                        await services.customers?.updateCustomer(
                          CustomerModel(
                            id: existing.id,
                            name: name,
                            phone: phone,
                            address: address,
                            latitude: resolvedLat,
                            longitude: resolvedLng,
                            totalOrders: existing.totalOrders,
                            lastOrderAt: existing.lastOrderAt,
                            createdAt: existing.createdAt,
                            branchId: existing.branchId,
                            notes: existing.notes,
                          ),
                        );
                      } else {
                        await services.customers?.saveOrUpdateCustomer(
                          name: name,
                          phone: phone,
                          address: address,
                          latitude: resolvedLat,
                          longitude: resolvedLng,
                        );
                      }

                      if (dialogCtx.mounted) {
                        Navigator.of(dialogCtx).pop();
                        PieToast.show(
                          context,
                          existing == null ? 'تمت إضافة العميل بنجاح' : 'تم تحديث بيانات العميل',
                          isSuccess: true,
                        );
                        setState(() {});
                      }
                    },
                    label: existing == null ? 'حفظ العميل' : 'حفظ التعديلات',
                    height: 40,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final customerRepo = services.customers;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Action & Search Bar
              Row(
                children: [
                  Expanded(
                    child: _CustomerInputField(
                      controller: _searchCtrl,
                      hint: 'بحث باسم العميل، رقم الموبايل، أو العنوان...',
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(width: 12),
                  PieButton.primary(
                    onPressed: () => _showAddOrEditCustomerDialog(context, services),
                    label: 'عميل جديد',
                    icon: Icons.person_add_rounded,
                    accentColor: PieColors.cashierAccent,
                    height: 44,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Customer Directory List
              Expanded(
                child: FutureBuilder<List<CustomerModel>>(
                  future: customerRepo?.listCustomers() ?? Future.value(<CustomerModel>[]),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    var customers = snapshot.data!;
                    if (_query.isNotEmpty) {
                      customers = customers.where((c) {
                        return c.name.toLowerCase().contains(_query) ||
                            c.phone.contains(_query) ||
                            c.address.toLowerCase().contains(_query);
                      }).toList();
                    }

                    if (customers.isEmpty) {
                      return Center(
                        child: PieEmptyState(
                          title: _query.isEmpty ? 'لا يوجد عملاء مسجلين بعد' : 'لا توجد نتائج مطابقة للبحث',
                          description: _query.isEmpty
                              ? 'اضغط على "عميل جديد" أو أنشئ طلباً من شاشة البيع لحفظ العملاء تلقائياً.'
                              : 'جرّب البحث برقم هاتف آخر أو تحقق من الاسم.',
                          icon: Icons.people_outline_rounded,
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: customers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final c = customers[idx];
                        final hasGps = c.latitude != null && c.longitude != null;

                        return PieCard(
                          padding: const EdgeInsets.all(16),
                          surfaceColor: PieColors.surface2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: PieColors.cashierSurface,
                                            borderRadius: PieRadius.borderMd,
                                            border: Border.all(color: PieColors.cashierAccent),
                                          ),
                                          child: const Center(
                                            child: Icon(Icons.person_rounded, color: PieColors.cashierAccent, size: 24),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      c.name,
                                                      style: PieTypography.heading,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (c.totalOrders > 0) ...[
                                                    const SizedBox(width: 8),
                                                    PieBadge(
                                                      label: '${c.totalOrders} أوردر',
                                                      color: c.totalOrders > 3 ? PieColors.stateSynced : PieColors.cashierAccent,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                c.phone,
                                                style: PieTypography.monoBody.copyWith(color: PieColors.inkSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: 'اتصال هاتفي',
                                        icon: const Icon(Icons.call_rounded, size: 18, color: Color(0xFF10B981)),
                                        onPressed: () => _callPhone(c.phone),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: 'مراسلة واتساب',
                                        icon: const Icon(Icons.chat_bubble_rounded, size: 18, color: Color(0xFF25D366)),
                                        onPressed: () => _openWhatsApp(c.phone),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: 'تعديل',
                                        icon: const Icon(Icons.edit_outlined, size: 18, color: PieColors.inkSecondary),
                                        onPressed: () => _showAddOrEditCustomerDialog(context, services, c),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (c.address.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on_rounded, size: 15, color: Color(0xFFEF4444)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        c.address,
                                        style: PieTypography.body.copyWith(color: PieColors.ink),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (hasGps)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: PieColors.stateSyncedBg,
                                          borderRadius: PieRadius.borderSm,
                                          border: Border.all(color: PieColors.stateSynced),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.gps_fixed_rounded, size: 11, color: PieColors.stateSynced),
                                            SizedBox(width: 4),
                                            Text(
                                              'GPS موثق',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: PieColors.stateSynced,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    c.lastOrderAt != null
                                        ? 'آخر طلب: ${c.lastOrderAt!.toLocal().toString().split(' ').first}'
                                        : 'تاريخ التسجيل: ${c.createdAt.toLocal().toString().split(' ').first}',
                                    style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                  ),
                                  PieButton.secondary(
                                    onPressed: () => _showOrderHistory(context, c, services),
                                    label: 'سجل الطلبات (${c.totalOrders})',
                                    icon: Icons.history_rounded,
                                    height: 32,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerInputField extends StatelessWidget {
  const _CustomerInputField({
    required this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final Widget? prefixIcon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: PieTypography.bodyStrong),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: PieTypography.body,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: PieTypography.body.copyWith(color: PieColors.inkMuted),
            prefixIcon: prefixIcon,
            filled: true,
            fillColor: PieColors.surface1,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: PieRadius.borderMd,
              borderSide: const BorderSide(color: PieColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: PieRadius.borderMd,
              borderSide: const BorderSide(color: PieColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: PieRadius.borderMd,
              borderSide: const BorderSide(color: PieColors.cashierAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
