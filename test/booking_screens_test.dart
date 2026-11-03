import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/money.dart';
import 'package:xpenc/core/theme/app_theme.dart';
import 'package:xpenc/data/business_tables.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/data/providers.dart';
import 'package:xpenc/features/business/biz_book.dart';
import 'package:xpenc/features/business/biz_repository.dart';
import 'package:xpenc/features/business/booking/booking_book.dart';
import 'package:xpenc/features/business/booking/booking_detail_screen.dart';
import 'package:xpenc/features/business/booking/booking_form_screen.dart';
import 'package:xpenc/features/business/booking/booking_repository.dart';
import 'package:xpenc/features/business/booking/booking_setup_screen.dart';
import 'package:xpenc/features/business/booking/bookings_screen.dart';
import 'package:xpenc/features/business/booking/business_types.dart';
import 'package:xpenc/features/business/business_home_screen.dart';

/// Bookings render at phone size (360×800 dp) for every business type, and a
/// wedding can be registered through the form. Same rules as
/// test/smoke_test.dart.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(theme: AppTheme.light, home: screen),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  /// A company of [type] with one confirmed booking today.
  Future<int> seed(BizBusinessType type) async {
    final co = await db.createBizCompany(
      name: 'Test ${type.name}',
      businessType: type,
    );
    await db.setBookingsEnabled(co, true);
    var book = await db.loadBookingBook(co);
    if (book.resources.isEmpty) {
      await db.createBookingResource(
        companyId: co,
        name: 'Room A',
        rate: Money.fromRupees(500),
      );
      book = await db.loadBookingBook(co);
    }
    final r = book.resources.first;
    final id = await db.saveBooking(
      BookingDraft(
        companyId: co,
        customerName: 'Patil family',
        title: 'Sharma – Patil wedding',
        phone: '9800000000',
        start: DateTime.now(),
        end: DateTime.now(),
        slot: decodeSlots(
          type.slots.isEmpty ? null : encodeSlots(type.slots),
        ).first,
        status: BizBookingStatus.confirmed,
        guests: 400,
        total: Money.fromRupees(70000),
        extra: const {'food': 'Veg', 'decoration': true},
        lines: [
          BookingLineDraft(
            resourceId: r.id,
            qty: r.shared ? 4 : 1,
            rate: r.rate,
          ),
        ],
      ),
    );
    final b = (await db.loadBookingBook(co)).bookingById[id]!;
    final cash = (await db.loadBizBook(co))!.ledgerByKey(BizSystemKey.cash)!.id;
    await db.recordBookingPayment(
      booking: b,
      amount: Money.fromRupees(20000),
      cashLedgerId: cash,
    );
    return id;
  }

  for (final type in BizBusinessType.values) {
    testWidgets('${type.name}: home, bookings, form, detail and setup render', (
      tester,
    ) async {
      final id = (await tester.runAsync(() => seed(type)))!;
      for (final screen in <Widget>[
        const BusinessHomeScreen(),
        const BookingsScreen(),
        const BookingFormScreen(),
        BookingFormScreen(bookingId: id),
        BookingDetailScreen(bookingId: id),
        const BookingSetupScreen(),
      ]) {
        await pump(tester, screen);
        expect(
          tester.takeException(),
          isNull,
          reason: '${type.name} ${screen.runtimeType}',
        );
        await unmount(tester);
      }
    });
  }

  testWidgets('first-run setup offers business types', (tester) async {
    await pump(tester, const BusinessHomeScreen());
    expect(find.text('WHAT KIND OF BUSINESS?'), findsOneWidget);
    expect(find.text('Wedding hall / Venue'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a wedding is registered in a free hall from the form', (
    tester,
  ) async {
    final co = (await tester.runAsync(
      () => db.createBizCompany(
        name: 'Shubh Mangal',
        businessType: BizBusinessType.venue,
      ),
    ))!;
    await pump(tester, const BookingFormScreen());
    await tester.enterText(
      find.widgetWithText(TextField, 'Customer name'),
      'Jadhav family',
    );
    Future<void> reveal(Finder f) async {
      await tester.scrollUntilVisible(
        f,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.ensureVisible(f);
      await tester.pump();
      // Centre it, clear of the screen edges.
      final box = tester.getCenter(f);
      await tester.drag(find.byType(Scrollable).first, Offset(0, 400 - box.dy));
      await tester.pump();
    }

    await tester.tap(find.text('Evening'));
    await tester.pump();
    await reveal(find.text('Lawn'));
    await tester.tap(find.text('Lawn'));
    await tester.pump();
    final guests = find.widgetWithText(TextField, 'Expected guests');
    await reveal(guests);
    await tester.enterText(guests, '600');
    await reveal(find.text('Veg'));
    await tester.tap(find.text('Veg'));
    await tester.pump();
    await tester.tap(find.text('Save event'));
    await settle(tester);
    await settle(tester);

    final book = (await tester.runAsync(() => db.loadBookingBook(co)))!;
    final b = book.bookings.single;
    expect(b.customerName, 'Jadhav family');
    expect(b.slot, 'Evening');
    expect(b.guests, 600);
    expect(book.resourceNames(b), 'Lawn');
    expect(book.extraOf(b)['food'], 'Veg');
    expect(b.totalAmount, Money.fromRupees(40000)); // Lawn rate × 1 day
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  test('BizPeriod still used by reports', () {
    expect(BizPeriod.month(DateTime(2026, 2, 3)).to, DateTime(2026, 2, 28));
  });
}
