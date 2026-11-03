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
import 'package:xpenc/features/business/biz_entry_kinds.dart';
import 'package:xpenc/features/business/biz_posting.dart';
import 'package:xpenc/features/business/biz_repository.dart';
import 'package:xpenc/features/business/business_home_screen.dart';
import 'package:xpenc/features/business/day_book_screen.dart';
import 'package:xpenc/features/business/items_screen.dart';
import 'package:xpenc/features/business/ledgers_screen.dart';
import 'package:xpenc/features/business/reports_screens.dart';
import 'package:xpenc/features/business/voucher_entry_screen.dart';

/// Every Business Books screen renders at phone size (360×800 dp) against a
/// real database without throwing or overflowing. Same rules as
/// test/smoke_test.dart: DB work in `runAsync`, no `pumpAndSettle`, unmount
/// before the test ends.
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

  /// A company with a bit of everything in it.
  Future<({int company, int sale})> seed() async {
    final co = await db.createBizCompany(
      name: 'Patil Traders',
      bankName: 'HDFC Current',
      openingCash: Money.fromRupees(5000),
    );
    final b = (await db.loadBizBook(co))!;
    final cash = b.ledgerByKey(BizSystemKey.cash)!.id;
    final capital = b.ledgerByKey(BizSystemKey.capital)!.id;
    final sales = b.ledgerByKey(BizSystemKey.sales)!.id;
    final gstOut = b.ledgerByKey(BizSystemKey.gstOut)!.id;
    final customer = await db.createBizLedger(
      companyId: co,
      name: 'Asha Stores',
      group: BizGroup.sundryDebtors,
      phone: '9800000000',
    );
    final item = await db.createBizItem(
      companyId: co,
      name: 'Rice 25kg',
      unit: 'bag',
      salePrice: Money.fromRupees(1500),
      purchasePrice: Money.fromRupees(1100),
      openingQty: 20,
    );
    await db.saveBizVoucher(
      BizVoucherDraft(
        companyId: co,
        type: BizVoucherType.receipt,
        date: DateTime.now(),
        entryKind: BizEntryKind.capitalIn.key,
        lines: simpleLines(
          kind: BizEntryKind.capitalIn,
          primaryLedgerId: capital,
          secondaryLedgerId: cash,
          amount: Money.fromRupees(100000),
        ),
      ),
    );
    final sale = await db.saveBizVoucher(
      BizVoucherDraft(
        companyId: co,
        type: BizVoucherType.sales,
        date: DateTime.now(),
        entryKind: BizEntryKind.sale.key,
        reference: 'INV-1',
        items: [
          BizItemLineDraft(itemId: item, qty: 2, rate: Money.fromRupees(1500)),
        ],
        lines: invoiceLines(
          kind: BizEntryKind.sale,
          partyLedgerId: customer,
          bookLedgerId: sales,
          taxable: Money.fromRupees(3000),
          gst: gstOn(Money.fromRupees(3000), 5),
          gstLedgerId: gstOut,
        ),
      ),
    );
    return (company: co, sale: sale);
  }

  testWidgets(
    'first run shows company setup, and creating one opens the dashboard',
    (tester) async {
      await pump(tester, const BusinessHomeScreen());
      expect(find.text('Create company'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Business name'),
        'Yash Enterprises',
      );
      await tester.tap(find.text('Create company'));
      await settle(tester);
      await settle(tester);
      expect(find.text('Yash Enterprises'), findsOneWidget);
      expect(find.text('Cash & Bank'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('dashboard and every report render with data', (tester) async {
    await tester.runAsync(seed);
    for (final screen in <Widget>[
      const BusinessHomeScreen(),
      const DayBookScreen(),
      const LedgersScreen(),
      const ItemsScreen(),
      const ProfitLossScreen(),
      const BalanceSheetScreen(),
      const TrialBalanceScreen(),
      const OutstandingScreen(),
      const GstSummaryScreen(),
    ]) {
      await pump(tester, screen);
      expect(tester.takeException(), isNull, reason: '${screen.runtimeType}');
      await unmount(tester);
    }
  });

  testWidgets('ledger statement renders', (tester) async {
    final s = (await tester.runAsync(seed))!;
    final b = (await tester.runAsync(() => db.loadBizBook(s.company)))!;
    final customer = b.ledgers.firstWhere((l) => l.name == 'Asha Stores');
    await pump(tester, LedgerDetailScreen(ledgerId: customer.id));
    expect(find.text('Asha Stores'), findsWidgets);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('every quick-entry form renders, and an existing sale reopens', (
    tester,
  ) async {
    final s = (await tester.runAsync(seed))!;
    for (final kind in BizEntryKind.all) {
      await pump(tester, VoucherEntryScreen(kind: kind));
      expect(tester.takeException(), isNull, reason: kind.key);
      await unmount(tester);
    }
    await pump(tester, VoucherEntryScreen(voucherId: s.sale));
    expect(find.text('Rice 25kg'), findsOneWidget);
    expect(find.text('Edit SAL/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a loan can be entered through the form', (tester) async {
    final s = (await tester.runAsync(seed))!;
    final loan = (await tester.runAsync(
      () => db.createBizLedger(
        companyId: s.company,
        name: 'SBI Term Loan',
        group: BizGroup.securedLoans,
      ),
    ))!;
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () =>
                  openVoucherEntry(context, kind: BizEntryKind.loanTaken),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    // Received-in defaults to Cash; pick the lender and type the amount.
    await tester.tap(
      find
          .ancestor(
            of: find.text('Lender (loan account)'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('SBI Term Loan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '50000');
    await tester.tap(find.text('Save loan taken'));
    await settle(tester);
    await settle(tester);

    final b = (await tester.runAsync(() => db.loadBizBook(s.company)))!;
    expect(b.balanceOf(b.ledgerById[loan]!), Money.fromRupees(-50000));
    expect(
      b.trialBalance(BizPeriod.financialYear(DateTime.now(), 4)).balanced,
      isTrue,
    );
    await unmount(tester);
  });
}
