import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/bootstrap.dart';
import '../data/repo.dart';
import 'common.dart';
import 'search_palette.dart';

class NavItem {
  const NavItem(this.path, this.icon, this.label, this.group);
  final String path;
  final IconData icon;
  final String label;
  final String group;
}

const navItems = [
  NavItem('/', Icons.space_dashboard_rounded, 'Dashboard', 'Overview'),
  NavItem('/goals', Icons.flag_rounded, 'Vision & Goals', 'Direction'),
  NavItem('/areas', Icons.donut_large_rounded, 'Life Areas', 'Direction'),
  NavItem('/projects', Icons.folder_rounded, 'Projects', 'Planning'),
  NavItem('/tasks', Icons.check_circle_rounded, 'Tasks', 'Planning'),
  NavItem('/planner', Icons.calendar_month_rounded, 'Planner', 'Execution'),
  NavItem('/habits', Icons.repeat_rounded, 'Habits', 'Execution'),
  NavItem('/time', Icons.timer_rounded, 'Time Tracking', 'Capture'),
  NavItem('/journal', Icons.edit_note_rounded, 'Journal', 'Capture'),
  NavItem('/ideas', Icons.lightbulb_rounded, 'Ideas', 'Capture'),
  NavItem('/wisdom', Icons.auto_stories_rounded, 'Wisdom & Mindset', 'Capture'),
  NavItem('/shopping', Icons.shopping_bag_rounded, 'Shopping', 'Capture'),
  NavItem('/review', Icons.insights_rounded, 'Weekly Review', 'Analysis'),
  NavItem('/map', Icons.account_tree_rounded, 'Life Map', 'Analysis'),
  NavItem('/settings', Icons.settings_rounded, 'Settings', 'System'),
];

const _mobileTabs = ['/', '/tasks', '/planner', '/habits'];

bool _isActive(String location, String path) =>
    path == '/' ? location == '/' : (location == path || location.startsWith('$path/'));

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(bootstrapProvider); // seed defaults on first sign-in
    final wide = isWide(context);

    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => openSearch(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => openSearch(context),
      },
      child: Focus(autofocus: true, child: child),
    );

    if (wide) {
      return Scaffold(
        key: shellScaffoldKey,
        body: Row(children: [
          SizedBox(width: 256, child: _Sidebar(location: location)),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }

    final tabIndex = _mobileTabs.indexWhere((p) => _isActive(location, p));
    return Scaffold(
      key: shellScaffoldKey,
      drawer: Drawer(child: _Sidebar(location: location, inDrawer: true)),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex < 0 ? 4 : tabIndex,
        onDestinationSelected: (i) {
          if (i == 4) {
            shellScaffoldKey.currentState?.openDrawer();
          } else {
            context.go(_mobileTabs[i]);
          }
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.space_dashboard_outlined), selectedIcon: const Icon(Icons.space_dashboard_rounded), label: context.t('Home')),
          NavigationDestination(icon: const Icon(Icons.check_circle_outline), selectedIcon: const Icon(Icons.check_circle_rounded), label: context.t('Tasks')),
          NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), selectedIcon: const Icon(Icons.calendar_month_rounded), label: context.t('Planner')),
          NavigationDestination(icon: const Icon(Icons.repeat_rounded), label: context.t('Habits')),
          NavigationDestination(icon: const Icon(Icons.grid_view_rounded), label: context.t('More')),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location, this.inDrawer = false});
  final String location;
  final bool inDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final email = ref.watch(supabaseProvider).auth.currentUser?.email ?? '';
    String? lastGroup;

    return Container(
      color: dark ? AppTheme.darkCard : Colors.white,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [cs.primary, const Color(0xFF8B5CF6)]),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('LifeOS', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(context.t('Personal Life System'),
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (inDrawer) Navigator.pop(context);
                openSearch(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.search_rounded, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.t('Search'), style: TextStyle(color: cs.onSurfaceVariant))),
                  Text('Ctrl K', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              children: [
                for (final item in navItems) ...[
                  if (item.group != lastGroup) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 14, 12, 6),
                      child: Text(context.t(lastGroup = item.group).toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  _NavTile(item: item, active: _isActive(location, item.path), inDrawer: inDrawer),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: cs.primaryContainer,
              child: Text(email.isEmpty ? '?' : email[0].toUpperCase(),
                  style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
            ),
            title: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: context.t('Sign out'),
              icon: const Icon(Icons.logout_rounded, size: 20),
              onPressed: () => ref.read(supabaseProvider).auth.signOut(),
            ),
          ),
        ]),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.active, required this.inDrawer});
  final NavItem item;
  final bool active;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: active ? cs.primary.withValues(alpha: .1) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (inDrawer) Navigator.pop(context);
            context.go(item.path);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(item.icon, size: 20, color: active ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(context.t(item.label),
                    style: TextStyle(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? cs.primary : cs.onSurface,
                    )),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
