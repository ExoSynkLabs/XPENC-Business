import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../biz_providers.dart';
import 'booking_book.dart';
import 'booking_repository.dart';
import 'business_types.dart';

/// The open company's business type — every booking screen words itself by it.
final bizBusinessTypeProvider = Provider<BizBusinessType>(
  (ref) => BizBusinessType.parse(
    ref.watch(
      activeBizCompanyProvider.select((c) => c.valueOrNull?.businessType),
    ),
  ),
);

final bookingsEnabledProvider = Provider<bool>(
  (ref) => ref.watch(
    activeBizCompanyProvider.select(
      (c) => c.valueOrNull?.bookingsEnabled ?? false,
    ),
  ),
);

final bookingSlotsProvider = Provider<List<String>>(
  (ref) => decodeSlots(
    ref.watch(
      activeBizCompanyProvider.select((c) => c.valueOrNull?.bookingSlots),
    ),
  ),
);

final bookingFieldsProvider = Provider<List<BookingField>>(
  (ref) => BookingField.decodeList(
    ref.watch(
      activeBizCompanyProvider.select((c) => c.valueOrNull?.bookingFields),
    ),
  ),
);

final bookingBookProvider = StreamProvider<BookingBook?>((ref) {
  final companyId = ref.watch(
    activeBizCompanyProvider.select((c) => c.valueOrNull?.id),
  );
  if (companyId == null) return Stream.value(null);
  return ref.watch(dbProvider).watchBookingBook(companyId);
});

/// The day the bookings calendar is showing.
final bookingDayProvider = StateProvider<DateTime>(
  (ref) => dayOf(DateTime.now()),
);
