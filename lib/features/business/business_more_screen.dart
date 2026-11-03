import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/branding/app_info.dart';
import '../../data/business_tables.dart';
import '../../data/providers.dart';
import 'biz_providers.dart';
import 'biz_repository.dart';
import 'biz_widgets.dart';
import 'booking/booking_providers.dart';
import 'booking/booking_setup_screen.dart';
import 'business_home_screen.dart';
import 'items_screen.dart';
import 'ledgers_screen.dart';
import 'reports_screens.dart';

/// The More tab — the company, its setup, masters (ledgers, parties, items)
/// and the app itself.
class BusinessMoreScreen extends ConsumerWidget {
  const BusinessMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final company = ref.watch(activeBizCompanyProvider).valueOrNull;
    final companies = ref.watch(bizCompaniesProvider).valueOrNull ?? const [];
    final type = ref.watch(bizBusinessTypeProvider);
    final bookingsOn = ref.watch(bookingsEnabledProvider);

    final groups = <(String, List<_Item>)>[
      (
        'Business',
        [
          _Item(
            type.icon,
            'Business type & bookings',
            '${type.label} · bookings ${bookingsOn ? 'on' : 'off'}',
            () => pushBizScreen(context, const BookingSetupScreen()),
          ),
          _Item(
            Icons.add_business_outlined,
            'Add another company',
            'Keep several businesses side by side',
            () => pushBizScreen(context, const CompanyFormScreen()),
          ),
        ],
      ),
      (
        'Masters',
        [
          _Item(
            Icons.groups_outlined,
            'Parties',
            'Customers & suppliers',
            () => pushBizScreen(
              context,
              const LedgersScreen(
                title: 'Parties',
                groups: [BizGroup.sundryDebtors, BizGroup.sundryCreditors],
              ),
            ),
          ),
          _Item(
            Icons.account_tree_outlined,
            'Ledgers',
            'All accounts under Tally groups',
            () => pushBizScreen(context, const LedgersScreen()),
          ),
          _Item(
            Icons.inventory_2_outlined,
            'Stock & items',
            'Goods you buy and sell',
            () => pushBizScreen(context, const ItemsScreen()),
          ),
        ],
      ),
      (
        'App',
        [
          _Item(
            Icons.backup_outlined,
            'Backup & Restore',
            'Back up, import & move to a new phone',
            () => context.push('/more/backup'),
          ),
          _Item(
            Icons.settings_outlined,
            'Settings',
            'Currency · theme · passcode',
            () => context.push('/more/settings'),
          ),
          _Item(
            Icons.info_outline_rounded,
            'About ${AppInfo.name}',
            'Version ${AppInfo.version}',
            () => context.push('/more/about'),
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (company != null)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.secondary.withValues(
                    alpha: 0.12,
                  ),
                  foregroundColor: theme.colorScheme.onSurface,
                  child: Icon(type.icon),
                ),
                title: Text(
                  company.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  [
                    type.label,
                    if (company.gstin != null) 'GSTIN ${company.gstin}',
                    if (companies.length > 1) '${companies.length} companies',
                  ].join(' · '),
                ),
                trailing: IconButton(
                  tooltip: 'Edit company',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => pushBizScreen(
                    context,
                    CompanyFormScreen(company: company),
                  ),
                ),
              ),
            ),
          if (companies.length > 1) ...[
            const BizSectionLabel('Switch company'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final c in companies)
                    ListTile(
                      leading: Icon(
                        c.id == company?.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(c.name),
                      onTap: () {
                        ref.read(bizPeriodOverrideProvider.notifier).state =
                            null;
                        ref.read(dbProvider).setActiveBizCompany(c.id);
                      },
                    ),
                ],
              ),
            ),
          ],
          for (final (title, items) in groups) ...[
            BizSectionLabel(title),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 60,
                        color: theme.colorScheme.outline,
                      ),
                    ListTile(
                      leading: Icon(items[i].icon),
                      title: Text(items[i].title),
                      subtitle: Text(items[i].subtitle),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: items[i].onTap,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Item {
  const _Item(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}
