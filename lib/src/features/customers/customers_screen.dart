import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/mock/mock_data.dart';
import '../common/format.dart';

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        Row(
          children: [
            const SectionHeader(
              title: 'Customers',
              subtitle: 'Cached read with local creation · syncs when reconnected',
            ),
            const Spacer(),
            RmsButton(label: 'Add customer', icon: Icons.person_add_alt, onPressed: () {}),
          ],
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: RmsTable(
            columns: const [
              RmsColumn('Name', flex: 3),
              RmsColumn('Phone', flex: 3),
              RmsColumn('Orders', flex: 2, align: TextAlign.right),
              RmsColumn('Lifetime spend', flex: 3, align: TextAlign.right),
              RmsColumn('Last visit', flex: 2, align: TextAlign.right),
              RmsColumn('', flex: 2),
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
                        child: Text(c.name.substring(0, 1), style: AppText.caption.copyWith(fontSize: 10)),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(c.name, style: AppText.tableCellPrimary, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  Text(c.phone, style: AppText.tableCell),
                  Text('${c.orders}', style: AppText.tableCell),
                  Text(money(c.spend), style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
                  Text(c.lastVisit, style: AppText.caption),
                  const RmsButton(label: 'View', onPressed: null),
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
                  'Cached personal data is restricted to authorized roles and encrypted at rest. Logging out isolates user-specific caches without destroying pending transactions.',
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
