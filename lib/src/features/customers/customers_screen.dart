import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/mock/mock_data.dart';
import '../common/format.dart';

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        // No add button: the screen reads cached data with no backing store,
        // so a dialog would pretend to persist. It returns with the store.
        const SectionHeader(
          title: 'العملاء',
          subtitle: 'قراءة مخزنة مع إنشاء محلي · مزامنة عند الاتصال',
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: RmsTable(
            columns: const [
              RmsColumn('الاسم', flex: 3),
              RmsColumn('الهاتف', flex: 3),
              RmsColumn('الطلبات', flex: 2, align: TextAlign.right),
              RmsColumn('إجمالي الإنفاق', flex: 3, align: TextAlign.right),
              RmsColumn('آخر زيارة', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final c in MockData.customers)
                [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(color: AppColors.hover, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(c.name.substring(0, 1), style: AppText.caption),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(c.name, style: AppText.tableCellPrimary, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  Text(c.phone, style: AppText.tableCell),
                  Text('${c.orders}', style: AppText.tableCell),
                  Text(money(c.spend), style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
                  Text(c.lastVisit, style: AppText.caption),
                ],
            ],
          ),
        ),
        SurfaceCard(
          level: SurfaceLevel.secondary,
          child: Row(
            children: const [
              Icon(Icons.lock_outline, size: 16, color: AppColors.info),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'البيانات الشخصية المخزنة مقصورة على الأدوار المصرح بها ومشفرة أثناء التخزين. تسجيل الخروج يعزل بيانات المستخدم دون إتلاف المعاملات المعلقة.',
                  style: AppText.body,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
