import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/repo.dart';
import 'features/areas/areas_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/habits/habits_screen.dart';
import 'features/ideas/ideas_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/map/map_screen.dart';
import 'features/planner/planner_screen.dart';
import 'features/projects/project_workspace.dart';
import 'features/projects/projects_screen.dart';
import 'features/review/review_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shopping/shopping_screen.dart';
import 'features/tasks/tasks_screen.dart';
import 'features/time/time_screen.dart';
import 'features/wisdom/wisdom_screen.dart';
import 'widgets/shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> s) {
    _sub = s.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

Page<void> _page(Widget child) => NoTransitionPage<void>(child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseProvider);
  final refresh = _StreamListenable(client.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = client.auth.currentSession != null;
      final atAuth = state.matchedLocation == '/auth';
      if (!signedIn) return atAuth ? null : '/auth';
      if (atAuth) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (c, s) => const AuthScreen()),
      ShellRoute(
        builder: (c, s, child) => AppShell(location: s.uri.path, child: child),
        routes: [
          GoRoute(path: '/', pageBuilder: (c, s) => _page(const DashboardScreen())),
          GoRoute(path: '/goals', pageBuilder: (c, s) => _page(const GoalsScreen())),
          GoRoute(path: '/areas', pageBuilder: (c, s) => _page(const AreasScreen())),
          GoRoute(
            path: '/projects',
            pageBuilder: (c, s) => _page(ProjectsScreen(goalFilter: s.uri.queryParameters['goal'])),
            routes: [
              GoRoute(
                path: ':id',
                builder: (c, s) => ProjectWorkspace(projectId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/tasks', pageBuilder: (c, s) => _page(const TasksScreen())),
          GoRoute(path: '/planner', pageBuilder: (c, s) => _page(const PlannerScreen())),
          GoRoute(path: '/habits', pageBuilder: (c, s) => _page(const HabitsScreen())),
          GoRoute(path: '/time', pageBuilder: (c, s) => _page(const TimeScreen())),
          GoRoute(path: '/journal', pageBuilder: (c, s) => _page(const JournalScreen())),
          GoRoute(path: '/ideas', pageBuilder: (c, s) => _page(const IdeasScreen())),
          GoRoute(path: '/wisdom', pageBuilder: (c, s) => _page(const WisdomScreen())),
          GoRoute(path: '/shopping', pageBuilder: (c, s) => _page(const ShoppingScreen())),
          GoRoute(path: '/review', pageBuilder: (c, s) => _page(const ReviewScreen())),
          GoRoute(path: '/map', pageBuilder: (c, s) => _page(const MapScreen())),
          GoRoute(path: '/settings', pageBuilder: (c, s) => _page(const SettingsScreen())),
        ],
      ),
    ],
  );
});
