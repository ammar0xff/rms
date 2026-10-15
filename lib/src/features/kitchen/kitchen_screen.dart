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
import '../../domain/models/kitchen_ticket.dart';
import '../common/format.dart';

/// The chef's dark KDS: tickets age in the open, colors carry the state.
///
/// Kitchens run hot and glary, so the lanes live on dark glass while the
/// header (title, station chips, recall) stays on the shared light chrome —
/// dialogs, inputs, and toasts never fork. Lane order and ticket flow are
/// the industry standard: مستني → بيتجهز → جاهز, with a red edge the moment
/// a ticket runs late. All data logic is unchanged.
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  String _station = 'الكل';
  List<KitchenTicketModel> _tickets = const [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    SyncMonitor.instance.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an inherited widget, so the first read has to happen here
    // rather than in initState.
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  @override
  void dispose() {
    SyncMonitor.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final kitchen = AppScope.of(context).kitchen;
    if (kitchen == null) return;
    final tickets = await kitchen.listTickets();
    if (!mounted) return;
    setState(() {
      _tickets = tickets;
      // The selected station ages out when its last open ticket completes: the
      // chip vanishes while the filter still points at it, leaving every lane
      // empty with no way back. Fall home to الكل.
      if (_station != 'الكل' &&
          tickets.every((t) =>
              t.state == TicketState.completed || t.station != _station)) {
        _station = 'الكل';
      }
    });
  }

  Future<void> _transition(KitchenTicketModel ticket, TicketState next) async {
    final kitchen = AppScope.of(context).kitchen;
    if (kitchen == null) return;
    try {
      await kitchen.transitionTicket(ticket.id, next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حركة غير صالحة لهذه التذكرة')),
      );
      return;
    }
    await _load();
  }

  List<String> get _stations => [
        'الكل',
        ...{
          for (final t in _tickets)
            if (t.state != TicketState.completed) t.station
        },
      ];

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
        // The filter scrolls inside a bounded lane; the recall button keeps
        // its own space so a long station list cannot push it off-screen.
        LayoutBuilder(
          builder: (context, c) {
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: SizedBox(
                    height: 44,
                    child: _StationFilter(stations: _stations, selected: _station, onSelect: (s) => setState(() => _station = s)),
                  ),
                ),
                const SizedBox(width: 8),
                RmsButton(label: 'استرجع اللي فات', icon: Icons.replay, onPressed: _load),
              ],
            );
            if (c.maxWidth >= 600) {
              return Row(
                children: [
                  const Expanded(
                    child: SectionHeader(
                      title: 'شاشة المطبخ',
                      subtitle: 'التذاكر تنجو من إعادة التشغيل · الطباعة مستقلة عن المزامنة',
                    ),
                  ),
                  actions,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: 'شاشة المطبخ',
                  subtitle: 'التذاكر تنجو من إعادة التشغيل · الطباعة مستقلة عن المزامنة',
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: actions,
                ),
              ],
            );
          },
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.kdsBase,
                border: Border.all(color: AppColors.kdsBorder),
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusLg),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DayStrip(tickets: _tickets),
                  const SizedBox(height: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final lanes = Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final state in [TicketState.queued, TicketState.preparing, TicketState.ready])
                              SizedBox(
                                // A lane narrower than this cannot show a ticket card;
                                // scroll sideways rather than crush all three.
                                width: c.maxWidth < 700 ? 280 : (c.maxWidth - 24) / 3,
                                child: _KdsColumn(
                                  state: state,
                                  tickets: columns[state]!,
                                  onTransition: _transition,
                                ),
                              ),
                          ],
                        );
                        if (c.maxWidth >= 700) return lanes;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: lanes,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The chef's day at a glance: open tickets by lane, on dark glass.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.tickets});

  final List<KitchenTicketModel> tickets;

  @override
  Widget build(BuildContext context) {
    var queued = 0;
    var preparing = 0;
    var ready = 0;
    for (final ticket in tickets) {
      switch (ticket.state) {
        case TicketState.queued:
          queued++;
        case TicketState.preparing:
          preparing++;
        case TicketState.ready:
          ready++;
        case TicketState.completed:
          break;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.kdsSurface,
        border: Border.all(color: AppColors.kdsBorder),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          _DayCount(label: 'مستني', count: queued),
          _DayDivider(),
          _DayCount(label: 'بيتجهز', count: preparing),
          _DayDivider(),
          _DayCount(label: 'جاهز', count: ready),
        ],
      ),
    );
  }
}

class _DayCount extends StatelessWidget {
  const _DayCount({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption
                    .copyWith(color: AppColors.kdsMuted)),
          ),
          const SizedBox(width: 6),
          Text('$count',
              style: AppText.bodyStrong.copyWith(
                  color: count > 0 ? AppColors.chefAccent : AppColors.kdsMuted)),
        ],
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 16,
        color: AppColors.kdsBorder,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: s == selected ? AppColors.brandSoft : Colors.transparent,
                  border: Border.all(color: s == selected ? AppColors.brandLine : AppColors.borderStrong),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Center(
                  child: Text(s,
                      style: AppText.caption.copyWith(
                        fontSize: 13,
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
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.sectionHeading
                          .copyWith(color: AppColors.kdsSecondary)),
                ),
                Text('${tickets.length}',
                    style: AppText.caption
                        .copyWith(color: AppColors.kdsMuted)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.kdsSurface.withValues(alpha: 0.6),
                border: Border.all(color: AppColors.kdsBorder),
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
                        child: Text('فاضي',
                            style: AppText.caption.copyWith(
                                color: AppColors.kdsMuted)),
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

  bool get _late => ticket.ageMinutes >= 12;

  Color get _ageColor {
    if (ticket.ageMinutes >= 12) return AppColors.negative;
    if (ticket.ageMinutes >= 8) return AppColors.warning;
    return AppColors.kdsMuted;
  }

  /// The lane edge: gray while waiting, amber while cooking, green when
  /// ready — red the moment it runs late, whatever the lane.
  Color get _edge {
    if (_late) return AppColors.negative;
    return switch (ticket.state) {
      TicketState.queued => AppColors.kdsMuted,
      TicketState.preparing => AppColors.warning,
      TicketState.ready => AppColors.positive,
      TicketState.completed => AppColors.kdsMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final (stateLabel, _) = ticketStateView(ticket.state);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.kdsRaised,
          border: Border.all(
            color: _late ? AppColors.negative : AppColors.kdsBorder,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: _edge,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(AppSpacing.radiusMd),
                  bottomRight: Radius.circular(AppSpacing.radiusMd),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(ticket.id,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.tableCellPrimary.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.kdsFg)),
                        ),
                        const SizedBox(width: 8),
                        Tag(label: ticket.station, tone: StatusTone.neutral),
                        if (ticket.provisional) ...[
                          const SizedBox(width: 6),
                          const Tag(label: 'على الجهاز', tone: StatusTone.warning),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(ticket.orderRef,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(
                                  color: AppColors.kdsMuted)),
                        ),
                        const SizedBox(width: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule, size: 11, color: _ageColor),
                            const SizedBox(width: 3),
                            Text('${ticket.ageMinutes} د',
                                style: AppText.caption
                                    .copyWith(color: _ageColor)),
                          ],
                        ),
                      ],
                    ),
                    Divider(height: 16, color: AppColors.kdsBorder),
                    for (final item in ticket.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('•  $item',
                            style: AppText.tableCell.copyWith(
                                color: AppColors.kdsSecondary)),
                      ),
                    const SizedBox(height: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(stateLabel,
                            style: AppText.caption.copyWith(
                                color: AppColors.kdsMuted)),
                        const SizedBox(height: 8),
                        if (ticket.state != TicketState.ready)
                          RmsButton(
                            label: ticket.state == TicketState.queued ? 'ابدأ' : 'علّم كجاهز',
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
                        else ...[
                          RmsButton(
                            label: 'اطبع تاني',
                            icon: Icons.print_rounded,
                            variant: BtnVariant.ghost,
                            onPressed: () {
                              final print = AppScope.of(context).print;
                              if (print != null) {
                                print.printKitchenTicket(ticket);
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          RmsButton(
                            label: 'اتقدّم',
                            icon: Icons.check_rounded,
                            variant: BtnVariant.primary,
                            onPressed: () =>
                                onTransition(ticket, TicketState.completed),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
