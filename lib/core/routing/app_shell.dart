import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/business/biz_providers.dart';
import '../../features/business/booking/booking_providers.dart';
import '../../features/business/business_home_screen.dart';
import '../../features/business/day_book_screen.dart';

/// `Home · Bookings · ➕ · Reports · More` — the ➕ slot is not a tab; it opens
/// the "what happened?" sheet. Tabs map to shell branches 0..3 while sitting
/// at bar slots 0, 1, 3, 4.
///
/// Until a company exists there is nothing to navigate, so the shell shows
/// company setup full-screen with no bar.
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int branchIndex) => navigationShell.goBranch(
    branchIndex,
    initialLocation: branchIndex == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(activeBizCompanyProvider);
    if (company.hasValue && company.value == null) {
      return const CompanyFormScreen(firstRun: true);
    }
    final type = ref.watch(bizBusinessTypeProvider);
    final theme = Theme.of(context);
    final tabs = <_TabSpec>[
      const _TabSpec(
        0,
        Icons.space_dashboard_outlined,
        Icons.space_dashboard_rounded,
        'Home',
      ),
      _TabSpec(
        1,
        Icons.calendar_month_outlined,
        Icons.calendar_month_rounded,
        _short(type.bookingPlural),
      ),
      const _TabSpec(
        2,
        Icons.insert_chart_outlined_rounded,
        Icons.insert_chart_rounded,
        'Reports',
      ),
      const _TabSpec(
        3,
        Icons.grid_view_outlined,
        Icons.grid_view_rounded,
        'More',
      ),
    ];

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colorScheme.outline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                _navItem(context, tabs[0]),
                _navItem(context, tabs[1]),
                _addButton(context),
                _navItem(context, tabs[2]),
                _navItem(context, tabs[3]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "Ticket bookings" doesn't fit under an icon.
  static String _short(String plural) => plural
      .split(' ')
      .last
      .replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase());

  Widget _navItem(BuildContext context, _TabSpec tab) {
    final theme = Theme.of(context);
    final selected = navigationShell.currentIndex == tab.branch;
    final color = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: () => _goBranch(tab.branch),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? tab.activeIcon : tab.icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addButton(BuildContext context) => Expanded(
    child: Center(
      child: Material(
        color: Theme.of(context).colorScheme.secondary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => showNewEntrySheet(context),
          child: const SizedBox(
            width: 52,
            height: 52,
            child: Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
        ),
      ),
    ),
  );
}

class _TabSpec {
  const _TabSpec(this.branch, this.icon, this.activeIcon, this.label);
  final int branch;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}
