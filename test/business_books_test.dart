import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/money.dart';
import 'package:xpenc/data/business_tables.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/features/business/biz_book.dart';
import 'package:xpenc/features/business/biz_entry_kinds.dart';
import 'package:xpenc/features/business/biz_posting.dart';
import 'package:xpenc/features/business/biz_repository.dart';

Money rs(num r) => Money.fromRupees(r);

void main() {
  late AppDatabase db;
  late int co;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    co = await db.createBizCompany(name: 'Patil Traders');
  });
  tearDown(() => db.close());

  Future<BizBook> book() async => (await db.loadBizBook(co))!;
  Future<int> key(String k) => db.ensureBizSystemLedger(co, k);
  final fy = BizPeriod(DateTime(2026, 4, 1), DateTime(2027, 3, 31));

  Future<int> simple(
    BizEntryKind kind,
    int primary,
    int secondary,
    Money amount, {
    DateTime? date,
  }) => db.saveBizVoucher(
    BizVoucherDraft(
      companyId: co,
      type: kind.type,
      date: date ?? DateTime(2026, 5, 1),
      entryKind: kind.key,
      lines: simpleLines(
        kind: kind,
        primaryLedgerId: primary,
        secondaryLedgerId: secondary,
        amount: amount,
      ),
    ),
  );

  test(
    'a new company is seeded with system ledgers and becomes active',
    () async {
      final b = await book();
      expect(b.ledgerByKey(BizSystemKey.cash), isNotNull);
      expect(
        b.ledgerByKey(BizSystemKey.gstOut)!.ledgerGroup,
        BizGroup.dutiesTaxes,
      );
      expect((await db.activeBizCompany())!.id, co);
    },
  );

  test('unbalanced vouchers are rejected', () async {
    final cash = await key(BizSystemKey.cash);
    final sales = await key(BizSystemKey.sales);
    expect(
      () => db.saveBizVoucher(
        BizVoucherDraft(
          companyId: co,
          type: BizVoucherType.journal,
          date: DateTime(2026, 5, 1),
          lines: [
            BizLineDraft.dr(cash, rs(100)),
            BizLineDraft.cr(sales, rs(90)),
          ],
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'capital, loan, sale with GST, purchase, expense → books balance',
    () async {
      final cash = await key(BizSystemKey.cash);
      final capital = await key(BizSystemKey.capital);
      final salesL = await key(BizSystemKey.sales);
      final purchaseL = await key(BizSystemKey.purchase);
      final gstOut = await key(BizSystemKey.gstOut);
      final gstIn = await key(BizSystemKey.gstIn);
      final bank = await db.createBizLedger(
        companyId: co,
        name: 'HDFC Current',
        group: BizGroup.bank,
      );
      final loan = await db.createBizLedger(
        companyId: co,
        name: 'SBI Term Loan',
        group: BizGroup.securedLoans,
      );
      final customer = await db.createBizLedger(
        companyId: co,
        name: 'Asha Stores',
        group: BizGroup.sundryDebtors,
      );
      final supplier = await db.createBizLedger(
        companyId: co,
        name: 'Kolhapur Wholesale',
        group: BizGroup.sundryCreditors,
      );
      final rent = (await book()).ledgers
          .firstWhere((l) => l.name == 'Rent')
          .id;

      await simple(BizEntryKind.capitalIn, capital, bank, rs(100000));
      await simple(BizEntryKind.loanTaken, loan, bank, rs(50000));
      await simple(BizEntryKind.contra, cash, bank, rs(10000));

      // Purchase 10,000 + 18% GST on credit.
      await db.saveBizVoucher(
        BizVoucherDraft(
          companyId: co,
          type: BizVoucherType.purchase,
          date: DateTime(2026, 5, 2),
          entryKind: 'purchase',
          lines: invoiceLines(
            kind: BizEntryKind.purchase,
            partyLedgerId: supplier,
            bookLedgerId: purchaseL,
            taxable: rs(10000),
            gst: gstOn(rs(10000), 18),
            gstLedgerId: gstIn,
          ),
        ),
      );
      // Sale 15,000 + 18% GST on credit.
      await db.saveBizVoucher(
        BizVoucherDraft(
          companyId: co,
          type: BizVoucherType.sales,
          date: DateTime(2026, 5, 3),
          entryKind: 'sale',
          lines: invoiceLines(
            kind: BizEntryKind.sale,
            partyLedgerId: customer,
            bookLedgerId: salesL,
            taxable: rs(15000),
            gst: gstOn(rs(15000), 18),
            gstLedgerId: gstOut,
          ),
        ),
      );
      await simple(BizEntryKind.expense, rent, cash, rs(2000));
      await simple(BizEntryKind.receiptFromParty, customer, bank, rs(5000));

      final b = await book();
      final pl = b.profitAndLoss(fy);
      expect(pl.sales.total, rs(15000));
      expect(pl.purchase.total, rs(10000));
      expect(pl.grossProfit, rs(5000));
      expect(pl.netProfit, rs(3000));

      final tb = b.trialBalance(fy);
      expect(tb.balanced, isTrue);

      final bs = b.balanceSheet(fy);
      expect(bs.totalAssets, bs.totalLiabilities);
      expect(bs.profitCurrent, rs(3000));

      final gst = b.gstSummary(fy);
      expect(gst.output, rs(2700));
      expect(gst.input, rs(1800));
      expect(gst.net, rs(900));

      final out = b.outstanding();
      expect(out.receivables.single.balance, rs(17700 - 5000));
      expect(out.payables.single.balance, rs(11800));

      expect(b.balanceOf(b.ledgerById[cash]!), rs(8000));
      expect(b.balanceOf(b.ledgerById[bank]!), rs(145000));
    },
  );

  test(
    'earlier-period profit and opening differences keep reports balanced',
    () async {
      final cash = await key(BizSystemKey.cash);
      final salesL = await key(BizSystemKey.sales);
      // Opening cash with no matching capital → opening difference.
      final ledger = (await book()).ledgerById[cash]!;
      await db.updateBizLedger(ledger.copyWith(openingBalance: rs(500)));
      await db.saveBizVoucher(
        BizVoucherDraft(
          companyId: co,
          type: BizVoucherType.sales,
          date: DateTime(2026, 2, 1), // previous FY
          lines: invoiceLines(
            kind: BizEntryKind.sale,
            partyLedgerId: cash,
            bookLedgerId: salesL,
            taxable: rs(1000),
            gst: const Money.zero(),
          ),
        ),
      );
      await db.setBizStock(
        companyId: co,
        openingStock: rs(300),
        closingStock: rs(450),
      );

      final b = await book();
      final tb = b.trialBalance(fy);
      expect(
        tb.balanced,
        isTrue,
        reason: '${tb.totalDebit} vs ${tb.totalCredit}',
      );
      final bs = b.balanceSheet(fy);
      expect(bs.profitEarlier, rs(1000));
      expect(bs.profitCurrent, rs(150)); // closing − opening stock
      expect(bs.openingDifference, rs(800));
      expect(bs.totalAssets, bs.totalLiabilities);
    },
  );

  test('stock summary tracks quantity and weighted average cost', () async {
    final item = await db.createBizItem(
      companyId: co,
      name: 'Rice 25kg',
      unit: 'bag',
      purchasePrice: rs(1000),
      openingQty: 10,
    );
    final cash = await key(BizSystemKey.cash);
    final purchaseL = await key(BizSystemKey.purchase);
    final salesL = await key(BizSystemKey.sales);
    await db.saveBizVoucher(
      BizVoucherDraft(
        companyId: co,
        type: BizVoucherType.purchase,
        date: DateTime(2026, 6, 1),
        items: [BizItemLineDraft(itemId: item, qty: 10, rate: rs(1200))],
        lines: invoiceLines(
          kind: BizEntryKind.purchase,
          partyLedgerId: cash,
          bookLedgerId: purchaseL,
          taxable: rs(12000),
          gst: const Money.zero(),
        ),
      ),
    );
    await db.saveBizVoucher(
      BizVoucherDraft(
        companyId: co,
        type: BizVoucherType.sales,
        date: DateTime(2026, 6, 2),
        items: [BizItemLineDraft(itemId: item, qty: 5, rate: rs(1500))],
        lines: invoiceLines(
          kind: BizEntryKind.sale,
          partyLedgerId: cash,
          bookLedgerId: salesL,
          taxable: rs(7500),
          gst: const Money.zero(),
        ),
      ),
    );
    final b = await book();
    final line = b.stockSummary().single;
    expect(line.closingQty, 15);
    expect(line.avgCost, rs(1100));
    expect(line.value, rs(16500));

    // Stock is valued from items automatically: opening 10 × 1000.
    expect(b.tracksInventory, isTrue);
    final pl = b.profitAndLoss(fy);
    expect(pl.openingStock, rs(10000));
    expect(pl.closingStock, rs(16500));
    // 7500 sales + 16500 closing − 10000 opening − 12000 purchase.
    expect(pl.grossProfit, rs(2000));
    expect(b.trialBalance(fy).balanced, isTrue);
    final bs = b.balanceSheet(fy);
    expect(bs.totalAssets, bs.totalLiabilities);

    // The next year opens with this year's closing stock, and still balances.
    final next = BizPeriod(DateTime(2027, 4, 1), DateTime(2028, 3, 31));
    expect(b.profitAndLoss(next).openingStock, rs(16500));
    expect(b.trialBalance(next).balanced, isTrue);
    final bsNext = b.balanceSheet(next);
    expect(bsNext.profitEarlier, rs(2000));
    expect(bsNext.totalAssets, bsNext.totalLiabilities);
  });

  test('editing a voucher replaces its lines and keeps its number', () async {
    final cash = await key(BizSystemKey.cash);
    final capital = await key(BizSystemKey.capital);
    final id = await simple(BizEntryKind.capitalIn, capital, cash, rs(100));
    await db.saveBizVoucher(
      BizVoucherDraft(
        id: id,
        companyId: co,
        type: BizVoucherType.receipt,
        date: DateTime(2026, 5, 1),
        lines: simpleLines(
          kind: BizEntryKind.capitalIn,
          primaryLedgerId: capital,
          secondaryLedgerId: cash,
          amount: rs(250),
        ),
      ),
    );
    final b = await book();
    expect(b.vouchers.single.number, 1);
    expect(b.voucherAmount(id), rs(250));
    expect(b.linesOf(id), hasLength(2));
    await db.deleteBizVoucher(id);
    expect((await book()).vouchers, isEmpty);
  });

  test('ledgers with history are archived, not deleted', () async {
    final cash = await key(BizSystemKey.cash);
    final capital = await key(BizSystemKey.capital);
    final spare = await db.createBizLedger(
      companyId: co,
      name: 'Spare',
      group: BizGroup.indirectExpense,
    );
    await simple(BizEntryKind.capitalIn, capital, cash, rs(100));
    expect(await db.deleteOrArchiveBizLedger(spare), isTrue);
    expect(await db.deleteOrArchiveBizLedger(cash), isFalse);
    expect((await book()).ledgerById[cash]!.isArchived, isTrue);
  });

  test('business books survive a backup round-trip', () async {
    final cash = await key(BizSystemKey.cash);
    final capital = await key(BizSystemKey.capital);
    await db.createBizItem(companyId: co, name: 'Widget');
    await simple(BizEntryKind.capitalIn, capital, cash, rs(1234));
    final dump =
        jsonDecode(jsonEncode(await db.exportAll())) as Map<String, dynamic>;

    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.importAll(dump);
    final restored = (await other.loadBizBook(co))!;
    expect(restored.company.name, 'Patil Traders');
    expect(restored.items.single.name, 'Widget');
    expect(restored.balanceOf(restored.ledgerById[cash]!), rs(1234));
  });

  test('deleting a company removes everything in it', () async {
    final cash = await key(BizSystemKey.cash);
    final capital = await key(BizSystemKey.capital);
    await simple(BizEntryKind.capitalIn, capital, cash, rs(1));
    await db.deleteBizCompany(co);
    expect(await db.loadBizBook(co), isNull);
    expect(await db.activeBizCompany(), isNull);
  });

  test('clear all data wipes the business books too', () async {
    final cash = await key(BizSystemKey.cash);
    final capital = await key(BizSystemKey.capital);
    await simple(BizEntryKind.capitalIn, capital, cash, rs(1));
    await db.clearAllData();
    expect(await db.activeBizCompany(), isNull);
    expect(await db.loadBizBook(co), isNull);
  });

  test('financial year period starts in April', () {
    final p = BizPeriod.financialYear(DateTime(2027, 2, 10), 4);
    expect(p.from, DateTime(2026, 4, 1));
    expect(p.to, DateTime(2027, 3, 31));
    expect(p.contains(DateTime(2027, 3, 31, 23, 59)), isTrue);
    expect(p.contains(DateTime(2027, 4, 1)), isFalse);
  });
}
