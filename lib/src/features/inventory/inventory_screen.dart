import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/mock/mock_data.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final low = MockData.inventory.where((i) => i.low).length;
    return PageBody(
      children: [
        GridRow(children: [
          const StatCard(label: 'Tracked items', value: '6'),
          StatCard(
            label: 'Below reorder',
            value: '$low',
            delta: 'action needed',
            deltaTone: low > 0 ? DeltaTone.negative : DeltaTone.positive,
          ),
          const StatCard(label: 'Offline movements', value: '5', delta: 'queued', deltaTone: DeltaTone.neutral),
          const StatCard(label: 'Stock conflicts', value: '1', delta: 'review', deltaTone: DeltaTone.negative),
        ]),
        const Row(
          children: [
            SectionHeader(
              title: 'Stock levels',
              subtitle: 'Movements are append-only and resolved explicitly on sync',
            ),
            Spacer(),
            RmsButton(label: 'Receive stock', icon: Icons.add, onPressed: null),
          ],
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: RmsTable(
            columns: const [
              RmsColumn('Item', flex: 4),
              RmsColumn('On hand', flex: 2),
              RmsColumn('Reorder at', flex: 2),
              RmsColumn('Status', flex: 3),
              RmsColumn('', flex: 2),
            ],
            rows: [
              for (final i in MockData.inventory)
                [
                  Text(i.item, style: AppText.tableCellPrimary),
                  Text('${i.onHand} ${i.unit}',
                      style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
                  Text('${i.reorderAt} ${i.unit}', style: AppText.tableCell),
                  StatusText(
                    label: i.low ? 'Below reorder' : 'Healthy',
                    tone: i.low ? StatusTone.warning : StatusTone.positive,
                  ),
                  const RmsButton(label: 'Move', onPressed: null),
                ],
            ],
          ),
        ),
        const SurfaceCard(
          level: SurfaceLevel.secondary,
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Concurrent stock movements from disconnected devices are flagged as conflicts and require explicit resolution — never silent last-write-wins.',
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
