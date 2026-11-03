import '../../core/money.dart';
import '../../data/business_tables.dart';
import '../../data/database.dart';

/// An inclusive, whole-day date range — `from` and `to` are both days, and a
/// voucher dated any time on `to` is inside it.
class BizPeriod {
  BizPeriod(DateTime from, DateTime to)
    : from = DateTime(from.year, from.month, from.day),
      to = DateTime(to.year, to.month, to.day);

  final DateTime from;
  final DateTime to;

  DateTime get _endExclusive => DateTime(to.year, to.month, to.day + 1);

  bool contains(DateTime d) => !d.isBefore(from) && d.isBefore(_endExclusive);
  bool isBeforeStart(DateTime d) => d.isBefore(from);
  bool isOnOrBeforeEnd(DateTime d) => d.isBefore(_endExclusive);

  /// The financial year containing [day], for a year starting in
  /// [startMonth] (India: April → 1 Apr – 31 Mar).
  factory BizPeriod.financialYear(DateTime day, int startMonth) {
    final startYear = day.month >= startMonth ? day.year : day.year - 1;
    final from = DateTime(startYear, startMonth);
    final to = DateTime(startYear + 1, startMonth, 0); // last day before
    return BizPeriod(from, to);
  }

  factory BizPeriod.month(DateTime day) => BizPeriod(
    DateTime(day.year, day.month),
    DateTime(day.year, day.month + 1, 0),
  );

  @override
  bool operator ==(Object other) =>
      other is BizPeriod && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// Debit and credit totals for one ledger over some window.
typedef DrCr = ({Money debit, Money credit});

/// One row of a ledger statement, with the running balance after it.
/// Balances are signed: positive = Dr, negative = Cr.
typedef BizStatementLine = ({
  BizVoucherRow voucher,
  String particulars,
  Money debit,
  Money credit,
  Money balance,
});

typedef BizLedgerStatement = ({
  Money opening,
  List<BizStatementLine> lines,
  Money totalDebit,
  Money totalCredit,
  Money closing,
});

/// A ledger and its signed closing balance (positive = Dr).
typedef BizLedgerBalance = ({BizLedgerRow ledger, Money balance});

/// One group on a report, with each ledger in it and the signed total.
class BizGroupTotal {
  BizGroupTotal(this.group, this.ledgers);
  final BizGroup group;
  final List<BizLedgerBalance> ledgers;
  Money get total => ledgers.fold(const Money.zero(), (s, l) => s + l.balance);
}

class BizTrialBalance {
  BizTrialBalance({
    required this.groups,
    required this.extraRows,
    required this.totalDebit,
    required this.totalCredit,
  });

  final List<BizGroupTotal> groups;

  /// Synthetic rows — opening stock, earlier-period profit, opening
  /// difference — that make the two columns agree, as Tally shows them.
  final List<({String label, Money balance})> extraRows;
  final Money totalDebit;
  final Money totalCredit;
  bool get balanced => totalDebit == totalCredit;
}

class BizProfitAndLoss {
  BizProfitAndLoss({
    required this.sales,
    required this.directIncome,
    required this.purchase,
    required this.directExpense,
    required this.indirectIncome,
    required this.indirectExpense,
    required this.openingStock,
    required this.closingStock,
  });

  /// Each group's ledgers, as positive amounts on their natural side
  /// (income as credit-positive, expenses as debit-positive).
  final BizGroupTotal sales;
  final BizGroupTotal directIncome;
  final BizGroupTotal purchase;
  final BizGroupTotal directExpense;
  final BizGroupTotal indirectIncome;
  final BizGroupTotal indirectExpense;
  final Money openingStock;
  final Money closingStock;

  Money get tradingCredit => sales.total + directIncome.total + closingStock;
  Money get tradingDebit => openingStock + purchase.total + directExpense.total;

  /// Negative = gross loss.
  Money get grossProfit => tradingCredit - tradingDebit;

  /// Negative = net loss.
  Money get netProfit =>
      grossProfit + indirectIncome.total - indirectExpense.total;
}

class BizBalanceSheet {
  BizBalanceSheet({
    required this.liabilities,
    required this.assets,
    required this.profitEarlier,
    required this.profitCurrent,
    required this.closingStock,
    required this.openingDifference,
  });

  /// Liability groups, shown credit-positive.
  final List<BizGroupTotal> liabilities;

  /// Asset groups, shown debit-positive.
  final List<BizGroupTotal> assets;

  final Money profitEarlier;
  final Money profitCurrent;
  final Money closingStock;

  /// Σ opening balances + opening stock. Non-zero means the opening entries
  /// don't balance — Tally's "Difference in opening balances". Positive is a
  /// net *debit* opening, shown on the liabilities side to balance it.
  final Money openingDifference;

  Money get totalLiabilities =>
      liabilities.fold(const Money.zero(), (s, g) => s + g.total) +
      profitEarlier +
      profitCurrent +
      (openingDifference.isPositive ? openingDifference : const Money.zero());

  Money get totalAssets =>
      assets.fold(const Money.zero(), (s, g) => s + g.total) +
      closingStock +
      (openingDifference.isNegative ? -openingDifference : const Money.zero());
}

typedef BizStockLine = ({
  BizItemRow item,
  double inQty,
  double outQty,
  double closingQty,
  Money avgCost,
  Money value,
});

/// A read-only snapshot of one company's books, with every report computed
/// from it in plain Dart — no SQL — so each one is trivial to test and the
/// UI can't drift from the numbers.
class BizBook {
  BizBook({
    required this.company,
    required List<BizLedgerRow> ledgers,
    required List<BizVoucherRow> vouchers,
    required List<BizVoucherLineRow> lines,
    required this.items,
    required List<BizVoucherItemRow> voucherItems,
  }) : ledgers = [...ledgers]..sort(_byName),
       vouchers = [...vouchers]..sort(_byDateThenNumber) {
    for (final l in this.ledgers) {
      ledgerById[l.id] = l;
    }
    for (final v in this.vouchers) {
      voucherById[v.id] = v;
    }
    for (final line in lines) {
      (linesByVoucher[line.voucherId] ??= []).add(line);
    }
    for (final vi in voucherItems) {
      (itemsByVoucher[vi.voucherId] ??= []).add(vi);
    }
  }

  static int _byName(BizLedgerRow a, BizLedgerRow b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  static int _byDateThenNumber(BizVoucherRow a, BizVoucherRow b) {
    final d = a.date.compareTo(b.date);
    return d != 0 ? d : a.id.compareTo(b.id);
  }

  final BizCompanyRow company;
  final List<BizLedgerRow> ledgers;
  final List<BizVoucherRow> vouchers;
  final List<BizItemRow> items;
  final Map<int, BizLedgerRow> ledgerById = {};
  final Map<int, BizVoucherRow> voucherById = {};
  final Map<int, List<BizVoucherLineRow>> linesByVoucher = {};
  final Map<int, List<BizVoucherItemRow>> itemsByVoucher = {};

  BizLedgerRow? ledgerByKey(String key) {
    for (final l in ledgers) {
      if (l.systemKey == key) return l;
    }
    return null;
  }

  List<BizVoucherLineRow> linesOf(int voucherId) =>
      linesByVoucher[voucherId] ?? const [];

  /// The voucher's value — its debit total (which equals its credit total).
  Money voucherAmount(int voucherId) =>
      linesOf(voucherId).fold(const Money.zero(), (s, l) => s + l.debit);

  /// Short "who/what" for a voucher: the first ledger that is not cash/bank,
  /// falling back to the first line's ledger.
  String voucherTitle(BizVoucherRow v) {
    final lines = linesOf(v.id);
    for (final l in lines) {
      final ledger = ledgerById[l.ledgerId];
      if (ledger != null && !ledger.ledgerGroup.isCashOrBank) {
        return ledger.name;
      }
    }
    return lines.isEmpty
        ? v.type.label
        : ledgerById[lines.first.ledgerId]?.name ?? '';
  }

  String voucherNumberLabel(BizVoucherRow v) => '${v.type.prefix}/${v.number}';

  /// Ledgers used most recently in vouchers, newest first, limited to
  /// [groups] (empty = any). Feeds the "Recently used" picks.
  List<int> recentLedgerIds({Set<BizGroup> groups = const {}, int limit = 4}) {
    final out = <int>[];
    for (final v in vouchers.reversed) {
      for (final l in linesOf(v.id)) {
        final ledger = ledgerById[l.ledgerId];
        if (ledger == null || out.contains(ledger.id)) continue;
        if (groups.isNotEmpty && !groups.contains(ledger.ledgerGroup)) continue;
        out.add(ledger.id);
        if (out.length == limit) return out;
      }
    }
    return out;
  }

  // ── Balances ──────────────────────────────────────────────────────────────

  DrCr _movement(int ledgerId, bool Function(DateTime) include) {
    var dr = 0, cr = 0;
    for (final v in vouchers) {
      if (!include(v.date)) continue;
      for (final l in linesOf(v.id)) {
        if (l.ledgerId != ledgerId) continue;
        dr += l.debit.paise;
        cr += l.credit.paise;
      }
    }
    return (debit: Money(dr), credit: Money(cr));
  }

  /// Signed closing balance as at the end of [period] (or all time).
  ///
  /// Balance-sheet ledgers carry forward forever: opening + every voucher up
  /// to the end. Profit & loss ledgers reset each period, so only vouchers
  /// inside it count.
  Money balanceOf(BizLedgerRow ledger, [BizPeriod? period]) {
    if (ledger.ledgerGroup.isBalanceSheet) {
      final mv = _movement(
        ledger.id,
        (d) => period == null || period.isOnOrBeforeEnd(d),
      );
      return ledger.openingBalance + mv.debit - mv.credit;
    }
    final mv = _movement(
      ledger.id,
      (d) => period == null || period.contains(d),
    );
    return mv.debit - mv.credit;
  }

  /// Every voucher line touching [ledger], with running balance.
  BizLedgerStatement statement(BizLedgerRow ledger, BizPeriod period) {
    var opening = const Money.zero();
    if (ledger.ledgerGroup.isBalanceSheet) {
      final before = _movement(ledger.id, period.isBeforeStart);
      opening = ledger.openingBalance + before.debit - before.credit;
    }
    var running = opening;
    var tDr = const Money.zero(), tCr = const Money.zero();
    final out = <BizStatementLine>[];
    for (final v in vouchers) {
      if (!period.contains(v.date)) continue;
      final lines = linesOf(v.id);
      for (final l in lines) {
        if (l.ledgerId != ledger.id) continue;
        running = running + l.debit - l.credit;
        tDr = tDr + l.debit;
        tCr = tCr + l.credit;
        out.add((
          voucher: v,
          particulars: _contraName(lines, l),
          debit: l.debit,
          credit: l.credit,
          balance: running,
        ));
      }
    }
    return (
      opening: opening,
      lines: out,
      totalDebit: tDr,
      totalCredit: tCr,
      closing: running,
    );
  }

  /// The "other side" of a line, as Tally prints it in Particulars.
  String _contraName(List<BizVoucherLineRow> lines, BizVoucherLineRow self) {
    final others = lines
        .where((l) => l.id != self.id && l.ledgerId != self.ledgerId)
        .where(
          (l) =>
              self.debit.isPositive ? l.credit.isPositive : l.debit.isPositive,
        )
        .toList();
    if (others.isEmpty) return '—';
    final first = ledgerById[others.first.ledgerId]?.name ?? '?';
    return others.length == 1 ? first : '$first (+${others.length - 1})';
  }

  BizGroupTotal _group(
    BizGroup g,
    BizPeriod period, {
    bool naturalSign = false,
  }) {
    final rows = <BizLedgerBalance>[];
    for (final l in ledgers) {
      if (l.ledgerGroup != g) continue;
      var b = balanceOf(l, period);
      if (naturalSign && !g.debitNature) b = -b;
      if (b.isZero && l.isArchived) continue;
      rows.add((ledger: l, balance: b));
    }
    return BizGroupTotal(g, rows);
  }

  /// Signed total of every P&L ledger's movement where [include] holds.
  Money _profitAndLossMovement(bool Function(DateTime) include) {
    var sum = 0;
    for (final v in vouchers) {
      if (!include(v.date)) continue;
      for (final l in linesOf(v.id)) {
        final ledger = ledgerById[l.ledgerId];
        if (ledger == null || !ledger.ledgerGroup.isProfitAndLoss) continue;
        sum += l.debit.paise - l.credit.paise;
      }
    }
    return Money(sum);
  }

  // ── Stock valuation ───────────────────────────────────────────────────────
  //
  // Two modes, like Tally. Once the company tracks items, stock is valued
  // automatically from them (weighted-average cost) at any date. Without
  // items, the user types opening/closing stock on the company.

  /// True when stock is valued from items rather than typed in.
  bool get tracksInventory => items.any((i) => !i.isArchived);

  /// Stock on hand when the books began.
  Money get openingStockAtStart => tracksInventory
      ? items
            .where((i) => !i.isArchived)
            .fold(
              const Money.zero(),
              (s, i) =>
                  s + Money((i.openingQty * i.purchasePrice.paise).round()),
            )
      : company.openingStock;

  /// Stock value at the end of [day].
  Money stockValueAt(DateTime day) => stockSummary(
    BizPeriod(day, day),
  ).fold(const Money.zero(), (s, l) => s + l.value);

  /// Opening stock for [period] — the stock on hand the day before it.
  Money openingStockFor(BizPeriod period) => tracksInventory
      ? stockValueAt(period.from.subtract(const Duration(days: 1)))
      : company.openingStock;

  /// Closing stock for [period].
  Money closingStockFor(BizPeriod period) =>
      tracksInventory ? stockValueAt(period.to) : company.closingStock;

  /// Σ every ledger's opening balance plus opening stock. Zero when the
  /// opening position balances.
  Money get openingDifference =>
      ledgers.fold(const Money.zero(), (s, l) => s + l.openingBalance) +
      openingStockAtStart;

  // ── Reports ───────────────────────────────────────────────────────────────

  BizTrialBalance trialBalance(BizPeriod period) {
    final groups = [
      for (final g in BizGroup.values) _group(g, period),
    ].where((g) => g.ledgers.any((l) => !l.balance.isZero)).toList();
    for (final g in groups) {
      g.ledgers.removeWhere((l) => l.balance.isZero);
    }

    final extras = <({String label, Money balance})>[];
    final openingStock = openingStockFor(period);
    if (!openingStock.isZero) {
      extras.add((label: 'Opening Stock', balance: openingStock));
    }
    // Earlier periods' P&L, including the stock they consumed — so that
    // with this period's opening stock the columns still agree.
    final earlier =
        _profitAndLossMovement(period.isBeforeStart) +
        openingStockAtStart -
        openingStock;
    if (!earlier.isZero) {
      extras.add((
        label: 'Profit & Loss A/c (earlier periods)',
        balance: earlier,
      ));
    }
    final diff = openingDifference;
    if (!diff.isZero) {
      extras.add((label: 'Difference in opening balances', balance: -diff));
    }

    var dr = 0, cr = 0;
    void add(Money b) => b.isNegative ? cr -= b.paise : dr += b.paise;
    for (final g in groups) {
      for (final l in g.ledgers) {
        add(l.balance);
      }
    }
    for (final e in extras) {
      add(e.balance);
    }
    return BizTrialBalance(
      groups: groups,
      extraRows: extras,
      totalDebit: Money(dr),
      totalCredit: Money(cr),
    );
  }

  BizProfitAndLoss profitAndLoss(BizPeriod period) => BizProfitAndLoss(
    sales: _group(BizGroup.sales, period, naturalSign: true),
    directIncome: _group(BizGroup.directIncome, period, naturalSign: true),
    purchase: _group(BizGroup.purchase, period, naturalSign: true),
    directExpense: _group(BizGroup.directExpense, period, naturalSign: true),
    indirectIncome: _group(BizGroup.indirectIncome, period, naturalSign: true),
    indirectExpense: _group(
      BizGroup.indirectExpense,
      period,
      naturalSign: true,
    ),
    openingStock: openingStockFor(period),
    closingStock: closingStockFor(period),
  );

  BizBalanceSheet balanceSheet(BizPeriod period) {
    final liabilities = <BizGroupTotal>[];
    final assets = <BizGroupTotal>[];
    for (final g in BizGroup.values) {
      if (!g.isBalanceSheet) continue;
      final total = _group(g, period, naturalSign: true);
      total.ledgers.removeWhere((l) => l.balance.isZero);
      if (total.ledgers.isEmpty) continue;
      (g.nature == BizNature.liability ? liabilities : assets).add(total);
    }
    return BizBalanceSheet(
      liabilities: liabilities,
      assets: assets,
      profitEarlier:
          -_profitAndLossMovement(period.isBeforeStart) -
          openingStockAtStart +
          openingStockFor(period),
      profitCurrent: profitAndLoss(period).netProfit,
      closingStock: closingStockFor(period),
      openingDifference: openingDifference,
    );
  }

  /// Parties with money due. Receivables are debit balances (they owe you),
  /// payables credit balances (you owe them) — whichever group the party
  /// sits in, since a customer can also end up in credit.
  ({List<BizLedgerBalance> receivables, List<BizLedgerBalance> payables})
  outstanding([BizPeriod? period]) {
    final rec = <BizLedgerBalance>[], pay = <BizLedgerBalance>[];
    for (final l in ledgers) {
      if (!l.ledgerGroup.isParty) continue;
      final b = balanceOf(l, period);
      if (b.isPositive) rec.add((ledger: l, balance: b));
      if (b.isNegative) pay.add((ledger: l, balance: -b));
    }
    int desc(BizLedgerBalance a, BizLedgerBalance b) =>
        b.balance.compareTo(a.balance);
    return (receivables: rec..sort(desc), payables: pay..sort(desc));
  }

  /// GST collected on sales vs paid on purchases inside [period]. Net
  /// positive = payable to the government.
  ({Money output, Money input, Money net}) gstSummary(BizPeriod period) {
    Money mv(String key, {required bool creditPositive}) {
      final l = ledgerByKey(key);
      if (l == null) return const Money.zero();
      final m = _movement(l.id, period.contains);
      return creditPositive ? m.credit - m.debit : m.debit - m.credit;
    }

    final out = mv(BizSystemKey.gstOut, creditPositive: true);
    final inp = mv(BizSystemKey.gstIn, creditPositive: false);
    return (output: out, input: inp, net: out - inp);
  }

  /// Stock on hand per item, valued at weighted-average purchase cost.
  List<BizStockLine> stockSummary([BizPeriod? period]) {
    final inQty = <int, double>{}, outQty = <int, double>{};
    final buyQty = <int, double>{}, buyValue = <int, int>{};
    for (final v in vouchers) {
      if (period != null && !period.isOnOrBeforeEnd(v.date)) continue;
      for (final vi in itemsByVoucher[v.id] ?? const <BizVoucherItemRow>[]) {
        switch (v.type) {
          case BizVoucherType.purchase:
            inQty[vi.itemId] = (inQty[vi.itemId] ?? 0) + vi.qty;
            buyQty[vi.itemId] = (buyQty[vi.itemId] ?? 0) + vi.qty;
            buyValue[vi.itemId] = (buyValue[vi.itemId] ?? 0) + vi.amount.paise;
          case BizVoucherType.creditNote: // sales return — goods come back
            inQty[vi.itemId] = (inQty[vi.itemId] ?? 0) + vi.qty;
          case BizVoucherType.sales:
          case BizVoucherType.debitNote: // purchase return — goods go out
            outQty[vi.itemId] = (outQty[vi.itemId] ?? 0) + vi.qty;
          default:
            break;
        }
      }
    }
    return [
      for (final item in items.where((i) => !i.isArchived))
        () {
          final iIn = inQty[item.id] ?? 0;
          final iOut = outQty[item.id] ?? 0;
          final closing = item.openingQty + iIn - iOut;
          final costQty = item.openingQty + (buyQty[item.id] ?? 0);
          final costValue =
              item.openingQty * item.purchasePrice.paise +
              (buyValue[item.id] ?? 0);
          final avg = costQty > 0
              ? Money((costValue / costQty).round())
              : item.purchasePrice;
          return (
            item: item,
            inQty: iIn,
            outQty: iOut,
            closingQty: closing,
            avgCost: avg,
            value: Money((avg.paise * (closing > 0 ? closing : 0)).round()),
          );
        }(),
    ];
  }

  Money get stockValue =>
      stockSummary().fold(const Money.zero(), (s, l) => s + l.value);

  /// Every voucher line in [period] as CSV — one row per Dr/Cr leg, the
  /// shape an accountant can pivot or import into Tally / a spreadsheet.
  String dayBookCsv(BizPeriod period) {
    String esc(String? s) {
      final v = s ?? '';
      return v.contains(RegExp('[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
    }

    String amt(Money m) => m.isZero ? '' : (m.paise / 100).toStringAsFixed(2);
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    final b = StringBuffer(
      'Date,Voucher Type,Voucher No,Ledger,Group,Debit,Credit,Reference,Narration\n',
    );
    for (final v in vouchers) {
      if (!period.contains(v.date)) continue;
      for (final l in linesOf(v.id)) {
        final ledger = ledgerById[l.ledgerId];
        b.writeln(
          [
            day(v.date),
            v.type.label,
            voucherNumberLabel(v),
            esc(ledger?.name),
            esc(ledger?.ledgerGroup.label),
            amt(l.debit),
            amt(l.credit),
            esc(v.reference),
            esc(v.narration),
          ].join(','),
        );
      }
    }
    return b.toString();
  }

  /// Sum of signed balances across every ledger in [groups].
  Money totalOf(Iterable<BizGroup> groups, [BizPeriod? period]) {
    final set = groups.toSet();
    return ledgers
        .where((l) => set.contains(l.ledgerGroup))
        .fold(const Money.zero(), (s, l) => s + balanceOf(l, period));
  }
}

/// Keys for the ledgers the app itself relies on.
abstract final class BizSystemKey {
  static const cash = 'cash';
  static const capital = 'capital';
  static const sales = 'sales';
  static const purchase = 'purchase';
  static const gstOut = 'gstOut';
  static const gstIn = 'gstIn';
}
