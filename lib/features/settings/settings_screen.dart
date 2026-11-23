import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final user = ref.watch(supabaseProvider).auth.currentUser;
    final theme = Theme.of(context);

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(title, style: theme.textTheme.titleSmall)),
            AppCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: children)),
          ]),
        );

    return Scaffold(
      appBar: lifeAppBar(context, context.t('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 60),
            children: [
              section(context.t('Appearance'), [
                ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: Text(context.t('Language')),
                  trailing: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'ar', label: Text('العربية')),
                      ButtonSegment(value: 'en', label: Text('English')),
                    ],
                    selected: {s.languageCode},
                    onSelectionChanged: (v) => n.setLanguage(v.first),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: Text(context.t('Theme')),
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_rounded, size: 18), tooltip: context.t('System')),
                      ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_rounded, size: 18), tooltip: context.t('Light')),
                      ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_rounded, size: 18), tooltip: context.t('Dark')),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) => n.setTheme(v.first),
                  ),
                ),
              ]),
              section(context.t('Preferences'), [
                ListTile(
                  leading: const Icon(Icons.calendar_view_week_rounded),
                  title: Text(context.t('Week starts on')),
                  trailing: DropdownButton<int>(
                    value: s.weekStartDay,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: DateTime.saturday, child: Text(context.t('Saturday'))),
                      DropdownMenuItem(value: DateTime.sunday, child: Text(context.t('Sunday'))),
                      DropdownMenuItem(value: DateTime.monday, child: Text(context.t('Monday'))),
                    ],
                    onChanged: (v) {
                      if (v != null) n.setWeekStart(v);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(context.t('Currency')),
                  trailing: DropdownButton<String>(
                    value: s.currency,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final c in {'SAR', 'EGP', 'AED', 'KWD', 'QAR', 'USD', 'EUR', s.currency})
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) {
                      if (v != null) n.setCurrency(v);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: Text(context.t('Life areas & categories')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.go('/areas'),
                ),
              ]),
              section(context.t('Account'), [
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(user?.email ?? ''),
                  subtitle: Text(context.t('Your data is stored privately in your Supabase database and syncs across devices.')),
                ),
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: Text(context.t('Reload all data')),
                  onTap: () {
                    ref.invalidate(userIdProvider);
                    toast(context, context.t('Reloading…'));
                  },
                ),
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
                  title: Text(context.t('Sign out'), style: TextStyle(color: theme.colorScheme.error)),
                  onTap: () => ref.read(supabaseProvider).auth.signOut(),
                ),
              ]),
              Center(
                child: Text('LifeOS 1.0 · ${context.t('Keyboard: Ctrl/⌘ + K to search')}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
