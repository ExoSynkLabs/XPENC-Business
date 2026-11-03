import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/money.dart';
import 'package:xpenc/data/business_tables.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/features/business/biz_book.dart';
import 'package:xpenc/features/business/biz_repository.dart';
import 'package:xpenc/features/business/booking/booking_book.dart';
import 'package:xpenc/features/business/booking/booking_repository.dart';
import 'package:xpenc/features/business/booking/business_types.dart';

Money rs(num r) => Money.fromRupees(r);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final day = DateTime(2026, 12, 12);

  Future<(int, BookingBook)> venue() async {
    final co = await db.createBizCompany(
      name: 'Shubh Mangal Hall',
      businessType: BizBusinessType.venue,
    );
    return (co, await db.loadBookingBook(co));
  }

  int res(BookingBook b, String name) =>
      b.resources.firstWhere((r) => r.name == name).id;

  BookingDraft draft(
    int co,
    List<BookingLineDraft> lines, {
    String slot = kFullDay,
    DateTime? start,
    DateTime? end,
    BizBookingStatus status = BizBookingStatus.confirmed,
    String name = 'Patil family',
    int? id,
  }) => BookingDraft(
    id: id,
    companyId: co,
    customerName: name,
    start: start ?? day,
    end: end ?? start ?? day,
    slot: slot,
    status: status,
    lines: lines,
    total: rs(70000),
  );

  test(
    'a venue company is seeded with halls, sessions and wedding fields',
    () async {
      final (co, book) = await venue();
      expect(book.resources.map((r) => r.name), [
        'Main Hall',
        'Dining Hall',
        'Lawn',
      ]);
      final company = (await db.activeBizCompany())!;
      expect(company.bookingsEnabled, isTrue);
      expect(decodeSlots(company.bookingSlots), contains('Evening'));
      expect(
        BookingField.decodeList(company.bookingFields).map((f) => f.key),
        contains('food'),
      );
      expect(co, company.id);
    },
  );

  test('accounting-only companies start with bookings off', () async {
    await db.createBizCompany(name: 'Kirana');
    expect((await db.activeBizCompany())!.bookingsEnabled, isFalse);
  });

  test(
    'a hall cannot be double-booked, but other halls and sessions stay free',
    () async {
      final (co, book) = await venue();
      final main = res(book, 'Main Hall'), lawn = res(book, 'Lawn');
      await db.saveBooking(
        draft(co, [BookingLineDraft(resourceId: main)], slot: 'Evening'),
      );

      // Same hall, same evening → conflict.
      expect(
        () => db.saveBooking(
          draft(
            co,
            [BookingLineDraft(resourceId: main)],
            slot: 'Evening',
            name: 'Shinde',
          ),
        ),
        throwsA(isA<BookingConflict>()),
      );
      // Full day clashes with the evening.
      expect(
        () => db.saveBooking(
          draft(co, [BookingLineDraft(resourceId: main)], name: 'Shinde'),
        ),
        throwsA(isA<BookingConflict>()),
      );
      // Morning session of the same hall, and the lawn, are fine.
      await db.saveBooking(
        draft(
          co,
          [BookingLineDraft(resourceId: main)],
          slot: 'Morning',
          name: 'Shinde',
        ),
      );
      await db.saveBooking(
        draft(
          co,
          [BookingLineDraft(resourceId: lawn)],
          slot: 'Evening',
          name: 'Jadhav',
        ),
      );
      // An enquiry never blocks.
      await db.saveBooking(
        draft(
          co,
          [BookingLineDraft(resourceId: main)],
          slot: 'Evening',
          status: BizBookingStatus.enquiry,
          name: 'Kale',
        ),
      );

      final b = await db.loadBookingBook(co);
      final main_ = b.resourceById[main]!;
      expect(b.availability(main_, day, 'Evening').state, SlotState.full);
      expect(
        b
            .availability(main_, day.add(const Duration(days: 1)), 'Evening')
            .state,
        SlotState.free,
      );
      expect(b.on(day), hasLength(4));
    },
  );

  test(
    'a multi-day wedding blocks every day it spans; editing ignores itself',
    () async {
      final (co, book) = await venue();
      final main = res(book, 'Main Hall');
      final id = await db.saveBooking(
        draft(
          co,
          [BookingLineDraft(resourceId: main)],
          start: day,
          end: day.add(const Duration(days: 2)),
        ),
      );
      expect(
        () => db.saveBooking(
          draft(
            co,
            [BookingLineDraft(resourceId: main)],
            start: day.add(const Duration(days: 2)),
            name: 'X',
          ),
        ),
        throwsA(isA<BookingConflict>()),
      );
      // Re-saving the same booking is not a clash with itself.
      await db.saveBooking(
        draft(
          co,
          [BookingLineDraft(resourceId: main)],
          start: day,
          end: day.add(const Duration(days: 1)),
          id: id,
        ),
      );
      final b = await db.loadBookingBook(co);
      expect(b.bookings.single.endDate, day.add(const Duration(days: 1)));
    },
  );

  test('cinema seats sell up to capacity', () async {
    final co = await db.createBizCompany(
      name: 'Prabhat Talkies',
      businessType: BizBusinessType.cinema,
    );
    final book = await db.loadBookingBook(co);
    final screen = book.resources.firstWhere(
      (r) => r.name == 'Screen 2',
    ); // 90 seats
    await db.saveBooking(
      draft(co, [
        BookingLineDraft(resourceId: screen.id, qty: 80),
      ], slot: '9:00 PM'),
    );
    final b = await db.loadBookingBook(co);
    expect(b.availability(screen, day, '9:00 PM').state, SlotState.partial);
    expect(
      () => db.saveBooking(
        draft(
          co,
          [BookingLineDraft(resourceId: screen.id, qty: 11)],
          slot: '9:00 PM',
          name: 'Y',
        ),
      ),
      throwsA(isA<BookingConflict>()),
    );
    await db.saveBooking(
      draft(
        co,
        [BookingLineDraft(resourceId: screen.id, qty: 10)],
        slot: '9:00 PM',
        name: 'Y',
      ),
    );
    expect(
      (await db.loadBookingBook(co)).availability(screen, day, '9:00 PM').state,
      SlotState.full,
    );
  });

  test('occupancy and month summary', () async {
    final (co, book) = await venue();
    final slots = ['Morning', 'Evening', kFullDay];
    await db.saveBooking(
      draft(co, [BookingLineDraft(resourceId: res(book, 'Main Hall'))], slot: 'Evening'),
    );
    await db.saveBooking(
      draft(co, [BookingLineDraft(resourceId: res(book, 'Lawn'))], name: 'Full-day lawn'),
    );
    await db.saveBooking(
      draft(
        co,
        [BookingLineDraft(resourceId: res(book, 'Dining Hall'))],
        status: BizBookingStatus.enquiry,
        name: 'Maybe',
      ),
    );
    final b = await db.loadBookingBook(co);
    // 3 halls × 2 sessions = 6; Main Hall evening + Lawn both sessions = 3.
    expect(b.occupancy(day, slots), closeTo(0.5, 1e-9));
    expect(b.occupancy(day.add(const Duration(days: 1)), slots), 0);
    final m = b.monthSummary(day, slots, null);
    expect(m.bookings, 2);
    expect(m.enquiries, 1);
    expect(m.booked, rs(140000));
    expect(m.occupancy, closeTo(0.5 / 31, 1e-9));
  });

  test('rates multiply by days or nights', () {
    final a = DateTime(2026, 1, 1), b = DateTime(2026, 1, 3);
    expect(rateMultiplier(RateBasis.perDay, a, b), 3);
    expect(rateMultiplier(RateBasis.perNight, a, b), 2);
    expect(rateMultiplier(RateBasis.perNight, a, a), 1);
    expect(rateMultiplier(RateBasis.perUnit, a, b), 1);
  });

  test('advance and bill post to the books and settle the booking', () async {
    final (co, book) = await venue();
    final id = await db.saveBooking(
      draft(co, [
        BookingLineDraft(resourceId: res(book, 'Main Hall'), rate: rs(70000)),
      ]),
    );
    var b = (await db.loadBookingBook(co)).bookingById[id]!;
    final cash = (await db.loadBizBook(co))!.ledgerByKey(BizSystemKey.cash)!.id;

    await db.recordBookingPayment(
      booking: b,
      amount: rs(20000),
      cashLedgerId: cash,
    );
    b = (await db.loadBookingBook(co)).bookingById[id]!;
    await db.postBookingBill(b);

    final bb = (await db.loadBookingBook(co));
    b = bb.bookingById[id]!;
    final books = (await db.loadBizBook(co))!;
    final m = bb.moneyOf(b, books);
    expect(m.paid, rs(20000));
    expect(m.due, rs(50000));
    expect(m.billed, isTrue);

    final party = books.ledgerById[b.partyLedgerId]!;
    expect(party.name, 'Patil family');
    expect(books.balanceOf(party), rs(50000)); // still owes
    final fy = BizPeriod(DateTime(2026, 4, 1), DateTime(2027, 3, 31));
    expect(books.profitAndLoss(fy).sales.total, rs(70000));
    expect(books.trialBalance(fy).balanced, isTrue);

    // Deleting the booking keeps the money in the books.
    await db.deleteBooking(id);
    final after = (await db.loadBizBook(co))!;
    expect(after.vouchers, hasLength(2));
    expect(after.vouchers.every((v) => v.bookingId == null), isTrue);
  });

  test('bookings survive a backup round-trip', () async {
    final (co, book) = await venue();
    await db.saveBooking(
      BookingDraft(
        companyId: co,
        customerName: 'Patil family',
        start: day,
        end: day,
        slot: 'Evening',
        status: BizBookingStatus.confirmed,
        guests: 450,
        extra: const {'food': 'Veg', 'decoration': true},
        lines: [BookingLineDraft(resourceId: res(book, 'Lawn'))],
      ),
    );
    final dump =
        jsonDecode(jsonEncode(await db.exportAll())) as Map<String, dynamic>;
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.importAll(dump);
    final restored = await other.loadBookingBook(co);
    final b = restored.bookings.single;
    expect(b.guests, 450);
    expect(restored.extraOf(b)['food'], 'Veg');
    expect(restored.resourceNames(b), 'Lawn');
  });

  test('deleting a company removes its bookings too', () async {
    final (co, book) = await venue();
    await db.saveBooking(
      draft(co, [BookingLineDraft(resourceId: res(book, 'Lawn'))]),
    );
    await db.deleteBizCompany(co);
    expect((await db.loadBookingBook(co)).bookings, isEmpty);
  });
}
