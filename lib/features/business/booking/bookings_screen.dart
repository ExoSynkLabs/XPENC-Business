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

/// Shows [builder] once both books are loaded and bookings are on.
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

/// One booking as a list row.
class BookingTile extends StatelessWidget {
  const BookingTile({
    required this.bookings,
    required this.books,
    required this.booking,
    super.key,
  });
  final BookingBook bookings;
  final BizBook books;
  final BizBookingRow booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = booking;
    final money = bookings.moneyOf(b, books);
    final dates = dayOf(b.startDate) == dayOf(b.endDate)
        ? bizShortDate.format(b.startDate)
        : '${DateFormat('d MMM').format(b.startDate)} – ${bizShortDate.format(b.endDate)}';
    return ListTile(
      onTap: () => pushBooking(context, BookingDetailScreen(bookingId: b.id)),
      title: Row(
        children: [
          Expanded(
            child: Text(
              b.title ?? b.customerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(b.status),
        ],
      ),
      subtitle: Text(
        [
          '$dates · ${b.slot}',
          bookings.resourceNames(b),
          if (b.title != null) b.customerName,
        ].where((s) => s.isNotEmpty).join('\n'),
        maxLines: 3,
      ),
      isThreeLine: true,
      trailing: money.due.isPositive
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Due', style: theme.textTheme.labelSmall),
                MoneyText(money.due, compact: true, color: AppColors.expense),
              ],
            )
          : null,
    );
  }
}

/// The bookings home: a date strip, what's free and booked that day, and
/// the bookings themselves — worded for the business type.
class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

enum _View { day, upcoming, enquiries, all }

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  _View _view = _View.day;
  late final _strip = ScrollController(
    initialScrollOffset: stripOffsetFor(ref.read(bookingDayProvider)),
  );

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = ref.watch(bizBusinessTypeProvider);
    final day = ref.watch(bookingDayProvider);
    final slots = ref.watch(bookingSlotsProvider);
    return BookingGate(
      title: type.bookingPlural,
      builder: (context, bookings, books) {
        final theme = Theme.of(context);
        final today = dayOf(DateTime.now());
        final list = switch (_view) {
          _View.day => bookings.on(day, includeCancelled: true),
          _View.upcoming => bookings.upcoming(today),
          _View.enquiries => bookings.withStatus(BizBookingStatus.enquiry),
          _View.all => bookings.bookings.reversed.toList(),
        };
        return Scaffold(
          appBar: AppBar(
            title: Text(type.bookingPlural),
            actions: [
              IconButton(
                tooltip: 'Jump to date',
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(today.year + 5),
                  );
                  if (d != null) {
                    ref.read(bookingDayProvider.notifier).state = dayOf(d);
                    setState(() => _view = _View.day);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_strip.hasClients) {
                        _strip.jumpTo(stripOffsetFor(dayOf(d)));
                      }
                    });
                  }
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
                            _View.day => 'By date',
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
              if (_view == _View.day) ...[
                _DateStrip(bookings: bookings, controller: _strip),
                if (bookings.activeResources.isEmpty)
                  BizEmpty(
                    icon: type.icon,
                    text:
                        'Add your ${type.resourcePlural.toLowerCase()} first — '
                        'what customers can book.',
                    action: FilledButton.tonal(
                      onPressed: () =>
                          pushBooking(context, const BookingSetupScreen()),
                      child: Text(
                        'Set up ${type.resourcePlural.toLowerCase()}',
                      ),
                    ),
                  )
                else ...[
                  BizSectionLabel(
                    'Availability · ${DateFormat('EEE d MMM').format(day)}',
                  ),
                  _AvailabilityGrid(bookings: bookings, day: day, slots: slots),
                ],
              ],
              BizSectionLabel(
                _view == _View.day
                    ? '${type.bookingPlural} on this day'
                    : '${list.length} ${type.bookingPlural.toLowerCase()}',
              ),
              if (list.isEmpty)
                BizEmpty(icon: Icons.event_busy_outlined, text: 'Nothing here.')
              else
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0)
                          Divider(height: 1, color: theme.colorScheme.outline),
                        BookingTile(
                          bookings: bookings,
                          books: books,
                          booking: list[i],
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

const _cell = 56.0;

/// First day shown on the date strip: a fixed window around today, moved
/// only when a date picked from the calendar falls outside it.
DateTime stripStart(DateTime selected) {
  final today = dayOf(DateTime.now());
  final base = today.subtract(const Duration(days: 30));
  final offset = selected.difference(base).inDays;
  return (offset >= 0 && offset < 120)
      ? base
      : selected.subtract(const Duration(days: 14));
}

double stripOffsetFor(DateTime selected) {
  final i = selected.difference(stripStart(selected)).inDays;
  return (i * _cell - 120).clamp(0, double.infinity).toDouble();
}

/// 120 days, each with a dot when something is booked.
class _DateStrip extends ConsumerWidget {
  const _DateStrip({required this.bookings, required this.controller});
  final BookingBook bookings;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = ref.watch(bookingDayProvider);
    final today = dayOf(DateTime.now());
    final start = stripStart(selected);
    final days = [
      for (var i = 0; i < 120; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
    return SizedBox(
      height: 76,
      child: ListView.builder(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: days.length,
        itemExtent: _cell,
        itemBuilder: (context, i) {
          final d = days[i];
          final isSel = d == selected;
          final count = bookings.on(d).where((b) => b.status.blocks).length;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: isSel ? cs.secondary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => ref.read(bookingDayProvider.notifier).state = d,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('EEE').format(d),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isSel ? Colors.white : cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${d.day}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isSel
                            ? Colors.white
                            : (d == today ? cs.secondary : null),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: count == 0
                            ? Colors.transparent
                            : (isSel ? Colors.white : AppColors.expense),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Resource × slot: green = free (tap to book), red = booked (tap to open),
/// amber = partly sold (shared resources).
class _AvailabilityGrid extends ConsumerWidget {
  const _AvailabilityGrid({
    required this.bookings,
    required this.day,
    required this.slots,
  });
  final BookingBook bookings;
  final DateTime day;
  final List<String> slots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in bookings.activeResources) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (r.capacity > 0)
                    Text(
                      r.shared ? '${r.capacity} units' : 'Up to ${r.capacity}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final slot in slots) _slotChip(context, r, slot),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _slotChip(BuildContext context, BizBookingResourceRow r, String slot) {
    final a = bookings.availability(r, day, slot);
    final (bg, label) = switch (a.state) {
      SlotState.free => (AppColors.income, slot),
      SlotState.partial => (
        const Color(0xFFD97706),
        '$slot · ${a.capacity - a.used} left',
      ),
      SlotState.full => (
        AppColors.expense,
        '$slot · ${r.shared ? 'Full' : a.bookings.first.customerName}',
      ),
    };
    return Material(
      color: bg.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (a.state == SlotState.full && a.bookings.length == 1) {
            pushBooking(
              context,
              BookingDetailScreen(bookingId: a.bookings.first.id),
            );
          } else {
            pushBooking(
              context,
              BookingFormScreen(
                initialDate: day,
                initialSlot: slot,
                initialResourceId: r.id,
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                a.state == SlotState.free
                    ? Icons.add_circle_outline
                    : Icons.event_busy_rounded,
                size: 14,
                color: bg,
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bg,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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
