import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../biz_providers.dart';
import 'booking_providers.dart';
import 'booking_repository.dart';
import 'booking_setup_screen.dart';
import 'bookings_screen.dart';

/// The Bookings tab: the calendar when bookings are on, otherwise a short
/// pitch with a one-tap switch — so the tab is never a dead end.
class BookingsTab extends ConsumerWidget {
  const BookingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(bookingsEnabledProvider)) return const BookingsScreen();
    final theme = Theme.of(context);
    final type = ref.watch(bizBusinessTypeProvider);
    final company = ref.watch(activeBizCompanyProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Bookings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.event_available_rounded,
            size: 64,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            'Take bookings',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Halls and lawns, screens and seats, rooms, chairs, courts or rentals — '
            'see what’s free each day, register customers with their requirements, '
            'stop double-bookings, and post advances straight into your books.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: company == null
                ? null
                : () =>
                      ref.read(dbProvider).setBookingsEnabled(company.id, true),
            icon: const Icon(Icons.toggle_on_outlined),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Turn on ${type.bookingPlural.toLowerCase()}'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => pushBooking(context, const BookingSetupScreen()),
            icon: const Icon(Icons.storefront_outlined),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Choose business type first'),
            ),
          ),
        ],
      ),
    );
  }
}
