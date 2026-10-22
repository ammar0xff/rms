import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
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
  Future<void> _showAddBranchDialog(AppServices services) async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final cityCtrl = TextEditingController(text: 'القاهرة');
    final formKey = GlobalKey<FormState>();

    final added = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          shape: const RoundedRectangleBorder(
            borderRadius: PieRadius.borderLg,
            side: BorderSide(color: PieColors.border),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: PieColors.managerSurface,
                  borderRadius: PieRadius.borderMd,
                ),
                child: const Icon(Icons.add_business_outlined,
                    color: PieColors.managerAccent, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('إضافة فرع جديد للشبكة', style: PieTypography.heading),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'اسم الفرع',
                    hintText: 'مثال: فرع التجمع الخامس',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'اكتب اسم الفرع' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'كود الفرع (Code)',
                    hintText: 'مثال: TAG-03',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'اكتب كود الفرع' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: cityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'المدينة / المحافظة',
                    hintText: 'مثال: القاهرة أو الجيزة',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text('إلغاء',
                  style: PieTypography.body.copyWith(color: PieColors.inkSecondary)),
            ),
            PieButton.primary(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogCtx).pop(true);
                }
              },
              label: 'حفظ الفرع',
              accentColor: PieColors.managerAccent,
              height: 40,
            ),
          ],
        ),
      ),
    );

    if (added == true && mounted) {
      final branchRepo = services.branches;
      if (branchRepo == null) return;
      final newBranch = BranchModel(
        id: 'branch-${DateTime.now().millisecondsSinceEpoch}',
        name: nameCtrl.text.trim(),
        code: codeCtrl.text.trim().toUpperCase(),
        city: cityCtrl.text.trim().isEmpty ? 'القاهرة' : cityCtrl.text.trim(),
        timezone: 'Africa/Cairo',
        openedAt: DateTime.now(),
        status: BranchStatus.active,
      );
      final existing = await branchRepo.listBranches();
      await branchRepo.cacheBranches([...existing, newBranch], replace: true);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: PieColors.surface2,
            content: Text(
              'تمت إضافة ${newBranch.name} بنجاح إلى شبكة الفروع',
              style: PieTypography.body.copyWith(color: const Color(0xFF4ADE80)),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showNewTransferDialog(List<BranchModel> branches) async {
    final itemController = TextEditingController();
    final qtyController = TextEditingController();
    final unitController = TextEditingController();
    final noteController = TextEditingController();

    String donorBranchId = branches.length > 1
        ? branches[1].id
        : (branches.isNotEmpty ? branches.first.id : '');
    String donorBranchName = branches.length > 1
        ? branches[1].name
        : (branches.isNotEmpty ? branches.first.name : '');

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
                  decoration: const InputDecoration(
                    labelText: 'اسم الخامة / الصنف',
                    hintText: 'مثال: جبنة موتزاريلا أو لحم مفروم',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الكمية',
                          hintText: 'مثال: 10',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: unitController,
                        decoration: const InputDecoration(
                          labelText: 'الوحدة',
                          hintText: 'كجم / لتر / علبة',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('الفرع المانح (المحول منه):', style: PieTypography.label),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: donorBranchId.isNotEmpty ? donorBranchId : null,
                  dropdownColor: PieColors.surface2,
                  items: branches
                      .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      donorBranchId = val;
                      donorBranchName =
                          branches.firstWhere((b) => b.id == val).name;
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
              child: Text('إلغاء',
                  style: PieTypography.body.copyWith(color: PieColors.inkSecondary)),
            ),
            PieButton.primary(
              onPressed: () async {
                final qty = double.tryParse(qtyController.text) ?? 1.0;
                final services = AppScope.of(context);
                final activeBranch = await services.branches?.activeBranch();
                final toBranchId = activeBranch?.id ?? 'main-branch';
                final toBranchName = activeBranch?.name ?? 'الفرع الحالي';

                await services.transfers?.requestTransfer(
                  itemId: 'raw_${DateTime.now().millisecondsSinceEpoch}',
                  itemName: itemController.text.trim().isEmpty
                      ? 'خامة غير محددة'
                      : itemController.text.trim(),
                  quantity: qty,
                  unit: unitController.text.trim().isEmpty
                      ? 'وحدة'
                      : unitController.text.trim(),
                  fromBranchId: donorBranchId,
                  fromBranchName: donorBranchName,
                  toBranchId: toBranchId,
                  toBranchName: toBranchName,
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
      child: FutureBuilder(
          future: Future.wait([
            branchRepo?.listBranches() ?? Future.value(<BranchModel>[]),
            transferRepo?.listTransfers() ?? Future.value(<StockTransfer>[]),
          ]),
          builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
            final rawBranches =
                (snapshot.data?[0] as List?)?.cast<BranchModel>() ?? [];
            final branches = rawBranches.isNotEmpty
                ? rawBranches
                : (services.isDemo
                    ? [
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
                      ]
                    : <BranchModel>[]);
            final transfers =
                (snapshot.data?[1] as List?)?.cast<StockTransfer>() ?? [];

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Top Header Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'شبكة الفروع والتحويل المخزني',
                      style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'تحديث البيانات',
                          icon: const Icon(Icons.refresh_rounded, color: PieColors.inkSecondary),
                          onPressed: () => setState(() {}),
                        ),
                        const SizedBox(width: 8),
                        PieButton.primary(
                          icon: Icons.add_business_outlined,
                          label: 'إضافة فرع جديد',
                          accentColor: PieColors.managerAccent,
                          onPressed: () => _showAddBranchDialog(services),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Request Transfer CTA Card
                PieCard(
                  padding: const EdgeInsets.all(18),
                  surfaceColor: PieColors.surface2,
                  child: LayoutBuilder(
                    builder: (context, ctaConstraints) {
                      final isCompact = ctaConstraints.maxWidth < 460;
                      final infoColumn = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('نقل خامات طارئ بين الفروع', style: PieTypography.subheading),
                          const SizedBox(height: 2),
                          Text(
                            'تحويل فوري لسد نواقص التشغيل من الفروع المجاورة',
                            style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                          ),
                        ],
                      );
                      final button = PieButton.primary(
                        onPressed: branches.isEmpty
                            ? () => _showAddBranchDialog(services)
                            : () => _showNewTransferDialog(branches),
                        label: branches.isEmpty ? 'إضافة فرع أولاً' : 'طلب تحويل',
                        icon: Icons.add_rounded,
                        accentColor: PieColors.managerAccent,
                        height: 42,
                      );

                      if (isCompact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            infoColumn,
                            const SizedBox(height: 12),
                            button,
                          ],
                        );
                      }

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: infoColumn),
                          const SizedBox(width: 14),
                          button,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Branches Directory Section
                Text(
                  'فروع الشبكة (${branches.length})',
                  style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (branches.isEmpty)
                  const PieCard(
                    padding: EdgeInsets.all(24),
                    child: PieEmptyState(
                      title: 'لا توجد فروع مسجلة بالشبكة بعد',
                      description: 'اضغط على زر «إضافة فرع جديد» بالأعلى لتسجيل الفروع ومستودعات التوزيع.',
                      icon: Icons.storefront_outlined,
                    ),
                  )
                else
                  for (final b in branches) ...[
                    PieCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: PieColors.managerSurface,
                              borderRadius: PieRadius.borderMd,
                            ),
                            child: const Icon(Icons.storefront_outlined, color: PieColors.managerAccent, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.name, style: PieTypography.bodyStrong),
                                Text('كود: ${b.code} • المدينة: ${b.city}',
                                    style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: b.isActive ? const Color(0xFF052E16) : PieColors.surface3,
                              borderRadius: PieRadius.borderSm,
                              border: Border.all(
                                color: b.isActive ? const Color(0xFF4ADE80) : PieColors.border,
                              ),
                            ),
                            child: Text(
                              b.isActive ? 'نشط' : 'معطل',
                              style: PieTypography.caption.copyWith(
                                color: b.isActive ? const Color(0xFF4ADE80) : PieColors.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
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
              Expanded(
                child: Text(
                  transfer.itemName,
                  style: PieTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _buildTransferStatusBadge(transfer.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'من: ${transfer.fromBranchName}  ←  إلى: ${transfer.toBranchName}',
            style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
        borderRadius: PieRadius.borderSm,
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: PieTypography.caption.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
