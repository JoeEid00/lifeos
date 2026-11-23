import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.languageCode,
    required this.weekStartDay,
    required this.currency,
  });

  final ThemeMode themeMode;
  final String languageCode;
  final int weekStartDay; // DateTime.saturday by default
  final String currency;

  AppSettings copyWith({ThemeMode? themeMode, String? languageCode, int? weekStartDay, String? currency}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        languageCode: languageCode ?? this.languageCode,
        weekStartDay: weekStartDay ?? this.weekStartDay,
        currency: currency ?? this.currency,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _p => ref.read(prefsProvider);

  @override
  AppSettings build() {
    final p = ref.read(prefsProvider);
    return AppSettings(
      themeMode: ThemeMode.values[(p.getInt('themeMode') ?? 0).clamp(0, 2)],
      languageCode: p.getString('lang') ?? 'ar',
      weekStartDay: p.getInt('weekStart') ?? DateTime.saturday,
      currency: p.getString('currency') ?? 'SAR',
    );
  }

  void setTheme(ThemeMode m) {
    _p.setInt('themeMode', m.index);
    state = state.copyWith(themeMode: m);
  }

  void setLanguage(String code) {
    _p.setString('lang', code);
    state = state.copyWith(languageCode: code);
  }

  void setWeekStart(int day) {
    _p.setInt('weekStart', day);
    state = state.copyWith(weekStartDay: day);
  }

  void setCurrency(String c) {
    _p.setString('currency', c);
    state = state.copyWith(currency: c);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// Convenience: the configured first day of the week.
final weekStartProvider = Provider<int>((ref) => ref.watch(settingsProvider).weekStartDay);
