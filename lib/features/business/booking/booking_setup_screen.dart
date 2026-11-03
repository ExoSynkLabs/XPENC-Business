import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money.dart';
import '../../../data/database.dart';
import '../../../data/providers.dart';
import '../biz_providers.dart';
import '../biz_widgets.dart';
import 'booking_providers.dart';
import 'booking_repository.dart';
import 'business_types.dart';

/// Turn bookings on, pick the business type, and shape the booking form:
/// what can be booked, the time slots, and any extra fields.
class BookingSetupScreen extends ConsumerWidget {
  const BookingSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(activeBizCompanyProvider).valueOrNull;
    final bookings = ref.watch(bookingBookProvider).valueOrNull;
    final type = ref.watch(bizBusinessTypeProvider);
    final enabled = ref.watch(bookingsEnabledProvider);
    final slots = ref.watch(bookingSlotsProvider);
    final fields = ref.watch(bookingFieldsProvider);
    final theme = Theme.of(context);
    if (company == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final db = ref.read(dbProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Business type & bookings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SwitchListTile(
              secondary: const Icon(Icons.event_available_rounded),
              title: const Text('Bookings module'),
              subtitle: Text(
                enabled
                    ? '${type.bookingPlural} calendar, availability and advances'
                    : 'Turn on to take ${type.bookingPlural.toLowerCase()}',
              ),
              value: enabled,
              onChanged: (v) => db.setBookingsEnabled(company.id, v),
            ),
          ),
          const BizSectionLabel('Business type'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: BusinessTypePicker(
              selected: type,
              onSelected: (t) => _changeType(context, ref, company.id, type, t),
            ),
          ),
          if (enabled) ...[
            BizSectionLabel(
              type.resourcePlural,
              trailing: TextButton.icon(
                onPressed: () => showResourceForm(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  if (bookings == null || bookings.activeResources.isEmpty)
                    ListTile(
                      title: Text(
                        'No ${type.resourcePlural.toLowerCase()} yet',
                      ),
                      subtitle: Text(
                        'Add each ${type.resourceNoun.toLowerCase()} customers can book.',
                      ),
                    ),
                  for (final r
                      in bookings?.activeResources ??
                          const <BizBookingResourceRow>[])
                    ListTile(
                      leading: Icon(type.icon),
                      title: Text(r.name),
                      subtitle: Text(
                        [
                          if (r.shared)
                            '${r.capacity} units per slot'
                          else if (r.capacity > 0)
                            'Holds ${r.capacity}',
                          if (r.rate.isPositive)
                            '${MoneyFormat.symbol(r.rate)} ${type.rateBasis.label}',
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => showResourceForm(context, ref, resource: r),
                    ),
                ],
              ),
            ),
            BizSectionLabel(
              type == BizBusinessType.cinema
                  ? 'Show times'
                  : 'Sessions / time slots',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in slots)
                    InputChip(
                      label: Text(s),
                      onDeleted: slots.length <= 1
                          ? null
                          : () => db.saveBookingSlots(
                              company.id,
                              [...slots]..remove(s),
                            ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                    onPressed: () async {
                      final name = await _askText(
                        context,
                        'New slot',
                        hint: 'e.g. Evening, 7:00 PM',
                      );
                      if (name != null && !slots.contains(name)) {
                        await db.saveBookingSlots(company.id, [...slots, name]);
                      }
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text(
                '“$kFullDay” clashes with every other slot on that day.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            BizSectionLabel(
              'Booking form fields',
              trailing: TextButton.icon(
                onPressed: () => _editField(context, ref, company.id, fields),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  if (fields.isEmpty)
                    const ListTile(
                      title: Text('No extra fields'),
                      subtitle: Text(
                        'Add what you ask every customer — menu, decoration, ID proof…',
                      ),
                    ),
                  for (var i = 0; i < fields.length; i++)
                    ListTile(
                      leading: Icon(switch (fields[i].type) {
                        BookingFieldType.text => Icons.short_text_rounded,
                        BookingFieldType.number => Icons.pin_outlined,
                        BookingFieldType.select => Icons.list_rounded,
                        BookingFieldType.toggle => Icons.toggle_on_outlined,
                      }),
                      title: Text(fields[i].label),
                      subtitle: fields[i].options.isEmpty
                          ? null
                          : Text(fields[i].options.join(' · ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i > 0)
                            IconButton(
                              tooltip: 'Move up',
                              icon: const Icon(Icons.arrow_upward_rounded),
                              onPressed: () {
                                final next = [...fields];
                                next.insert(i - 1, next.removeAt(i));
                                db.saveBookingFields(company.id, next);
                              },
                            ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => db.saveBookingFields(
                              company.id,
                              [...fields]..removeAt(i),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _editField(
                        context,
                        ref,
                        company.id,
                        fields,
                        index: i,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _changeType(
    BuildContext context,
    WidgetRef ref,
    int companyId,
    BizBusinessType from,
    BizBusinessType to,
  ) async {
    if (from == to) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(to.icon),
        title: Text('Switch to ${to.label}?'),
        content: Text(
          'Screens will speak in ${to.bookingPlural.toLowerCase()} and '
          '${to.resourcePlural.toLowerCase()}. Load the starter setup too? '
          'It adds ${to.resources.isEmpty ? 'nothing' : to.resources.map((r) => r.name).join(', ')} and '
          'replaces your slots and form fields. Existing bookings are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('Keep my setup'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'load'),
            child: const Text('Load starter'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final db = ref.read(dbProvider);
    await db.applyBusinessTemplate(
      companyId,
      to,
      replaceSetup: choice == 'load',
    );
    if (to.defaultBookings) await db.setBookingsEnabled(companyId, true);
  }

  Future<void> _editField(
    BuildContext context,
    WidgetRef ref,
    int companyId,
    List<BookingField> fields, {
    int? index,
  }) async {
    final existing = index == null ? null : fields[index];
    final label = TextEditingController(text: existing?.label ?? '');
    final options = TextEditingController(
      text: existing?.options.join(', ') ?? '',
    );
    var type = existing?.type ?? BookingFieldType.text;
    final saved = await showModalBottomSheet<bool>(
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
                existing == null ? 'New field' : 'Edit field',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: label,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Question',
                  hintText: 'e.g. Mehendi stage, Parking, Projector',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<BookingFieldType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: BookingFieldType.text,
                    label: Text('Text'),
                  ),
                  ButtonSegment(
                    value: BookingFieldType.number,
                    label: Text('Number'),
                  ),
                  ButtonSegment(
                    value: BookingFieldType.select,
                    label: Text('Choice'),
                  ),
                  ButtonSegment(
                    value: BookingFieldType.toggle,
                    label: Text('Yes/No'),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (s) => setState(() => type = s.first),
              ),
              if (type == BookingFieldType.select) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: options,
                  decoration: const InputDecoration(
                    labelText: 'Choices (comma separated)',
                    hintText: 'Veg, Non-veg, Jain',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(sheet, true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Save field'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final text = label.text.trim();
    final opts = options.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    label.dispose();
    options.dispose();
    if (saved != true || text.isEmpty) return;
    if (type == BookingFieldType.select && opts.isEmpty) {
      type = BookingFieldType.text;
    }
    final field = BookingField(
      key: existing?.key ?? 'f${DateTime.now().microsecondsSinceEpoch}',
      label: text,
      type: type,
      options: type == BookingFieldType.select ? opts : const [],
    );
    final next = [...fields];
    index == null ? next.add(field) : next[index] = field;
    await ref.read(dbProvider).saveBookingFields(companyId, next);
  }
}

Future<String?> _askText(
  BuildContext context,
  String title, {
  String? hint,
}) async {
  final c = TextEditingController();
  final v = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, c.text),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  c.dispose();
  final t = v?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// The business-type cards — on company setup and in Booking setup.
class BusinessTypePicker extends StatelessWidget {
  const BusinessTypePicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });
  final BizBusinessType selected;
  final ValueChanged<BizBusinessType> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        for (final t in BizBusinessType.values)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: t == selected ? cs.secondary : Colors.transparent,
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              onTap: () => onSelected(t),
              leading: CircleAvatar(
                backgroundColor: cs.secondary.withValues(
                  alpha: t == selected ? 0.18 : 0.08,
                ),
                foregroundColor: cs.onSurface,
                child: Icon(t.icon),
              ),
              title: Text(
                t.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(t.description),
              trailing: t == selected
                  ? Icon(Icons.check_circle_rounded, color: cs.secondary)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Add or edit a bookable resource.
Future<void> showResourceForm(
  BuildContext context,
  WidgetRef ref, {
  BizBookingResourceRow? resource,
}) async {
  final type = ref.read(bizBusinessTypeProvider);
  final company = ref.read(activeBizCompanyProvider).valueOrNull;
  if (company == null) return;
  final name = TextEditingController(text: resource?.name ?? '');
  final capacity = TextEditingController(
    text: (resource?.capacity ?? 0) == 0 ? '' : '${resource!.capacity}',
  );
  final rate = TextEditingController(
    text: resource == null || resource.rate.isZero
        ? ''
        : resource.rate.rupees.toStringAsFixed(2),
  );
  var shared = resource?.shared ?? (type == BizBusinessType.cinema);
  final result = await showModalBottomSheet<String>(
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      resource == null
                          ? 'New ${type.resourceNoun.toLowerCase()}'
                          : 'Edit ${resource.name}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (resource != null)
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => Navigator.pop(sheet, 'delete'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                autofocus: resource == null,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: '${type.resourceNoun} name',
                  hintText: switch (type) {
                    BizBusinessType.venue =>
                      'e.g. Main Hall, Lawn, Dining Hall',
                    BizBusinessType.cinema => 'e.g. Screen 3 (Gold)',
                    BizBusinessType.hotel => 'e.g. Room 201',
                    _ => null,
                  },
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sell by units (seats, pieces)'),
                subtitle: Text(
                  shared
                      ? 'Many bookings share it until units run out'
                      : 'One booking takes it whole per slot',
                ),
                value: shared,
                onChanged: (v) => setState(() => shared = v),
              ),
              TextField(
                controller: capacity,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: shared
                      ? 'Units available per slot'
                      : 'Capacity (people, optional)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              BizAmountField(
                controller: rate,
                label: 'Default rate ${type.rateBasis.label}',
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(sheet, 'save'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  final db = ref.read(dbProvider);
  final n = name.text.trim();
  final cap = int.tryParse(capacity.text.trim()) ?? 0;
  final r = parseMoney(rate.text);
  name.dispose();
  capacity.dispose();
  rate.dispose();
  if (result == 'delete' && resource != null) {
    final deleted = await db.deleteOrArchiveBookingResource(resource.id);
    if (context.mounted && !deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('It has bookings — archived instead, history kept.'),
        ),
      );
    }
    return;
  }
  if (result != 'save' || n.isEmpty) return;
  if (shared && cap == 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter how many units are available.')),
      );
    }
    return;
  }
  if (resource == null) {
    await db.createBookingResource(
      companyId: company.id,
      name: n,
      capacity: cap,
      shared: shared,
      rate: r,
    );
  } else {
    await db.updateBookingResource(
      resource.copyWith(name: n, capacity: cap, shared: shared, rate: r),
    );
  }
}
