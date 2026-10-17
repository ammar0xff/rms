import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../domain/models/branch.dart';
import '../../domain/models/stock_transfer.dart';

/// Screen 20: Branch Network & Emergency Stock Transfer (شبكة الفروع والتحويل المخزني)
///
/// Functional contract:
/// - Branches directory
/// - Emergency inter-branch stock transfer requests
/// - Transfer status lifecycle (requested -> approved -> inTransit -> received)
class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  Future<void> _showNewTransferDialog(List<BranchModel> branches) async {
    final itemController = TextEditingController(text: 'لحم برجر مفروم');
    final qtyController = TextEditingController(text: '10');
    final unitController = TextEditingController(text: 'كجم');
    final noteController = TextEditingController();

    String donorBranchId = branches.length > 1 ? branches[1].id : 'maadi';
    String donorBranchName = branches.length > 1 ? branches[1].name : 'فرع المعادي';

    await showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          title: Text('طلب تحويل مخزني طارئ', style: PieTypography.heading),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: itemController,
                  decoration: const InputDecoration(labelText: 'اسم الخامة / الصنف'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'الكمية'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: unitController,
                        decoration: const InputDecoration(labelText: 'الوحدة'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('الفرع المانح (المحول منه):', style: PieTypography.label),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: donorBranchId,
                  dropdownColor: PieColors.surface2,
                  items: branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      donorBranchId = val;
                      donorBranchName = branches.firstWhere((b) => b.id == val).name;
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة',
                    hintText: 'سبب التحويل الطارئ...',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إلغاء', style: PieTypography.body.copyWith(color: PieColors.inkSecondary)),
            ),
            PieButton.primary(
              onPressed: () async {
                final qty = double.tryParse(qtyController.text) ?? 1.0;
                final services = AppScope.of(context);

                await services.transfers?.requestTransfer(
                  itemId: 'raw_${DateTime.now().millisecondsSinceEpoch}',
                  itemName: itemController.text.trim(),
                  quantity: qty,
                  unit: unitController.text.trim(),
                  fromBranchId: donorBranchId,
                  fromBranchName: donorBranchName,
                  toBranchId: 'dokki',
                  toBranchName: 'فرع الدقي الرئيسي',
                  note: noteController.text.trim(),
                );

                if (mounted) {
                  Navigator.of(context).pop();
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: PieColors.surface2,
                      content: Text('تم إنشاء طلب التحويل المخزني بنجاح'),
                    ),
                  );
                }
              },
              label: 'إرسال الطلب',
              accentColor: PieColors.managerAccent,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final branchRepo = services.branches;
    final transferRepo = services.transfers;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        appBar: AppBar(
          title: Text('الفروع والتحويل المخزني', style: PieTypography.heading),
        ),
        body: FutureBuilder(
          future: Future.wait([
            branchRepo?.listBranches() ?? Future.value(<BranchModel>[]),
            transferRepo?.listTransfers() ?? Future.value(<StockTransfer>[]),
          ]),
          builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
            final branches = (snapshot.data?[0] as List?)?.cast<BranchModel>() ?? [
              BranchModel(
                id: 'dokki',
                name: 'فرع الدقي الرئيسي',
                code: 'DKI-01',
                city: 'القاهرة',
                timezone: 'Africa/Cairo',
                openedAt: DateTime(2024, 1, 1),
                status: BranchStatus.active,
              ),
              BranchModel(
                id: 'maadi',
                name: 'فرع المعادي',
                code: 'MDI-02',
                city: 'القاهرة',
                timezone: 'Africa/Cairo',
                openedAt: DateTime(2024, 3, 1),
                status: BranchStatus.active,
              ),
            ];
            final transfers = (snapshot.data?[1] as List?)?.cast<StockTransfer>() ?? [];

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Request Transfer CTA Card
                PieCard(
                  padding: const EdgeInsets.all(18),
                  surfaceColor: PieColors.surface2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('نقل خامات طارئ بين الفروع', style: PieTypography.subheading),
                          const SizedBox(height: 2),
                          Text(
                            'تحويل فوري لسد نواقص التشغيل من الفروع المجاورة',
                            style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                          ),
                        ],
                      ),
                      PieButton.primary(
                        onPressed: () => _showNewTransferDialog(branches),
                        label: 'طلب تحويل',
                        icon: Icons.add_rounded,
                        accentColor: PieColors.managerAccent,
                        height: 42,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Active Transfers Section
                Text(
                  'طلبات التحويل المخزني (${transfers.length})',
                  style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),

                if (transfers.isEmpty)
                  const PieCard(
                    padding: EdgeInsets.all(28),
                    child: PieEmptyState(
                      title: 'مفيش تحويلات مخزنية جارية',
                      description: 'تقدر تطلب تحويل خامات أو مستلزمات من أي فرع في الشبكة.',
                      icon: Icons.swap_horiz_rounded,
                    ),
                  )
                else
                  for (final transfer in transfers) ...[
                    _buildTransferCard(transfer),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTransferCard(StockTransfer transfer) {
    final services = AppScope.of(context);

    return PieCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                transfer.itemName,
                style: PieTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
              ),
              _buildTransferStatusBadge(transfer.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'من: ${transfer.fromBranchName}  ←  إلى: ${transfer.toBranchName}',
            style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الكمية: ${transfer.quantity} ${transfer.unit}',
                style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${transfer.createdAt.hour.toString().padLeft(2, '0')}:${transfer.createdAt.minute.toString().padLeft(2, '0')}',
                style: PieTypography.monoCaption,
              ),
            ],
          ),
          if (transfer.status.isOpen) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (transfer.status == TransferStatus.requested)
                  Expanded(
                    child: PieButton.primary(
                      onPressed: () async {
                        await services.transfers?.advanceTransfer(transfer.id);
                        setState(() {});
                      },
                      label: 'اعتماد وبدء الشحن',
                      accentColor: PieColors.managerAccent,
                      height: 38,
                    ),
                  ),
                if (transfer.status == TransferStatus.inTransit)
                  Expanded(
                    child: PieButton.primary(
                      onPressed: () async {
                        await services.transfers?.receiveTransfer(transfer.id);
                        setState(() {});
                      },
                      label: 'تأكيد الاستلام وإضافة للمخزون',
                      accentColor: const Color(0xFF10B981),
                      height: 38,
                    ),
                  ),
                const SizedBox(width: 8),
                PieButton.ghost(
                  onPressed: () async {
                    await services.transfers?.cancelTransfer(transfer.id);
                    setState(() {});
                  },
                  label: 'إلغاء',
                  height: 38,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransferStatusBadge(TransferStatus status) {
    final (label, color, bg) = switch (status) {
      TransferStatus.requested => ('مطلوبة', PieColors.managerAccent, PieColors.managerSurface),
      TransferStatus.approved => ('معتمدة', const Color(0xFF60A5FA), const Color(0xFF172554)),
      TransferStatus.inTransit => ('في الطريق', const Color(0xFF38BDF8), const Color(0xFF0C4A6E)),
      TransferStatus.received => ('اتستلمت', const Color(0xFF4ADE80), const Color(0xFF052E16)),
      TransferStatus.cancelled => ('ملغية', PieColors.stateError, PieColors.stateErrorBg),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: PieTypography.caption.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
