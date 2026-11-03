import '../../core/money.dart';
import 'biz_entry_kinds.dart';

/// One leg of a voucher before it is saved. Exactly one side is non-zero.
class BizLineDraft {
  const BizLineDraft({
    required this.ledgerId,
    this.debit = const Money.zero(),
    this.credit = const Money.zero(),
  });

  const BizLineDraft.dr(this.ledgerId, Money amount)
    : debit = amount,
      credit = const Money.zero();

  const BizLineDraft.cr(this.ledgerId, Money amount)
    : debit = const Money.zero(),
      credit = amount;

  final int ledgerId;
  final Money debit;
  final Money credit;

  @override
  String toString() => 'Line($ledgerId, Dr ${debit.paise}, Cr ${credit.paise})';
}

/// An item row on a bill before it is saved.
class BizItemLineDraft {
  const BizItemLineDraft({
    required this.itemId,
    required this.qty,
    required this.rate,
  });

  final int itemId;
  final double qty;
  final Money rate;

  Money get amount => Money((rate.paise * qty).round());
}

/// Why a set of lines can't be saved, or null when it can.
String? validateLines(List<BizLineDraft> lines) {
  final real = lines.where((l) => !l.debit.isZero || !l.credit.isZero).toList();
  if (real.length < 2) {
    return 'A voucher needs at least one debit and one credit.';
  }
  for (final l in real) {
    if (l.debit.isNegative || l.credit.isNegative) {
      return 'Amounts can’t be negative.';
    }
    if (!l.debit.isZero && !l.credit.isZero) {
      return 'A line is either debit or credit, not both.';
    }
  }
  final dr = real.fold(0, (s, l) => s + l.debit.paise);
  final cr = real.fold(0, (s, l) => s + l.credit.paise);
  if (dr == 0) return 'Enter an amount.';
  if (dr != cr) {
    return 'Debit (${MoneyFormat.symbol(Money(dr))}) and credit '
        '(${MoneyFormat.symbol(Money(cr))}) must be equal.';
  }
  return null;
}

/// The two legs of a [BizEntryShape.simple] entry.
List<BizLineDraft> simpleLines({
  required BizEntryKind kind,
  required int primaryLedgerId,
  required int secondaryLedgerId,
  required Money amount,
}) => kind.primaryIsDebit
    ? [
        BizLineDraft.dr(primaryLedgerId, amount),
        BizLineDraft.cr(secondaryLedgerId, amount),
      ]
    : [
        BizLineDraft.dr(secondaryLedgerId, amount),
        BizLineDraft.cr(primaryLedgerId, amount),
      ];

/// GST on [taxable] at [ratePct], rounded to the nearest paisa.
Money gstOn(Money taxable, double ratePct) =>
    Money((taxable.paise * ratePct / 100).round());

/// The legs of a bill (sale, purchase, and their returns).
///
/// - **Sale**: Dr party (total) · Cr sales (taxable) · Cr output GST
/// - **Purchase**: Dr purchase (taxable) · Dr input GST · Cr party (total)
/// - **Credit note** (sales return): the sale, reversed
/// - **Debit note** (purchase return): the purchase, reversed
List<BizLineDraft> invoiceLines({
  required BizEntryKind kind,
  required int partyLedgerId,
  required int bookLedgerId,
  required Money taxable,
  required Money gst,
  int? gstLedgerId,
}) {
  final total = taxable + gst;
  final hasGst = !gst.isZero && gstLedgerId != null;
  if (kind.partyIsDebit) {
    // Party debited; book ledger + GST credited.
    return [
      BizLineDraft.dr(partyLedgerId, hasGst ? total : taxable),
      BizLineDraft.cr(bookLedgerId, taxable),
      if (hasGst) BizLineDraft.cr(gstLedgerId, gst),
    ];
  }
  return [
    BizLineDraft.dr(bookLedgerId, taxable),
    if (hasGst) BizLineDraft.dr(gstLedgerId, gst),
    BizLineDraft.cr(partyLedgerId, hasGst ? total : taxable),
  ];
}
