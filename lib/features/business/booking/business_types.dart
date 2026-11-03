import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/money.dart';

/// The kind of value a custom booking field holds.
enum BookingFieldType { text, number, select, toggle }

/// A per-company custom field on the booking form ("Food: Veg / Non-veg",
/// "Movie", "Meal plan"). The business type seeds a sensible set; the user
/// can add, rename or remove them.
class BookingField {
  const BookingField({
    required this.key,
    required this.label,
    this.type = BookingFieldType.text,
    this.options = const [],
  });

  final String key;
  final String label;
  final BookingFieldType type;
  final List<String> options;

  Map<String, Object?> toJson() => {
    'key': key,
    'label': label,
    'type': type.name,
    if (options.isNotEmpty) 'options': options,
  };

  static BookingField? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'], label = json['label'];
    if (key is! String || label is! String) return null;
    return BookingField(
      key: key,
      label: label,
      type: BookingFieldType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => BookingFieldType.text,
      ),
      options: (json['options'] as List? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }

  static List<BookingField> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.map(fromJson).whereType<BookingField>().toList();
    } on FormatException {
      return const [];
    }
  }

  static String encodeList(List<BookingField> fields) =>
      jsonEncode(fields.map((f) => f.toJson()).toList());
}

List<String> decodeSlots(String? raw) {
  if (raw == null || raw.isEmpty) return const [kFullDay];
  try {
    final list = jsonDecode(raw);
    final slots = list is List ? list.whereType<String>().toList() : <String>[];
    return slots.isEmpty ? const [kFullDay] : slots;
  } on FormatException {
    return const [kFullDay];
  }
}

String encodeSlots(List<String> slots) => jsonEncode(slots);

/// A slot that takes the whole day — it clashes with every other slot.
const kFullDay = 'Full day';

/// How a resource's rate multiplies.
enum RateBasis {
  perDay('per day'),
  perNight('per night'),
  perUnit('each'),
  perBooking('per booking');

  const RateBasis(this.label);
  final String label;
}

/// A template resource seeded for a business type.
typedef ResourceTemplate = ({String name, int capacity, bool shared, num rate});

/// Every business XPENC can personalise itself for. Each type brings its own
/// words (Event / Show / Stay / Appointment), starter resources, time slots
/// and custom fields — all editable afterwards, so the template is only a
/// starting point, never a cage.
enum BizBusinessType {
  general(
    label: 'Accounting only',
    description: 'Shop, trading, services — books without bookings',
    icon: Icons.calculate_outlined,
    bookingNoun: 'Booking',
    resourceNoun: 'Resource',
    peopleLabel: 'People',
    incomeLedger: 'Booking Income',
    rateBasis: RateBasis.perBooking,
    multiDay: false,
    defaultBookings: false,
    slots: [kFullDay],
    resources: [],
    fields: [],
  ),
  venue(
    label: 'Wedding hall / Venue',
    description: 'Halls, lawns, banquets — events by date and session',
    icon: Icons.celebration_outlined,
    bookingNoun: 'Event',
    resourceNoun: 'Hall',
    peopleLabel: 'Expected guests',
    incomeLedger: 'Hall Rent',
    rateBasis: RateBasis.perDay,
    multiDay: true,
    slots: ['Morning', 'Evening', kFullDay],
    resources: [
      (name: 'Main Hall', capacity: 800, shared: false, rate: 50000),
      (name: 'Dining Hall', capacity: 400, shared: false, rate: 20000),
      (name: 'Lawn', capacity: 1500, shared: false, rate: 40000),
    ],
    fields: [
      BookingField(
        key: 'eventType',
        label: 'Event type',
        type: BookingFieldType.select,
        options: [
          'Wedding',
          'Reception',
          'Engagement',
          'Birthday',
          'Corporate',
          'Other',
        ],
      ),
      BookingField(
        key: 'food',
        label: 'Food',
        type: BookingFieldType.select,
        options: ['Veg', 'Non-veg', 'Veg + Non-veg', 'Not needed'],
      ),
      BookingField(
        key: 'plates',
        label: 'Catering plates',
        type: BookingFieldType.number,
      ),
      BookingField(
        key: 'decoration',
        label: 'Decoration',
        type: BookingFieldType.toggle,
      ),
      BookingField(
        key: 'sound',
        label: 'DJ / Sound system',
        type: BookingFieldType.toggle,
      ),
      BookingField(
        key: 'rooms',
        label: 'Rooms for guests',
        type: BookingFieldType.number,
      ),
      BookingField(
        key: 'generator',
        label: 'Generator backup',
        type: BookingFieldType.toggle,
      ),
    ],
  ),
  cinema(
    label: 'Movie theatre',
    description: 'Screens, shows and seats',
    icon: Icons.movie_outlined,
    bookingNoun: 'Ticket booking',
    resourceNoun: 'Screen',
    peopleLabel: 'Seats',
    incomeLedger: 'Ticket Sales',
    rateBasis: RateBasis.perUnit,
    multiDay: false,
    slots: ['10:00 AM', '1:30 PM', '5:00 PM', '9:00 PM'],
    resources: [
      (name: 'Screen 1', capacity: 150, shared: true, rate: 180),
      (name: 'Screen 2', capacity: 90, shared: true, rate: 200),
    ],
    fields: [
      BookingField(key: 'movie', label: 'Movie'),
      BookingField(
        key: 'language',
        label: 'Language',
        type: BookingFieldType.select,
        options: ['Marathi', 'Hindi', 'English', 'Other'],
      ),
      BookingField(
        key: 'seatClass',
        label: 'Seat class',
        type: BookingFieldType.select,
        options: ['Regular', 'Premium', 'Recliner'],
      ),
      BookingField(key: 'seatNos', label: 'Seat numbers'),
    ],
  ),
  hotel(
    label: 'Hotel / Lodge / Homestay',
    description: 'Rooms by night — check-in to check-out',
    icon: Icons.hotel_outlined,
    bookingNoun: 'Stay',
    resourceNoun: 'Room',
    peopleLabel: 'Guests',
    incomeLedger: 'Room Revenue',
    rateBasis: RateBasis.perNight,
    multiDay: true,
    slots: [kFullDay],
    resources: [
      (name: 'Room 101', capacity: 2, shared: false, rate: 1500),
      (name: 'Room 102', capacity: 2, shared: false, rate: 1500),
      (name: 'Deluxe Suite', capacity: 4, shared: false, rate: 3500),
    ],
    fields: [
      BookingField(
        key: 'mealPlan',
        label: 'Meal plan',
        type: BookingFieldType.select,
        options: ['Room only', 'Breakfast', 'Half board', 'Full board'],
      ),
      BookingField(key: 'idProof', label: 'ID proof'),
      BookingField(key: 'vehicle', label: 'Vehicle no.'),
      BookingField(
        key: 'extraBed',
        label: 'Extra bed',
        type: BookingFieldType.toggle,
      ),
    ],
  ),
  appointments(
    label: 'Salon / Clinic / Services',
    description: 'Appointments by time slot and staff',
    icon: Icons.event_available_outlined,
    bookingNoun: 'Appointment',
    resourceNoun: 'Staff / Chair',
    peopleLabel: 'People',
    incomeLedger: 'Service Income',
    rateBasis: RateBasis.perBooking,
    multiDay: false,
    slots: [
      '10:00 AM',
      '11:00 AM',
      '12:00 PM',
      '2:00 PM',
      '3:00 PM',
      '4:00 PM',
      '5:00 PM',
      '6:00 PM',
    ],
    resources: [
      (name: 'Chair 1', capacity: 1, shared: false, rate: 300),
      (name: 'Chair 2', capacity: 1, shared: false, rate: 300),
    ],
    fields: [
      BookingField(key: 'service', label: 'Service'),
      BookingField(key: 'staff', label: 'Preferred staff'),
      BookingField(
        key: 'reminder',
        label: 'Send reminder',
        type: BookingFieldType.toggle,
      ),
    ],
  ),
  rentals(
    label: 'Rentals',
    description: 'Vehicles, equipment, tents, costumes by the day',
    icon: Icons.key_outlined,
    bookingNoun: 'Rental',
    resourceNoun: 'Item',
    peopleLabel: 'People',
    incomeLedger: 'Rental Income',
    rateBasis: RateBasis.perDay,
    multiDay: true,
    slots: [kFullDay],
    resources: [
      (name: 'Car (Innova)', capacity: 0, shared: false, rate: 3500),
      (name: 'Chairs', capacity: 500, shared: true, rate: 10),
    ],
    fields: [
      BookingField(
        key: 'deposit',
        label: 'Security deposit',
        type: BookingFieldType.number,
      ),
      BookingField(key: 'idProof', label: 'ID proof'),
      BookingField(
        key: 'delivery',
        label: 'Delivery needed',
        type: BookingFieldType.toggle,
      ),
    ],
  ),
  sports(
    label: 'Turf / Sports court',
    description: 'Courts and grounds by the hour',
    icon: Icons.sports_soccer_outlined,
    bookingNoun: 'Slot booking',
    resourceNoun: 'Court',
    peopleLabel: 'Players',
    incomeLedger: 'Turf Income',
    rateBasis: RateBasis.perBooking,
    multiDay: false,
    slots: [
      '6–7 AM',
      '7–8 AM',
      '5–6 PM',
      '6–7 PM',
      '7–8 PM',
      '8–9 PM',
      '9–10 PM',
    ],
    resources: [
      (name: 'Turf A', capacity: 14, shared: false, rate: 1200),
      (name: 'Turf B', capacity: 14, shared: false, rate: 1000),
    ],
    fields: [
      BookingField(
        key: 'sport',
        label: 'Sport',
        type: BookingFieldType.select,
        options: ['Football', 'Cricket', 'Badminton', 'Other'],
      ),
      BookingField(key: 'team', label: 'Team name'),
    ],
  ),
  custom(
    label: 'Other business',
    description: 'Start blank and design your own booking form',
    icon: Icons.tune_rounded,
    bookingNoun: 'Booking',
    resourceNoun: 'Resource',
    peopleLabel: 'People',
    incomeLedger: 'Booking Income',
    rateBasis: RateBasis.perBooking,
    multiDay: true,
    slots: [kFullDay],
    resources: [],
    fields: [],
  );

  const BizBusinessType({
    required this.label,
    required this.description,
    required this.icon,
    required this.bookingNoun,
    required this.resourceNoun,
    required this.peopleLabel,
    required this.incomeLedger,
    required this.rateBasis,
    required this.multiDay,
    required this.slots,
    required this.resources,
    required this.fields,
    this.defaultBookings = true,
  });

  final String label;
  final String description;
  final IconData icon;

  /// What one booking is called — "Event", "Stay", "Appointment".
  final String bookingNoun;

  /// What gets booked — "Hall", "Screen", "Room".
  final String resourceNoun;
  final String peopleLabel;

  /// Name of the income ledger booking bills post to.
  final String incomeLedger;
  final RateBasis rateBasis;

  /// Can a booking span several dates (a 3-day wedding, a hotel stay)?
  final bool multiDay;

  /// Is the Bookings module on by default for this type?
  final bool defaultBookings;
  final List<String> slots;
  final List<ResourceTemplate> resources;
  final List<BookingField> fields;

  String get bookingPlural => switch (this) {
    venue => 'Events',
    cinema => 'Ticket bookings',
    hotel => 'Stays',
    appointments => 'Appointments',
    rentals => 'Rentals',
    sports => 'Slot bookings',
    _ => 'Bookings',
  };

  String get resourcePlural => switch (this) {
    venue => 'Halls',
    cinema => 'Screens',
    hotel => 'Rooms',
    appointments => 'Staff / Chairs',
    rentals => 'Items',
    sports => 'Courts',
    _ => 'Resources',
  };

  static BizBusinessType parse(String? name) => BizBusinessType.values
      .firstWhere((t) => t.name == name, orElse: () => BizBusinessType.general);

  Money templateRate(ResourceTemplate r) => Money.fromRupees(r.rate);
}
