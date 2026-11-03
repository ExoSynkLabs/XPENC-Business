import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/business_tables.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import 'biz_book.dart';
import 'biz_repository.dart';

final bizCompaniesProvider = StreamProvider<List<BizCompanyRow>>(
  (ref) => ref.watch(dbProvider).watchBizCompanies(),
);

final activeBizCompanyProvider = StreamProvider<BizCompanyRow?>(
  (ref) => ref.watch(dbProvider).watchActiveBizCompany(),
);

/// The open company's whole book, refreshed on every change.
final bizBookProvider = StreamProvider<BizBook?>((ref) {
  final companyId = ref.watch(
    activeBizCompanyProvider.select((c) => c.valueOrNull?.id),
  );
  if (companyId == null) return Stream.value(null);
  return ref.watch(dbProvider).watchBizBook(companyId);
});

/// A period the user picked. Null = the current financial year.
final bizPeriodOverrideProvider = StateProvider<BizPeriod?>((ref) => null);

/// The period every business report is shown for.
final bizPeriodProvider = Provider<BizPeriod>((ref) {
  final picked = ref.watch(bizPeriodOverrideProvider);
  if (picked != null) return picked;
  final fyStart = ref.watch(
    activeBizCompanyProvider.select((c) => c.valueOrNull?.fyStartMonth ?? 4),
  );
  return BizPeriod.financialYear(DateTime.now(), fyStart);
});

/// Voucher-type filter on the Day Book. Empty = all.
final bizDayBookFilterProvider = StateProvider<Set<BizVoucherType>>(
  (ref) => const {},
);
