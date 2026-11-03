import 'package:drift/drift.dart';

import '../../core/money.dart';
import '../../data/business_tables.dart';
import '../../data/database.dart';
import 'biz_book.dart';
import 'biz_posting.dart';

/// Everything a voucher needs to be saved (new or edited).
class BizVoucherDraft {
  const BizVoucherDraft({
    this.id,
    required this.companyId,
    required this.type,
    required this.date,
    required this.lines,
    this.items = const [],
    this.narration,
    this.reference,
    this.entryKind,
  });

  final int? id;
  final int companyId;
  final BizVoucherType type;
  final DateTime date;
  final List<BizLineDraft> lines;
  final List<BizItemLineDraft> items;
  final String? narration;
  final String? reference;
  final String? entryKind;
}

/// Ledgers every new company starts with, so the first entry needs no setup.
const _defaultLedgers = <(String, BizGroup, String?)>[
  ('Cash', BizGroup.cash, BizSystemKey.cash),
  ('Capital Account', BizGroup.capital, BizSystemKey.capital),
  ('Sales', BizGroup.sales, BizSystemKey.sales),
  ('Purchase', BizGroup.purchase, BizSystemKey.purchase),
  ('Output GST', BizGroup.dutiesTaxes, BizSystemKey.gstOut),
  ('Input GST', BizGroup.dutiesTaxes, BizSystemKey.gstIn),
  ('Freight Inward', BizGroup.directExpense, null),
  ('Wages', BizGroup.directExpense, null),
  ('Rent', BizGroup.indirectExpense, null),
  ('Salary', BizGroup.indirectExpense, null),
  ('Electricity', BizGroup.indirectExpense, null),
  ('Office Expenses', BizGroup.indirectExpense, null),
  ('Telephone & Internet', BizGroup.indirectExpense, null),
  ('Bank Charges', BizGroup.indirectExpense, null),
  ('Interest Paid', BizGroup.indirectExpense, null),
  ('Interest Received', BizGroup.indirectIncome, null),
  ('Commission Received', BizGroup.indirectIncome, null),
  ('Discount Received', BizGroup.indirectIncome, null),
];

/// Business Books persistence. An extension rather than more methods on
/// `AppDatabase` itself, so the personal ledger's 3,000-line class stays
/// about the personal ledger.
extension BizRepository on AppDatabase {
  // ── Companies ─────────────────────────────────────────────────────────────

  Stream<List<BizCompanyRow>> watchBizCompanies() => (select(
    bizCompanies,
  )..orderBy([(c) => OrderingTerm(expression: c.name)])).watch();

  /// The open company: the one Settings points at, else the first one.
  Stream<BizCompanyRow?> watchActiveBizCompany() {
    final query = customSelect('SELECT 1', readsFrom: {bizCompanies, settings});
    return query.watch().asyncMap((_) => activeBizCompany());
  }

  Future<BizCompanyRow?> activeBizCompany() async {
    final s = await select(settings).getSingleOrNull();
    final all = await (select(
      bizCompanies,
    )..orderBy([(c) => OrderingTerm(expression: c.id)])).get();
    if (all.isEmpty) return null;
    return all.firstWhere(
      (c) => c.id == s?.activeBizCompanyId,
      orElse: () => all.first,
    );
  }

  Future<void> setActiveBizCompany(int id) =>
      update(settings).write(SettingsCompanion(activeBizCompanyId: Value(id)));

  Future<int> createBizCompany({
    required String name,
    String? address,
    String? phone,
    String? gstin,
    int fyStartMonth = 4,
    String? bankName,
    Money openingCash = const Money.zero(),
  }) => transaction(() async {
    final id = await into(bizCompanies).insert(
      BizCompaniesCompanion.insert(
        name: name.trim(),
        address: Value(_blankToNull(address)),
        phone: Value(_blankToNull(phone)),
        gstin: Value(_blankToNull(gstin)),
        fyStartMonth: Value(fyStartMonth),
      ),
    );
    for (final (ledgerName, group, key) in _defaultLedgers) {
      await into(bizLedgers).insert(
        BizLedgersCompanion.insert(
          companyId: id,
          name: ledgerName,
          ledgerGroup: group,
          systemKey: Value(key),
          // Opening cash is the owner's capital — post both sides so the
          // opening position balances from day one.
          openingBalance: Value(switch (key) {
            BizSystemKey.cash => openingCash,
            BizSystemKey.capital => -openingCash,
            _ => const Money.zero(),
          }),
        ),
      );
    }
    final bank = _blankToNull(bankName);
    if (bank != null) {
      await into(bizLedgers).insert(
        BizLedgersCompanion.insert(
          companyId: id,
          name: bank,
          ledgerGroup: BizGroup.bank,
        ),
      );
    }
    await setActiveBizCompany(id);
    return id;
  });

  Future<void> updateBizCompany(BizCompanyRow company) =>
      update(bizCompanies).replace(company);

  Future<void> setBizStock({
    required int companyId,
    Money? openingStock,
    Money? closingStock,
  }) => (update(bizCompanies)..where((c) => c.id.equals(companyId))).write(
    BizCompaniesCompanion(
      openingStock: openingStock == null
          ? const Value.absent()
          : Value(openingStock),
      closingStock: closingStock == null
          ? const Value.absent()
          : Value(closingStock),
    ),
  );

  /// Deletes a company and **everything** in it.
  Future<void> deleteBizCompany(int id) => transaction(() async {
    final voucherIds = selectOnly(bizVouchers)
      ..addColumns([bizVouchers.id])
      ..where(bizVouchers.companyId.equals(id));
    await (delete(
      bizVoucherItems,
    )..where((t) => t.voucherId.isInQuery(voucherIds))).go();
    await (delete(
      bizVoucherLines,
    )..where((t) => t.voucherId.isInQuery(voucherIds))).go();
    await (delete(bizVouchers)..where((t) => t.companyId.equals(id))).go();
    await (delete(bizItems)..where((t) => t.companyId.equals(id))).go();
    await (delete(bizLedgers)..where((t) => t.companyId.equals(id))).go();
    await (delete(bizCompanies)..where((t) => t.id.equals(id))).go();
  });

  // ── Snapshot ──────────────────────────────────────────────────────────────

  Future<BizBook?> loadBizBook(int companyId) async {
    final company = await (select(
      bizCompanies,
    )..where((c) => c.id.equals(companyId))).getSingleOrNull();
    if (company == null) return null;
    final ledgers = await (select(
      bizLedgers,
    )..where((l) => l.companyId.equals(companyId))).get();
    final vouchers = await (select(
      bizVouchers,
    )..where((v) => v.companyId.equals(companyId))).get();
    final ids = vouchers.map((v) => v.id).toList();
    final lines = ids.isEmpty
        ? <BizVoucherLineRow>[]
        : await (select(
            bizVoucherLines,
          )..where((l) => l.voucherId.isIn(ids))).get();
    final items = await (select(
      bizItems,
    )..where((i) => i.companyId.equals(companyId))).get();
    final vItems = ids.isEmpty
        ? <BizVoucherItemRow>[]
        : await (select(
            bizVoucherItems,
          )..where((l) => l.voucherId.isIn(ids))).get();
    return BizBook(
      company: company,
      ledgers: ledgers,
      vouchers: vouchers,
      lines: lines,
      items: items,
      voucherItems: vItems,
    );
  }

  /// Re-emits a fresh [BizBook] whenever any business table changes.
  Stream<BizBook?> watchBizBook(int companyId) => customSelect(
    'SELECT 1',
    readsFrom: {
      bizCompanies,
      bizLedgers,
      bizItems,
      bizVouchers,
      bizVoucherLines,
      bizVoucherItems,
    },
  ).watch().asyncMap((_) => loadBizBook(companyId));

  // ── Ledgers ───────────────────────────────────────────────────────────────

  Future<int> createBizLedger({
    required int companyId,
    required String name,
    required BizGroup group,
    Money openingBalance = const Money.zero(),
    String? phone,
    String? gstin,
    String? note,
  }) => into(bizLedgers).insert(
    BizLedgersCompanion.insert(
      companyId: companyId,
      name: name.trim(),
      ledgerGroup: group,
      openingBalance: Value(openingBalance),
      phone: Value(_blankToNull(phone)),
      gstin: Value(_blankToNull(gstin)),
      note: Value(_blankToNull(note)),
    ),
  );

  Future<void> updateBizLedger(BizLedgerRow ledger) =>
      update(bizLedgers).replace(ledger);

  Future<bool> bizLedgerInUse(int ledgerId) async {
    final row =
        await (select(bizVoucherLines)
              ..where((l) => l.ledgerId.equals(ledgerId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Deletes an unused ledger, or archives one that vouchers still point at
  /// (history must keep its names). Returns true if it was deleted outright.
  Future<bool> deleteOrArchiveBizLedger(int ledgerId) async {
    if (await bizLedgerInUse(ledgerId)) {
      await (update(bizLedgers)..where((l) => l.id.equals(ledgerId))).write(
        const BizLedgersCompanion(isArchived: Value(true)),
      );
      return false;
    }
    await (delete(bizLedgers)..where((l) => l.id.equals(ledgerId))).go();
    return true;
  }

  /// The ledger with [key] in [companyId], created on first use.
  Future<int> ensureBizSystemLedger(int companyId, String key) async {
    final existing =
        await (select(bizLedgers)
              ..where(
                (l) => l.companyId.equals(companyId) & l.systemKey.equals(key),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    final (name, group) = switch (key) {
      BizSystemKey.gstOut => ('Output GST', BizGroup.dutiesTaxes),
      BizSystemKey.gstIn => ('Input GST', BizGroup.dutiesTaxes),
      BizSystemKey.sales => ('Sales', BizGroup.sales),
      BizSystemKey.purchase => ('Purchase', BizGroup.purchase),
      BizSystemKey.capital => ('Capital Account', BizGroup.capital),
      _ => ('Cash', BizGroup.cash),
    };
    return into(bizLedgers).insert(
      BizLedgersCompanion.insert(
        companyId: companyId,
        name: name,
        ledgerGroup: group,
        systemKey: Value(key),
      ),
    );
  }

  // ── Items ─────────────────────────────────────────────────────────────────

  Future<int> createBizItem({
    required int companyId,
    required String name,
    String unit = 'pcs',
    Money salePrice = const Money.zero(),
    Money purchasePrice = const Money.zero(),
    double gstRate = 0,
    double openingQty = 0,
  }) => into(bizItems).insert(
    BizItemsCompanion.insert(
      companyId: companyId,
      name: name.trim(),
      unit: Value(unit.trim().isEmpty ? 'pcs' : unit.trim()),
      salePrice: Value(salePrice),
      purchasePrice: Value(purchasePrice),
      gstRate: Value(gstRate),
      openingQty: Value(openingQty),
    ),
  );

  Future<void> updateBizItem(BizItemRow item) => update(bizItems).replace(item);

  Future<bool> deleteOrArchiveBizItem(int itemId) async {
    final used =
        await (select(bizVoucherItems)
              ..where((l) => l.itemId.equals(itemId))
              ..limit(1))
            .getSingleOrNull();
    if (used != null) {
      await (update(bizItems)..where((i) => i.id.equals(itemId))).write(
        const BizItemsCompanion(isArchived: Value(true)),
      );
      return false;
    }
    await (delete(bizItems)..where((i) => i.id.equals(itemId))).go();
    return true;
  }

  // ── Vouchers ──────────────────────────────────────────────────────────────

  Future<int> nextBizVoucherNumber(int companyId, BizVoucherType type) async {
    final maxExpr = bizVouchers.number.max();
    final row =
        await (selectOnly(bizVouchers)
              ..addColumns([maxExpr])
              ..where(
                bizVouchers.companyId.equals(companyId) &
                    bizVouchers.type.equalsValue(type),
              ))
            .getSingle();
    return (row.read(maxExpr) ?? 0) + 1;
  }

  /// Inserts or replaces a voucher with its lines and items, atomically.
  /// Throws [ArgumentError] if the lines don't balance.
  Future<int> saveBizVoucher(BizVoucherDraft draft) {
    final error = validateLines(draft.lines);
    if (error != null) throw ArgumentError(error);
    final day = DateTime(draft.date.year, draft.date.month, draft.date.day);
    return transaction(() async {
      int id;
      if (draft.id == null) {
        final number = await nextBizVoucherNumber(draft.companyId, draft.type);
        id = await into(bizVouchers).insert(
          BizVouchersCompanion.insert(
            companyId: draft.companyId,
            type: draft.type,
            number: number,
            date: day,
            narration: Value(_blankToNull(draft.narration)),
            reference: Value(_blankToNull(draft.reference)),
            entryKind: Value(draft.entryKind),
          ),
        );
      } else {
        id = draft.id!;
        final existing = await (select(
          bizVouchers,
        )..where((v) => v.id.equals(id))).getSingle();
        // Changing type moves the voucher into the other type's numbering.
        final number = existing.type == draft.type
            ? existing.number
            : await nextBizVoucherNumber(draft.companyId, draft.type);
        await (update(bizVouchers)..where((v) => v.id.equals(id))).write(
          BizVouchersCompanion(
            type: Value(draft.type),
            number: Value(number),
            date: Value(day),
            narration: Value(_blankToNull(draft.narration)),
            reference: Value(_blankToNull(draft.reference)),
            entryKind: Value(draft.entryKind),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await (delete(
          bizVoucherLines,
        )..where((l) => l.voucherId.equals(id))).go();
        await (delete(
          bizVoucherItems,
        )..where((l) => l.voucherId.equals(id))).go();
      }
      for (final l in draft.lines) {
        if (l.debit.isZero && l.credit.isZero) continue;
        await into(bizVoucherLines).insert(
          BizVoucherLinesCompanion.insert(
            voucherId: id,
            ledgerId: l.ledgerId,
            debit: Value(l.debit),
            credit: Value(l.credit),
          ),
        );
      }
      for (final it in draft.items) {
        if (it.qty == 0) continue;
        await into(bizVoucherItems).insert(
          BizVoucherItemsCompanion.insert(
            voucherId: id,
            itemId: it.itemId,
            qty: it.qty,
            rate: it.rate,
            amount: it.amount,
          ),
        );
      }
      return id;
    });
  }

  Future<void> deleteBizVoucher(int id) => transaction(() async {
    await (delete(bizVoucherItems)..where((l) => l.voucherId.equals(id))).go();
    await (delete(bizVoucherLines)..where((l) => l.voucherId.equals(id))).go();
    await (delete(bizVouchers)..where((v) => v.id.equals(id))).go();
  });
}

String? _blankToNull(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}
