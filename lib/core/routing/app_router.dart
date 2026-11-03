import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/about_screen.dart';
import '../../features/business/booking/bookings_tab.dart';
import '../../features/business/business_home_screen.dart';
import '../../features/business/business_more_screen.dart';
import '../../features/business/reports_hub_screen.dart';
import '../../features/data_export/backup_screen.dart';
import '../../features/security/set_passcode_screen.dart';
import '../../features/settings/settings_screen.dart';
import 'app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Shows a SnackBar from outside any screen's own `BuildContext`. A no-op if
/// the router isn't mounted yet.
void showAppSnackBar(String message, {SnackBarAction? action}) {
  final context = _rootKey.currentContext;
  if (context == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

/// XPENC Business: `Home · Bookings · ➕ · Reports · More`.
///
/// Detail screens push above the shell (`parentNavigatorKey: _rootKey`, or a
/// root-navigator `MaterialPageRoute` from the business screens) so they get a
/// back button and hide the bottom bar.
final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const BusinessHomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/bookings', builder: (_, _) => const BookingsTab()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/reports',
              builder: (_, _) => const ReportsHubScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/more',
              builder: (_, _) => const BusinessMoreScreen(),
              routes: [
                GoRoute(
                  path: 'settings',
                  parentNavigatorKey: _rootKey,
                  builder: (_, _) => const SettingsScreen(),
                  routes: [
                    GoRoute(
                      path: 'passcode',
                      parentNavigatorKey: _rootKey,
                      builder: (_, state) => SetPasscodeScreen(
                        isRemoving:
                            state.uri.queryParameters['remove'] == 'true',
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'backup',
                  parentNavigatorKey: _rootKey,
                  builder: (_, _) => const BackupScreen(),
                ),
                GoRoute(
                  path: 'about',
                  parentNavigatorKey: _rootKey,
                  builder: (_, _) => const AboutScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
