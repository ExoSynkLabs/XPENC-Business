import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/money_text.dart';
import '../../data/business_tables.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import 'biz_book.dart';
import 'biz_entry_kinds.dart';
import 'biz_posting.dart';
import 'biz_providers.dart';
import 'biz_repository.dart';
import 'biz_widgets.dart';
import 'items_screen.dart' show showItemForm;

/// Opens the right form for [kind] — or, given [voucherId], reopens an
/// existing voucher in the form it was made with.
Future<void> openVoucherEntry(
  BuildContext context, {
  BizEntryKind? kind,
  int? voucherId,
}) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute<void>(
    builder: (_) => VoucherEntryScreen(kind: kind, voucherId: voucherId),
  ),
);

class VoucherEntryScreen extends ConsumerWidget {
  const VoucherEntryScreen({super.key, this.kind, this.voucherId});
  final BizEntryKind? kind;
  final int? voucherId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read once: the form owns its state from here on, and a live book
    // rebuilding underneath would reset half-typed fields.
    return BizBookGate(
      title: kind?.label ?? 'Voucher',
      builder: (context, book) {
        final existing = voucherId == null ? null : book.voucherById[voucherId];
        final k =
            kind ??
            BizEntryKind.byKey(existing?.entryKind) ??
            BizEntryKind.fallbackFor(existing?.type ?? BizVoucherType.journal);
        return _VoucherForm(
          key: ValueKey('${k.key}-$voucherId'),
          kind: k,
          initialBook: book,
          existing: existing,
        );
      },
    );
  }
}

class _ItemRow {
  _ItemRow({this.itemId, String qty = '1', String rate = ''})
    : qty = TextEditingController(text: qty),
      rate = TextEditingController(text: rate);
  int? itemId;
  final TextEditingController qty;
  final TextEditingController rate;

  double get qtyValue => double.tryParse(qty.text.replaceAll(',', '')) ?? 0;
  Money get rateValue => parseMoney(rate.text);
  Money get amount => Money((rateValue.paise * qtyValue).round());

  void dispose() {
    qty.dispose();
    rate.dispose();
  }
}

class _JournalRow {
  _JournalRow({this.ledgerId, this.isDebit = true, String amount = ''})
    : amount = TextEditingController(text: amount);
  int? ledgerId;
  bool isDebit;
  final TextEditingController amount;
}

class _VoucherForm extends ConsumerStatefulWidget {
  const _VoucherForm({
    required this.kind,
    required this.initialBook,
    required this.existing,
    super.key,
  });
  final BizEntryKind kind;
  final BizBook initialBook;
  final BizVoucherRow? existing;

  @override
  ConsumerState<_VoucherForm> createState() => _VoucherFormState();
}

const _gstRates = [0.0, 5.0, 12.0, 18.0, 28.0];

class _VoucherFormState extends ConsumerState<_VoucherForm> {
  late BizEntryKind _kind = widget.kind;
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  final _amount = TextEditingController();
  final _narration = TextEditingController();
  final _reference = TextEditingController();
  int? _primary;
  int? _secondary;
  double _gstRate = 0;
  final List<_ItemRow> _items = [];
  final List<_JournalRow> _journal = [];
  bool _saving = false;

  BizBook get _book =>
      ref.read(bizBookProvider).valueOrNull ?? widget.initialBook;

  @override
  void initState() {
    super.initState();
    final v = widget.existing;
    if (v == null) {
      _applyDefaults();
    } else {
      _narration.text = v.narration ?? '';
      _reference.text = v.reference ?? '';
      if (!_loadExisting(v)) {
        _kind = BizEntryKind.journal;
        _loadJournal(v);
      }
    }
    if (_kind.shape == BizEntryShape.journal && _journal.isEmpty) {
      _journal
        ..add(_JournalRow(isDebit: true))
        ..add(_JournalRow(isDebit: false));
    }
  }

  void _applyDefaults() {
    final b = widget.initialBook;
    int? firstIn(List<BizGroup> groups, {String? preferKey}) {
      if (preferKey != null) {
        final l = b.ledgerByKey(preferKey);
        if (l != null && groups.contains(l.ledgerGroup) && !l.isArchived) {
          return l.id;
        }
      }
      for (final g in groups) {
        for (final l in b.ledgers) {
          if (l.ledgerGroup == g && !l.isArchived) return l.id;
        }
      }
      return null;
    }

    switch (_kind.shape) {
      case BizEntryShape.simple:
        if (_kind.primaryGroups.contains(BizGroup.capital)) {
          _primary = firstIn(
            _kind.primaryGroups,
            preferKey: BizSystemKey.capital,
          );
        }
        _secondary = firstIn(
          _kind.secondaryGroups,
          preferKey: BizSystemKey.cash,
        );
        if (_kind == BizEntryKind.contra) {
          // Default: cash deposited into the first bank.
          _secondary = firstIn([BizGroup.cash]);
          _primary = firstIn([BizGroup.bank]);
        }
      case BizEntryShape.invoice:
        _secondary = firstIn(
          _kind.secondaryGroups,
          preferKey: _kind.isSalesSide
              ? BizSystemKey.sales
              : BizSystemKey.purchase,
        );
      case BizEntryShape.journal:
        break;
    }
  }

  String _fmt(Money m) => m.isZero ? '' : m.rupees.toStringAsFixed(2);

  /// Rebuild the form from a saved voucher. False when its lines don't fit
  /// this kind's shape (then it opens as a raw journal instead).
  bool _loadExisting(BizVoucherRow v) {
    final b = widget.initialBook;
    final lines = b.linesOf(v.id);
    switch (_kind.shape) {
      case BizEntryShape.journal:
        _loadJournal(v);
        return true;
      case BizEntryShape.simple:
        final dr = lines.where((l) => l.debit.isPositive).toList();
        final cr = lines.where((l) => l.credit.isPositive).toList();
        if (dr.length != 1 || cr.length != 1) return false;
        _primary = _kind.primaryIsDebit
            ? dr.single.ledgerId
            : cr.single.ledgerId;
        _secondary = _kind.primaryIsDebit
            ? cr.single.ledgerId
            : dr.single.ledgerId;
        _amount.text = _fmt(dr.single.debit);
        return true;
      case BizEntryShape.invoice:
        bool isGst(BizVoucherLineRow l) {
          final key = b.ledgerById[l.ledgerId]?.systemKey;
          return key == BizSystemKey.gstOut || key == BizSystemKey.gstIn;
        }
        final partySide = lines
            .where(
              (l) =>
                  _kind.partyIsDebit ? l.debit.isPositive : l.credit.isPositive,
            )
            .toList();
        final bookSide = lines
            .where(
              (l) =>
                  _kind.partyIsDebit ? l.credit.isPositive : l.debit.isPositive,
            )
            .toList();
        final book = bookSide.where((l) => !isGst(l)).toList();
        final gst = bookSide.where(isGst).toList();
        if (partySide.length != 1 || book.length != 1 || gst.length > 1) {
          return false;
        }
        _primary = partySide.single.ledgerId;
        _secondary = book.single.ledgerId;
        final taxable = book.single.debit + book.single.credit;
        final tax = gst.isEmpty
            ? const Money.zero()
            : gst.single.debit + gst.single.credit;
        if (taxable.isPositive && tax.isPositive) {
          final rate = tax.paise * 100 / taxable.paise;
          _gstRate = _gstRates.firstWhere(
            (r) => (r - rate).abs() < 0.05,
            orElse: () => double.parse(rate.toStringAsFixed(2)),
          );
        }
        for (final vi
            in b.itemsByVoucher[v.id] ?? const <BizVoucherItemRow>[]) {
          _items.add(
            _ItemRow(
              itemId: vi.itemId,
              qty: formatQty(vi.qty),
              rate: vi.rate.rupees.toStringAsFixed(2),
            ),
          );
        }
        if (_items.isEmpty) _amount.text = _fmt(taxable);
        return true;
    }
  }

  void _loadJournal(BizVoucherRow v) {
    _journal.clear();
    for (final l in widget.initialBook.linesOf(v.id)) {
      _journal.add(
        _JournalRow(
          ledgerId: l.ledgerId,
          isDebit: l.debit.isPositive,
          amount: _fmt(l.debit.isPositive ? l.debit : l.credit),
        ),
      );
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _narration.dispose();
    _reference.dispose();
    for (final i in _items) {
      i.dispose();
    }
    for (final j in _journal) {
      j.amount.dispose();
    }
    super.dispose();
  }

  // ── Totals ────────────────────────────────────────────────────────────────

  Money get _taxable => _items.isEmpty
      ? parseMoney(_amount.text)
      : _items.fold(const Money.zero(), (s, i) => s + i.amount);
  Money get _gst => gstOn(_taxable, _gstRate);

  ({Money dr, Money cr}) get _journalTotals {
    var dr = 0, cr = 0;
    for (final j in _journal) {
      final a = parseMoney(j.amount.text).paise;
      j.isDebit ? dr += a : cr += a;
    }
    return (dr: Money(dr), cr: Money(cr));
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    void fail(String msg) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));

    final db = ref.read(dbProvider);
    final companyId = _book.company.id;
    List<BizLineDraft> lines;
    var items = <BizItemLineDraft>[];

    switch (_kind.shape) {
      case BizEntryShape.simple:
        if (_primary == null || _secondary == null) {
          return fail(
            'Choose both ${_kind.primaryLabel.toLowerCase()} and '
            '${_kind.secondaryLabel.toLowerCase()}.',
          );
        }
        if (_primary == _secondary) return fail('Pick two different ledgers.');
        final amount = parseMoney(_amount.text);
        if (!amount.isPositive) return fail('Enter an amount.');
        lines = simpleLines(
          kind: _kind,
          primaryLedgerId: _primary!,
          secondaryLedgerId: _secondary!,
          amount: amount,
        );
      case BizEntryShape.invoice:
        if (_primary == null) {
          return fail('Choose the ${_kind.primaryLabel.toLowerCase()}.');
        }
        if (_secondary == null) {
          return fail('Choose the ${_kind.secondaryLabel.toLowerCase()}.');
        }
        if (_items.any((i) => i.itemId == null)) {
          return fail('Pick an item on every row, or remove the empty row.');
        }
        final taxable = _taxable;
        if (!taxable.isPositive) return fail('Enter an amount or add items.');
        final gst = _gst;
        int? gstLedger;
        if (gst.isPositive) {
          gstLedger = await db.ensureBizSystemLedger(
            companyId,
            _kind.isSalesSide ? BizSystemKey.gstOut : BizSystemKey.gstIn,
          );
        }
        lines = invoiceLines(
          kind: _kind,
          partyLedgerId: _primary!,
          bookLedgerId: _secondary!,
          taxable: taxable,
          gst: gst,
          gstLedgerId: gstLedger,
        );
        items = [
          for (final i in _items)
            BizItemLineDraft(
              itemId: i.itemId!,
              qty: i.qtyValue,
              rate: i.rateValue,
            ),
        ];
      case BizEntryShape.journal:
        if (_journal.any(
          (j) => j.ledgerId == null && parseMoney(j.amount.text).isPositive,
        )) {
          return fail('Choose a ledger on every line with an amount.');
        }
        lines = [
          for (final j in _journal)
            if (j.ledgerId != null)
              j.isDebit
                  ? BizLineDraft.dr(j.ledgerId!, parseMoney(j.amount.text))
                  : BizLineDraft.cr(j.ledgerId!, parseMoney(j.amount.text)),
        ];
    }

    final error = validateLines(lines);
    if (error != null) return fail(error);

    setState(() => _saving = true);
    try {
      await db.saveBizVoucher(
        BizVoucherDraft(
          id: widget.existing?.id,
          companyId: companyId,
          type: _kind.type,
          date: _date,
          lines: lines,
          items: items,
          narration: _narration.text,
          reference: _reference.text,
          entryKind: _kind.key,
        ),
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${_kind.label} saved')));
      Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      fail('Couldn’t save: $e');
    }
  }

  Future<void> _delete() async {
    final v = widget.existing;
    if (v == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete voucher?'),
        content: Text(
          '${_book.voucherNumberLabel(v)} will be removed from every ledger and report.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(dbProvider).deleteBizVoucher(v.id);
    if (mounted) Navigator.pop(context);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = widget.existing;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          v == null ? _kind.label : 'Edit ${_book.voucherNumberLabel(v)}',
        ),
        actions: [
          if (v != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Card(
            child: ListTile(
              leading: Icon(_kind.icon),
              title: Text('${_kind.type.label} voucher'),
              subtitle: Text(_kind.hint),
            ),
          ),
          const SizedBox(height: 12),
          _DateField(date: _date, onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: 12),
          ...switch (_kind.shape) {
            BizEntryShape.simple => _simpleFields(),
            BizEntryShape.invoice => _invoiceFields(theme),
            BizEntryShape.journal => _journalFields(theme),
          },
          const SizedBox(height: 12),
          TextField(
            controller: _narration,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Narration (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                v == null
                    ? 'Save ${_kind.label.toLowerCase()}'
                    : 'Save changes',
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _simpleFields() => [
    LedgerPickerField(
      label: _kind.primaryLabel,
      groups: _kind.primaryGroups,
      value: _primary,
      onChanged: (id) => setState(() => _primary = id),
    ),
    const SizedBox(height: 16),
    LedgerPickerField(
      label: _kind.secondaryLabel,
      groups: _kind.secondaryGroups,
      value: _secondary,
      onChanged: (id) => setState(() => _secondary = id),
    ),
    const SizedBox(height: 16),
    BizAmountField(
      controller: _amount,
      label: 'Amount',
      large: true,
      autofocus: widget.existing == null,
    ),
  ];

  List<Widget> _invoiceFields(ThemeData theme) {
    final taxable = _taxable;
    final gst = _gst;
    return [
      LedgerPickerField(
        label: _kind.primaryLabel,
        groups: _kind.primaryGroups,
        value: _primary,
        onChanged: (id) => setState(() => _primary = id),
      ),
      const SizedBox(height: 16),
      LedgerPickerField(
        label: _kind.secondaryLabel,
        groups: _kind.secondaryGroups,
        value: _secondary,
        onChanged: (id) => setState(() => _secondary = id),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _reference,
        decoration: InputDecoration(
          labelText: _kind.isSalesSide
              ? 'Invoice no. (optional)'
              : 'Supplier bill no. (optional)',
          border: const OutlineInputBorder(),
        ),
      ),
      BizSectionLabel(
        'Items',
        trailing: TextButton.icon(
          onPressed: _addItemRow,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add item'),
        ),
      ),
      if (_items.isEmpty) ...[
        BizAmountField(
          controller: _amount,
          label: 'Amount (before GST)',
          large: true,
          onChanged: (_) => setState(() {}),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            'Or add items to track stock quantities.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ] else
        for (var i = 0; i < _items.length; i++) _itemRowCard(i),
      const SizedBox(height: 12),
      Text('GST rate', style: theme.textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final r in {..._gstRates, _gstRate})
            ChoiceChip(
              label: Text(r == 0 ? 'No GST' : '${formatQty(r)}%'),
              selected: _gstRate == r,
              onSelected: (_) => setState(() => _gstRate = r),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Card(
        child: Column(
          children: [
            BizAmountRow(label: 'Taxable value', amount: taxable),
            if (gst.isPositive)
              BizAmountRow(
                label: _kind.isSalesSide
                    ? 'Output GST ${formatQty(_gstRate)}%'
                    : 'Input GST ${formatQty(_gstRate)}%',
                amount: gst,
              ),
            const Divider(height: 1),
            BizAmountRow(
              label: 'Bill total',
              amount: taxable + gst,
              bold: true,
            ),
          ],
        ),
      ),
    ];
  }

  void _addItemRow() {
    setState(() {
      // Carry the typed amount over as a first item would lose it; start blank.
      _items.add(_ItemRow());
    });
  }

  Widget _itemRowCard(int index) {
    final row = _items[index];
    final book = ref.watch(bizBookProvider).valueOrNull ?? widget.initialBook;
    final item = row.itemId == null
        ? null
        : book.items.where((i) => i.id == row.itemId).firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickItem(row),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item?.name ?? 'Choose item',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(Icons.expand_more_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () =>
                      setState(() => _items.removeAt(index).dispose()),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: row.qty,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText:
                            'Qty${item == null ? '' : ' (${item.unit})'}',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: row.rate,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Rate',
                        prefixText: MoneyFormat.inputPrefix,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Amount  ',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  MoneyText(
                    row.amount,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickItem(_ItemRow row) async {
    final book = ref.read(bizBookProvider).valueOrNull ?? widget.initialBook;
    final items = book.items.where((i) => !i.isArchived).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final stock = {
      for (final s in book.stockSummary()) s.item.id: s.closingQty,
    };
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle_outline_rounded),
              title: const Text('Create new item'),
              onTap: () async {
                final id = await showItemForm(sheet, ref);
                if (id != null && sheet.mounted) Navigator.pop(sheet, id);
              },
            ),
            const Divider(height: 1),
            for (final i in items)
              ListTile(
                title: Text(i.name),
                subtitle: Text(
                  'In stock: ${formatQty(stock[i.id] ?? 0)} ${i.unit}',
                ),
                trailing: MoneyText(
                  _kind.isSalesSide ? i.salePrice : i.purchasePrice,
                ),
                onTap: () => Navigator.pop(sheet, i.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final fresh = ref.read(bizBookProvider).valueOrNull ?? book;
    final item = fresh.items.where((i) => i.id == picked).firstOrNull;
    setState(() {
      final firstPick = _items.every((r) => r.itemId == null);
      row.itemId = picked;
      if (item != null) {
        final price = _kind.isSalesSide ? item.salePrice : item.purchasePrice;
        if (price.isPositive) row.rate.text = price.rupees.toStringAsFixed(2);
        if (firstPick && _gstRate == 0 && item.gstRate > 0) {
          _gstRate = item.gstRate;
        }
      }
    });
  }

  List<Widget> _journalFields(ThemeData theme) {
    final t = _journalTotals;
    final diff = t.dr - t.cr;
    return [
      for (var i = 0; i < _journal.length; i++)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: true, label: Text('Dr')),
                        ButtonSegment(value: false, label: Text('Cr')),
                      ],
                      selected: {_journal[i].isDebit},
                      onSelectionChanged: (s) =>
                          setState(() => _journal[i].isDebit = s.first),
                    ),
                    const Spacer(),
                    if (_journal.length > 2)
                      IconButton(
                        tooltip: 'Remove line',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(
                          () => _journal.removeAt(i).amount.dispose(),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: LedgerPickerField(
                    label: 'Ledger',
                    groups: const [],
                    value: _journal[i].ledgerId,
                    onChanged: (id) =>
                        setState(() => _journal[i].ledgerId = id),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: BizAmountField(
                    controller: _journal[i].amount,
                    label: 'Amount',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _journal.add(
            _JournalRow(
              isDebit: diff.isNegative,
              amount: diff.isZero ? '' : diff.abs.rupees.toStringAsFixed(2),
            ),
          );
        }),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add line'),
      ),
      const SizedBox(height: 12),
      Card(
        child: Column(
          children: [
            BizAmountRow(label: 'Total debit', amount: t.dr),
            BizAmountRow(label: 'Total credit', amount: t.cr),
            const Divider(height: 1),
            BizAmountRow(
              label: diff.isZero ? 'Balanced' : 'Difference',
              amount: diff.abs,
              bold: true,
              color: diff.isZero ? AppColors.income : AppColors.expense,
            ),
          ],
        ),
      ),
    ];
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onChanged});
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime(DateTime.now().year + 5),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today_outlined),
        ),
        child: Text(bizDate.format(date)),
      ),
    );
  }
}
