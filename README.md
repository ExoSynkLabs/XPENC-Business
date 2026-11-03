
<div align="center">

# XPENC Business

**Tally-style books and bookings for your business — on your phone, offline.**

[![Release](https://img.shields.io/github/v/release/GeabNet/XPENC-Business?label=release&color=white&labelColor=black)](https://github.com/GeabNet/XPENC-Business/releases/latest)
[![Release APK](https://github.com/GeabNet/XPENC-Business/actions/workflows/release.yml/badge.svg)](https://github.com/GeabNet/XPENC-Business/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-white?labelColor=black)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.38.9-02569B?logo=flutter&logoColor=white&labelColor=black)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android%207.0%2B-3DDC84?logo=android&logoColor=white&labelColor=black)](https://github.com/GeabNet/XPENC-Business/releases/latest)

Capital, loans, purchases, sales with GST, expenses and income as real double-entry
vouchers — plus bookings for halls, screens, rooms, chairs, courts and rentals.
Everything lives in a local SQLite database on your phone. Nothing is ever uploaded.

[**⬇️ Download APK**](https://github.com/GeabNet/XPENC-Business/releases/latest) · [**🐛 Report a bug**](../../issues/new?template=bug_report.yml) · [**✨ Request a feature**](../../issues/new?template=feature_request.yml)

</div>

---

XPENC Business is a separate app built from [XPENC](https://github.com/PATILYASHH/XPENC)'s
engine. XPENC is for personal money; XPENC Business is only for running a business. It
has its own app ID (`com.yash.xpenc.business`), so both can sit on one phone.

## Features

| | |
|---|---|
| 🏪 **Tally-style books** | Double entry under Tally's groups — Capital, Loans, Sundry Debtors/Creditors, Duties & Taxes, Fixed Assets, Investments, Bank, Cash, Sales, Purchase, Direct/Indirect Income & Expense. Every voucher's debits equal its credits. |
| ✍️ **Plain-language entries** | Capital invested, drawings, loan taken / repaid / given / recovered, investment made / redeemed, asset bought, sale, purchase, returns, income, expense, receive / make payment, cash ↔ bank, journal — no Dr/Cr knowledge needed. |
| 🧾 **Bills with GST & stock** | Sales and purchase bills with items or a plain amount and a GST rate (0–28%) posted to Output/Input GST. Stock quantities update from bills; stock is valued automatically at weighted-average cost. |
| 📊 **Reports** | Day Book, ledger statements, Trial Balance, Profit & Loss, Balance Sheet, receivables & payables, GST summary, stock summary — by financial year, month or any range. Day Book exports to CSV. |
| 📅 **Bookings, personalised by business type** | Wedding hall / venue, movie theatre, hotel, salon / clinic, rentals, turf or your own: your halls / screens / rooms, sessions or show times and form fields. See what's free each day, register customers with their requirements, stop double-bookings (seats sell up to capacity). Advances post as Receipts and the bill as a Sale. Share a booking slip. |
| 🏢 **Several companies** | Keep more than one business side by side and switch in one tap. |
| 🔒 **Private by design** | Offline, no account, no server. Optional passcode with biometric unlock, block screenshots, hide amounts. |
| 💾 **Backup & restore** | One JSON backup of everything, saved to `Download/BACKUP XPENC` so it survives an uninstall, with an optional automatic schedule. |

## Download

Grab it from [**Releases**](https://github.com/GeabNet/XPENC-Business/releases/latest):

| Your phone | Asset |
|---|---|
| Most phones (~2017+) | [`xpenc-business-arm64-v8a.apk`](https://github.com/GeabNet/XPENC-Business/releases/latest/download/xpenc-business-arm64-v8a.apk) |
| Older 32-bit phones | [`xpenc-business-armeabi-v7a.apk`](https://github.com/GeabNet/XPENC-Business/releases/latest/download/xpenc-business-armeabi-v7a.apk) |
| Emulators | [`xpenc-business-x86_64.apk`](https://github.com/GeabNet/XPENC-Business/releases/latest/download/xpenc-business-x86_64.apk) |

Every release ships `SHA256SUMS.txt` — verify your download. APKs are built, tested
and published by [GitHub Actions](.github/workflows/release.yml) from a `v*` tag
(or a manual run of that workflow).

## Privacy

Everything is stored on-device in the app's private SQLite database. The app asks
for **no runtime permissions** — no SMS, no notifications, no contacts, no location.
**There is no server.** See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Tech stack

| Concern | Choice |
|---|---|
| Framework | Flutter 3.38.9 · Dart 3.10.8 |
| State | Riverpod |
| Database | Drift (SQLite), local-first, reactive queries |
| Routing | go_router |
| Charts | fl_chart |
| Notifications | flutter_local_notifications + timezone |

> ⚠️ Several packages are **deliberately pinned** (drift 2.31.0, riverpod 2.6.1, …).
> Do not bump them without reading the "Pinned dependencies" section of
> [CONTRIBUTING.md](CONTRIBUTING.md) — one of those bumps once shipped an APK
> that crashed on first open.

## Building from source

```sh
git clone https://github.com/PATILYASHH/XPENC.git
cd XPENC
flutter pub get
flutter run
```

### Tests

```sh
rm -rf build/native_assets   # Windows only: Flutter native-assets bug
flutter analyze
flutter test
```

The widget tests render every screen against a real in-memory database at a real
phone size (360 × 800 dp) and fail on a layout overflow, so they catch what
`flutter analyze` cannot. `test/branding_test.dart` additionally fails the build
if `AppInfo.version` ever drifts from the `version:` line in `pubspec.yaml`.

### Shipping an APK

```sh
flutter build apk --release --split-per-abi
bash tool/verify_apk.sh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

`verify_apk.sh` **must pass.** It is the only thing standing between you and
shipping an APK with no `libsqlite3.so` — a failure no unit test can see,
because every test overrides the database with an in-memory one.

### Code generation

Database classes are generated from `lib/data/tables.dart` by drift. After
changing a table:

```sh
dart run build_runner build --force-jit --delete-conflicting-outputs
```

**`--force-jit` is required** — without it build_runner fails with
`'dart compile' does not support build hooks` on this SDK. Schema-change
steps are in [CONTRIBUTING.md](CONTRIBUTING.md#changing-the-database-schema).

## Brand

<img src="branding/xpenc_icon_512.png" width="72" align="right" alt="XPENC icon">

Every asset — launcher icons, adaptive icon, Android 13 themed icon, splash
marks, favicons and the website icons — is generated from **one geometric
definition**:

```sh
python tool/generate_icons.py
```

Nothing is hand-drawn, so the icons cannot drift out of sync. The in-app logo
(`lib/core/branding/brand_mark.dart`) redraws the same geometry as a
`CustomPainter`, so it stays sharp at any size and follows the theme.

## Project structure

```
lib/
  core/          theme, Money type, branding, notifications
  data/          drift database, tables, DAOs, seed data
  domain/        entities, repository interfaces
  features/      one folder per screen (dashboard, transactions, budgets, …)
website/         landing page (Vercel)
tool/            icon generator, APK verification gate
.github/         CI + release workflows, issue & PR templates
docs/            releasing / maintainer docs
```

## Contributing

Contributions are very welcome — the highest-impact one is
[**adding an SMS template for your bank**](../../issues/new?template=bank_support.yml)
(config + regex, no app internals needed).

- 📖 [CONTRIBUTING.md](CONTRIBUTING.md) — setup, invariants, PR checklist
- 🤝 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- 🔒 [SECURITY.md](SECURITY.md) — private vulnerability reporting
- 📦 [CHANGELOG.md](CHANGELOG.md) · [docs/RELEASING.md](docs/RELEASING.md) — SemVer, `v*` tags, automated releases

## Sponsor

XPENC is free, open source, and has no ads, no trackers and no paid tier — and
it stays that way. If it keeps your money honest, you can fund the work:

[![Sponsor XPENC](https://img.shields.io/badge/♥%20Sponsor-PATILYASHH-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white&labelColor=black)](https://github.com/sponsors/PATILYASHH)

Not in a position to sponsor? A ⭐, a bug report, or
[an SMS template for your bank](../../issues/new?template=bank_support.yml)
helps just as much.

## Developer

**Yash Patil** — GitHub [@PATILYASHH](https://github.com/PATILYASHH) · LinkedIn [in/patilyasshh](https://www.linkedin.com/in/patilyasshh/)

## License

[MIT](LICENSE) © 2026 Yash Patil

<div align="center">
<sub>If XPENC keeps your money honest, a ⭐ keeps the project alive.</sub>
</div>
