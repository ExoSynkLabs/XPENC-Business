import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/money_text.dart';
import '../../data/business_tables.dart';
import '../../data/providers.dart';
import 'biz_book.dart';
import 'biz_providers.dart';
import 'biz_repository.dart';
import 'biz_widgets.dart';
import 'ledgers_screen.dart';

void pushBizScreen(BuildContext context, Widget screen) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(builder: (_) => screen));

/// Scaffold shared by every report: title, period chip, scrolling body.
class _ReportScaffold extends StatelessWidget {
  const _ReportScaffold({
    required this.title,
    required this.children,
    this.actions,
  });
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(alignment: Alignment.centerLeft, child: BizPeriodChip()),
        ),
        ...children,
      ],
    ),
  );
}

/// A card listing one group's ledgers with its total — tap a ledger to open it.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});
  final BizGroupTotal group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          BizAmountRow(
            label: group.group.label,
            amount: group.total,
            bold: true,
          ),
          // Zero rows are noise on a report; the group total still shows.
          for (final l in group.ledgers.where((l) => !l.balance.isZero))
            BizAmountRow(
              label: l.ledger.name,
              amount: l.balance,
              indent: 12,
              onTap: () => openLedger(context, l.ledger.id),
            ),
          if (group.ledgers.every((l) => l.balance.isZero))
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Nothing yet', style: theme.textTheme.bodySmall),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Profit & Loss ───────────────────────────────────────────────────────────

class ProfitLossScreen extends ConsumerWidget {
  const ProfitLossScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(bizPeriodProvider);
    return BizBookGate(
      title: 'Profit & Loss',
      builder: (context, book) {
        final pl = book.profitAndLoss(period);
        final net = pl.netProfit;
        final gross = pl.grossProfit;
        return _ReportScaffold(
          title: 'Profit & Loss',
          actions: [
            IconButton(
              tooltip: 'Stock values',
              icon: const Icon(Icons.inventory_outlined),
              onPressed: () => showStockValuesDialog(context, ref, book),
            ),
          ],
          children: [
            BizHeadline(
              label: net.isNegative ? 'Net loss' : 'Net profit',
              amount: net.abs,
              color: profitColor(net),
              footer:
                  'Gross ${gross.isNegative ? 'loss' : 'profit'} ${MoneyFormat.symbol(gross.abs)}',
            ),
            const BizSectionLabel('Trading account'),
            _GroupCard(group: pl.sales),
            if (pl.directIncome.ledgers.isNotEmpty)
              _GroupCard(group: pl.directIncome),
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  BizAmountRow(label: 'Opening stock', amount: pl.openingStock),
                  BizAmountRow(label: 'Closing stock', amount: pl.closingStock),
                ],
              ),
            ),
            _GroupCard(group: pl.purchase),
            if (pl.directExpense.ledgers.isNotEmpty)
              _GroupCard(group: pl.directExpense),
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: BizAmountRow(
                label: gross.isNegative ? 'Gross loss' : 'Gross profit',
                amount: gross.abs,
                bold: true,
                color: profitColor(gross),
              ),
            ),
            const BizSectionLabel('Profit & loss account'),
            _GroupCard(group: pl.indirectIncome),
            _GroupCard(group: pl.indirectExpense),
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: BizAmountRow(
                label: net.isNegative ? 'Net loss' : 'Net profit',
                amount: net.abs,
                bold: true,
                color: profitColor(net),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> showStockValuesDialog(
  BuildContext context,
  WidgetRef ref,
  BizBook book,
) async {
  if (book.tracksInventory) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stock values'),
        content: const Text(
          'This company tracks items, so opening and closing stock are '
          'valued automatically from Stock & items at weighted-average cost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }
  final opening = TextEditingController(
    text: book.company.openingStock.isZero
        ? ''
        : book.company.openingStock.rupees.toStringAsFixed(2),
  );
  final closing = TextEditingController(
    text: book.company.closingStock.isZero
        ? ''
        : book.company.closingStock.rupees.toStringAsFixed(2),
  );
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Stock values'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BizAmountField(controller: opening, label: 'Opening stock'),
          const SizedBox(height: 12),
          BizAmountField(controller: closing, label: 'Closing stock'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await ref
        .read(dbProvider)
        .setBizStock(
          companyId: book.company.id,
          openingStock: parseMoney(opening.text),
          closingStock: parseMoney(closing.text),
        );
  }
  opening.dispose();
  closing.dispose();
}

// ── Balance sheet ───────────────────────────────────────────────────────────

class BalanceSheetScreen extends ConsumerWidget {
  const BalanceSheetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(bizPeriodProvider);
    return BizBookGate(
      title: 'Balance Sheet',
      builder: (context, book) {
        final theme = Theme.of(context);
        final bs = book.balanceSheet(period);
        final balanced = bs.totalAssets == bs.totalLiabilities;
        return _ReportScaffold(
          title: 'Balance Sheet',
          children: [
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    _Side(label: 'Liabilities', amount: bs.totalLiabilities),
                    Container(
                      width: 1,
                      height: 40,
                      color: theme.colorScheme.outline,
                    ),
                    _Side(label: 'Assets', amount: bs.totalAssets),
                  ],
                ),
              ),
            ),
            if (!balanced)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Text(
                  'Sides differ by ${MoneyFormat.symbol((bs.totalAssets - bs.totalLiabilities).abs)}.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const BizSectionLabel('Liabilities'),
            for (final g in bs.liabilities) _GroupCard(group: g),
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  BizAmountRow(
                    label: 'Profit & Loss A/c',
                    amount: bs.profitEarlier + bs.profitCurrent,
                    bold: true,
                    color: profitColor(bs.profitEarlier + bs.profitCurrent),
                  ),
                  BizAmountRow(
                    label: 'Opening balance',
                    amount: bs.profitEarlier,
                    indent: 12,
                  ),
                  BizAmountRow(
                    label: 'Current period',
                    amount: bs.profitCurrent,
                    indent: 12,
                  ),
                  if (bs.openingDifference.isPositive)
                    BizAmountRow(
                      label: 'Difference in opening balances',
                      subtitle: 'Opening balances/stock not matched by capital',
                      amount: bs.openingDifference,
                      color: theme.colorScheme.error,
                    ),
                ],
              ),
            ),
            const BizSectionLabel('Assets'),
            for (final g in bs.assets) _GroupCard(group: g),
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  BizAmountRow(
                    label: 'Closing stock',
                    amount: bs.closingStock,
                    bold: true,
                  ),
                  if (bs.openingDifference.isNegative)
                    BizAmountRow(
                      label: 'Difference in opening balances',
                      subtitle: 'Opening balances/stock not matched by capital',
                      amount: -bs.openingDifference,
                      color: theme.colorScheme.error,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.label, required this.amount});
  final String label;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          MoneyText(
            amount,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Trial balance ───────────────────────────────────────────────────────────

class TrialBalanceScreen extends ConsumerWidget {
  const TrialBalanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(bizPeriodProvider);
    return BizBookGate(
      title: 'Trial Balance',
      builder: (context, book) {
        final theme = Theme.of(context);
        final tb = book.trialBalance(period);
        Widget row(
          String label,
          Money signed, {
          VoidCallback? onTap,
          bool bold = false,
          double indent = 12,
        }) {
          final style = bold
              ? theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                )
              : theme.textTheme.bodyMedium;
          return InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16 + indent, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: style)),
                  SizedBox(
                    width: 96,
                    child: signed.isPositive
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: MoneyText(signed, style: style),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: signed.isNegative
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: MoneyText(-signed, style: style),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          );
        }

        return _ReportScaffold(
          title: 'Trial Balance',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 16, 4),
              child: Row(
                children: [
                  const Expanded(child: Text('Particulars')),
                  SizedBox(
                    width: 96,
                    child: Text(
                      'Debit',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: Text(
                      'Credit',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final g in tb.groups) ...[
                    row(g.group.label, g.total, bold: true, indent: 0),
                    for (final l in g.ledgers)
                      row(
                        l.ledger.name,
                        l.balance,
                        onTap: () => openLedger(context, l.ledger.id),
                      ),
                  ],
                  for (final e in tb.extraRows)
                    row(e.label, e.balance, indent: 0),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Grand total',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 96,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: MoneyText(tb.totalDebit),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 96,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: MoneyText(tb.totalCredit),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    tb.balanced
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: tb.balanced
                        ? AppColors.income
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tb.balanced
                          ? 'Debits equal credits.'
                          : 'Totals don’t agree.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Outstanding ─────────────────────────────────────────────────────────────

class OutstandingScreen extends ConsumerWidget {
  const OutstandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BizBookGate(
      title: 'Outstanding',
      builder: (context, book) {
        final out = book.outstanding();
        final rec = out.receivables.fold(
          const Money.zero(),
          (s, l) => s + l.balance,
        );
        final pay = out.payables.fold(
          const Money.zero(),
          (s, l) => s + l.balance,
        );
        Widget list(List<BizLedgerBalance> rows, Color color) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (rows.isEmpty) const ListTile(title: Text('All settled')),
              for (final r in rows)
                ListTile(
                  title: Text(r.ledger.name),
                  subtitle: Text(
                    [
                      r.ledger.ledgerGroup.label,
                      if (r.ledger.phone != null) r.ledger.phone!,
                    ].join(' · '),
                  ),
                  trailing: MoneyText(
                    r.balance,
                    color: color,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => openLedger(context, r.ledger.id),
                ),
            ],
          ),
        );
        return Scaffold(
          appBar: AppBar(title: const Text('Outstanding')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              Card(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      _Side(label: 'To receive', amount: rec),
                      _Side(label: 'To pay', amount: pay),
                    ],
                  ),
                ),
              ),
              const BizSectionLabel('Receivables — they owe you'),
              list(out.receivables, AppColors.income),
              const BizSectionLabel('Payables — you owe them'),
              list(out.payables, AppColors.expense),
            ],
          ),
        );
      },
    );
  }
}

// ── GST ─────────────────────────────────────────────────────────────────────

class GstSummaryScreen extends ConsumerWidget {
  const GstSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(bizPeriodProvider);
    return BizBookGate(
      title: 'GST summary',
      builder: (context, book) {
        final theme = Theme.of(context);
        final g = book.gstSummary(period);
        final taxable = <BizVoucherType, Money>{};
        for (final v in book.vouchers.where((v) => period.contains(v.date))) {
          final isBill = const {
            BizVoucherType.sales,
            BizVoucherType.purchase,
            BizVoucherType.creditNote,
            BizVoucherType.debitNote,
          }.contains(v.type);
          if (!isBill) continue;
          for (final l in book.linesOf(v.id)) {
            final ledger = book.ledgerById[l.ledgerId];
            if (ledger == null) continue;
            final isBook =
                ledger.ledgerGroup == BizGroup.sales ||
                ledger.ledgerGroup == BizGroup.purchase ||
                ledger.ledgerGroup == BizGroup.directIncome ||
                ledger.ledgerGroup == BizGroup.directExpense;
            if (isBook) {
              taxable[v.type] =
                  (taxable[v.type] ?? const Money.zero()) + l.debit + l.credit;
            }
          }
        }
        return _ReportScaffold(
          title: 'GST summary',
          children: [
            BizHeadline(
              label: g.net.isNegative
                  ? 'Input credit carried forward'
                  : 'GST payable',
              amount: g.net.abs,
              color: g.net.isNegative ? AppColors.income : AppColors.expense,
              footer: 'Output GST − Input GST for the period',
            ),
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  BizAmountRow(
                    label: 'Output GST (on sales)',
                    amount: g.output,
                  ),
                  BizAmountRow(
                    label: 'Input GST (on purchases)',
                    amount: g.input,
                  ),
                  const Divider(height: 1),
                  BizAmountRow(label: 'Net', amount: g.net, bold: true),
                ],
              ),
            ),
            const BizSectionLabel('Taxable value'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (final t in const [
                    BizVoucherType.sales,
                    BizVoucherType.creditNote,
                    BizVoucherType.purchase,
                    BizVoucherType.debitNote,
                  ])
                    BizAmountRow(
                      label: t.label,
                      amount: taxable[t] ?? const Money.zero(),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'A summary for your own reference — not a GSTR filing. '
                'Check figures with your accountant before filing returns.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
