import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/business_tables.dart';
import '../../../data/database.dart';
import '../../../data/providers.dart';
import '../biz_widgets.dart';
import 'booking_book.dart';
import 'booking_detail_screen.dart';
import 'booking_providers.dart';
import 'booking_repository.dart';
import 'bookings_screen.dart';
import 'business_types.dart';

/// New booking (optionally prefilled from a tapped free slot), or edit one.
class BookingFormScreen extends ConsumerWidget {
  const BookingFormScreen({
    super.key,
    this.bookingId,
    this.initialDate,
    this.initialSlot,
    this.initialResourceId,
  });

  final int? bookingId;
  final DateTime? initialDate;
  final String? initialSlot;
  final int? initialResourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(bizBusinessTypeProvider);
    return BookingGate(
      title: 'New ${type.bookingNoun.toLowerCase()}',
      builder: (context, bookings, books) => _BookingForm(
        key: ValueKey(bookingId),
        initialBookings: bookings,
        existing: bookingId == null ? null : bookings.bookingById[bookingId],
        initialDate: initialDate,
        initialSlot: initialSlot,
        initialResourceId: initialResourceId,
        companyId: books.company.id,
      ),
    );
  }
}

class _Line {
  _Line({required this.qty, required Money rate})
    : rate = TextEditingController(
        text: rate.isZero ? '' : rate.rupees.toStringAsFixed(2),
      );
  int qty;
  final TextEditingController rate;
}

class _BookingForm extends ConsumerStatefulWidget {
  const _BookingForm({
    required this.initialBookings,
    required this.existing,
    required this.initialDate,
    required this.initialSlot,
    required this.initialResourceId,
    required this.companyId,
    super.key,
  });

  final BookingBook initialBookings;
  final BizBookingRow? existing;
  final DateTime? initialDate;
  final String? initialSlot;
  final int? initialResourceId;
  final int companyId;

  @override
  ConsumerState<_BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends ConsumerState<_BookingForm> {
  late final BizBookingRow? _b = widget.existing;
  late final _name = TextEditingController(text: _b?.customerName ?? '');
  late final _phone = TextEditingController(text: _b?.phone ?? '');
  late final _title = TextEditingController(text: _b?.title ?? '');
  late final _guests = TextEditingController(
    text: (_b?.guests ?? 0) == 0 ? '' : '${_b!.guests}',
  );
  late final _notes = TextEditingController(text: _b?.notes ?? '');
  late final _total = TextEditingController(
    text: _b == null || _b.totalAmount.isZero
        ? ''
        : _b.totalAmount.rupees.toStringAsFixed(2),
  );
  late DateTime _start = dayOf(
    _b?.startDate ?? widget.initialDate ?? DateTime.now(),
  );
  late DateTime _end = dayOf(_b?.endDate ?? _start);
  late String _slot;
  late BizBookingStatus _status = _b?.status ?? BizBookingStatus.confirmed;
  final Map<int, _Line> _lines = {};
  final Map<String, Object?> _extra = {};
  final Map<String, TextEditingController> _extraText = {};

  /// Once the user types a total, stop overwriting it from the rates.
  late bool _totalEdited = _b != null;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final slots = ref.read(bookingSlotsProvider);
    _slot =
        _b?.slot ??
        widget.initialSlot ??
        (slots.contains(kFullDay) ? kFullDay : slots.first);
    final book = widget.initialBookings;
    if (_b != null) {
      for (final l in book.linesOf(_b.id)) {
        _lines[l.resourceId] = _Line(qty: l.qty, rate: l.rate);
      }
      _extra.addAll(book.extraOf(_b));
    } else if (widget.initialResourceId != null) {
      final r = book.resourceById[widget.initialResourceId];
      if (r != null) _lines[r.id] = _Line(qty: 1, rate: r.rate);
    }
    for (final f in ref.read(bookingFieldsProvider)) {
      if (f.type == BookingFieldType.text ||
          f.type == BookingFieldType.number) {
        final v = _extra[f.key];
        _extraText[f.key] = TextEditingController(text: v == null ? '' : '$v');
      }
    }
    _recalc();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _title,
      _guests,
      _notes,
      _total,
      ..._extraText.values,
    ]) {
      c.dispose();
    }
    for (final l in _lines.values) {
      l.rate.dispose();
    }
    super.dispose();
  }

  int get _multiplier =>
      rateMultiplier(ref.read(bizBusinessTypeProvider).rateBasis, _start, _end);

  Money get _computed => _lines.values.fold(
    const Money.zero(),
    (s, l) => s + parseMoney(l.rate.text) * (l.qty * _multiplier),
  );

  void _recalc() {
    if (_totalEdited) return;
    final t = _computed;
    _total.text = t.isZero ? '' : t.rupees.toStringAsFixed(2);
  }

  List<BookingLineDraft> get _drafts => [
    for (final e in _lines.entries)
      BookingLineDraft(
        resourceId: e.key,
        qty: e.value.qty,
        rate: parseMoney(e.value.rate.text),
      ),
  ];

  Future<void> _save({bool force = false, BizBookingStatus? asStatus}) async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter the customer’s name.')),
      );
      return;
    }
    if (_lines.isEmpty) {
      final noun = ref.read(bizBusinessTypeProvider).resourceNoun.toLowerCase();
      messenger.showSnackBar(
        SnackBar(content: Text('Choose at least one $noun.')),
      );
      return;
    }
    final extra = <String, Object?>{
      ..._extra,
      for (final f in ref.read(bookingFieldsProvider))
        if (_extraText.containsKey(f.key))
          f.key: f.type == BookingFieldType.number
              ? num.tryParse(_extraText[f.key]!.text.trim())
              : _extraText[f.key]!.text.trim(),
    };
    final status = asStatus ?? _status;
    setState(() => _saving = true);
    try {
      final id = await ref
          .read(dbProvider)
          .saveBooking(
            BookingDraft(
              id: _b?.id,
              companyId: widget.companyId,
              customerName: _name.text,
              phone: _phone.text,
              title: _title.text,
              start: _start,
              end: _end,
              slot: _slot,
              status: status,
              lines: _drafts,
              guests: int.tryParse(_guests.text.trim()) ?? 0,
              total: parseMoney(_total.text),
              extra: extra,
              notes: _notes.text,
              multiplier: _multiplier,
            ),
            force: force,
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(
        SnackBar(content: Text('Saved BK · ${_name.text.trim()}')),
      );
      if (_b == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => BookingDetailScreen(bookingId: id),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    } on BookingConflict catch (c) {
      setState(() => _saving = false);
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.event_busy_rounded, color: AppColors.expense),
          title: const Text('Already booked'),
          content: Text(c.messages.join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Change'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'enquiry'),
              child: const Text('Save as enquiry'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'force'),
              child: const Text('Book anyway'),
            ),
          ],
        ),
      );
      if (choice == 'enquiry') await _save(asStatus: BizBookingStatus.enquiry);
      if (choice == 'force') await _save(force: true);
    } on ArgumentError catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    }
  }

  Future<void> _pickDate({required bool end}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: end ? _end : _start,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (d == null) return;
    setState(() {
      if (end) {
        _end = dayOf(d).isBefore(_start) ? _start : dayOf(d);
      } else {
        _start = dayOf(d);
        if (_end.isBefore(_start)) _end = _start;
        if (!ref.read(bizBusinessTypeProvider).multiDay) _end = _start;
      }
      _recalc();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = ref.watch(bizBusinessTypeProvider);
    final slots = ref.watch(bookingSlotsProvider);
    final fields = ref.watch(bookingFieldsProvider);
    final bookings =
        ref.watch(bookingBookProvider).valueOrNull ?? widget.initialBookings;
    final resources = bookings.activeResources;
    final mult = _multiplier;
    final hotel = type == BizBusinessType.hotel;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _b == null
              ? 'New ${type.bookingNoun.toLowerCase()}'
              : 'Edit ${bookings.numberLabel(_b)}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          // ── Who ──
          TextField(
            controller: _name,
            autofocus: _b == null,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Customer name',
              prefixIcon: Icon(Icons.person_outline_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone',
              prefixIcon: Icon(Icons.call_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: '${type.bookingNoun} name (optional)',
              hintText: switch (type) {
                BizBusinessType.venue => 'e.g. Sharma – Patil wedding',
                BizBusinessType.cinema => 'e.g. School group booking',
                _ => null,
              },
              border: const OutlineInputBorder(),
            ),
          ),

          // ── When ──
          const BizSectionLabel('When'),
          Row(
            children: [
              Expanded(
                child: _DateBox(
                  label: hotel ? 'Check-in' : (type.multiDay ? 'From' : 'Date'),
                  date: _start,
                  onTap: () => _pickDate(end: false),
                ),
              ),
              if (type.multiDay) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _DateBox(
                    label: hotel ? 'Check-out' : 'Till',
                    date: _end,
                    onTap: () => _pickDate(end: true),
                  ),
                ),
              ],
            ],
          ),
          if (type.multiDay && mult > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                '$mult ${type.rateBasis == RateBasis.perNight ? 'nights' : 'days'}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (slots.length > 1) ...[
            const SizedBox(height: 12),
            Text(
              type == BizBusinessType.cinema ? 'Show' : 'Session / slot',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in {...slots, _slot})
                  ChoiceChip(
                    label: Text(s),
                    selected: _slot == s,
                    onSelected: (_) => setState(() => _slot = s),
                  ),
              ],
            ),
          ],

          // ── What ──
          BizSectionLabel(type.resourcePlural),
          if (resources.isEmpty)
            Text(
              'No ${type.resourcePlural.toLowerCase()} yet — add them in Booking setup.',
            ),
          for (final r in resources)
            _resourceCard(context, bookings, r, mult, type),

          // ── Details ──
          BizSectionLabel('Details'),
          TextField(
            controller: _guests,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: type.peopleLabel,
              prefixIcon: const Icon(Icons.groups_outlined),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          ..._capacityWarning(bookings, theme),
          for (final f in fields) ...[
            const SizedBox(height: 12),
            _fieldInput(f),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes / requirements',
              border: OutlineInputBorder(),
            ),
          ),

          // ── Status & amount ──
          const BizSectionLabel('Status'),
          Wrap(
            spacing: 8,
            children: [
              for (final s in const [
                BizBookingStatus.enquiry,
                BizBookingStatus.tentative,
                BizBookingStatus.confirmed,
              ])
                ChoiceChip(
                  label: Text(s.label),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                ),
              if (_b != null &&
                  !const [
                    BizBookingStatus.enquiry,
                    BizBookingStatus.tentative,
                    BizBookingStatus.confirmed,
                  ].contains(_status))
                ChoiceChip(
                  label: Text(_status.label),
                  selected: true,
                  onSelected: (_) {},
                ),
            ],
          ),
          const BizSectionLabel('Amount'),
          BizAmountField(
            controller: _total,
            label: 'Total amount',
            large: true,
            onChanged: (_) => _totalEdited = true,
          ),
          if (_computed.isPositive)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _totalEdited = false;
                  _recalc();
                }),
                icon: const Icon(Icons.calculate_outlined, size: 18),
                label: Text('Use rates: ${MoneyFormat.symbol(_computed)}'),
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
                _b == null
                    ? 'Save ${type.bookingNoun.toLowerCase()}'
                    : 'Save changes',
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _capacityWarning(BookingBook bookings, ThemeData theme) {
    final guests = int.tryParse(_guests.text.trim()) ?? 0;
    if (guests == 0) return const [];
    final cap = _lines.keys
        .map((id) => bookings.resourceById[id])
        .where((r) => r != null && !r.shared)
        .fold(0, (s, r) => s + r!.capacity);
    if (cap == 0 || guests <= cap) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(
          'More than the selected capacity ($cap).',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
    ];
  }

  Widget _resourceCard(
    BuildContext context,
    BookingBook bookings,
    BizBookingResourceRow r,
    int mult,
    BizBusinessType type,
  ) {
    final theme = Theme.of(context);
    final selected = _lines.containsKey(r.id);
    // Worst state across every day of the booking.
    var state = SlotState.free;
    var left = r.shared ? r.capacity : 1;
    String? by;
    for (
      var d = _start;
      !d.isAfter(_end);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      final a = bookings.availability(r, d, _slot, excludeBookingId: _b?.id);
      if (a.state.index > state.index) state = a.state;
      if (a.capacity - a.used < left) left = a.capacity - a.used;
      if (a.bookings.isNotEmpty) by ??= a.bookings.first.customerName;
    }
    final (color, text) = switch (state) {
      SlotState.free => (AppColors.income, 'Available'),
      SlotState.partial => (const Color(0xFFD97706), '$left left'),
      SlotState.full => (
        AppColors.expense,
        r.shared ? 'Sold out' : 'Booked${by == null ? '' : ' · $by'}',
      ),
    };
    final line = _lines[r.id];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? theme.colorScheme.secondary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: selected,
            onChanged: (on) => setState(() {
              if (on == true) {
                _lines[r.id] = _Line(qty: r.shared ? 1 : 1, rate: r.rate);
              } else {
                _lines.remove(r.id)?.rate.dispose();
              }
              _recalc();
            }),
            title: Text(
              r.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Icon(Icons.circle, size: 8, color: color),
                Text(text, style: TextStyle(color: color)),
                if (r.rate.isPositive)
                  Text(
                    '· ${MoneyFormat.compact(r.rate)} ${type.rateBasis.label}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (line != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  if (r.shared) ...[
                    IconButton.outlined(
                      onPressed: line.qty > 1
                          ? () => setState(() {
                              line.qty--;
                              _recalc();
                            })
                          : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${line.qty}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton.outlined(
                      onPressed: () => setState(() {
                        line.qty++;
                        _recalc();
                      }),
                      icon: const Icon(Icons.add_rounded),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: TextField(
                      controller: line.rate,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => setState(_recalc),
                      decoration: InputDecoration(
                        labelText: 'Rate ${type.rateBasis.label}',
                        prefixText: MoneyFormat.inputPrefix,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _fieldInput(BookingField f) {
    switch (f.type) {
      case BookingFieldType.text:
      case BookingFieldType.number:
        return TextField(
          controller: _extraText[f.key] ??= TextEditingController(),
          keyboardType: f.type == BookingFieldType.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: f.label,
            border: const OutlineInputBorder(),
          ),
        );
      case BookingFieldType.select:
        final value = _extra[f.key] as String?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in f.options)
                  ChoiceChip(
                    label: Text(o),
                    selected: value == o,
                    onSelected: (on) =>
                        setState(() => _extra[f.key] = on ? o : null),
                  ),
              ],
            ),
          ],
        );
      case BookingFieldType.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _extra[f.key] == true,
          onChanged: (v) => setState(() => _extra[f.key] = v),
        );
    }
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.label,
    required this.date,
    required this.onTap,
  });
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(4),
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
      ),
      child: Text(bizDate.format(date)),
    ),
  );
}
