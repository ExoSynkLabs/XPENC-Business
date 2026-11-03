import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/business_tables.dart';
import '../../../data/database.dart';
import '../../../data/providers.dart';
import '../biz_book.dart';
import '../biz_widgets.dart';
import '../day_book_screen.dart';
import 'booking_book.dart';
import 'booking_form_screen.dart';
import 'booking_providers.dart';
import 'booking_repository.dart';
import 'bookings_screen.dart';
import 'business_types.dart';

class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({required this.bookingId, super.key});
  final int bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(bizBusinessTypeProvider);
    final fields = ref.watch(bookingFieldsProvider);
    return BookingGate(
      title: type.bookingNoun,
      builder: (context, bookings, books) {
        final theme = Theme.of(context);
        final b = bookings.bookingById[bookingId];
        if (b == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const BizEmpty(
              icon: Icons.event_busy_outlined,
              text: 'This booking was deleted.',
            ),
          );
        }
        final money = bookings.moneyOf(b, books);
        final extra = bookings.extraOf(b);
        final vouchers = books.vouchers
            .where((v) => v.bookingId == b.id)
            .toList();
        final mult = rateMultiplier(type.rateBasis, b.startDate, b.endDate);
        final dates = dayOf(b.startDate) == dayOf(b.endDate)
            ? bizDate.format(b.startDate)
            : '${bizDate.format(b.startDate)} – ${bizDate.format(b.endDate)}';

        return Scaffold(
          appBar: AppBar(
            title: Text(bookings.numberLabel(b)),
            actions: [
              IconButton(
                tooltip: 'Share booking slip',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    text: _slip(books, bookings, b, type, fields, money),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    pushBooking(context, BookingFormScreen(bookingId: b.id)),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'delete') {
                    await _delete(context, ref, b, vouchers.isNotEmpty);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              // ── Header ──
              Card(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              b.title ?? b.customerName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          StatusPill(b.status),
                        ],
                      ),
                      if (b.title != null)
                        Text(b.customerName, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 10),
                      _Info(Icons.event_outlined, dates),
                      _Info(Icons.schedule_rounded, b.slot),
                      _Info(type.icon, bookings.resourceNames(b)),
                      if (b.guests > 0)
                        _Info(
                          Icons.groups_outlined,
                          '${b.guests} ${type.peopleLabel.toLowerCase()}',
                        ),
                      if (b.phone != null)
                        InkWell(
                          onTap: () =>
                              launchUrl(Uri(scheme: 'tel', path: b.phone)),
                          child: _Info(
                            Icons.call_outlined,
                            b.phone!,
                            link: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // ── Status actions ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _nextStatuses(b.status))
                      OutlinedButton.icon(
                        onPressed: () =>
                            ref.read(dbProvider).setBookingStatus(b.id, s),
                        icon: Icon(
                          _statusIcon(s),
                          size: 18,
                          color: statusColor(s, theme.colorScheme),
                        ),
                        label: Text(_statusAction(s)),
                      ),
                  ],
                ),
              ),
              // ── Money ──
              const BizSectionLabel('Payment'),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    BizAmountRow(
                      label: 'Total',
                      amount: money.total,
                      bold: true,
                    ),
                    BizAmountRow(
                      label: 'Received',
                      amount: money.paid,
                      color: AppColors.income,
                    ),
                    const Divider(height: 1),
                    BizAmountRow(
                      label: money.due.isNegative
                          ? 'Excess received'
                          : 'Balance due',
                      amount: money.due.abs,
                      bold: true,
                      color: money.due.isPositive
                          ? AppColors.expense
                          : AppColors.income,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () =>
                                _receive(context, ref, b, books, money.due),
                            icon: const Icon(
                              Icons.call_received_rounded,
                              size: 18,
                            ),
                            label: const Text('Receive payment'),
                          ),
                          if (!money.billed && money.total.isPositive)
                            FilledButton.tonalIcon(
                              onPressed: () => _bill(context, ref, b),
                              icon: const Icon(
                                Icons.receipt_long_outlined,
                                size: 18,
                              ),
                              label: const Text('Post bill to books'),
                            ),
                          if (money.paid.isPositive)
                            TextButton.icon(
                              onPressed: () => _receive(
                                context,
                                ref,
                                b,
                                books,
                                money.paid,
                                refund: true,
                              ),
                              icon: const Icon(Icons.undo_rounded, size: 18),
                              label: const Text('Refund'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (money.billed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Text(
                    'Billed — income is in Profit & Loss and the customer’s ledger.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              // ── Resources ──
              BizSectionLabel(type.resourcePlural),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    for (final l in bookings.linesOf(b.id))
                      BizAmountRow(
                        label: bookings.resourceById[l.resourceId]?.name ?? '?',
                        subtitle: [
                          if (l.qty > 1) '${l.qty} ×',
                          '${MoneyFormat.symbol(l.rate)} ${type.rateBasis.label}',
                          if (mult > 1) '× $mult',
                        ].join(' '),
                        amount: l.amount,
                      ),
                  ],
                ),
              ),
              // ── Details ──
              if (fields.any((f) => extra[f.key] != null) ||
                  b.notes != null) ...[
                const BizSectionLabel('Requirements'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      for (final f in fields)
                        if (extra[f.key] != null && extra[f.key] != false)
                          ListTile(
                            dense: true,
                            title: Text(f.label),
                            trailing: Text(
                              _fmtValue(extra[f.key]),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      if (b.notes != null)
                        ListTile(
                          dense: true,
                          title: const Text('Notes'),
                          subtitle: Text(b.notes!),
                        ),
                    ],
                  ),
                ),
              ],
              // ── Vouchers ──
              if (vouchers.isNotEmpty) ...[
                const BizSectionLabel('In the books'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final v in vouchers)
                        VoucherTile(book: books, voucher: v),
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

  static String _fmtValue(Object? v) => switch (v) {
    true => 'Yes',
    num n => n == n.roundToDouble() ? n.toInt().toString() : '$n',
    _ => '$v',
  };

  static List<BizBookingStatus> _nextStatuses(BizBookingStatus s) =>
      switch (s) {
        BizBookingStatus.enquiry => [
          BizBookingStatus.tentative,
          BizBookingStatus.confirmed,
          BizBookingStatus.cancelled,
        ],
        BizBookingStatus.tentative => [
          BizBookingStatus.confirmed,
          BizBookingStatus.cancelled,
        ],
        BizBookingStatus.confirmed => [
          BizBookingStatus.completed,
          BizBookingStatus.cancelled,
        ],
        BizBookingStatus.completed => [BizBookingStatus.confirmed],
        BizBookingStatus.cancelled => [BizBookingStatus.enquiry],
      };

  static String _statusAction(BizBookingStatus s) => switch (s) {
    BizBookingStatus.enquiry => 'Reopen as enquiry',
    BizBookingStatus.tentative => 'Mark tentative',
    BizBookingStatus.confirmed => 'Confirm',
    BizBookingStatus.completed => 'Mark completed',
    BizBookingStatus.cancelled => 'Cancel booking',
  };

  static IconData _statusIcon(BizBookingStatus s) => switch (s) {
    BizBookingStatus.enquiry => Icons.help_outline_rounded,
    BizBookingStatus.tentative => Icons.hourglass_top_rounded,
    BizBookingStatus.confirmed => Icons.check_circle_outline_rounded,
    BizBookingStatus.completed => Icons.task_alt_rounded,
    BizBookingStatus.cancelled => Icons.cancel_outlined,
  };

  String _slip(
    BizBook books,
    BookingBook bookings,
    BizBookingRow b,
    BizBusinessType type,
    List<BookingField> fields,
    BookingMoney money,
  ) {
    final extra = bookings.extraOf(b);
    final dates = dayOf(b.startDate) == dayOf(b.endDate)
        ? bizDate.format(b.startDate)
        : '${bizDate.format(b.startDate)} to ${bizDate.format(b.endDate)}';
    return [
      '*${books.company.name}*',
      if (books.company.phone != null) books.company.phone!,
      '',
      '${type.bookingNoun} ${bookings.numberLabel(b)} — ${b.status.label}',
      if (b.title != null) b.title!,
      'Customer: ${b.customerName}${b.phone == null ? '' : ' (${b.phone})'}',
      'Date: $dates · ${b.slot}',
      '${type.resourcePlural}: ${bookings.resourceNames(b)}',
      if (b.guests > 0) '${type.peopleLabel}: ${b.guests}',
      for (final f in fields)
        if (extra[f.key] != null && extra[f.key] != false)
          '${f.label}: ${_fmtValue(extra[f.key])}',
      '',
      'Total: ${MoneyFormat.symbol(money.total)}',
      'Received: ${MoneyFormat.symbol(money.paid)}',
      'Balance: ${MoneyFormat.symbol(money.due)}',
    ].join('\n');
  }

  Future<void> _bill(
    BuildContext context,
    WidgetRef ref,
    BizBookingRow b,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(dbProvider).postBookingBill(b);
      messenger.showSnackBar(
        const SnackBar(content: Text('Bill posted as a Sales voucher')),
      );
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    }
  }

  Future<void> _receive(
    BuildContext context,
    WidgetRef ref,
    BizBookingRow b,
    BizBook books,
    Money suggested, {
    bool refund = false,
  }) async {
    final amount = TextEditingController(
      text: suggested.isPositive ? suggested.rupees.toStringAsFixed(2) : '',
    );
    int? ledger = books.ledgerByKey(BizSystemKey.cash)?.id;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom +
                MediaQuery.paddingOf(context).bottom +
                16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                refund ? 'Refund' : 'Receive payment',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              BizAmountField(
                controller: amount,
                label: 'Amount',
                large: true,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              LedgerPickerField(
                label: refund ? 'Paid from' : 'Received in',
                groups: const [BizGroup.cash, BizGroup.bank],
                value: ledger,
                onChanged: (id) => setState(() => ledger = id),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(sheet, true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final value = parseMoney(amount.text);
    amount.dispose();
    if (ok != true || ledger == null || !value.isPositive) return;
    await ref
        .read(dbProvider)
        .recordBookingPayment(
          booking: b,
          amount: value,
          cashLedgerId: ledger!,
          refund: refund,
        );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    BizBookingRow b,
    bool hasMoney,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete booking?'),
        content: Text(
          hasMoney
              ? 'Payments and bills already posted stay in your books — only the booking is removed. '
                    'To return money, use Refund first, or cancel the booking instead.'
              : 'This frees its dates for others.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(dbProvider).deleteBooking(b.id);
    if (context.mounted) Navigator.pop(context);
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.text, {this.link = false});
  final IconData icon;
  final String text;
  final bool link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: link
                  ? TextStyle(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
