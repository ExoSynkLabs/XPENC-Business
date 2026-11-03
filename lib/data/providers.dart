import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/currency.dart';
import '../core/theme/theme_preset.dart';
import '../features/data_export/backup_service.dart';
import 'database.dart';
import 'tables.dart';

// XPENC Business keeps only the app-wide plumbing here — the database,
// settings, theme, currency, security and backups. Everything business
// lives in `features/business/` (see biz_providers.dart and
// booking/booking_providers.dart).

final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Opens the database once at startup and surfaces the failure loudly.
///
/// Drift opens lazily on first query, so a broken native library (a missing
/// `libsqlite3.so`, for instance) used to show up as every screen spinning
/// forever. Touching the DB here turns that into a visible error with a retry.
final databaseReadyProvider = FutureProvider<bool>((ref) async {
  await ref.watch(dbProvider).getSettings();
  return true;
});

final settingsProvider = StreamProvider<SettingRow>(
  (ref) => ref.watch(dbProvider).watchSettings(),
);

/// The theme the user picked. Falls back to [ThemePreset.fallback] while the
/// settings row is loading, and if the database never opens — the app must
/// still be able to paint its own error screen.
final themePresetProvider = Provider<ThemePreset>((ref) {
  final name = ref.watch(settingsProvider).valueOrNull?.themeName;
  return ThemePreset.fromName(name);
});

/// The currency the user picked. An unknown code degrades to the default, so a
/// bad setting never blanks out every amount in the app.
final currencyProvider = Provider<Currency>((ref) {
  final code = ref.watch(settingsProvider).valueOrNull?.currencyCode;
  return currencyForCode(code);
});

/// Whether to draw the currency symbol. Defaults to shown while settings load.
final showCurrencySymbolProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.showCurrencySymbol ?? true;
});

/// Whether a passcode is set at all — the switch the app-lock gate checks on
/// every launch and resume.
final hasPasscodeProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.passcodeHash != null;
});

final biometricEnabledProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.biometricEnabled ?? false;
});

/// The current passcode's digit count — 4, 5 or 6. Null in [Settings] means
/// 4 (every passcode set before length was configurable, see GitHub #18).
final passcodeLengthProvider = Provider<int>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.passcodeLength ?? 4;
});

final preventScreenshotsProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.preventScreenshots ?? false;
});

/// Whether every amount app-wide is masked — the top bar's eye icon. See
/// `AmountVisibilityScope` in `money_text.dart`.
final hideAmountsProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.hideAmounts ?? false;
});

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(dbProvider)),
);

/// The live list of known backups. Reads `AppDatabase.watchBackupRecords`
/// directly (a real stream) rather than `BackupService.listBackups` (a
/// one-shot snapshot), so the screen updates itself after every backup or
/// delete with no explicit `ref.invalidate` needed.
final backupRecordsProvider = StreamProvider<List<BackupRecordRow>>(
  (ref) => ref.watch(dbProvider).watchBackupRecords(),
);

/// Auto-backup schedule + retention, straight off [Settings] — a safe
/// default (off) while settings are still loading.
typedef AutoBackupSettings = ({
  bool enabled,
  AutoBackupFrequency frequency,
  int customDays,
  int customHours,
  int retentionDays,
  DateTime? lastAutoBackupAt,
});

final autoBackupSettingsProvider = Provider<AutoBackupSettings>((ref) {
  final s = ref.watch(settingsProvider).valueOrNull;
  return (
    enabled: s?.autoBackupEnabled ?? false,
    frequency: s?.autoBackupFrequency ?? AutoBackupFrequency.daily,
    customDays: s?.autoBackupCustomDays ?? 0,
    customHours: s?.autoBackupCustomHours ?? 0,
    retentionDays: s?.backupRetentionDays ?? 180,
    lastAutoBackupAt: s?.lastAutoBackupAt,
  );
});
