import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/money.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/money_text.dart';
import '../../data/business_tables.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import 'biz_book.dart';
import 'biz_entry_kinds.dart';
import 'biz_providers.dart';
import 'biz_repository.dart';
import 'biz_widgets.dart';
import 'day_book_screen.dart';
import 'items_screen.dart';
import 'ledgers_screen.dart';
import 'reports_screens.dart';
import 'voucher_entry_screen.dart';

/// XPENC Business — Tally-style books for a small business, built for a
/// phone: one tap from "what happened" (a sale, a loan, capital put in) to a
/// balanced voucher, and every Tally report a glance away.
class BusinessHomeScreen extends ConsumerWidget {
  const BusinessHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(activeBizCompanyProvider);
    return company.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$e')),
      ),
      data: (c) => c == null
          ? const CompanyFormScreen(firstRun: true)
          : const _BusinessDashboard(),
    );
  }
}

class _BusinessDashboard extends ConsumerWidget {
  const _BusinessDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(bizPeriodProvider);
    return BizBookGate(
      title: 'Business',
      builder: (context, book) {
        final theme = Theme.of(context);
        final cashBank = book.totalOf(const [BizGroup.cash, BizGroup.bank]);
        final pl = book.profitAndLoss(period);
        final out = book.outstanding();
        final receivable = out.receivables.fold(
          const Money.zero(),
          (s, l) => s + l.balance,
        );
        final payable = out.payables.fold(
          const Money.zero(),
          (s, l) => s + l.balance,
        );
        final capital = -book.totalOf(const [
          BizGroup.capital,
          BizGroup.reserves,
        ]);
        final loansTaken = -book.totalOf(const [BizGroup.securedLoans]);
        final loansGiven = book.totalOf(const [
          BizGroup.loansAdvances,
          BizGroup.deposits,
        ]);
        final investments = book.totalOf(const [BizGroup.investments]);
        final assets = book.totalOf(const [BizGroup.fixedAssets]);
        final expenses = pl.indirectExpense.total + pl.directExpense.total;
        final income = pl.indirectIncome.total + pl.directIncome.total;
        final recent = book.vouchers.reversed.take(6).toList();

        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showCompanySwitcher(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        book.company.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Export Day Book (CSV)',
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => _exportCsv(context, ref, book, period),
              ),
              IconButton(
                tooltip: 'Company settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => pushBizScreen(
                  context,
                  CompanyFormScreen(company: book.company),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showNewEntrySheet(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New entry'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 104),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: BizPeriodChip(),
                ),
              ),
              // ── Hero ──
              Card(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Column(
                    children: [
                      Text('Cash & Bank', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 4),
                      MoneyText(
                        cashBank,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _HeroStat(
                            label: pl.netProfit.isNegative
                                ? 'Net loss'
                                : 'Net profit',
                            amount: pl.netProfit.abs,
                            color: profitColor(pl.netProfit),
                            onTap: () => pushBizScreen(
                              context,
                              const ProfitLossScreen(),
                            ),
                          ),
                          _HeroStat(
                            label: 'To receive',
                            amount: receivable,
                            color: AppColors.income,
                            onTap: () => pushBizScreen(
                              context,
                              const OutstandingScreen(),
                            ),
                          ),
                          _HeroStat(
                            label: 'To pay',
                            amount: payable,
                            color: AppColors.expense,
                            onTap: () => pushBizScreen(
                              context,
                              const OutstandingScreen(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // ── Quick entries ──
              const BizSectionLabel('Quick entry'),
              SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final k in const [
                      BizEntryKind.sale,
                      BizEntryKind.purchase,
                      BizEntryKind.expense,
                      BizEntryKind.receiptFromParty,
                      BizEntryKind.paymentToParty,
                      BizEntryKind.capitalIn,
                      BizEntryKind.loanTaken,
                      BizEntryKind.investmentMade,
                    ])
                      _QuickChip(
                        icon: k.icon,
                        label: k.label,
                        onTap: () => openVoucherEntry(context, kind: k),
                      ),
                    _QuickChip(
                      icon: Icons.apps_rounded,
                      label: 'All entries',
                      onTap: () => showNewEntrySheet(context),
                    ),
                  ],
                ),
              ),
              // ── Position ──
              const BizSectionLabel('This period'),
              _StatGrid(
                stats: [
                  _Stat(
                    'Sales',
                    pl.sales.total,
                    Icons.point_of_sale_rounded,
                    () => pushBizScreen(context, const ProfitLossScreen()),
                  ),
                  _Stat(
                    'Purchases',
                    pl.purchase.total,
                    Icons.shopping_cart_outlined,
                    () => pushBizScreen(context, const ProfitLossScreen()),
                  ),
                  _Stat(
                    'Other income',
                    income,
                    Icons.south_west_rounded,
                    () => pushBizScreen(context, const ProfitLossScreen()),
                  ),
                  _Stat(
                    'Expenses',
                    expenses,
                    Icons.north_east_rounded,
                    () => pushBizScreen(context, const ProfitLossScreen()),
                  ),
                ],
              ),
              const BizSectionLabel('Capital, loans & assets'),
              _StatGrid(
                stats: [
                  _Stat(
                    'Capital invested',
                    capital,
                    Icons.account_balance_rounded,
                    () => pushBizScreen(
                      context,
                      const LedgersScreen(
                        title: 'Capital',
                        groups: [BizGroup.capital, BizGroup.reserves],
                      ),
                    ),
                  ),
                  _Stat(
                    'Loans taken',
                    loansTaken,
                    Icons.request_quote_outlined,
                    () => pushBizScreen(
                      context,
                      const LedgersScreen(
                        title: 'Loans taken',
                        groups: [BizGroup.securedLoans],
                      ),
                    ),
                  ),
                  _Stat(
                    'Loans given',
                    loansGiven,
                    Icons.volunteer_activism_outlined,
                    () => pushBizScreen(
                      context,
                      const LedgersScreen(
                        title: 'Loans & advances',
                        groups: [BizGroup.loansAdvances, BizGroup.deposits],
                      ),
                    ),
                  ),
                  _Stat(
                    'Investments',
                    investments,
                    Icons.trending_up_rounded,
                    () => pushBizScreen(
                      context,
                      const LedgersScreen(
                        title: 'Investments',
                        groups: [BizGroup.investments],
                      ),
                    ),
                  ),
                  _Stat(
                    'Fixed assets',
                    assets,
                    Icons.precision_manufacturing_outlined,
                    () => pushBizScreen(
                      context,
                      const LedgersScreen(
                        title: 'Fixed assets',
                        groups: [BizGroup.fixedAssets],
                      ),
                    ),
                  ),
                  _Stat(
                    'Stock value',
                    book.stockValue,
                    Icons.inventory_2_outlined,
                    () => pushBizScreen(context, const ItemsScreen()),
                  ),
                ],
              ),
              // ── Books & reports ──
              const BizSectionLabel('Books'),
              _MenuCard(
                items: [
                  _Menu(
                    Icons.receipt_long_outlined,
                    'Day Book',
                    'Every voucher, date-wise',
                    () => pushBizScreen(context, const DayBookScreen()),
                  ),
                  _Menu(
                    Icons.account_tree_outlined,
                    'Ledgers',
                    '${book.ledgers.where((l) => !l.isArchived).length} accounts under Tally groups',
                    () => pushBizScreen(context, const LedgersScreen()),
                  ),
                  _Menu(
                    Icons.groups_outlined,
                    'Parties',
                    'Customers & suppliers',
                    () => pushBizScreen(
                      context,
                      const LedgersScreen(
                        title: 'Parties',
                        groups: [
                          BizGroup.sundryDebtors,
                          BizGroup.sundryCreditors,
                        ],
                      ),
                    ),
                  ),
                  _Menu(
                    Icons.account_balance_wallet_outlined,
                    'Cash & Bank book',
                    'Running balance per account',
                    () => pushBizScreen(
                      context,
                      const LedgersScreen(
                        title: 'Cash & Bank',
                        groups: [BizGroup.cash, BizGroup.bank],
                      ),
                    ),
                  ),
                  _Menu(
                    Icons.inventory_2_outlined,
                    'Stock & items',
                    'Quantities and stock value',
                    () => pushBizScreen(context, const ItemsScreen()),
                  ),
                ],
              ),
              const BizSectionLabel('Reports'),
              _MenuCard(
                items: [
                  _Menu(
                    Icons.stacked_line_chart_rounded,
                    'Profit & Loss',
                    'Trading and P&L account',
                    () => pushBizScreen(context, const ProfitLossScreen()),
                  ),
                  _Menu(
                    Icons.balance_rounded,
                    'Balance Sheet',
                    'Liabilities vs assets',
                    () => pushBizScreen(context, const BalanceSheetScreen()),
                  ),
                  _Menu(
                    Icons.table_rows_outlined,
                    'Trial Balance',
                    'Every ledger, Dr and Cr',
                    () => pushBizScreen(context, const TrialBalanceScreen()),
                  ),
                  _Menu(
                    Icons.pending_actions_outlined,
                    'Outstanding',
                    'Receivables & payables',
                    () => pushBizScreen(context, const OutstandingScreen()),
                  ),
                  _Menu(
                    Icons.percent_rounded,
                    'GST summary',
                    'Output vs input tax',
                    () => pushBizScreen(context, const GstSummaryScreen()),
                  ),
                ],
              ),
              BizSectionLabel(
                'Recent vouchers',
                trailing: TextButton(
                  onPressed: () =>
                      pushBizScreen(context, const DayBookScreen()),
                  child: const Text('Day Book'),
                ),
              ),
              if (recent.isEmpty)
                BizEmpty(
                  icon: Icons.edit_note_rounded,
                  text:
                      'No entries yet. Start with the capital you put in, a loan, or your first sale.',
                  action: FilledButton.tonalIcon(
                    onPressed: () =>
                        openVoucherEntry(context, kind: BizEntryKind.capitalIn),
                    icon: const Icon(Icons.account_balance_rounded),
                    label: const Text('Record capital invested'),
                  ),
                )
              else
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < recent.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 72,
                            color: theme.colorScheme.outline,
                          ),
                        VoucherTile(book: book, voucher: recent[i]),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportCsv(
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
}

Future<void> _showCompanySwitcher(BuildContext context, WidgetRef ref) async {
  final picked = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => Consumer(
      builder: (context, ref, _) {
        final companies =
            ref.watch(bizCompaniesProvider).valueOrNull ?? const [];
        final active = ref.watch(activeBizCompanyProvider).valueOrNull;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Companies',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final c in companies)
                ListTile(
                  leading: Icon(
                    c.id == active?.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(c.name),
                  subtitle: c.gstin == null ? null : Text('GSTIN ${c.gstin}'),
                  onTap: () => Navigator.pop(sheet, c.id),
                ),
              ListTile(
                leading: const Icon(Icons.add_business_outlined),
                title: const Text('Create another company'),
                onTap: () => Navigator.pop(sheet, 'new'),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (!context.mounted) return;
  if (picked is int) {
    ref.read(bizPeriodOverrideProvider.notifier).state = null;
    await ref.read(dbProvider).setActiveBizCompany(picked);
  } else if (picked == 'new') {
    pushBizScreen(context, const CompanyFormScreen());
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.amount,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Money amount;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              const SizedBox(height: 2),
              MoneyText(
                amount,
                compact: true,
                color: color,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 86,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat {
  const _Stat(this.label, this.amount, this.icon, this.onTap);
  final String label;
  final Money amount;
  final IconData icon;
  final VoidCallback onTap;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});
  final List<_Stat> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth > 560 ? 3 : 2;
          final w = (c.maxWidth - (cols - 1) * 8) / cols;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in stats)
                SizedBox(
                  width: w,
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: s.onTap,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  s.icon,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    s.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            MoneyText(
                              s.amount,
                              compact: true,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Menu {
  const _Menu(this.icon, this.label, this.subtitle, this.onTap);
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.items});
  final List<_Menu> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 60, color: cs.outline),
            ListTile(
              leading: Icon(items[i].icon),
              title: Text(items[i].label),
              subtitle: Text(items[i].subtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: items[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Company setup ───────────────────────────────────────────────────────────

class CompanyFormScreen extends ConsumerStatefulWidget {
  const CompanyFormScreen({super.key, this.company, this.firstRun = false});
  final BizCompanyRow? company;
  final bool firstRun;

  @override
  ConsumerState<CompanyFormScreen> createState() => _CompanyFormScreenState();
}

class _CompanyFormScreenState extends ConsumerState<CompanyFormScreen> {
  late final _name = TextEditingController(text: widget.company?.name ?? '');
  late final _address = TextEditingController(
    text: widget.company?.address ?? '',
  );
  late final _phone = TextEditingController(text: widget.company?.phone ?? '');
  late final _gstin = TextEditingController(text: widget.company?.gstin ?? '');
  final _bank = TextEditingController();
  final _cash = TextEditingController();
  late int _fyStart = widget.company?.fyStartMonth ?? 4;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _gstin, _bank, _cash]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    final db = ref.read(dbProvider);
    String? n(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    if (widget.company == null) {
      await db.createBizCompany(
        name: name,
        address: _address.text,
        phone: _phone.text,
        gstin: _gstin.text,
        fyStartMonth: _fyStart,
        bankName: _bank.text,
        openingCash: parseMoney(_cash.text),
      );
      ref.read(bizPeriodOverrideProvider.notifier).state = null;
    } else {
      await db.updateBizCompany(
        widget.company!.copyWith(
          name: name,
          address: Value(n(_address)),
          phone: Value(n(_phone)),
          gstin: Value(n(_gstin)),
          fyStartMonth: _fyStart,
        ),
      );
    }
    if (!mounted) return;
    if (!widget.firstRun) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final c = widget.company!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text(
          'Every ledger, item and voucher in this company is permanently deleted. '
          'Your personal XPENC data is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete company'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(dbProvider).deleteBizCompany(c.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.company == null;
    final months = DateFormat.MMMM();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isNew
              ? (widget.firstRun ? 'XPENC Business' : 'New company')
              : 'Company',
        ),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'Delete company',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          if (widget.firstRun) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Keep your business books',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tally-style double-entry accounting on your phone: record capital invested, '
                      'loans, purchases, sales with GST, expenses and income — and get Day Book, '
                      'Ledgers, Profit & Loss, Balance Sheet, Trial Balance, Outstanding and Stock. '
                      'Separate from your personal money.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Business name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Address (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _gstin,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'GSTIN',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _fyStart,
            decoration: const InputDecoration(
              labelText: 'Financial year starts',
              border: OutlineInputBorder(),
            ),
            items: [
              for (var m = 1; m <= 12; m++)
                DropdownMenuItem(
                  value: m,
                  child: Text(months.format(DateTime(2000, m))),
                ),
            ],
            onChanged: (m) => setState(() => _fyStart = m ?? _fyStart),
          ),
          if (isNew) ...[
            const BizSectionLabel('Opening position (optional)'),
            BizAmountField(controller: _cash, label: 'Cash in hand today'),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
              child: Text(
                'Posted as cash brought in by the owner (capital). Add bank balances, '
                'loans and party balances later as ledger opening balances.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextField(
              controller: _bank,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Bank account name (optional)',
                hintText: 'e.g. HDFC Current A/c',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(isNew ? 'Create company' : 'Save'),
            ),
          ),
        ),
      ),
    );
  }
}
