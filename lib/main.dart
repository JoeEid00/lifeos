import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final prefs = await SharedPreferences.getInstance();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  }
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const LifeOSApp(),
  ));
}

class LifeOSApp extends ConsumerWidget {
  const LifeOSApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final locale = Locale(s.languageCode);
    const delegates = [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];
    const locales = [Locale('ar'), Locale('en')];
    final light = AppTheme.build(Brightness.light, s.languageCode);
    final dark = AppTheme.build(Brightness.dark, s.languageCode);

    if (!AppConfig.isConfigured) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LifeOS',
        theme: light,
        darkTheme: dark,
        themeMode: s.themeMode,
        locale: locale,
        supportedLocales: locales,
        localizationsDelegates: delegates,
        home: const _SetupRequired(),
      );
    }

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'LifeOS',
      theme: light,
      darkTheme: dark,
      themeMode: s.themeMode,
      locale: locale,
      supportedLocales: locales,
      localizationsDelegates: delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _SetupRequired extends StatelessWidget {
  const _SetupRequired();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.storage_rounded, size: 56),
              const SizedBox(height: 16),
              Text('Connect your Supabase database', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const SelectableText(
                'Run the app with:\n\n'
                'flutter run --dart-define=SUPABASE_URL=https://YOUR.supabase.co '
                '--dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY\n\n'
                'See README.md for the full setup (2 minutes).',
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
