import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/models/kitchen_ticket.dart';
import '../common/format.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  String _station = 'الكل';
  List<KitchenTicketModel> _tickets = const [];


  @override
  void initState() {
    super.initState();
    _load();
    SyncMonitor.instance.addListener(_load);
  }

  @override
  void dispose() {
    SyncMonitor.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final kitchen = AppScope.of(context).kitchen;
    if (kitchen == null) return;
    final tickets = await kitchen.listTickets();
    if (!mounted) return;
    setState(() => _tickets = tickets);
  }

  Future<void> _transition(KitchenTicketModel ticket, TicketState next) async {
    final kitchen = AppScope.of(context).kitchen;
    if (kitchen == null) return;
    await kitchen.transitionTicket(ticket.id, next);
    await _load();
  }

  List<String> get _stations =>
      ['الكل', ...{for (final t in _tickets) t.station}];

  @override
  Widget build(BuildContext context) {
    final tickets = _station == 'الكل'
        ? _tickets
        : _tickets.where((t) => t.station == _station).toList();

    final columns = {
      TicketState.queued: tickets.where((t) => t.state == TicketState.queued).toList(),
      TicketState.preparing: tickets.where((t) => t.state == TicketState.preparing).toList(),
      TicketState.ready: tickets.where((t) => t.state == TicketState.ready).toList(),
    };

    return PageBody(
      scrollable: false,
      children: [
        Row(
          children: [
            const SectionHeader(
              title: 'شاشة المطبخ',
              subtitle: 'التذاكر تنجو من إعادة التشغيل · الطباعة مستقلة عن المزامنة',
            ),
            const Spacer(),
            SizedBox(height: 30, child: _StationFilter(stations: _stations, selected: _station, onSelect: (s) => setState(() => _station = s))),
            const SizedBox(width: 12),
            RmsButton(label: 'استدعاء السابقة', icon: Icons.replay, onPressed: _load),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final state in [TicketState.queued, TicketState.preparing, TicketState.ready])
                  Expanded(
                    child: _KdsColumn(
                      state: state,
                      tickets: columns[state]!,
                      onTransition: _transition,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StationFilter extends StatelessWidget {
  const _StationFilter({required this.stations, required this.selected, required this.onSelect});

  final List<String> stations;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final s in stations)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onSelect(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: s == selected ? AppColors.brandSoft : Colors.transparent,
                  border: Border.all(color: s == selected ? AppColors.brandLine : AppColors.borderStrong),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Center(
                  child: Text(s,
                      style: AppText.caption.copyWith(
                        fontSize: 11,
                        color: s == selected ? AppColors.brand : AppColors.fgMuted,
                      )),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _KdsColumn extends StatelessWidget {
  const _KdsColumn({required this.state, required this.tickets, required this.onTransition});

  final void Function(KitchenTicketModel ticket, TicketState next) onTransition;

  final TicketState state;
  final List<KitchenTicketModel> tickets;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = ticketStateView(state);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                StatusDot(tone: tone),
                const SizedBox(width: 8),
                Text(label, style: AppText.sectionHeading),
                const Spacer(),
                Text('${tickets.length}', style: AppText.caption),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken.withValues(alpha: 0.5),
                border: Border.all(color: AppColors.borderFaint),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              padding: const EdgeInsets.all(8),
              child: ListView(
                children: [
                  for (final t in tickets) _TicketCard(ticket: t, onTransition: onTransition),
                  if (tickets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text('فارغ', style: AppText.caption),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTransition});

  final void Function(KitchenTicketModel ticket, TicketState next) onTransition;

  final KitchenTicketModel ticket;

  Color get _ageColor {
    if (ticket.ageMinutes >= 12) return AppColors.negative;
    if (ticket.ageMinutes >= 8) return AppColors.warning;
    return AppColors.fgMuted;
  }

  @override
  Widget build(BuildContext context) {
    final (stateLabel, _) = ticketStateView(ticket.state);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        level: SurfaceLevel.content,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(ticket.id, style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Tag(label: ticket.station, tone: StatusTone.neutral),
                const Spacer(),
                if (ticket.provisional)
                  const Tag(label: 'محلي', tone: StatusTone.warning),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(ticket.orderRef, style: AppText.caption),
                const Spacer(),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 11, color: _ageColor),
                    const SizedBox(width: 3),
                    Text('${ticket.ageMinutes} د', style: AppText.caption.copyWith(color: _ageColor)),
                  ],
                ),
              ],
            ),
            const Divider(height: 16, color: AppColors.borderSubtle),
            for (final item in ticket.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('•  $item', style: AppText.tableCell.copyWith(color: AppColors.fgSecondary)),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(stateLabel, style: AppText.caption),
                ),
                if (ticket.state != TicketState.ready)
                  RmsButton(
                    label: ticket.state == TicketState.queued ? 'بدء' : 'تحديد كجاهز',
                    icon: Icons.play_arrow_rounded,
                    variant: BtnVariant.secondary,
                    onPressed: () {
                      final next = ticket.state == TicketState.queued
                          ? TicketState.preparing
                          : TicketState.ready;
                      onTransition(ticket, next);
                      if (ticket.state == TicketState.queued) {
                        final print = AppScope.of(context).print;
                        if (print != null) {
                          unawaited(print.printKitchenTicket(ticket.copyWith(state: next)));
                        }
                      }
                    },
                  )
                else
                  Row(
                    children: [
                      RmsButton(
                        label: 'إعادة طباعة',
                        icon: Icons.print_rounded,
                        variant: BtnVariant.ghost,
                        onPressed: () {
                          final print = AppScope.of(context).print;
                          if (print != null) {
                            print.printKitchenTicket(ticket);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      RmsButton(
                        label: 'تم التقديم',
                        icon: Icons.check_rounded,
                        variant: BtnVariant.primary,
                        onPressed: () {},
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
