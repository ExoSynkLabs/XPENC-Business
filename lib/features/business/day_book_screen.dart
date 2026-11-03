import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets/money_text.dart';
import '../../data/business_tables.dart';
import '../../data/database.dart';
import 'biz_book.dart';
import 'biz_entry_kinds.dart';
import 'biz_providers.dart';
import 'biz_widgets.dart';
import 'booking/booking_form_screen.dart';
import 'booking/booking_providers.dart';
import 'voucher_entry_screen.dart';

IconData iconForVoucher(BizVoucherRow v) =>
    BizEntryKind.byKey(v.entryKind)?.icon ??
    switch (v.type) {
      BizVoucherType.sales => Icons.point_of_sale_rounded,
      BizVoucherType.purchase => Icons.shopping_cart_outlined,
      BizVoucherType.receipt => Icons.south_west_rounded,
      BizVoucherType.payment => Icons.north_east_rounded,
      BizVoucherType.contra => Icons.swap_horiz_rounded,
      BizVoucherType.journal => Icons.menu_book_outlined,
      BizVoucherType.creditNote => Icons.assignment_return_outlined,
      BizVoucherType.debitNote => Icons.keyboard_return_rounded,
    };

/// Marks the "New booking" choice in the entry sheet.
const _bookingSentinel = BizEntryKind(
  key: '_booking',
  label: 'Booking',
  hint: '',
  icon: Icons.event_available_rounded,
  type: BizVoucherType.journal,
  section: '',
);

/// One voucher as a list row. Tap to edit.
class VoucherTile extends StatelessWidget {
  const VoucherTile({required this.book, required this.voucher, super.key});
  final BizBook book;
  final BizVoucherRow voucher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = BizEntryKind.byKey(voucher.entryKind);
    final subtitle = [
      '${book.voucherNumberLabel(voucher)} · ${kind?.label ?? voucher.type.label}',
      if (voucher.narration != null) voucher.narration!,
    ].join(' · ');
    return ListTile(
      onTap: () => openVoucherEntry(context, voucherId: voucher.id),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        foregroundColor: theme.colorScheme.onSurface,
        child: Icon(iconForVoucher(voucher), size: 20),
      ),
      title: Text(
        book.voucherTitle(voucher),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: MoneyText(
        book.voucherAmount(voucher.id),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Every voucher in the period, newest day first — Tally's Day Book.
class DayBookScreen extends ConsumerWidget {
  const DayBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(bizPeriodProvider);
    final filter = ref.watch(bizDayBookFilterProvider);
    return BizBookGate(
      title: 'Day Book',
      builder: (context, book) {
        final theme = Theme.of(context);
        final vouchers = book.vouchers
            .where((v) => period.contains(v.date))
            .where((v) => filter.isEmpty || filter.contains(v.type))
            .toList()
            .reversed
            .toList();
        final byDay = <DateTime, List<BizVoucherRow>>{};
        for (final v in vouchers) {
          (byDay[DateTime(v.date.year, v.date.month, v.date.day)] ??= []).add(
            v,
          );
        }
        final total = vouchers.fold(
          const Money.zero(),
          (s, v) => s + book.voucherAmount(v.id),
        );
        return Scaffold(
          appBar: AppBar(title: const Text('Day Book')),
          floatingActionButton: FloatingActionButton(
            tooltip: 'New entry',
            onPressed: () => showNewEntrySheet(context),
            child: const Icon(Icons.add_rounded),
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      const BizPeriodChip(),
                      Text(
                        '${vouchers.length} vouchers',
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    children: [
                      for (final t in BizVoucherType.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(t.label),
                            selected: filter.contains(t),
                            onSelected: (on) {
                              final next = {...filter};
                              on ? next.add(t) : next.remove(t);
                              ref
                                      .read(bizDayBookFilterProvider.notifier)
                                      .state =
                                  next;
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (vouchers.isEmpty)
                const SliverToBoxAdapter(
                  child: BizEmpty(
                    icon: Icons.receipt_long_outlined,
                    text: 'No vouchers in this period.',
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: BizHeadline(
                    label: 'Total value of vouchers',
                    amount: total,
                  ),
                ),
                for (final entry in byDay.entries) ...[
                  SliverToBoxAdapter(
                    child: BizSectionLabel(bizDate.format(entry.key)),
                  ),
                  SliverToBoxAdapter(
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < entry.value.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                indent: 72,
                                color: theme.colorScheme.outline,
                              ),
                            VoucherTile(book: book, voucher: entry.value[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        );
      },
    );
  }
}

/// The "what happened?" picker — every quick-entry kind, grouped.
Future<void> showNewEntrySheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final type = container.read(bizBusinessTypeProvider);
  final bookingKind = container.read(bookingsEnabledProvider)
      ? (type.bookingNoun, type.bookingPlural, type.icon)
      : null;
  final kind = await showModalBottomSheet<BizEntryKind>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) {
        final theme = Theme.of(context);
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('New entry', style: theme.textTheme.titleLarge),
            ),
            if (bookingKind != null) ...[
              BizSectionLabel(bookingKind.$2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(bookingKind.$3),
                    title: Text('New ${bookingKind.$1.toLowerCase()}'),
                    subtitle: const Text(
                      'Register a customer and block the date',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(sheet, _bookingSentinel),
                  ),
                ),
              ),
            ],
            for (final section in BizEntryKind.bySection.entries) ...[
              BizSectionLabel(section.key),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final cols = c.maxWidth > 520 ? 4 : 3;
                    final w = (c.maxWidth - (cols - 1) * 8) / cols;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final k in section.value)
                          SizedBox(
                            width: w,
                            child: _KindTile(
                              kind: k,
                              onTap: () => Navigator.pop(sheet, k),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
  if (kind == null || !context.mounted) return;
  if (identical(kind, _bookingSentinel)) {
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => const BookingFormScreen()));
    return;
  }
  await openVoucherEntry(context, kind: kind);
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind, required this.onTap});
  final BizEntryKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Icon(kind.icon, size: 26),
              const SizedBox(height: 8),
              Text(
                kind.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
