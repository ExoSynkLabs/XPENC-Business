import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/money.dart';
import '../../../data/business_tables.dart';
import '../../../data/database.dart';
import '../biz_entry_kinds.dart';
import '../biz_posting.dart';
import '../biz_repository.dart';
import 'booking_book.dart';
import 'business_types.dart';

/// Everything a booking needs to be saved (new or edited).
class BookingDraft {
  const BookingDraft({
    this.id,
    required this.companyId,
    required this.customerName,
    required this.start,
    required this.end,
    required this.slot,
    required this.status,
    required this.lines,
    this.phone,
    this.title,
    this.guests = 0,
    this.total = const Money.zero(),
    this.extra = const {},
    this.notes,
    this.multiplier = 1,
  });

  final int? id;
  final int companyId;
  final String customerName;
  final String? phone;
  final String? title;
  final DateTime start;
  final DateTime end;
  final String slot;
  final BizBookingStatus status;
  final List<BookingLineDraft> lines;
  final int guests;
  final Money total;
  final Map<String, Object?> extra;
  final String? notes;

  /// Days / nights the rates apply for (see `rateMultiplier`).
  final int multiplier;
}

/// Thrown when a booking would double-book a resource.
class BookingConflict implements Exception {
  BookingConflict(this.messages);
  final List<String> messages;
  @override
  String toString() => messages.join('\n');
}

/// The system key of the income ledger booking bills post to.
const kBookingIncomeKey = 'bookingIncome';

extension BookingRepository on AppDatabase {
  // ── Setup ─────────────────────────────────────────────────────────────────

  /// Switches the company to [type]. Seeds the type's resources, slots and
  /// custom fields only where the company has none yet — never overwrites
  /// what the user already built.
  Future<void> applyBusinessTemplate(
    int companyId,
    BizBusinessType type, {
    bool replaceSetup = false,
  }) => transaction(() async {
    final company = await (select(
      bizCompanies,
    )..where((c) => c.id.equals(companyId))).getSingle();
    final hasFields = BookingField.decodeList(company.bookingFields).isNotEmpty;
    await (update(bizCompanies)..where((c) => c.id.equals(companyId))).write(
      BizCompaniesCompanion(
        businessType: Value(type.name),
        bookingSlots: replaceSetup || company.bookingSlots == null
            ? Value(encodeSlots(type.slots))
            : const Value.absent(),
        bookingFields: replaceSetup || !hasFields
            ? Value(BookingField.encodeList(type.fields))
            : const Value.absent(),
      ),
    );
    final existing =
        await (select(bizBookingResources)..where(
              (r) => r.companyId.equals(companyId) & r.isArchived.equals(false),
            ))
            .get();
    if (existing.isEmpty || replaceSetup) {
      final names = existing.map((r) => r.name.toLowerCase()).toSet();
      var sort = existing.length;
      for (final r in type.resources) {
        if (names.contains(r.name.toLowerCase())) continue;
        await into(bizBookingResources).insert(
          BizBookingResourcesCompanion.insert(
            companyId: companyId,
            name: r.name,
            capacity: Value(r.capacity),
            shared: Value(r.shared),
            rate: Value(type.templateRate(r)),
            sort: Value(sort++),
          ),
        );
      }
    }
  });

  Future<void> setBookingsEnabled(int companyId, bool enabled) =>
      (update(bizCompanies)..where((c) => c.id.equals(companyId))).write(
        BizCompaniesCompanion(bookingsEnabled: Value(enabled)),
      );

  Future<void> saveBookingSlots(int companyId, List<String> slots) =>
      (update(bizCompanies)..where((c) => c.id.equals(companyId))).write(
        BizCompaniesCompanion(bookingSlots: Value(encodeSlots(slots))),
      );

  Future<void> saveBookingFields(int companyId, List<BookingField> fields) =>
      (update(bizCompanies)..where((c) => c.id.equals(companyId))).write(
        BizCompaniesCompanion(
          bookingFields: Value(BookingField.encodeList(fields)),
        ),
      );

  // ── Resources ─────────────────────────────────────────────────────────────

  Future<int> createBookingResource({
    required int companyId,
    required String name,
    int capacity = 0,
    bool shared = false,
    Money rate = const Money.zero(),
  }) async {
    final count = await (select(
      bizBookingResources,
    )..where((r) => r.companyId.equals(companyId))).get();
    return into(bizBookingResources).insert(
      BizBookingResourcesCompanion.insert(
        companyId: companyId,
        name: name.trim(),
        capacity: Value(capacity),
        shared: Value(shared),
        rate: Value(rate),
        sort: Value(count.length),
      ),
    );
  }

  Future<void> updateBookingResource(BizBookingResourceRow r) =>
      update(bizBookingResources).replace(r);

  /// Deletes an unused resource, archives one that bookings point at.
  Future<bool> deleteOrArchiveBookingResource(int id) async {
    final used =
        await (select(bizBookingLines)
              ..where((l) => l.resourceId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (used != null) {
      await (update(bizBookingResources)..where((r) => r.id.equals(id))).write(
        const BizBookingResourcesCompanion(isArchived: Value(true)),
      );
      return false;
    }
    await (delete(bizBookingResources)..where((r) => r.id.equals(id))).go();
    return true;
  }

  // ── Snapshot ──────────────────────────────────────────────────────────────

  Future<BookingBook> loadBookingBook(int companyId) async {
    final resources = await (select(
      bizBookingResources,
    )..where((r) => r.companyId.equals(companyId))).get();
    final bookings = await (select(
      bizBookings,
    )..where((b) => b.companyId.equals(companyId))).get();
    final ids = bookings.map((b) => b.id).toList();
    final lines = ids.isEmpty
        ? <BizBookingLineRow>[]
        : await (select(
            bizBookingLines,
          )..where((l) => l.bookingId.isIn(ids))).get();
    return BookingBook(resources: resources, bookings: bookings, lines: lines);
  }

  Stream<BookingBook> watchBookingBook(int companyId) => customSelect(
    'SELECT 1',
    readsFrom: {bizBookingResources, bizBookings, bizBookingLines},
  ).watch().asyncMap((_) => loadBookingBook(companyId));

  // ── Bookings ──────────────────────────────────────────────────────────────

  /// Saves a booking. Throws [BookingConflict] when it would double-book a
  /// resource, unless [force].
  Future<int> saveBooking(BookingDraft d, {bool force = false}) async {
    if (d.customerName.trim().isEmpty) {
      throw ArgumentError('Enter the customer’s name.');
    }
    if (dayOf(d.end).isBefore(dayOf(d.start))) {
      throw ArgumentError('The end date is before the start date.');
    }
    if (!force) {
      final book = await loadBookingBook(d.companyId);
      final clashes = book.conflicts(
        start: d.start,
        end: d.end,
        slot: d.slot,
        lines: d.lines,
        status: d.status,
        excludeBookingId: d.id,
      );
      if (clashes.isNotEmpty) throw BookingConflict(clashes);
    }
    String? n(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    final extra = jsonEncode({
      for (final e in d.extra.entries)
        if (e.value != null && e.value != '') e.key: e.value,
    });
    return transaction(() async {
      int id;
      if (d.id == null) {
        final maxExpr = bizBookings.number.max();
        final row =
            await (selectOnly(bizBookings)
                  ..addColumns([maxExpr])
                  ..where(bizBookings.companyId.equals(d.companyId)))
                .getSingle();
        id = await into(bizBookings).insert(
          BizBookingsCompanion.insert(
            companyId: d.companyId,
            number: (row.read(maxExpr) ?? 0) + 1,
            customerName: d.customerName.trim(),
            phone: Value(n(d.phone)),
            title: Value(n(d.title)),
            startDate: dayOf(d.start),
            endDate: dayOf(d.end),
            slot: Value(d.slot),
            status: d.status,
            guests: Value(d.guests),
            totalAmount: Value(d.total),
            extra: Value(extra),
            notes: Value(n(d.notes)),
          ),
        );
      } else {
        id = d.id!;
        await (update(bizBookings)..where((b) => b.id.equals(id))).write(
          BizBookingsCompanion(
            customerName: Value(d.customerName.trim()),
            phone: Value(n(d.phone)),
            title: Value(n(d.title)),
            startDate: Value(dayOf(d.start)),
            endDate: Value(dayOf(d.end)),
            slot: Value(d.slot),
            status: Value(d.status),
            guests: Value(d.guests),
            totalAmount: Value(d.total),
            extra: Value(extra),
            notes: Value(n(d.notes)),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await (delete(
          bizBookingLines,
        )..where((l) => l.bookingId.equals(id))).go();
      }
      for (final l in d.lines) {
        await into(bizBookingLines).insert(
          BizBookingLinesCompanion.insert(
            bookingId: id,
            resourceId: l.resourceId,
            qty: Value(l.qty),
            rate: Value(l.rate),
            amount: Value(l.amount(d.multiplier)),
          ),
        );
      }
      return id;
    });
  }

  Future<void> setBookingStatus(int bookingId, BizBookingStatus status) =>
      (update(bizBookings)..where((b) => b.id.equals(bookingId))).write(
        BizBookingsCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Deletes a booking. Money already received stays in the books (its
  /// vouchers are only unlinked) — deleting an event never deletes cash.
  Future<void> deleteBooking(int bookingId) => transaction(() async {
    await (update(bizVouchers)..where((v) => v.bookingId.equals(bookingId)))
        .write(const BizVouchersCompanion(bookingId: Value(null)));
    await (delete(
      bizBookingLines,
    )..where((l) => l.bookingId.equals(bookingId))).go();
    await (delete(bizBookings)..where((b) => b.id.equals(bookingId))).go();
  });

  // ── Money ─────────────────────────────────────────────────────────────────

  /// The customer's Sundry Debtors ledger — reusing one with the same name,
  /// creating it on first use — and remembers it on the booking.
  Future<int> ensureBookingParty(BizBookingRow b) async {
    if (b.partyLedgerId != null) {
      final l = await (select(
        bizLedgers,
      )..where((l) => l.id.equals(b.partyLedgerId!))).getSingleOrNull();
      if (l != null) return l.id;
    }
    final name = b.customerName.trim();
    final match =
        await (select(bizLedgers)
              ..where(
                (l) =>
                    l.companyId.equals(b.companyId) &
                    l.ledgerGroup.equalsValue(BizGroup.sundryDebtors) &
                    l.name.lower().equals(name.toLowerCase()),
              )
              ..limit(1))
            .getSingleOrNull();
    final id =
        match?.id ??
        await createBizLedger(
          companyId: b.companyId,
          name: name,
          group: BizGroup.sundryDebtors,
          phone: b.phone,
        );
    await (update(bizBookings)..where((x) => x.id.equals(b.id))).write(
      BizBookingsCompanion(partyLedgerId: Value(id)),
    );
    return id;
  }

  Future<int> _bookingIncomeLedger(int companyId) async {
    final existing =
        await (select(bizLedgers)
              ..where(
                (l) =>
                    l.companyId.equals(companyId) &
                    l.systemKey.equals(kBookingIncomeKey),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    final company = await (select(
      bizCompanies,
    )..where((c) => c.id.equals(companyId))).getSingle();
    return into(bizLedgers).insert(
      BizLedgersCompanion.insert(
        companyId: companyId,
        name: BizBusinessType.parse(company.businessType).incomeLedger,
        ledgerGroup: BizGroup.sales,
        systemKey: const Value(kBookingIncomeKey),
      ),
    );
  }

  /// Records an advance / payment (or, with [refund], money paid back) as a
  /// Receipt (Payment) voucher linked to the booking.
  Future<int> recordBookingPayment({
    required BizBookingRow booking,
    required Money amount,
    required int cashLedgerId,
    DateTime? date,
    bool refund = false,
    String? narration,
  }) async {
    final party = await ensureBookingParty(booking);
    return saveBizVoucher(
      BizVoucherDraft(
        companyId: booking.companyId,
        type: refund ? BizVoucherType.payment : BizVoucherType.receipt,
        date: date ?? DateTime.now(),
        entryKind: refund ? 'paymentToParty' : 'receiptFromParty',
        bookingId: booking.id,
        reference: 'BK/${booking.number}',
        narration:
            narration ??
            '${refund ? 'Refund' : 'Advance / payment'} — BK/${booking.number}',
        lines: refund
            ? [
                BizLineDraft.dr(party, amount),
                BizLineDraft.cr(cashLedgerId, amount),
              ]
            : [
                BizLineDraft.dr(cashLedgerId, amount),
                BizLineDraft.cr(party, amount),
              ],
      ),
    );
  }

  /// Posts the booking's total as a Sales voucher to the customer — the
  /// bill. Advances already received then settle against it.
  Future<int> postBookingBill(BizBookingRow booking, {DateTime? date}) async {
    if (!booking.totalAmount.isPositive) {
      throw ArgumentError('Set the booking amount first.');
    }
    final party = await ensureBookingParty(booking);
    final income = await _bookingIncomeLedger(booking.companyId);
    return saveBizVoucher(
      BizVoucherDraft(
        companyId: booking.companyId,
        type: BizVoucherType.sales,
        date: date ?? booking.startDate,
        entryKind: 'sale',
        bookingId: booking.id,
        reference: 'BK/${booking.number}',
        narration: [
          'Booking BK/${booking.number}',
          if (booking.title != null) booking.title!,
        ].join(' — '),
        lines: invoiceLines(
          kind: BizEntryKind.sale,
          partyLedgerId: party,
          bookLedgerId: income,
          taxable: booking.totalAmount,
          gst: const Money.zero(),
        ),
      ),
    );
  }
}
