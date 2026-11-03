import 'package:drift/drift.dart';

import 'tables.dart' show MoneyConverter;

// ─── Business Books (Tally-style double-entry) ──────────────────────────────
//
// A self-contained bookkeeping module for a small business, modelled on how
// Tally works: a *company* owns *ledgers*, every ledger sits under one fixed
// *group* (Capital Account, Loans, Sundry Debtors, Sales Accounts, ...), and
// every money event is a *voucher* whose debit lines equal its credit lines.
//
// It deliberately shares nothing with the personal ledger (`Accounts` /
// `Transactions`): a business's capital, loans and stock follow double-entry
// rules the personal model was never meant to carry, and keeping the two
// apart means neither can corrupt the other's invariants.

/// The fixed chart of groups every ledger belongs to — Tally's primary groups,
/// trimmed to the ones a small business actually uses.
///
/// Each group knows which statement it lands on and its *nature*: an asset or
/// expense group normally carries a **debit** balance, a liability or income
/// group normally carries a **credit** balance.
enum BizGroup {
  // Balance sheet — liabilities (credit nature)
  capital('Capital Account', BizNature.liability),
  reserves('Reserves & Surplus', BizNature.liability),
  securedLoans('Loans (Liability)', BizNature.liability),
  sundryCreditors('Sundry Creditors', BizNature.liability),
  dutiesTaxes('Duties & Taxes', BizNature.liability),
  currentLiabilities('Current Liabilities', BizNature.liability),
  provisions('Provisions', BizNature.liability),

  // Balance sheet — assets (debit nature)
  fixedAssets('Fixed Assets', BizNature.asset),
  investments('Investments', BizNature.asset),
  sundryDebtors('Sundry Debtors', BizNature.asset),
  loansAdvances('Loans & Advances (Asset)', BizNature.asset),
  deposits('Deposits (Asset)', BizNature.asset),
  bank('Bank Accounts', BizNature.asset),
  cash('Cash-in-Hand', BizNature.asset),
  currentAssets('Current Assets', BizNature.asset),

  // Profit & loss — trading account
  sales('Sales Accounts', BizNature.income),
  directIncome('Direct Incomes', BizNature.income),
  purchase('Purchase Accounts', BizNature.expense),
  directExpense('Direct Expenses', BizNature.expense),

  // Profit & loss — P&L account
  indirectIncome('Indirect Incomes', BizNature.income),
  indirectExpense('Indirect Expenses', BizNature.expense);

  const BizGroup(this.label, this.nature);

  final String label;
  final BizNature nature;

  bool get isBalanceSheet =>
      nature == BizNature.asset || nature == BizNature.liability;
  bool get isProfitAndLoss => !isBalanceSheet;

  /// Sales/purchase and their direct incomes/expenses feed *gross* profit
  /// (Tally's Trading Account); indirect ones only feed *net* profit.
  bool get isTrading =>
      this == sales ||
      this == directIncome ||
      this == purchase ||
      this == directExpense;

  /// Cash and bank — the ledgers money can physically be paid from.
  bool get isCashOrBank => this == cash || this == bank;

  /// Parties you trade with on credit.
  bool get isParty => this == sundryDebtors || this == sundryCreditors;

  /// True when a positive (debit) balance is this group's normal side.
  bool get debitNature =>
      nature == BizNature.asset || nature == BizNature.expense;
}

enum BizNature { asset, liability, income, expense }

/// Tally's voucher types. Each keeps its own running number per company.
enum BizVoucherType {
  sales('Sales', 'SAL'),
  purchase('Purchase', 'PUR'),
  receipt('Receipt', 'RCT'),
  payment('Payment', 'PMT'),
  contra('Contra', 'CON'),
  journal('Journal', 'JRN'),
  creditNote('Credit Note', 'CRN'),
  debitNote('Debit Note', 'DRN');

  const BizVoucherType(this.label, this.prefix);
  final String label;
  final String prefix;
}

/// Lifecycle of a booking. Only [enquiry] and [cancelled] leave the
/// resource free for someone else.
enum BizBookingStatus {
  enquiry('Enquiry'),
  tentative('Tentative'),
  confirmed('Confirmed'),
  completed('Completed'),
  cancelled('Cancelled');

  const BizBookingStatus(this.label);
  final String label;

  /// Does this booking hold its resources (block double-booking)?
  bool get blocks =>
      this == tentative || this == confirmed || this == completed;
}

/// One business — Tally's "company". Every ledger, item and voucher belongs
/// to exactly one, so a user can keep several businesses side by side.
@DataClassName('BizCompanyRow')
class BizCompanies extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get gstin => text().nullable()();

  /// Month the financial year starts in (1–12). India: April (4).
  IntColumn get fyStartMonth => integer().withDefault(const Constant(4))();

  /// Value of stock on hand when the books started (feeds the trading
  /// account's debit side).
  IntColumn get openingStock =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();

  /// Value of stock on hand now (feeds gross profit and the balance sheet).
  /// Entered by the user, or copied from the stock summary.
  IntColumn get closingStock =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();

  /// `BizBusinessType.name` — drives the bookings template and the wording
  /// across the module (Event / Show / Stay …). Text, not an enum column, so
  /// a type added later never breaks an older database.
  TextColumn get businessType =>
      text().withDefault(const Constant('general'))();

  /// The Bookings module is opt-in per company.
  BoolColumn get bookingsEnabled =>
      boolean().withDefault(const Constant(false))();

  /// JSON list of slot names ("Morning", "Evening", "Full day", "10:00 AM").
  TextColumn get bookingSlots => text().nullable()();

  /// JSON list of custom booking fields — see `BookingField`.
  TextColumn get bookingFields => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('BizLedgerRow')
class BizLedgers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(BizCompanies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get ledgerGroup => textEnum<BizGroup>()();

  /// Signed: positive = **Dr**, negative = **Cr**. Only meaningful for
  /// balance-sheet ledgers (P&L ledgers start every period at zero).
  IntColumn get openingBalance =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();

  /// Marks a ledger the app itself relies on (`cash`, `capital`, `sales`,
  /// `purchase`, `gstOut`, `gstIn`) so it can be found without matching on a
  /// name the user is free to rename.
  TextColumn get systemKey => text().nullable()();

  TextColumn get phone => text().nullable()();
  TextColumn get gstin => text().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A stock item (inventory). Quantities are plain doubles — kg, litres and
/// metres are fractional — but every *money* figure stays integer paise.
@DataClassName('BizItemRow')
class BizItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(BizCompanies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get unit => text().withDefault(const Constant('pcs'))();
  IntColumn get salePrice =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get purchasePrice =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  RealColumn get gstRate => real().withDefault(const Constant(0))();
  RealColumn get openingQty => real().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('BizVoucherRow')
class BizVouchers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(BizCompanies, #id)();
  TextColumn get type => textEnum<BizVoucherType>()();

  /// Running number within (company, type) — "SAL/12".
  IntColumn get number => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get narration => text().nullable()();

  /// Supplier's bill / customer invoice reference typed by the user.
  TextColumn get reference => text().nullable()();

  /// The quick-entry kind this voucher was made with (`sale`, `loanTaken`,
  /// ...), so editing reopens the same friendly form. Null = raw journal.
  TextColumn get entryKind => text().nullable()();

  /// The booking this voucher belongs to (an advance received, the final
  /// bill). Plain int, not a foreign key: deleting a booking keeps its money.
  IntColumn get bookingId => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// One debit or credit leg of a voucher. Exactly one of [debit] / [credit] is
/// non-zero, and a voucher's debits always sum to its credits.
@DataClassName('BizVoucherLineRow')
class BizVoucherLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get voucherId => integer().references(BizVouchers, #id)();
  IntColumn get ledgerId => integer().references(BizLedgers, #id)();
  IntColumn get debit =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get credit =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
}

/// Item rows on a sales / purchase / credit-note / debit-note voucher.
@DataClassName('BizVoucherItemRow')
class BizVoucherItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get voucherId => integer().references(BizVouchers, #id)();
  IntColumn get itemId => integer().references(BizItems, #id)();
  RealColumn get qty => real()();
  IntColumn get rate => integer().map(const MoneyConverter())();
  IntColumn get amount => integer().map(const MoneyConverter())();
}

// ─── Bookings ───────────────────────────────────────────────────────────────

/// Something that can be booked: a hall, a lawn, a screen, a room, a chair,
/// a court, a vehicle.
///
/// An **exclusive** resource is taken whole by one booking per slot (a hall).
/// A **shared** resource sells up to [capacity] units per slot (a cinema
/// screen's seats).
@DataClassName('BizBookingResourceRow')
class BizBookingResources extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(BizCompanies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 120)();

  /// Exclusive: guests it holds (a warning only). Shared: units on sale.
  IntColumn get capacity => integer().withDefault(const Constant(0))();
  BoolColumn get shared => boolean().withDefault(const Constant(false))();

  /// Default price — per day, per night, per seat or per booking, by type.
  IntColumn get rate =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get sort => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
}

@DataClassName('BizBookingRow')
class BizBookings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(BizCompanies, #id)();
  IntColumn get number => integer()();
  TextColumn get customerName => text().withLength(min: 1, max: 120)();
  TextColumn get phone => text().nullable()();

  /// "Sharma–Patil wedding", a movie name, … optional.
  TextColumn get title => text().nullable()();
  DateTimeColumn get startDate => dateTime()();

  /// Same as [startDate] for single-day bookings.
  DateTimeColumn get endDate => dateTime()();
  TextColumn get slot => text().withDefault(const Constant('Full day'))();
  TextColumn get status => textEnum<BizBookingStatus>()();

  /// Expected people / guests / adults.
  IntColumn get guests => integer().withDefault(const Constant(0))();
  IntColumn get totalAmount =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();

  /// The customer's ledger in the books, created on first payment.
  IntColumn get partyLedgerId => integer().nullable()();

  /// Values of the company's custom fields, as a JSON object.
  TextColumn get extra => text().withDefault(const Constant('{}'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// A resource taken by a booking — with how many units for a shared one.
@DataClassName('BizBookingLineRow')
class BizBookingLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookingId => integer().references(BizBookings, #id)();
  IntColumn get resourceId => integer().references(BizBookingResources, #id)();
  IntColumn get qty => integer().withDefault(const Constant(1))();
  IntColumn get rate =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get amount =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
}
