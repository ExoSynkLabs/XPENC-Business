import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/money_text.dart';
import '../../data/business_tables.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import 'biz_book.dart';
import 'biz_providers.dart';
import 'biz_repository.dart';
import 'biz_widgets.dart';
import 'voucher_entry_screen.dart';

void openLedger(BuildContext context, int ledgerId) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => LedgerDetailScreen(ledgerId: ledgerId),
      ),
    );

/// Every ledger, grouped under its Tally group, with closing balances.
class LedgersScreen extends ConsumerStatefulWidget {
  const LedgersScreen({
    super.key,
    this.groups = const [],
    this.title = 'Ledgers',
  });

  /// Limit to these groups (e.g. only parties). Empty = all.
  final List<BizGroup> groups;
  final String title;

  @override
  ConsumerState<LedgersScreen> createState() => _LedgersScreenState();
}

class _LedgersScreenState extends ConsumerState<LedgersScreen> {
  String _query = '';
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(bizPeriodProvider);
    return BizBookGate(
      title: widget.title,
      builder: (context, book) {
        final theme = Theme.of(context);
        final allowed = widget.groups.toSet();
        final q = _query.toLowerCase();
        final groups = <BizGroup, List<BizLedgerRow>>{};
        for (final l in book.ledgers) {
          if (l.isArchived != _showArchived) continue;
          if (allowed.isNotEmpty && !allowed.contains(l.ledgerGroup)) continue;
          if (q.isNotEmpty && !l.name.toLowerCase().contains(q)) continue;
          (groups[l.ledgerGroup] ??= []).add(l);
        }
        final ordered = BizGroup.values.where(groups.containsKey).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            actions: [
              IconButton(
                tooltip: _showArchived ? 'Show active' : 'Show archived',
                icon: Icon(
                  _showArchived
                      ? Icons.unarchive_outlined
                      : Icons.inventory_2_outlined,
                ),
                onPressed: () => setState(() => _showArchived = !_showArchived),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () =>
                showLedgerForm(context, ref, allowedGroups: widget.groups),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ledger'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search ledgers',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (ordered.isEmpty)
                BizEmpty(
                  icon: Icons.account_tree_outlined,
                  text: _showArchived
                      ? 'No archived ledgers.'
                      : 'No ledgers match.',
                ),
              for (final g in ordered) ...[
                BizSectionLabel(
                  g.label,
                  trailing: DrCrText(
                    groups[g]!.fold(
                      const Money.zero(),
                      (s, l) => s + book.balanceOf(l, period),
                    ),
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < groups[g]!.length; i++) ...[
                        if (i > 0)
                          Divider(height: 1, color: theme.colorScheme.outline),
                        ListTile(
                          title: Text(groups[g]![i].name),
                          subtitle: groups[g]![i].phone == null
                              ? null
                              : Text(groups[g]![i].phone!),
                          trailing: DrCrText(
                            book.balanceOf(groups[g]![i], period),
                          ),
                          onTap: () => openLedger(context, groups[g]![i].id),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One ledger's account statement with running balance.
class LedgerDetailScreen extends ConsumerWidget {
  const LedgerDetailScreen({required this.ledgerId, super.key});
  final int ledgerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(bizPeriodProvider);
    return BizBookGate(
      title: 'Ledger',
      builder: (context, book) {
        final theme = Theme.of(context);
        final ledger = book.ledgerById[ledgerId];
        if (ledger == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const BizEmpty(
              icon: Icons.delete_outline,
              text: 'Ledger removed.',
            ),
          );
        }
        final st = book.statement(ledger, period);
        return Scaffold(
          appBar: AppBar(
            title: Text(ledger.name),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showLedgerForm(context, ref, ledger: ledger),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'delete') await _deleteLedger(context, ref, ledger);
                  if (v == 'restore') {
                    await ref
                        .read(dbProvider)
                        .updateBizLedger(ledger.copyWith(isArchived: false));
                  }
                },
                itemBuilder: (_) => [
                  if (ledger.isArchived)
                    const PopupMenuItem(
                      value: 'restore',
                      child: Text('Restore'),
                    )
                  else
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete / archive'),
                    ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(label: Text(ledger.ledgerGroup.label)),
                    const BizPeriodChip(),
                  ],
                ),
              ),
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Text(
                        'Closing balance',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      DrCrText(
                        st.closing,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _Mini(label: 'Opening', child: DrCrText(st.opening)),
                          _Mini(
                            label: 'Debit',
                            child: MoneyText(
                              st.totalDebit,
                              color: AppColors.income,
                            ),
                          ),
                          _Mini(
                            label: 'Credit',
                            child: MoneyText(
                              st.totalCredit,
                              color: AppColors.expense,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (st.lines.isEmpty)
                const BizEmpty(
                  icon: Icons.receipt_long_outlined,
                  text: 'No entries in this period.',
                )
              else
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = st.lines.length - 1; i >= 0; i--) ...[
                        if (i < st.lines.length - 1)
                          Divider(height: 1, color: theme.colorScheme.outline),
                        _StatementTile(book: book, line: st.lines[i]),
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

  Future<void> _deleteLedger(
    BuildContext context,
    WidgetRef ref,
    BizLedgerRow ledger,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${ledger.name}?'),
        content: const Text(
          'An unused ledger is deleted. One with entries is archived instead so '
          'past vouchers keep their names.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await ref
        .read(dbProvider)
        .deleteOrArchiveBizLedger(ledger.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(deleted ? 'Ledger deleted' : 'Ledger archived')),
    );
    if (deleted) Navigator.pop(context);
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        child,
      ],
    ),
  );
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({required this.book, required this.line});
  final BizBook book;
  final BizStatementLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDr = line.debit.isPositive;
    return ListTile(
      onTap: () => openVoucherEntry(context, voucherId: line.voucher.id),
      title: Text(
        line.particulars,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${bizShortDate.format(line.voucher.date)} · ${book.voucherNumberLabel(line.voucher)}'
        '${line.voucher.narration == null ? '' : ' · ${line.voucher.narration}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MoneyText(
                isDr ? line.debit : line.credit,
                color: isDr ? AppColors.income : AppColors.expense,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(isDr ? ' Dr' : ' Cr', style: theme.textTheme.labelSmall),
            ],
          ),
          DrCrText(line.balance, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
