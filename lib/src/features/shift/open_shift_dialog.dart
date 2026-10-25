import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../domain/models/cash_session.dart';

/// Modal dialog for opening a new cashier cash drawer shift with an opening float.
abstract final class OpenShiftDialog {
  static Future<CashSession?> show(BuildContext context) async {
    PieSoundService.instance.click();
    final ctrl = TextEditingController(text: '500');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
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
                decoration: const BoxDecoration(
                  color: PieColors.cashierSurface,
                  borderRadius: PieRadius.borderMd,
                ),
                child: const Icon(
                  Icons.lock_open_rounded,
                  color: PieColors.cashierAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text('افتتاح وردية جديدة', style: PieTypography.heading),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'أدخل مبلغ العهدة الافتتاحية في درج الكاشير للبدء بعمليات البيع:',
                style: PieTypography.body,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: PieTypography.monoHeading.copyWith(color: PieColors.cashierAccent),
                decoration: const InputDecoration(
                  labelText: 'عهدة الافتتاح (Float)',
                  suffixText: 'ج.م',
                  filled: true,
                  fillColor: PieColors.well,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [200, 500, 1000].map((amt) {
                  return ActionChip(
                    label: Text('+$amt ج.م'),
                    backgroundColor: PieColors.surface2,
                    side: const BorderSide(color: PieColors.border),
                    onPressed: () {
                      ctrl.text = amt.toString();
                      PieSoundService.instance.click();
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'إلغاء',
                style: PieTypography.body.copyWith(color: PieColors.textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: PieColors.cashierAccent,
                foregroundColor: const Color(0xFF0F1117),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: const RoundedRectangleBorder(borderRadius: PieRadius.borderMd),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('فتح الوردية الآن'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      final float = double.tryParse(ctrl.text.trim()) ?? 500.0;
      final services = AppScope.of(context);
      final repo = services.cashSessions;
      final user = services.auth.currentUser;
      final facility = await services.facility?.load();
      if (repo != null) {
        final session = await repo.openSession(
          openingFloat: float,
          cashierUid: user?.uid,
          cashierName: (user?.displayName != null && user!.displayName!.isNotEmpty)
              ? user.displayName
              : (user?.email?.split('@').first ?? 'الكاشير'),
          branchId: facility?.activeBranchId,
          branchName: facility?.activeBranchName,
          createdOffline: services.sync?.isOnline != true,
        );
        PieSoundService.instance.chime();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: PieColors.stateSynced,
              content: Text(
                'تم فتح الوردية بنجاح بعهدة ${float.toStringAsFixed(0)} ج.م. يمكنك الآن تسجيل المبيعات.',
              ),
            ),
          );
        }
        return session;
      }
    }
    return null;
  }
}
