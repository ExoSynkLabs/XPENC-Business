import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:xpenc/core/routing/app_router.dart';
import 'package:xpenc/core/theme/app_theme.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/data/providers.dart';
import 'package:xpenc/features/business/biz_repository.dart';
import 'package:xpenc/features/business/booking/business_types.dart';

/// XPENC Business is business-first: no personal dashboard, transactions or
/// persons — the shell is `Home · Bookings · ➕ · Reports · More`, and the
/// app opens on company setup until a company exists.
///
/// Same rules as the other widget tests: DB work in `runAsync`, no
/// `pumpAndSettle`, unmount before the test ends.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appRouter.go('/home');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: appRouter,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('with no company the app opens on business setup, no tabs', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Create company'), findsOneWidget);
    expect(find.text('Reports'), findsNothing);
    // Nothing from the personal app.
    expect(find.text('Transactions'), findsNothing);
    expect(find.text('Persons'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
    'a venue gets Home · Events · ➕ · Reports · More and every tab renders',
    (tester) async {
      await tester.runAsync(
        () => db.createBizCompany(
          name: 'Shubh Mangal Hall',
          businessType: BizBusinessType.venue,
        ),
      );
      await pumpApp(tester);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Events'), findsWidgets);
      expect(find.text('Cash & Bank'), findsOneWidget);

      await tester.tap(find.text('Reports').last);
      await settle(tester);
      expect(find.text('FINANCIAL STATEMENTS'), findsOneWidget);

      await tester.tap(find.text('More').last);
      await settle(tester);
      expect(find.text('MASTERS'), findsOneWidget);
      expect(find.text('Shubh Mangal Hall'), findsOneWidget);

      await tester.tap(find.text('Events').last);
      await settle(tester);
      expect(find.text('Main Hall'), findsWidgets);

      // ➕ offers the booking first, then the vouchers.
      await tester.tap(find.byIcon(Icons.add_rounded).last);
      await settle(tester);
      expect(find.text('New event'), findsWidgets);
      expect(find.text('Sale'), findsWidgets);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'an accounting-only company gets a Bookings tab that offers to turn them on',
    (tester) async {
      await tester.runAsync(() => db.createBizCompany(name: 'Kirana Stores'));
      await pumpApp(tester);
      await tester.tap(find.text('Bookings').last);
      await settle(tester);
      expect(find.text('Turn on bookings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  test('every route belongs to the business app', () {
    final paths = <String>[];
    void walk(List<RouteBase> routes) {
      for (final r in routes) {
        if (r is GoRoute) paths.add(r.path);
        walk(r.routes);
      }
    }

    walk(appRouter.configuration.routes);
    expect(
      paths,
      containsAll([
        '/home',
        '/bookings',
        '/reports',
        '/more',
        'settings',
        'backup',
        'about',
      ]),
    );
    for (final personal in [
      '/dashboard',
      '/transactions',
      '/persons',
      '/add',
      '/inbox',
      'budgets',
    ]) {
      expect(paths, isNot(contains(personal)));
    }
  });
}
