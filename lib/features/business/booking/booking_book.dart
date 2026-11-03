import 'dart:convert';

import '../../../core/money.dart';
import '../../../data/business_tables.dart';
import '../../../data/database.dart';
import '../biz_book.dart';
import 'business_types.dart';

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Two slots clash when they are the same, or either takes the full day.
bool slotsClash(String a, String b) => a == b || a == kFullDay || b == kFullDay;

/// Inclusive whole-day ranges overlap.
bool datesOverlap(DateTime aFrom, DateTime aTo, DateTime bFrom, DateTime bTo) =>
    !dayOf(aTo).isBefore(dayOf(bFrom)) && !dayOf(bTo).isBefore(dayOf(aFrom));

/// How many times a resource's rate applies over a booking's dates.
int rateMultiplier(RateBasis basis, DateTime start, DateTime end) {
  final days = dayOf(end).difference(dayOf(start)).inDays;
  return switch (basis) {
    RateBasis.perDay => days + 1,
    RateBasis.perNight => days < 1 ? 1 : days,
    RateBasis.perUnit || RateBasis.perBooking => 1,
  };
}

/// A resource line on a booking before it is saved.
class BookingLineDraft {
  const BookingLineDraft({
    required this.resourceId,
    this.qty = 1,
    this.rate = const Money.zero(),
  });
  final int resourceId;
  final int qty;
  final Money rate;

  Money amount(int multiplier) => rate * (qty * multiplier);
}

enum SlotState { free, partial, full }

/// Whether a resource is free in one slot on one day.
typedef SlotAvailability = ({
  SlotState state,
  int used,
  int capacity,
  List<BizBookingRow> bookings,
});

/// Money received against a booking, and whether it has been billed.
typedef BookingMoney = ({Money total, Money paid, Money due, bool billed});

/// A read-only snapshot of a company's bookings, with availability and
/// conflict checks in plain Dart.
class BookingBook {
  BookingBook({
    required List<BizBookingResourceRow> resources,
    required List<BizBookingRow> bookings,
    required List<BizBookingLineRow> lines,
  }) : resources = [...resources]
         ..sort((a, b) {
           final s = a.sort.compareTo(b.sort);
           return s != 0 ? s : a.id.compareTo(b.id);
         }),
       bookings = [...bookings]
         ..sort((a, b) {
           final d = a.startDate.compareTo(b.startDate);
           return d != 0 ? d : a.id.compareTo(b.id);
         }) {
    for (final r in this.resources) {
      resourceById[r.id] = r;
    }
    for (final b in this.bookings) {
      bookingById[b.id] = b;
    }
    for (final l in lines) {
      (linesByBooking[l.bookingId] ??= []).add(l);
    }
  }

  final List<BizBookingResourceRow> resources;
  final List<BizBookingRow> bookings;
  final Map<int, BizBookingResourceRow> resourceById = {};
  final Map<int, BizBookingRow> bookingById = {};
  final Map<int, List<BizBookingLineRow>> linesByBooking = {};

  List<BizBookingResourceRow> get activeResources =>
      resources.where((r) => !r.isArchived).toList();

  List<BizBookingLineRow> linesOf(int bookingId) =>
      linesByBooking[bookingId] ?? const [];

  String numberLabel(BizBookingRow b) => 'BK/${b.number}';

  /// Resource names on a booking, e.g. "Main Hall, Lawn".
  String resourceNames(BizBookingRow b) => linesOf(b.id)
      .map((l) {
        final r = resourceById[l.resourceId];
        if (r == null) return '?';
        return r.shared ? '${r.name} ×${l.qty}' : r.name;
      })
      .join(', ');

  Map<String, Object?> extraOf(BizBookingRow b) {
    try {
      final v = jsonDecode(b.extra);
      return v is Map ? v.cast<String, Object?>() : const {};
    } on FormatException {
      return const {};
    }
  }

  bool covers(BizBookingRow b, DateTime day) =>
      datesOverlap(b.startDate, b.endDate, day, day);

  /// Bookings (any status but cancelled) on [day], earliest slot first.
  List<BizBookingRow> on(DateTime day, {bool includeCancelled = false}) => [
    for (final b in bookings)
      if (covers(b, day) &&
          (includeCancelled || b.status != BizBookingStatus.cancelled))
        b,
  ];

  /// Blocking bookings from [from] onwards, soonest first.
  List<BizBookingRow> upcoming(DateTime from) => [
    for (final b in bookings)
      if (!dayOf(b.endDate).isBefore(dayOf(from)) &&
          b.status.blocks &&
          b.status != BizBookingStatus.completed)
        b,
  ];

  List<BizBookingRow> withStatus(BizBookingStatus status) =>
      bookings.where((b) => b.status == status).toList().reversed.toList();

  /// How [resource] stands in [slot] on [day], ignoring [excludeBookingId]
  /// (the booking being edited).
  SlotAvailability availability(
    BizBookingResourceRow resource,
    DateTime day,
    String slot, {
    int? excludeBookingId,
  }) {
    var used = 0;
    final holders = <BizBookingRow>[];
    for (final b in bookings) {
      if (b.id == excludeBookingId || !b.status.blocks) continue;
      if (!covers(b, day) || !slotsClash(b.slot, slot)) continue;
      for (final l in linesOf(b.id)) {
        if (l.resourceId != resource.id) continue;
        used += resource.shared ? l.qty : 1;
        holders.add(b);
      }
    }
    final capacity = resource.shared ? resource.capacity : 1;
    final state = used == 0
        ? SlotState.free
        : used >= capacity
        ? SlotState.full
        : SlotState.partial;
    return (state: state, used: used, capacity: capacity, bookings: holders);
  }

  /// How full [day] is, 0–1: units taken over units on offer across every
  /// active resource and slot. A full-day booking takes every slot it
  /// clashes with, so it counts in each. When the business has real
  /// sessions besides "Full day", the full-day slot itself isn't counted
  /// again (it overlaps them all).
  double occupancy(DateTime day, List<String> slots) {
    final counted = slots.length > 1
        ? slots.where((s) => s != kFullDay).toList()
        : slots;
    var offered = 0, used = 0;
    for (final r in activeResources) {
      for (final slot in counted) {
        final a = availability(r, day, slot);
        offered += a.capacity;
        used += a.used > a.capacity ? a.capacity : a.used;
      }
    }
    return offered == 0 ? 0 : used / offered;
  }

  /// Blocking bookings touching any day of [month], plus money figures.
  ({int bookings, int enquiries, Money booked, Money due, double occupancy})
  monthSummary(DateTime month, List<String> slots, BizBook? books) {
    final first = DateTime(month.year, month.month);
    final last = DateTime(month.year, month.month + 1, 0);
    var count = 0, enquiries = 0, booked = 0, due = 0;
    for (final b in bookings) {
      if (!datesOverlap(b.startDate, b.endDate, first, last)) continue;
      if (b.status == BizBookingStatus.enquiry) enquiries++;
      if (!b.status.blocks) continue;
      count++;
      booked += b.totalAmount.paise;
      final d = moneyOf(b, books).due;
      if (d.isPositive) due += d.paise;
    }
    var occ = 0.0;
    for (
      var d = first;
      !d.isAfter(last);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      occ += occupancy(d, slots);
    }
    return (
      bookings: count,
      enquiries: enquiries,
      booked: Money(booked),
      due: Money(due),
      occupancy: occ / last.day,
    );
  }

  /// Every reason a booking can't hold these resources. Empty = OK.
  /// Enquiries and cancellations never conflict — they hold nothing.
  List<String> conflicts({
    required DateTime start,
    required DateTime end,
    required String slot,
    required List<BookingLineDraft> lines,
    required BizBookingStatus status,
    int? excludeBookingId,
  }) {
    if (!status.blocks) return const [];
    final out = <String>[];
    for (final line in lines) {
      final r = resourceById[line.resourceId];
      if (r == null) continue;
      for (
        var d = dayOf(start);
        !d.isAfter(dayOf(end));
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        final a = availability(r, d, slot, excludeBookingId: excludeBookingId);
        final want = r.shared ? line.qty : 1;
        if (a.used + want > a.capacity) {
          final who = a.bookings.isEmpty
              ? ''
              : ' (${a.bookings.first.customerName})';
          out.add(
            r.shared
                ? '${r.name}: only ${a.capacity - a.used} left on ${_d(d)} $slot'
                : '${r.name} is already booked on ${_d(d)} · ${a.bookings.isEmpty ? slot : a.bookings.first.slot}$who',
          );
          break;
        }
      }
    }
    return out;
  }

  static String _d(DateTime d) => '${d.day}/${d.month}/${d.year}';

  /// Advances received (receipts linked to the booking) and its bill.
  BookingMoney moneyOf(BizBookingRow b, BizBook? book) {
    var paid = 0;
    var refunded = 0;
    var billed = false;
    if (book != null) {
      for (final v in book.vouchers) {
        if (v.bookingId != b.id) continue;
        switch (v.type) {
          case BizVoucherType.receipt:
            paid += book.voucherAmount(v.id).paise;
          case BizVoucherType.payment:
            refunded += book.voucherAmount(v.id).paise;
          case BizVoucherType.sales:
            billed = true;
          default:
            break;
        }
      }
    }
    final net = Money(paid - refunded);
    return (
      total: b.totalAmount,
      paid: net,
      due: b.totalAmount - net,
      billed: billed,
    );
  }
}
