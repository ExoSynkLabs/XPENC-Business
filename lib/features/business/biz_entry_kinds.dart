import 'package:flutter/material.dart';

import '../../data/business_tables.dart';

/// How a quick entry is laid out on screen.
enum BizEntryShape {
  /// Two ledgers and an amount: one debited, one credited.
  simple,

  /// A sales / purchase style bill: party, items or amount, GST.
  invoice,

  /// Free debit/credit lines (Tally's Journal).
  journal,
}

/// A friendly, plain-language way to post a voucher — "Loan taken",
/// "Capital invested" — so nobody has to know which side is debit.
///
/// For [BizEntryShape.simple] kinds, [primary] is the ledger the entry is
/// *about* (the lender, the expense head, the asset) and [secondary] is where
/// the money moved (usually cash/bank). [primaryIsDebit] says which side the
/// primary ledger lands on.
class BizEntryKind {
  const BizEntryKind({
    required this.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.type,
    required this.section,
    this.shape = BizEntryShape.simple,
    this.primaryLabel = '',
    this.primaryGroups = const [],
    this.primaryIsDebit = true,
    this.secondaryLabel = '',
    this.secondaryGroups = const [],
  });

  final String key;
  final String label;
  final String hint;
  final IconData icon;
  final BizVoucherType type;
  final String section;
  final BizEntryShape shape;

  final String primaryLabel;
  final List<BizGroup> primaryGroups;
  final bool primaryIsDebit;
  final String secondaryLabel;
  final List<BizGroup> secondaryGroups;

  /// Invoice kinds: does the party *receive* the goods (sale / purchase
  /// return) — so it is debited?
  bool get partyIsDebit =>
      type == BizVoucherType.sales || type == BizVoucherType.debitNote;

  /// Invoice kinds: is this the sales side (sales / credit note) rather than
  /// the purchase side?
  bool get isSalesSide =>
      type == BizVoucherType.sales || type == BizVoucherType.creditNote;

  static BizEntryKind? byKey(String? key) {
    for (final k in all) {
      if (k.key == key) return k;
    }
    return null;
  }

  /// The kind a voucher should reopen with when it has no stored entryKind.
  static BizEntryKind fallbackFor(BizVoucherType type) => switch (type) {
    BizVoucherType.sales => sale,
    BizVoucherType.purchase => purchase,
    BizVoucherType.creditNote => salesReturn,
    BizVoucherType.debitNote => purchaseReturn,
    _ => journal,
  };

  static const _cashBank = [BizGroup.cash, BizGroup.bank];
  static const _billParty = [
    BizGroup.sundryDebtors,
    BizGroup.sundryCreditors,
    BizGroup.cash,
    BizGroup.bank,
  ];

  // ── Trading ───────────────────────────────────────────────────────────────

  static const sale = BizEntryKind(
    key: 'sale',
    label: 'Sale',
    hint: 'Sell goods or services — cash or on credit',
    icon: Icons.point_of_sale_rounded,
    type: BizVoucherType.sales,
    section: 'Trading',
    shape: BizEntryShape.invoice,
    primaryLabel: 'Customer / received in',
    primaryGroups: [
      BizGroup.sundryDebtors,
      BizGroup.cash,
      BizGroup.bank,
      BizGroup.sundryCreditors,
    ],
    secondaryLabel: 'Sales ledger',
    secondaryGroups: [BizGroup.sales, BizGroup.directIncome],
  );

  static const purchase = BizEntryKind(
    key: 'purchase',
    label: 'Purchase',
    hint: 'Buy stock or materials — cash or on credit',
    icon: Icons.shopping_cart_outlined,
    type: BizVoucherType.purchase,
    section: 'Trading',
    shape: BizEntryShape.invoice,
    primaryLabel: 'Supplier / paid from',
    primaryGroups: [
      BizGroup.sundryCreditors,
      BizGroup.cash,
      BizGroup.bank,
      BizGroup.sundryDebtors,
    ],
    secondaryLabel: 'Purchase ledger',
    secondaryGroups: [BizGroup.purchase, BizGroup.directExpense],
  );

  static const salesReturn = BizEntryKind(
    key: 'salesReturn',
    label: 'Sales return',
    hint: 'Customer returned goods (Credit Note)',
    icon: Icons.assignment_return_outlined,
    type: BizVoucherType.creditNote,
    section: 'Trading',
    shape: BizEntryShape.invoice,
    primaryLabel: 'Customer / refunded from',
    primaryGroups: _billParty,
    secondaryLabel: 'Sales ledger',
    secondaryGroups: [BizGroup.sales],
  );

  static const purchaseReturn = BizEntryKind(
    key: 'purchaseReturn',
    label: 'Purchase return',
    hint: 'Goods sent back to supplier (Debit Note)',
    icon: Icons.keyboard_return_rounded,
    type: BizVoucherType.debitNote,
    section: 'Trading',
    shape: BizEntryShape.invoice,
    primaryLabel: 'Supplier / refund received in',
    primaryGroups: [
      BizGroup.sundryCreditors,
      BizGroup.sundryDebtors,
      BizGroup.cash,
      BizGroup.bank,
    ],
    secondaryLabel: 'Purchase ledger',
    secondaryGroups: [BizGroup.purchase],
  );

  // ── Money in / out ────────────────────────────────────────────────────────

  static const income = BizEntryKind(
    key: 'income',
    label: 'Income',
    hint: 'Commission, interest, rent received…',
    icon: Icons.south_west_rounded,
    type: BizVoucherType.receipt,
    section: 'Money in & out',
    primaryLabel: 'Income head',
    primaryGroups: [BizGroup.indirectIncome, BizGroup.directIncome],
    primaryIsDebit: false,
    secondaryLabel: 'Received in',
    secondaryGroups: _cashBank,
  );

  static const expense = BizEntryKind(
    key: 'expense',
    label: 'Expense',
    hint: 'Rent, salary, electricity, freight…',
    icon: Icons.north_east_rounded,
    type: BizVoucherType.payment,
    section: 'Money in & out',
    primaryLabel: 'Expense head',
    primaryGroups: [BizGroup.indirectExpense, BizGroup.directExpense],
    secondaryLabel: 'Paid from',
    secondaryGroups: [BizGroup.cash, BizGroup.bank, BizGroup.sundryCreditors],
  );

  static const receiptFromParty = BizEntryKind(
    key: 'receiptFromParty',
    label: 'Receive payment',
    hint: 'A customer pays what they owe',
    icon: Icons.call_received_rounded,
    type: BizVoucherType.receipt,
    section: 'Money in & out',
    primaryLabel: 'Received from',
    primaryGroups: [BizGroup.sundryDebtors, BizGroup.sundryCreditors],
    primaryIsDebit: false,
    secondaryLabel: 'Received in',
    secondaryGroups: _cashBank,
  );

  static const paymentToParty = BizEntryKind(
    key: 'paymentToParty',
    label: 'Make payment',
    hint: 'Pay a supplier what you owe',
    icon: Icons.call_made_rounded,
    type: BizVoucherType.payment,
    section: 'Money in & out',
    primaryLabel: 'Paid to',
    primaryGroups: [BizGroup.sundryCreditors, BizGroup.sundryDebtors],
    secondaryLabel: 'Paid from',
    secondaryGroups: _cashBank,
  );

  static const contra = BizEntryKind(
    key: 'contra',
    label: 'Cash ↔ Bank',
    hint: 'Deposit or withdraw cash (Contra)',
    icon: Icons.swap_horiz_rounded,
    type: BizVoucherType.contra,
    section: 'Money in & out',
    primaryLabel: 'To',
    primaryGroups: _cashBank,
    secondaryLabel: 'From',
    secondaryGroups: _cashBank,
  );

  // ── Capital & loans ───────────────────────────────────────────────────────

  static const capitalIn = BizEntryKind(
    key: 'capitalIn',
    label: 'Capital invested',
    hint: 'Owner puts money into the business',
    icon: Icons.account_balance_rounded,
    type: BizVoucherType.receipt,
    section: 'Capital & loans',
    primaryLabel: 'Capital account',
    primaryGroups: [BizGroup.capital],
    primaryIsDebit: false,
    secondaryLabel: 'Received in',
    secondaryGroups: _cashBank,
  );

  static const drawings = BizEntryKind(
    key: 'drawings',
    label: 'Drawings',
    hint: 'Owner takes money out for personal use',
    icon: Icons.person_remove_alt_1_outlined,
    type: BizVoucherType.payment,
    section: 'Capital & loans',
    primaryLabel: 'Capital / drawings account',
    primaryGroups: [BizGroup.capital],
    secondaryLabel: 'Paid from',
    secondaryGroups: _cashBank,
  );

  static const loanTaken = BizEntryKind(
    key: 'loanTaken',
    label: 'Loan taken',
    hint: 'Borrow from a bank, NBFC or person',
    icon: Icons.request_quote_outlined,
    type: BizVoucherType.receipt,
    section: 'Capital & loans',
    primaryLabel: 'Lender (loan account)',
    primaryGroups: [BizGroup.securedLoans, BizGroup.currentLiabilities],
    primaryIsDebit: false,
    secondaryLabel: 'Received in',
    secondaryGroups: _cashBank,
  );

  static const loanRepaid = BizEntryKind(
    key: 'loanRepaid',
    label: 'Loan repaid / EMI',
    hint: 'Pay back principal on a loan',
    icon: Icons.price_check_rounded,
    type: BizVoucherType.payment,
    section: 'Capital & loans',
    primaryLabel: 'Lender (loan account)',
    primaryGroups: [BizGroup.securedLoans, BizGroup.currentLiabilities],
    secondaryLabel: 'Paid from',
    secondaryGroups: _cashBank,
  );

  static const loanGiven = BizEntryKind(
    key: 'loanGiven',
    label: 'Loan given',
    hint: 'Lend money or pay an advance',
    icon: Icons.volunteer_activism_outlined,
    type: BizVoucherType.payment,
    section: 'Capital & loans',
    primaryLabel: 'Borrower',
    primaryGroups: [BizGroup.loansAdvances, BizGroup.deposits],
    secondaryLabel: 'Paid from',
    secondaryGroups: _cashBank,
  );

  static const loanRecovered = BizEntryKind(
    key: 'loanRecovered',
    label: 'Loan recovered',
    hint: 'Borrower pays you back',
    icon: Icons.assignment_turned_in_outlined,
    type: BizVoucherType.receipt,
    section: 'Capital & loans',
    primaryLabel: 'Borrower',
    primaryGroups: [BizGroup.loansAdvances, BizGroup.deposits],
    primaryIsDebit: false,
    secondaryLabel: 'Received in',
    secondaryGroups: _cashBank,
  );

  // ── Assets & investments ──────────────────────────────────────────────────

  static const investmentMade = BizEntryKind(
    key: 'investmentMade',
    label: 'Investment made',
    hint: 'FD, shares, mutual funds, gold…',
    icon: Icons.trending_up_rounded,
    type: BizVoucherType.payment,
    section: 'Assets & investments',
    primaryLabel: 'Investment',
    primaryGroups: [BizGroup.investments, BizGroup.deposits],
    secondaryLabel: 'Paid from',
    secondaryGroups: _cashBank,
  );

  static const investmentRedeemed = BizEntryKind(
    key: 'investmentRedeemed',
    label: 'Investment redeemed',
    hint: 'Sell or mature an investment',
    icon: Icons.trending_down_rounded,
    type: BizVoucherType.receipt,
    section: 'Assets & investments',
    primaryLabel: 'Investment',
    primaryGroups: [BizGroup.investments, BizGroup.deposits],
    primaryIsDebit: false,
    secondaryLabel: 'Received in',
    secondaryGroups: _cashBank,
  );

  static const assetBought = BizEntryKind(
    key: 'assetBought',
    label: 'Asset bought',
    hint: 'Machinery, furniture, computer, vehicle',
    icon: Icons.precision_manufacturing_outlined,
    type: BizVoucherType.payment,
    section: 'Assets & investments',
    primaryLabel: 'Asset',
    primaryGroups: [BizGroup.fixedAssets],
    secondaryLabel: 'Paid from',
    secondaryGroups: [BizGroup.cash, BizGroup.bank, BizGroup.sundryCreditors],
  );

  // ── Advanced ──────────────────────────────────────────────────────────────

  static const journal = BizEntryKind(
    key: 'journal',
    label: 'Journal',
    hint: 'Any adjustment — free Dr/Cr lines',
    icon: Icons.menu_book_outlined,
    type: BizVoucherType.journal,
    section: 'Advanced',
    shape: BizEntryShape.journal,
  );

  static const all = [
    sale,
    purchase,
    salesReturn,
    purchaseReturn,
    income,
    expense,
    receiptFromParty,
    paymentToParty,
    contra,
    capitalIn,
    drawings,
    loanTaken,
    loanRepaid,
    loanGiven,
    loanRecovered,
    investmentMade,
    investmentRedeemed,
    assetBought,
    journal,
  ];

  /// [all], in display order, grouped by [section].
  static Map<String, List<BizEntryKind>> get bySection {
    final out = <String, List<BizEntryKind>>{};
    for (final k in all) {
      (out[k.section] ??= []).add(k);
    }
    return out;
  }
}
