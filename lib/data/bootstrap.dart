import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import 'repo.dart';

/// Seeds default life areas, idea stages and categories the first time a user signs in.
final bootstrapProvider = FutureProvider<void>((ref) async {
  final uid = ref.watch(userIdProvider);
  if (uid == null) return;
  final prefs = ref.read(prefsProvider);
  final key = 'seeded_$uid';
  if (prefs.getBool(key) == true) return;

  final ar = ref.read(settingsProvider).languageCode == 'ar';
  String n(String en, String a) => ar ? a : en;

  final areas = await ref.read(areasProvider.future);
  final stages = await ref.read(ideaStagesProvider.future);
  final cats = await ref.read(categoriesProvider.future);

  if (areas.isEmpty) {
    final defaults = [
      [n('Career', 'المسار المهني'), 'work', '#4F46E5'],
      [n('Health', 'الصحة'), 'health', '#EF4444'],
      [n('Fitness', 'اللياقة'), 'fitness', '#F97316'],
      [n('Finance', 'المال'), 'finance', '#10B981'],
      [n('Relationships', 'العلاقات'), 'relationships', '#EC4899'],
      [n('Learning', 'التعلم'), 'learning', '#0EA5E9'],
      [n('Social Life', 'الحياة الاجتماعية'), 'social', '#F59E0B'],
      [n('Travel', 'السفر'), 'travel', '#06B6D4'],
      [n('Personal Growth', 'التطور الشخصي'), 'growth', '#8B5CF6'],
    ];
    await ref.read(areasProvider.notifier).addMany([
      for (var i = 0; i < defaults.length; i++)
        {'name': defaults[i][0], 'icon': defaults[i][1], 'color': defaults[i][2], 'sort_order': i},
    ]);
  }

  if (stages.isEmpty) {
    final defaults = [
      [n('Inbox', 'صندوق الوارد'), '#64748B'],
      [n('Research', 'بحث'), '#0EA5E9'],
      [n('Planning', 'تخطيط'), '#F59E0B'],
      [n('In progress', 'قيد التنفيذ'), '#8B5CF6'],
      [n('Done', 'منجزة'), '#10B981'],
    ];
    await ref.read(ideaStagesProvider.notifier).addMany([
      for (var i = 0; i < defaults.length; i++) {'name': defaults[i][0], 'color': defaults[i][1], 'sort_order': i},
    ]);
  }

  if (cats.isEmpty) {
    final defaults = <List<String>>[
      ['task', n('Work', 'عمل'), '#4F46E5'],
      ['task', n('Personal', 'شخصي'), '#EC4899'],
      ['task', n('Errands', 'مشاوير'), '#F59E0B'],
      ['habit', n('Health', 'صحة'), '#10B981'],
      ['habit', n('Mind', 'ذهن'), '#8B5CF6'],
      ['idea', n('Business', 'أعمال'), '#0EA5E9'],
      ['idea', n('Personal', 'شخصي'), '#EC4899'],
      ['shopping', n('Groceries', 'بقالة'), '#10B981'],
      ['shopping', n('Home', 'المنزل'), '#F97316'],
      ['shopping', n('Electronics', 'إلكترونيات'), '#64748B'],
    ];
    await ref.read(categoriesProvider.notifier).addMany([
      for (var i = 0; i < defaults.length; i++)
        {'kind': defaults[i][0], 'name': defaults[i][1], 'color': defaults[i][2], 'sort_order': i},
    ]);
  }

  await prefs.setBool(key, true);
});
