import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/money_text.dart';
import '../../data/business_tables.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import 'biz_book.dart';
import 'biz_providers.dart';
import 'biz_repository.dart';

final bizDate = DateFormat('d MMM yyyy');
final bizShortDate = DateFormat('d MMM yy');

/// "₹1,200 Dr" / "₹300 Cr" — a signed balance, Tally-style.
String drCr(Money signed) {
  if (signed.isZero) return MoneyFormat.symbol(signed);
  return '${MoneyFormat.symbol(signed.abs)} ${signed.isNegative ? 'Cr' : 'Dr'}';
}

/// A signed balance as text, coloured only by side (Dr / Cr).
class DrCrText extends StatelessWidget {
  const DrCrText(this.signed, {this.style, super.key});
  final Money signed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final hidden = AmountVisibilityScope.of(context);
    CurrencyScope.depend(context);
    final base = (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );
    return Text(hidden ? '••••' : drCr(signed), style: base);
  }
}

String formatQty(double q) =>
    q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);

// ── Period ──────────────────────────────────────────────────────────────────

/// "Apr 26 – Mar 27" for whole months, "Jul 2026" for one month, otherwise
/// exact days — short enough for a chip on a 360dp phone.
String bizPeriodLabel(BizPeriod p) {
  final wholeMonths =
      p.from.day == 1 && DateTime(p.to.year, p.to.month, p.to.day + 1).day == 1;
  if (wholeMonths) {
    if (p.from.year == p.to.year && p.from.month == p.to.month) {
      return DateFormat('MMM yyyy').format(p.from);
    }
    final m = DateFormat('MMM yy');
    return '${m.format(p.from)} – ${m.format(p.to)}';
  }
  if (p.from == p.to) return bizDate.format(p.from);
  return '${bizShortDate.format(p.from)} – ${bizShortDate.format(p.to)}';
}

class BizPeriodChip extends ConsumerWidget {
  const BizPeriodChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(bizPeriodProvider);
    return ActionChip(
      avatar: const Icon(Icons.date_range_rounded, size: 18),
      label: Text(bizPeriodLabel(p)),
      onPressed: () => pickBizPeriod(context, ref),
    );
  }
}

Future<void> pickBizPeriod(BuildContext context, WidgetRef ref) async {
  final fyStart =
      ref.read(activeBizCompanyProvider).valueOrNull?.fyStartMonth ?? 4;
  final now = DateTime.now();
  final thisFy = BizPeriod.financialYear(now, fyStart);
  final lastFy = BizPeriod.financialYear(
    DateTime(thisFy.from.year, thisFy.from.month, 0),
    fyStart,
  );
  final options = <(String, BizPeriod?)>[
    ('This financial year', null),
    ('Last financial year', lastFy),
    ('This month', BizPeriod.month(now)),
    ('Last month', BizPeriod.month(DateTime(now.year, now.month, 0))),
    ('Today', BizPeriod(now, now)),
  ];
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, period) in options)
            ListTile(
              title: Text(label),
              subtitle: Text(() {
                final p = period ?? thisFy;
                return '${bizDate.format(p.from)} – ${bizDate.format(p.to)}';
              }()),
              onTap: () => Navigator.pop(context, period ?? 'fy'),
            ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('Custom range…'),
            onTap: () => Navigator.pop(context, 'custom'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final notifier = ref.read(bizPeriodOverrideProvider.notifier);
  if (choice == 'fy') {
    notifier.state = null;
  } else if (choice is BizPeriod) {
    notifier.state = choice;
  } else if (choice == 'custom') {
    final current = ref.read(bizPeriodProvider);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
    );
    if (range != null) notifier.state = BizPeriod(range.start, range.end);
  }
}

// ── Layout bits ─────────────────────────────────────────────────────────────

class BizSectionLabel extends StatelessWidget {
  const BizSectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class BizEmpty extends StatelessWidget {
  const BizEmpty({
    required this.icon,
    required this.text,
    super.key,
    this.action,
  });
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Shows [child] when the book is loaded, a prompt when there is no company.
class BizBookGate extends ConsumerWidget {
  const BizBookGate({required this.title, required this.builder, super.key});
  final String title;
  final Widget Function(BuildContext context, BizBook book) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bizBookProvider);
    return book.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text('Couldn’t load the books: $e')),
      ),
      data: (b) => b == null
          ? Scaffold(
              appBar: AppBar(title: Text(title)),
              body: const BizEmpty(
                icon: Icons.business_outlined,
                text: 'Create a company first.',
              ),
            )
          : builder(context, b),
    );
  }
}

/// A label-left, amount-right row used across every report.
class BizAmountRow extends StatelessWidget {
  const BizAmountRow({
    required this.label,
    required this.amount,
    super.key,
    this.bold = false,
    this.indent = 0,
    this.color,
    this.onTap,
    this.subtitle,
  });

  final String label;
  final Money amount;
  final bool bold;
  final double indent;
  final Color? color;
  final VoidCallback? onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        (bold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
            ?.copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16 + indent, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: style),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            MoneyText(amount, style: style, color: color),
          ],
        ),
      ),
    );
  }
}

/// A big titled figure — the head of each report.
class BizHeadline extends StatelessWidget {
  const BizHeadline({
    required this.label,
    required this.amount,
    super.key,
    this.color,
    this.footer,
  });
  final String label;
  final Money amount;
  final Color? color;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            MoneyText(
              amount,
              color: color,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 4),
              Text(
                footer!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Color profitColor(Money m) =>
    m.isNegative ? AppColors.expense : AppColors.income;

/// Amount input that accepts `1,250.50`.
class BizAmountField extends StatelessWidget {
  const BizAmountField({
    required this.controller,
    required this.label,
    super.key,
    this.onChanged,
    this.autofocus = false,
    this.large = false,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      onChanged: onChanged,
      style: large
          ? theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)
          : null,
      decoration: InputDecoration(
        labelText: label,
        prefixText: MoneyFormat.inputPrefix,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

Money parseMoney(String text) => Money.tryParse(text) ?? const Money.zero();

// ── Ledger picker & form ────────────────────────────────────────────────────

/// A tappable field showing the chosen ledger; opens [showLedgerPicker].
class LedgerPickerField extends ConsumerWidget {
  const LedgerPickerField({
    required this.label,
    required this.groups,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final List<BizGroup> groups;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bizBookProvider).valueOrNull;
    final ledger = value == null ? null : book?.ledgerById[value];
    final balance = ledger == null ? null : book!.balanceOf(ledger);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final id = await showLedgerPicker(
          context,
          ref,
          title: label,
          groups: groups,
        );
        if (id != null) onChanged(id);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.expand_more_rounded),
          helperText: ledger == null
              ? null
              : '${ledger.ledgerGroup.label}'
                    '${ledger.ledgerGroup.isProfitAndLoss ? '' : ' · Bal ${drCr(balance!)}'}',
        ),
        isEmpty: ledger == null,
        child: Text(
          ledger?.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Searchable ledger list limited to [groups] (empty = all), with an inline
/// "Create ledger" so a new party or head never needs a detour.
Future<int?> showLedgerPicker(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  List<BizGroup> groups = const [],
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _LedgerPickerSheet(title: title, groups: groups),
  );
}

class _LedgerPickerSheet extends ConsumerStatefulWidget {
  const _LedgerPickerSheet({required this.title, required this.groups});
  final String title;
  final List<BizGroup> groups;

  @override
  ConsumerState<_LedgerPickerSheet> createState() => _LedgerPickerSheetState();
}

class _LedgerPickerSheetState extends ConsumerState<_LedgerPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = ref.watch(bizBookProvider).valueOrNull;
    final allowed = widget.groups.toSet();
    final ledgers = (book?.ledgers ?? const <BizLedgerRow>[])
        .where((l) => !l.isArchived)
        .where((l) => allowed.isEmpty || allowed.contains(l.ledgerGroup))
        .where((l) => l.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final order = widget.groups.isEmpty ? BizGroup.values : widget.groups;
    ledgers.sort((a, b) {
      final g = order
          .indexOf(a.ledgerGroup)
          .compareTo(order.indexOf(b.ledgerGroup));
      return g != 0 ? g : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(widget.title, style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search ledgers',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline_rounded),
            title: Text(
              _query.trim().isEmpty
                  ? 'Create new ledger'
                  : 'Create “${_query.trim()}”',
            ),
            onTap: () async {
              final id = await showLedgerForm(
                context,
                ref,
                initialName: _query.trim(),
                allowedGroups: widget.groups,
              );
              if (id != null && context.mounted) Navigator.pop(context, id);
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: ledgers.length,
              itemBuilder: (context, i) {
                final l = ledgers[i];
                final showHeader =
                    i == 0 || ledgers[i - 1].ledgerGroup != l.ledgerGroup;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showHeader) BizSectionLabel(l.ledgerGroup.label),
                    ListTile(
                      title: Text(l.name),
                      trailing: l.ledgerGroup.isBalanceSheet
                          ? DrCrText(
                              book!.balanceOf(l),
                              style: theme.textTheme.bodySmall,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, l.id),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Create (or edit, given [ledger]) a ledger. Returns its id.
Future<int?> showLedgerForm(
  BuildContext context,
  WidgetRef ref, {
  BizLedgerRow? ledger,
  String initialName = '',
  List<BizGroup> allowedGroups = const [],
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _LedgerForm(
      ledger: ledger,
      initialName: initialName,
      allowedGroups: allowedGroups,
    ),
  );
}

class _LedgerForm extends ConsumerStatefulWidget {
  const _LedgerForm({
    required this.ledger,
    required this.initialName,
    required this.allowedGroups,
  });
  final BizLedgerRow? ledger;
  final String initialName;
  final List<BizGroup> allowedGroups;

  @override
  ConsumerState<_LedgerForm> createState() => _LedgerFormState();
}

class _LedgerFormState extends ConsumerState<_LedgerForm> {
  late final _name = TextEditingController(
    text: widget.ledger?.name ?? widget.initialName,
  );
  late final _opening = TextEditingController(
    text: widget.ledger == null || widget.ledger!.openingBalance.isZero
        ? ''
        : widget.ledger!.openingBalance.abs.rupees.toStringAsFixed(2),
  );
  late final _phone = TextEditingController(text: widget.ledger?.phone ?? '');
  late final _gstin = TextEditingController(text: widget.ledger?.gstin ?? '');
  late BizGroup _group =
      widget.ledger?.ledgerGroup ??
      (widget.allowedGroups.isNotEmpty
          ? widget.allowedGroups.first
          : BizGroup.sundryDebtors);
  late bool _openingIsDebit = widget.ledger == null
      ? _group.debitNature
      : !widget.ledger!.openingBalance.isNegative;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    _phone.dispose();
    _gstin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    final db = ref.read(dbProvider);
    final amount = _group.isBalanceSheet
        ? parseMoney(_opening.text)
        : const Money.zero();
    final signed = _openingIsDebit ? amount : -amount;
    int id;
    if (widget.ledger == null) {
      final company = ref.read(activeBizCompanyProvider).valueOrNull;
      if (company == null) return;
      id = await db.createBizLedger(
        companyId: company.id,
        name: name,
        group: _group,
        openingBalance: signed,
        phone: _phone.text,
        gstin: _gstin.text,
      );
    } else {
      id = widget.ledger!.id;
      String? n(String s) => s.trim().isEmpty ? null : s.trim();
      await db.updateBizLedger(
        widget.ledger!.copyWith(
          name: name,
          ledgerGroup: _group,
          openingBalance: signed,
          phone: Value(n(_phone.text)),
          gstin: Value(n(_gstin.text)),
        ),
      );
    }
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = widget.allowedGroups.isEmpty || widget.ledger != null
        ? BizGroup.values
        : widget.allowedGroups;
    if (!groups.contains(_group)) _group = groups.first;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom +
            16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.ledger == null ? 'New ledger' : 'Edit ledger',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.initialName.isEmpty && widget.ledger == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Ledger name',
                hintText: 'e.g. Asha Stores, HDFC Bank, SBI Loan',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BizGroup>(
              initialValue: _group,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Under group',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final g in groups)
                  DropdownMenuItem(value: g, child: Text(g.label)),
              ],
              onChanged: (g) => setState(() {
                _group = g ?? _group;
                if (widget.ledger == null) _openingIsDebit = _group.debitNature;
              }),
            ),
            if (_group.isBalanceSheet) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: BizAmountField(
                      controller: _opening,
                      label: 'Opening balance',
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: true, label: Text('Dr')),
                      ButtonSegment(value: false, label: Text('Cr')),
                    ],
                    selected: {_openingIsDebit},
                    onSelectionChanged: (s) =>
                        setState(() => _openingIsDebit = s.first),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  _openingIsDebit
                      ? 'Dr = you have it / they owe you'
                      : 'Cr = you owe it (capital, loans, suppliers)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (_group.isParty) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _gstin,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'GSTIN (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Save ledger'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
