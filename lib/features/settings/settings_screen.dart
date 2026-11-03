import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/branding/app_info.dart';
import '../../core/branding/brand_mark.dart';
import '../../data/providers.dart';
import 'currency_picker_sheet.dart';
import 'theme_picker_sheet.dart';

/// App preferences: currency, theme, security, and clearing data.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final preset = ref.watch(themePresetProvider);
    final currency = ref.watch(currencyProvider);
    final showSymbol = ref.watch(showCurrencySymbolProvider);
    final hasPasscode = ref.watch(hasPasscodeProvider);
    final biometricEnabled = ref.watch(biometricEnabledProvider);
    final preventScreenshots = ref.watch(preventScreenshotsProvider);

    final trailingStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          // ── General ────────────────────────────────────────────────────────
          _sectionLabel(context, 'General'),
          Card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Currency'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${currency.symbol} ${currency.code}',
                        style: trailingStyle,
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                  onTap: () => CurrencyPickerSheet.show(context, ref),
                ),
                Divider(height: 1, indent: 60, color: cs.outline),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  secondary: const Icon(Icons.attach_money_rounded),
                  title: const Text('Show currency symbol'),
                  subtitle: Text(
                    showSymbol
                        ? 'Amounts show ${currency.symbol}'
                        : 'Amounts show plain numbers — use this if your '
                              'currency symbol is missing',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  value: showSymbol,
                  onChanged: (v) =>
                      ref.read(dbProvider).setShowCurrencySymbol(v),
                ),
                Divider(height: 1, indent: 60, color: cs.outline),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(preset.icon),
                  title: const Text('Theme'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(preset.label, style: trailingStyle),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                  onTap: () => ThemePickerSheet.show(context),
                ),
              ],
            ),
          ),

          // ── Security ───────────────────────────────────────────────────────
          _sectionLabel(context, 'Security'),
          Card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.lock_outline_rounded),
                  title: Text(hasPasscode ? 'Change passcode' : 'Set passcode'),
                  subtitle: Text(
                    hasPasscode
                        ? 'A PIN is required to open the app'
                        : 'Require a PIN to open the app',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  onTap: () => context.push('/more/settings/passcode'),
                ),
                if (hasPasscode) ...[
                  Divider(height: 1, indent: 60, color: cs.outline),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    secondary: const Icon(Icons.fingerprint_rounded),
                    title: const Text('Biometric unlock'),
                    subtitle: Text(
                      'Use your fingerprint or face instead of the PIN — the '
                      'PIN always still works',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: biometricEnabled,
                    onChanged: (v) =>
                        ref.read(dbProvider).setBiometricEnabled(v),
                  ),
                  Divider(height: 1, indent: 60, color: cs.outline),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(Icons.lock_open_outlined, color: cs.error),
                    title: Text(
                      'Remove passcode',
                      style: TextStyle(color: cs.error),
                    ),
                    onTap: () =>
                        context.push('/more/settings/passcode?remove=true'),
                  ),
                ],
                Divider(height: 1, indent: 60, color: cs.outline),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  secondary: const Icon(Icons.screenshot_outlined),
                  title: const Text('Block screenshots'),
                  subtitle: Text(
                    'Hides the app from screenshots, screen recording and the '
                    'recent-apps thumbnail',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  value: preventScreenshots,
                  onChanged: (v) =>
                      ref.read(dbProvider).setPreventScreenshots(v),
                ),
              ],
            ),
          ),

          _sectionLabel(context, 'Data'),
          Card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(Icons.delete_forever_outlined, color: cs.error),
                  title: Text(
                    'Clear all data',
                    style: TextStyle(color: cs.error),
                  ),
                  subtitle: Text(
                    'Wipe every company, ledger, voucher and booking, and '
                    'start fresh. A safety backup is saved first.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _clearAllData(context, ref),
                ),
              ],
            ),
          ),

          // ── About ──────────────────────────────────────────────────────────
          _sectionLabel(context, 'About'),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: const BrandMark(size: 34),
              title: const Text('${AppInfo.name} · ${AppInfo.version}'),
              subtitle: Text(
                'Developer, links and build info',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/more/about'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  /// A safety backup is taken first — same convention as restoring or
  /// importing a backup elsewhere in this screen's family — so a mistaken
  /// tap is recoverable from Backup & Restore afterward.
  Future<void> _clearAllData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
          'This wipes every company, ledger, voucher, item and booking on '
          'this phone, then starts fresh like a new install. A safety '
          'backup is saved to '
          'Download/BACKUP XPENC first — restore it from Backup & Restore '
          'if this was a mistake.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(backupServiceProvider).createBackup();
      await ref.read(dbProvider).clearAllData();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('All data cleared. A safety backup was saved.'),
          ),
        );
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text("Couldn't clear data: $e")));
    }
  }
}
