import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets/money_text.dart';
import '../../data/database.dart';
import 'biz_book.dart';
import 'biz_providers.dart';
import 'biz_widgets.dart';
import 'booking/booking_book.dart';
import 'booking/booking_providers.dart';
import 'booking/bookings_screen.dart';
import 'day_book_screen.dart';
import 'items_screen.dart';
import 'ledgers_screen.dart';

/// Everything matching [query] across the open company.
typedef SearchResults = ({
  List<BizLedgerRow> ledgers,
  List<BizVoucherRow> vouchers,
  List<BizBookingRow> bookings,
  List<BizItemRow> items,
});

/// Pure, so it is testable without a screen. Matches names, phones, GSTINs,
/// narrations, references, voucher numbers ("SAL/12", "BK/3") and exact
/// amounts ("45000").
SearchResults searchBusiness(
  String query,
  BizBook book,
  BookingBook? bookings,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return (
      ledgers: const [],
      vouchers: const [],
      bookings: const [],
      items: const [],
    );
  }
  bool has(String? s) => s != null && s.toLowerCase().contains(q);
  final amount = Money.tryParse(q);
  final ledgers = book.ledgers
      .where((l) => has(l.name) || has(l.phone) || has(l.gstin))
      .toList();
  final ledgerHits = ledgers.map((l) => l.id).toSet();
  final vouchers = book.vouchers.reversed
      .where((v) {
        if (has(v.narration) ||
            has(v.reference) ||
            has(book.voucherNumberLabel(v))) {
          return true;
        }
        if (amount != null &&
            amount.isPositive &&
            book.voucherAmount(v.id) == amount) {
          return true;
        }
        return book.linesOf(v.id).any((l) => ledgerHits.contains(l.ledgerId));
      })
      .take(30)
      .toList();
  final bookingRows = bookings == null
      ? const <BizBookingRow>[]
      : bookings.bookings.reversed
            .where(
              (b) =>
                  has(b.customerName) ||
                  has(b.phone) ||
                  has(b.title) ||
                  has(bookings.numberLabel(b)),
            )
            .take(30)
            .toList();
  final items = book.items.where((i) => has(i.name)).toList();
  return (
    ledgers: ledgers.take(20).toList(),
    vouchers: vouchers,
    bookings: bookingRows,
    items: items,
  );
}

class BizSearchScreen extends ConsumerStatefulWidget {
  const BizSearchScreen({super.key});

  @override
  ConsumerState<BizSearchScreen> createState() => _BizSearchScreenState();
}

class _BizSearchScreenState extends ConsumerState<BizSearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(bizBookProvider).valueOrNull;
    final bookings = ref.watch(bookingBookProvider).valueOrNull;
    final theme = Theme.of(context);
    final q = _controller.text;
    final r = book == null ? null : searchBusiness(q, book, bookings);
    final total = r == null
        ? 0
        : r.ledgers.length +
              r.vouchers.length +
              r.bookings.length +
              r.items.length;

    Widget section(String title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BizSectionLabel(title),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search parties, vouchers, bookings…',
            prefixIcon: const Icon(Icons.search_rounded),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(_controller.clear),
                  ),
          ),
        ),
      ),
      body: book == null
          ? const Center(child: CircularProgressIndicator())
          : q.trim().isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Try', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final hint in const [
                        'a customer’s name',
                        'a phone number',
                        'SAL/1',
                        'BK/1',
                        '45000',
                      ])
                        Chip(label: Text(hint)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Search looks through party and ledger names, phones and GSTINs, '
                    'voucher numbers, references and narrations, exact amounts, '
                    'booking customers, and stock items.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : total == 0
          ? BizEmpty(
              icon: Icons.search_off_rounded,
              text: 'Nothing matches “${q.trim()}”.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (r!.bookings.isNotEmpty && bookings != null)
                  section('Bookings', [
                    for (final b in r.bookings)
                      BookingTile(bookings: bookings, books: book, booking: b),
                  ]),
                if (r.ledgers.isNotEmpty)
                  section('Parties & ledgers', [
                    for (final l in r.ledgers)
                      ListTile(
                        leading: const Icon(Icons.account_circle_outlined),
                        title: Text(l.name),
                        subtitle: Text(
                          [
                            l.ledgerGroup.label,
                            if (l.phone != null) l.phone!,
                          ].join(' · '),
                        ),
                        trailing: l.ledgerGroup.isBalanceSheet
                            ? DrCrText(book.balanceOf(l))
                            : null,
                        onTap: () => openLedger(context, l.id),
                      ),
                  ]),
                if (r.vouchers.isNotEmpty)
                  section('Vouchers', [
                    for (final v in r.vouchers)
                      VoucherTile(book: book, voucher: v),
                  ]),
                if (r.items.isNotEmpty)
                  section('Items', [
                    for (final i in r.items)
                      ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(i.name),
                        subtitle: Text(i.unit),
                        trailing: MoneyText(i.salePrice),
                        onTap: () => showItemForm(context, ref, item: i),
                      ),
                  ]),
              ],
            ),
    );
  }
}
