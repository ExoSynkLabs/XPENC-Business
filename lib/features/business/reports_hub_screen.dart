import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/money.dart';
import '../../core/widgets/money_text.dart';
import '../../data/business_tables.dart';
import '../../data/providers.dart';
import 'biz_book.dart';
import 'biz_providers.dart';
import 'biz_widgets.dart';
import 'day_book_screen.dart';
import 'items_screen.dart';
import 'ledgers_screen.dart';
import 'reports_screens.dart';

/// The Reports tab — every statement a glance away, with the headline
/// figures right on the tiles for the chosen period.
class ReportsHubScreen extends ConsumerWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(bizPeriodProvider);
    return BizBookGate(
      title: 'Reports',
      builder: (context, book) {
        final pl = book.profitAndLoss(period);
        final bs = book.balanceSheet(period);
        final tb = book.trialBalance(period);
        final out = book.outstanding();
        final rec = out.receivables.fold(
          const Money.zero(),
          (s, l) => s + l.balance,
        );
        final pay = out.payables.fold(
          const Money.zero(),
          (s, l) => s + l.balance,
        );
        final gst = book.gstSummary(period);
        final vouchers = book.vouchers
            .where((v) => period.contains(v.date))
            .length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Reports'),
            actions: [
              IconButton(
                tooltip: 'Export Day Book (CSV)',
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => exportDayBookCsv(context, ref, book, period),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: BizPeriodChip(),
                ),
              ),
              const BizSectionLabel('Financial statements'),
              _ReportCard(
                items: [
                  _Report(
                    Icons.stacked_line_chart_rounded,
                    'Profit & Loss',
                    pl.netProfit.isNegative ? 'Net loss' : 'Net profit',
                    pl.netProfit.abs,
                    profitColor(pl.netProfit),
                    () => pushBizScreen(context, const ProfitLossScreen()),
                  ),
                  _Report(
                    Icons.balance_rounded,
                    'Balance Sheet',
                    'Total assets',
                    bs.totalAssets,
                    null,
                    () => pushBizScreen(context, const BalanceSheetScreen()),
                  ),
                  _Report(
                    Icons.table_rows_outlined,
                    'Trial Balance',
                    tb.balanced ? 'Balanced' : 'Not balanced',
                    tb.totalDebit,
                    null,
                    () => pushBizScreen(context, const TrialBalanceScreen()),
                  ),
                ],
              ),
              const BizSectionLabel('Money owed'),
              _ReportCard(
                items: [
                  _Report(
                    Icons.call_received_rounded,
                    'Receivables',
                    _parties(out.receivables.length),
                    rec,
                    null,
                    () => pushBizScreen(context, const OutstandingScreen()),
                  ),
                  _Report(
                    Icons.call_made_rounded,
                    'Payables',
                    _parties(out.payables.length),
                    pay,
                    null,
                    () => pushBizScreen(context, const OutstandingScreen()),
                  ),
                  _Report(
                    Icons.percent_rounded,
                    'GST summary',
                    gst.net.isNegative ? 'Input credit' : 'GST payable',
                    gst.net.abs,
                    null,
                    () => pushBizScreen(context, const GstSummaryScreen()),
                  ),
                ],
              ),
              const BizSectionLabel('Books'),
              _ReportCard(
                items: [
                  _Report(
                    Icons.receipt_long_outlined,
                    'Day Book',
                    '$vouchers vouchers',
                    null,
                    null,
                    () => pushBizScreen(context, const DayBookScreen()),
                  ),
                  _Report(
                    Icons.account_tree_outlined,
                    'Ledgers',
                    'Statement of any account',
                    null,
                    null,
                    () => pushBizScreen(context, const LedgersScreen()),
                  ),
                  _Report(
                    Icons.account_balance_wallet_outlined,
                    'Cash & Bank book',
                    'Cash and bank balance',
                    book.totalOf(const [BizGroup.cash, BizGroup.bank]),
                    null,
                    () => pushBizScreen(
                      context,
                      const LedgersScreen(
                        title: 'Cash & Bank',
                        groups: [BizGroup.cash, BizGroup.bank],
                      ),
                    ),
                  ),
                  _Report(
                    Icons.inventory_2_outlined,
                    'Stock summary',
                    'Stock value',
                    book.stockValue,
                    null,
                    () => pushBizScreen(context, const ItemsScreen()),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

String _parties(int n) => n == 1 ? '1 party' : '$n parties';

/// Writes the period's Day Book as CSV and hands it to the share sheet.
Future<void> exportDayBookCsv(
  BuildContext context,
  WidgetRef ref,
  BizBook book,
  BizPeriod period,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
    final safe = book.company.name.replaceAll(RegExp('[^A-Za-z0-9]+'), '-');
    final file = File('${dir.path}/xpenc-business-$safe-$stamp.csv');
    await file.writeAsString(book.dayBookCsv(period), flush: true);
    await ref
        .read(backupServiceProvider)
        .share(file, subject: '${book.company.name} — Day Book');
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Couldn’t export: $e')));
  }
}

class _Report {
  const _Report(
    this.icon,
    this.title,
    this.caption,
    this.amount,
    this.color,
    this.onTap,
  );
  final IconData icon;
  final String title;
  final String caption;
  final Money? amount;
  final Color? color;
  final VoidCallback onTap;
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.items});
  final List<_Report> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 60, color: theme.colorScheme.outline),
            ListTile(
              leading: Icon(items[i].icon),
              title: Text(items[i].title),
              subtitle: Text(items[i].caption),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (items[i].amount != null)
                    MoneyText(
                      items[i].amount!,
                      compact: true,
                      color: items[i].color,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              onTap: items[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}
