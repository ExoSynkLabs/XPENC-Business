import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets/money_text.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import 'biz_providers.dart';
import 'biz_repository.dart';
import 'biz_widgets.dart';

/// Stock items with quantity on hand and value — Tally's Stock Summary.
class ItemsScreen extends ConsumerWidget {
  const ItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BizBookGate(
      title: 'Stock & items',
      builder: (context, book) {
        final theme = Theme.of(context);
        final lines = book.stockSummary()
          ..sort(
            (a, b) =>
                a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase()),
          );
        final total = lines.fold(const Money.zero(), (s, l) => s + l.value);
        return Scaffold(
          appBar: AppBar(title: const Text('Stock & items')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showItemForm(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Item'),
          ),
          body: lines.isEmpty
              ? const BizEmpty(
                  icon: Icons.inventory_2_outlined,
                  text:
                      'No items yet. Add the goods you buy and sell — quantities '
                      'update automatically from purchase and sales entries.',
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    BizHeadline(
                      label: 'Stock value (avg. cost)',
                      amount: total,
                      footer:
                          'Used automatically as closing stock in P&L and Balance Sheet',
                    ),
                    Card(
                      margin: const EdgeInsets.all(16),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < lines.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                color: theme.colorScheme.outline,
                              ),
                            ListTile(
                              onTap: () => showItemForm(
                                context,
                                ref,
                                item: lines[i].item,
                              ),
                              title: Text(lines[i].item.name),
                              subtitle: Text(
                                'In ${formatQty(lines[i].inQty)} · Out ${formatQty(lines[i].outQty)}'
                                ' · @ ${MoneyFormat.symbol(lines[i].avgCost)}',
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${formatQty(lines[i].closingQty)} ${lines[i].item.unit}',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: lines[i].closingQty < 0
                                          ? theme.colorScheme.error
                                          : null,
                                    ),
                                  ),
                                  MoneyText(
                                    lines[i].value,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
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
}

/// Create or edit a stock item. Returns its id.
Future<int?> showItemForm(
  BuildContext context,
  WidgetRef ref, {
  BizItemRow? item,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _ItemForm(item: item),
);

class _ItemForm extends ConsumerStatefulWidget {
  const _ItemForm({required this.item});
  final BizItemRow? item;

  @override
  ConsumerState<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends ConsumerState<_ItemForm> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _unit = TextEditingController(text: widget.item?.unit ?? 'pcs');
  late final _sale = TextEditingController(text: _m(widget.item?.salePrice));
  late final _purchase = TextEditingController(
    text: _m(widget.item?.purchasePrice),
  );
  late final _openingQty = TextEditingController(
    text: widget.item == null || widget.item!.openingQty == 0
        ? ''
        : formatQty(widget.item!.openingQty),
  );
  late double _gst = widget.item?.gstRate ?? 0;

  static String _m(Money? m) =>
      m == null || m.isZero ? '' : m.rupees.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [_name, _unit, _sale, _purchase, _openingQty]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final db = ref.read(dbProvider);
    final qty = double.tryParse(_openingQty.text) ?? 0;
    int id;
    if (widget.item == null) {
      final company = ref.read(activeBizCompanyProvider).valueOrNull;
      if (company == null) return;
      id = await db.createBizItem(
        companyId: company.id,
        name: name,
        unit: _unit.text,
        salePrice: parseMoney(_sale.text),
        purchasePrice: parseMoney(_purchase.text),
        gstRate: _gst,
        openingQty: qty,
      );
    } else {
      id = widget.item!.id;
      await db.updateBizItem(
        widget.item!.copyWith(
          name: name,
          unit: _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim(),
          salePrice: parseMoney(_sale.text),
          purchasePrice: parseMoney(_purchase.text),
          gstRate: _gst,
          openingQty: qty,
        ),
      );
    }
    if (mounted) Navigator.pop(context, id);
  }

  Future<void> _delete() async {
    final deleted = await ref
        .read(dbProvider)
        .deleteOrArchiveBizItem(widget.item!.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted ? 'Item deleted' : 'Item has entries — archived instead',
        ),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item == null ? 'New item' : 'Edit item',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (widget.item != null)
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _delete,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.item == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Item name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      hintText: 'pcs, kg, box',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _openingQty,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Opening qty',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: BizAmountField(
                    controller: _purchase,
                    label: 'Purchase rate',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BizAmountField(controller: _sale, label: 'Sale rate'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('GST rate', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final r in const [0.0, 5.0, 12.0, 18.0, 28.0])
                  ChoiceChip(
                    label: Text(r == 0 ? 'None' : '${formatQty(r)}%'),
                    selected: _gst == r,
                    onSelected: (_) => setState(() => _gst = r),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Save item'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
