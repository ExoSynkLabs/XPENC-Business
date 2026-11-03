import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/money_text.dart';
import '../../../data/business_tables.dart';
import '../../../data/database.dart';
import '../biz_book.dart';
import '../biz_providers.dart';
import '../biz_widgets.dart';
import 'booking_book.dart';
import 'booking_detail_screen.dart';
import 'booking_form_screen.dart';
import 'booking_providers.dart';
import 'booking_setup_screen.dart';
import 'business_types.dart';

void pushBooking(BuildContext context, Widget screen) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(builder: (_) => screen));

Color statusColor(BizBookingStatus s, ColorScheme cs) => switch (s) {
  BizBookingStatus.enquiry => cs.onSurfaceVariant,
  BizBookingStatus.tentative => const Color(0xFFD97706),
  BizBookingStatus.confirmed => AppColors.income,
  BizBookingStatus.completed => AppColors.transfer,
  BizBookingStatus.cancelled => AppColors.expense,
};

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final BizBookingStatus status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ── Occupancy heat scale ────────────────────────────────────────────────────
//
// One quantity (how full a day is), so one hue, light → dark (sequential),
// in four buckets. Steps come from the validated blue ramp; dark mode uses
// its own steps that brighten with load against the dark surface. Each
// step's day-number ink was chosen by measured contrast (≥ 4.4:1).

const _heatLight = [
  Color(0xFFCDE2FB),
  Color(0xFF86B6EF),
  Color(0xFF3987E5),
  Color(0xFF1C5CAB),
];
const _heatLightInk = [
  Color(0xFF0A0A0B),
  Color(0xFF0A0A0B),
  Color(0xFF0A0A0B),
  Colors.white,
];
const _heatDark = [
  Color(0xFF104281),
  Color(0xFF1C5CAB),
  Color(0xFF2A78D6),
  Color(0xFF5598E7),
];
const _heatDarkInk = [
  Colors.white,
  Colors.white,
  Colors.white,
  Color(0xFF0A0A0B),
];

int? _heatStep(double occupancy) {
  if (occupancy <= 0) return null;
  if (occupancy <= 0.25) return 0;
  if (occupancy <= 0.5) return 1;
  if (occupancy <= 0.75) return 2;
  return 3;
}

({Color fill, Color ink})? heatColors(double occupancy, Brightness b) {
  final step = _heatStep(occupancy);
  if (step == null) return null;
  final dark = b == Brightness.dark;
  return (
    fill: (dark ? _heatDark : _heatLight)[step],
    ink: (dark ? _heatDarkInk : _heatLightInk)[step],
  );
}

/// Shows [builder] once both books are loaded.
class BookingGate extends ConsumerWidget {
  const BookingGate({required this.title, required this.builder, super.key});
  final String title;
  final Widget Function(
    BuildContext context,
    BookingBook bookings,
    BizBook books,
  )
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(bookingBookProvider);
    final books = ref.watch(bizBookProvider);
    final b = bookings.valueOrNull;
    final k = books.valueOrNull;
    if (b == null || k == null) {
      final err = bookings.error ?? books.error;
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: err != null
              ? Text('Couldn’t load: $err')
              : (bookings.isLoading || books.isLoading)
              ? const CircularProgressIndicator()
              : const BizEmpty(
                  icon: Icons.business_outlined,
                  text: 'Create a company first.',
                ),
        ),
      );
    }
    return builder(context, b, k);
  }
}

/// One booking as a card row: a status stripe, what & when, who, and the
/// balance still due.
class BookingTile extends StatelessWidget {
  const BookingTile({
    required this.bookings,
    required this.books,
    required this.booking,
    super.key,
    this.showDate = true,
    this.showSlot = true,
  });
  final BookingBook bookings;
  final BizBook books;
  final BizBookingRow booking;
  final bool showDate;

  /// Off inside the day agenda, where the session is already the heading.
  final bool showSlot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = booking;
    final money = bookings.moneyOf(b, books);
    final stripe = statusColor(b.status, cs);
    final dates = dayOf(b.startDate) == dayOf(b.endDate)
        ? DateFormat('EEE d MMM').format(b.startDate)
        : '${DateFormat('d MMM').format(b.startDate)} – ${DateFormat('d MMM').format(b.endDate)}';
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final cancelled = b.status == BizBookingStatus.cancelled;

    Widget meta(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    return InkWell(
      onTap: () => pushBooking(context, BookingDetailScreen(bookingId: b.id)),
      child: Opacity(
        opacity: cancelled ? 0.55 : 1,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: stripe,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              b.title ?? b.customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                decoration: cancelled
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusPill(b.status),
                        ],
                      ),
                      if (showDate || showSlot)
                        meta(
                          Icons.schedule_rounded,
                          showDate ? '$dates · ${b.slot}' : b.slot,
                        ),
                      meta(Icons.place_outlined, bookings.resourceNames(b)),
                      if (b.title != null || b.guests > 0)
                        meta(
                          Icons.person_outline_rounded,
                          [
                            if (b.title != null) b.customerName,
                            if (b.guests > 0) '${b.guests} people',
                          ].join(' · '),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 14, 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (money.due.isPositive) ...[
                      Text(
                        'Due',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      MoneyText(
                        money.due,
                        compact: true,
                        color: AppColors.expense,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else if (money.total.isPositive) ...[
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: AppColors.income,
                      ),
                      Text(
                        'Paid',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _View { calendar, upcoming, enquiries, all }

/// The bookings home: a month you can read at a glance (how full each day
/// is), the month's numbers, and the chosen day laid out session by session
/// — booked cards and free resources side by side.
class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  _View _view = _View.calendar;

  void _select(DateTime d) {
    ref.read(bookingDayProvider.notifier).state = dayOf(d);
    setState(() => _view = _View.calendar);
  }

  @override
  Widget build(BuildContext context) {
    final type = ref.watch(bizBusinessTypeProvider);
    final day = ref.watch(bookingDayProvider);
    final slots = ref.watch(bookingSlotsProvider);
    return BookingGate(
      title: type.bookingPlural,
      builder: (context, bookings, books) {
        final today = dayOf(DateTime.now());
        return Scaffold(
          appBar: AppBar(
            title: Text(type.bookingPlural),
            actions: [
              if (day != today || _view != _View.calendar)
                TextButton(
                  onPressed: () => _select(today),
                  child: const Text('Today'),
                ),
              IconButton(
                tooltip: 'Jump to date',
                icon: const Icon(Icons.edit_calendar_outlined),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(today.year + 5),
                  );
                  if (d != null) _select(d);
                },
              ),
              IconButton(
                tooltip: 'Booking setup',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () =>
                    pushBooking(context, const BookingSetupScreen()),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () =>
                pushBooking(context, BookingFormScreen(initialDate: day)),
            icon: const Icon(Icons.add_rounded),
            label: Text('New ${type.bookingNoun.toLowerCase()}'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 104),
            children: [
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  children: [
                    for (final v in _View.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(switch (v) {
                            _View.calendar => 'Calendar',
                            _View.upcoming => 'Upcoming',
                            _View.enquiries => 'Enquiries',
                            _View.all => 'All',
                          }),
                          selected: _view == v,
                          onSelected: (_) => setState(() => _view = v),
                        ),
                      ),
                  ],
                ),
              ),
              if (_view == _View.calendar) ...[
                _MonthCalendar(
                  bookings: bookings,
                  books: books,
                  slots: slots,
                  selected: day,
                  onSelect: _select,
                ),
                if (bookings.activeResources.isEmpty)
                  BizEmpty(
                    icon: type.icon,
                    text:
                        'Add your ${type.resourcePlural.toLowerCase()} first — what customers can book.',
                    action: FilledButton.tonal(
                      onPressed: () =>
                          pushBooking(context, const BookingSetupScreen()),
                      child: Text(
                        'Set up ${type.resourcePlural.toLowerCase()}',
                      ),
                    ),
                  )
                else
                  _DayAgenda(
                    bookings: bookings,
                    books: books,
                    day: day,
                    slots: slots,
                    type: type,
                  ),
              ] else
                ..._groupedList(context, bookings, books, switch (_view) {
                  _View.upcoming => bookings.upcoming(today),
                  _View.enquiries =>
                    bookings
                        .withStatus(BizBookingStatus.enquiry)
                        .reversed
                        .toList(),
                  _ => bookings.bookings.reversed.toList(),
                }),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _groupedList(
    BuildContext context,
    BookingBook bookings,
    BizBook books,
    List<BizBookingRow> list,
  ) {
    if (list.isEmpty) {
      return const [
        BizEmpty(icon: Icons.event_busy_outlined, text: 'Nothing here.'),
      ];
    }
    final theme = Theme.of(context);
    final groups = <DateTime, List<BizBookingRow>>{};
    for (final b in list) {
      (groups[dayOf(b.startDate)] ??= []).add(b);
    }
    return [
      for (final e in groups.entries) ...[
        BizSectionLabel(DateFormat('EEEE, d MMMM yyyy').format(e.key)),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < e.value.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 16,
                    color: theme.colorScheme.outline,
                  ),
                BookingTile(
                  bookings: bookings,
                  books: books,
                  booking: e.value[i],
                  showDate: false,
                ),
              ],
            ],
          ),
        ),
      ],
    ];
  }
}

// ── Month calendar ──────────────────────────────────────────────────────────

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.bookings,
    required this.books,
    required this.slots,
    required this.selected,
    required this.onSelect,
  });

  final BookingBook bookings;
  final BizBook books;
  final List<String> slots;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  void _shiftMonth(int delta) {
    final m = DateTime(selected.year, selected.month + delta);
    final lastDay = DateTime(m.year, m.month + 1, 0).day;
    onSelect(DateTime(m.year, m.month, selected.day.clamp(1, lastDay)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final month = DateTime(selected.year, selected.month);
    final summary = bookings.monthSummary(month, slots, books);
    final firstDow = MaterialLocalizations.of(
      context,
    ).firstDayOfWeekIndex; // 0 = Sunday
    final lead = (month.weekday % 7 - firstDow + 7) % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((lead + daysInMonth) / 7).ceil() * 7;
    final today = dayOf(DateTime.now());
    final weekdays = [
      for (var i = 0; i < 7; i++)
        DateFormat('EEEEE').format(
          DateTime(2024, 1, 7 + (firstDow + i) % 7),
        ), // 7 Jan 2024 = Sunday
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(month),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            // KPI row — the month in four numbers.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _Kpi(label: 'Booked', value: Text('${summary.bookings}')),
                  _Kpi(
                    label: 'Occupancy',
                    value: Text('${(summary.occupancy * 100).round()}%'),
                  ),
                  _Kpi(
                    label: 'Value',
                    value: MoneyText(summary.booked, compact: true),
                  ),
                  _Kpi(
                    label: 'Due',
                    value: MoneyText(
                      summary.due,
                      compact: true,
                      color: summary.due.isPositive ? AppColors.expense : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final w in weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() < 200) return;
                _shiftMonth(v < 0 ? 1 : -1);
              },
              child: Column(
                children: [
                  for (var row = 0; row < cells ~/ 7; row++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          for (var col = 0; col < 7; col++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: () {
                                  final n = row * 7 + col - lead + 1;
                                  if (n < 1 || n > daysInMonth) {
                                    return const SizedBox(height: 46);
                                  }
                                  final d = DateTime(
                                    month.year,
                                    month.month,
                                    n,
                                  );
                                  return _DayCell(
                                    day: d,
                                    occupancy: bookings.occupancy(d, slots),
                                    count: bookings
                                        .on(d)
                                        .where((b) => b.status.blocks)
                                        .length,
                                    enquiry: bookings
                                        .on(d)
                                        .any(
                                          (b) =>
                                              b.status ==
                                              BizBookingStatus.enquiry,
                                        ),
                                    isToday: d == today,
                                    isSelected: d == selected,
                                    onTap: () => onSelect(d),
                                  );
                                }(),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _Legend(brightness: theme.brightness),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          DefaultTextStyle.merge(
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: value,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.occupancy,
    required this.count,
    required this.enquiry,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final double occupancy;
  final int count;
  final bool enquiry;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final heat = heatColors(occupancy, theme.brightness);
    final ink = heat?.ink ?? cs.onSurface;
    final pct = (occupancy * 100).round();
    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${DateFormat('d MMMM').format(day)}, $count booked, $pct percent full'
          '${enquiry ? ', has enquiries' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: heat?.fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? cs.onSurface
                  : (isToday ? cs.secondary : Colors.transparent),
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  '${day.day}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: ink,
                    fontWeight: isToday || isSelected
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ),
              if (count > 0)
                Positioned(
                  right: 4,
                  top: 3,
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
              if (enquiry)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 4,
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: ink, width: 1.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.brightness});
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final steps = brightness == Brightness.dark ? _heatDark : _heatLight;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Text('Free', style: style),
        for (final c in steps)
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        Text('Full', style: style),
        const SizedBox(width: 8),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.onSurfaceVariant, width: 1.5),
          ),
        ),
        Text('Enquiry', style: style),
        const SizedBox(width: 8),
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: cs.secondary, width: 2),
          ),
        ),
        Text('Today', style: style),
      ],
    );
  }
}

// ── Day agenda ──────────────────────────────────────────────────────────────

/// The chosen day, session by session: what's booked (cards) and what's
/// still free (tap a dashed chip to book it, prefilled).
class _DayAgenda extends StatelessWidget {
  const _DayAgenda({
    required this.bookings,
    required this.books,
    required this.day,
    required this.slots,
    required this.type,
  });

  final BookingBook bookings;
  final BizBook books;
  final DateTime day;
  final List<String> slots;
  final BizBusinessType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onDay = bookings.on(day, includeCancelled: true);
    final occupancy = bookings.occupancy(day, slots);
    final blocking = onDay.where((b) => b.status.blocks).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, d MMMM').format(day),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      blocking == 0
                          ? 'Everything is free'
                          : '$blocking ${blocking == 1 ? type.bookingNoun.toLowerCase() : type.bookingPlural.toLowerCase()}'
                                ' · ${(occupancy * 100).round()}% booked',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () =>
                    pushBooking(context, BookingFormScreen(initialDate: day)),
                // The theme makes filled buttons full-width; this one sits in a row.
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Book'),
              ),
            ],
          ),
        ),
        for (final slot in slots) _slotSection(context, slot, onDay),
        // Bookings in a slot the business no longer offers still show.
        ...() {
          final orphans = onDay.where((b) => !slots.contains(b.slot)).toList();
          if (orphans.isEmpty) return const <Widget>[];
          return [_slotCard(context, 'Other', orphans, const [])];
        }(),
      ],
    );
  }

  Widget _slotSection(
    BuildContext context,
    String slot,
    List<BizBookingRow> onDay,
  ) {
    final inSlot = onDay.where((b) => b.slot == slot).toList();
    final free = <({BizBookingResourceRow r, SlotAvailability a})>[
      for (final r in bookings.activeResources)
        (r: r, a: bookings.availability(r, day, slot)),
    ].where((x) => x.a.state != SlotState.full).toList();
    return _slotCard(context, slot, inSlot, free);
  }

  Widget _slotCard(
    BuildContext context,
    String slot,
    List<BizBookingRow> inSlot,
    List<({BizBookingResourceRow r, SlotAvailability a})> free,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(
                children: [
                  Icon(
                    slot == kFullDay
                        ? Icons.wb_sunny_outlined
                        : Icons.schedule_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    slot,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    free.isEmpty ? 'Fully booked' : '${free.length} free',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: free.isEmpty
                          ? AppColors.expense
                          : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            for (final b in inSlot) ...[
              Divider(height: 1, color: cs.outline),
              BookingTile(
                bookings: bookings,
                books: books,
                booking: b,
                showDate: false,
                showSlot: false,
              ),
            ],
            if (free.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in free)
                      _FreeChip(
                        label: f.r.shared && f.a.used > 0
                            ? '${f.r.name} · ${f.a.capacity - f.a.used} left'
                            : f.r.name,
                        onTap: () => pushBooking(
                          context,
                          BookingFormScreen(
                            initialDate: day,
                            initialSlot: slot,
                            initialResourceId: f.r.id,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A free resource: dashed outline, "+", tap to book it.
class _FreeChip extends StatelessWidget {
  const _FreeChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: CustomPaint(
        painter: _DashedBorder(
          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: cs.secondary),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
