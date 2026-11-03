import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/money.dart';
import 'package:xpenc/core/theme/app_theme.dart';
import 'package:xpenc/data/business_tables.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/data/providers.dart';
import 'package:xpenc/features/business/amount_words.dart';
import 'package:xpenc/features/business/biz_book.dart';
import 'package:xpenc/features/business/biz_entry_kinds.dart';
import 'package:xpenc/features/business/biz_posting.dart';
import 'package:xpenc/features/business/biz_repository.dart';
import 'package:xpenc/features/business/booking/booking_book.dart';
import 'package:xpenc/features/business/booking/booking_repository.dart';
import 'package:xpenc/features/business/booking/business_types.dart';
import 'package:xpenc/features/business/business_home_screen.dart';
import 'package:xpenc/features/business/search_screen.dart';

Money rs(num r) => Money.fromRupees(r);

void main() {
  group('amount in words (Indian numbering)', () {
    test('crore, lakh, thousand, hundred', () {
      expect(indianWords(0), 'zero');
      expect(indianWords(45), 'forty-five');
      expect(indianWords(1000), 'one thousand');
      expect(indianWords(100000), 'one lakh');
      expect(indianWords(1234567), 'twelve lakh thirty-four thousand five hundred sixty-seven');
      expect(indianWords(250000000), 'twenty-five crore');
    });

    test('rupees and paise, cheque style', () {
      expect(amountInWords(rs(45000)), 'Rupees forty-five thousand only');
      expect(amountInWords(Money(105050)), 'Rupees one thousand fifty and fifty paise only');
    });
  });

  group('with a company', () {
    late AppDatabase db;
    late int co;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      co = await db.createBizCompany(name: 'Shubh Mangal', businessType: BizBusinessType.venue);
    });
    tearDown(() => db.close());

    Future<BizBook> book() async => (await db.loadBizBook(co))!;

    test('recently used ledgers come newest first, filtered by group', () async {
      final b0 = await book();
      final cash = b0.ledgerByKey(BizSystemKey.cash)!.id;
      final capital = b0.ledgerByKey(BizSystemKey.capital)!.id;
      final rent = b0.ledgers.firstWhere((l) => l.name == 'Rent').id;
      final salary = b0.ledgers.firstWhere((l) => l.name == 'Salary').id;
      Future<void> post(BizEntryKind k, int p, int s, DateTime d) => db.saveBizVoucher(
        BizVoucherDraft(
          companyId: co,
          type: k.type,
          date: d,
          lines: simpleLines(kind: k, primaryLedgerId: p, secondaryLedgerId: s, amount: rs(100)),
        ),
      );
      await post(BizEntryKind.capitalIn, capital, cash, DateTime(2026, 5, 1));
      await post(BizEntryKind.expense, rent, cash, DateTime(2026, 5, 2));
      await post(BizEntryKind.expense, salary, cash, DateTime(2026, 5, 3));
      final b = await book();
      expect(b.recentLedgerIds(groups: {BizGroup.indirectExpense}), [salary, rent]);
      expect(b.recentLedgerIds(limit: 2), [salary, cash]);
    });

    test('search finds parties, vouchers by number/amount, and bookings', () async {
      final b0 = await book();
      final cash = b0.ledgerByKey(BizSystemKey.cash)!.id;
      final sales = b0.ledgerByKey(BizSystemKey.sales)!.id;
      final asha = await db.createBizLedger(
        companyId: co,
        name: 'Asha Stores',
        group: BizGroup.sundryDebtors,
        phone: '9822012345',
      );
      await db.saveBizVoucher(
        BizVoucherDraft(
          companyId: co,
          type: BizVoucherType.sales,
          date: DateTime(2026, 5, 1),
          reference: 'INV-77',
          lines: invoiceLines(
            kind: BizEntryKind.sale,
            partyLedgerId: asha,
            bookLedgerId: sales,
            taxable: rs(45000),
            gst: const Money.zero(),
          ),
        ),
      );
      final bb = await db.loadBookingBook(co);
      await db.saveBooking(
        BookingDraft(
          companyId: co,
          customerName: 'Patil family',
          phone: '9000011111',
          start: DateTime(2026, 12, 1),
          end: DateTime(2026, 12, 1),
          slot: kFullDay,
          status: BizBookingStatus.confirmed,
          lines: [BookingLineDraft(resourceId: bb.resources.first.id)],
        ),
      );
      final b = await book();
      final bookings = await db.loadBookingBook(co);
      expect(searchBusiness('asha', b, bookings).ledgers.single.id, asha);
      expect(searchBusiness('98220', b, bookings).ledgers, hasLength(1));
      expect(searchBusiness('asha', b, bookings).vouchers, hasLength(1)); // via its party
      expect(searchBusiness('SAL/1', b, bookings).vouchers, hasLength(1));
      expect(searchBusiness('inv-77', b, bookings).vouchers, hasLength(1));
      expect(searchBusiness('45000', b, bookings).vouchers, hasLength(1));
      expect(searchBusiness('patil', b, bookings).bookings, hasLength(1));
      expect(searchBusiness('BK/1', b, bookings).bookings, hasLength(1));
      expect(searchBusiness('', b, bookings).ledgers, isEmpty);
      expect(cash, isPositive);
    });

    testWidgets('home shows the getting-started checklist and no zero tiles', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(theme: AppTheme.light, home: const BusinessHomeScreen()),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Record the capital you put in'), findsOneWidget);
      expect(find.text('Take your first event'), findsOneWidget);
      expect(find.text('CAPITAL, LOANS & ASSETS'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  });
}
