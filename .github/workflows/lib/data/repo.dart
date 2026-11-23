import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils.dart';
import 'models.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

/// Current signed-in user id (null when signed out). Tables reload when it changes.
final userIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser?.id;
});

class TableSpec<T extends Entity> {
  const TableSpec(this.table, this.create, {this.orderBy = 'created_at', this.ascending = true});
  final String table;
  final T Function(Map<String, dynamic>) create;
  final String orderBy;
  final bool ascending;
}

/// Generic, optimistic CRUD over one Supabase table.
class TableNotifier<T extends Entity> extends AsyncNotifier<List<T>> {
  TableNotifier(this.spec);
  final TableSpec<T> spec;

  SupabaseClient get _db => ref.read(supabaseProvider);
  List<T> get items => state.valueOrNull ?? <T>[];

  @override
  Future<List<T>> build() async {
    final uid = ref.watch(userIdProvider);
    if (uid == null) return <T>[];
    const page = 1000;
    final out = <T>[];
    var from = 0;
    while (true) {
      final rows = await _db
          .from(spec.table)
          .select()
          .order(spec.orderBy, ascending: spec.ascending)
          .range(from, from + page - 1);
      out.addAll(rows.map((r) => spec.create(r)));
      if (rows.length < page) break;
      from += page;
    }
    return out;
  }

  T? byId(String? id) => id == null ? null : items.where((e) => e.id == id).firstOrNull;

  Future<T> add(Map<String, dynamic> data) async {
    final row = await _db.from(spec.table).insert(data).select().single();
    final item = spec.create(row);
    state = AsyncData([...items, item]);
    return item;
  }

  Future<List<T>> addMany(List<Map<String, dynamic>> data) async {
    if (data.isEmpty) return <T>[];
    final rows = await _db.from(spec.table).insert(data).select();
    final created = rows.map((r) => spec.create(r)).toList();
    state = AsyncData([...items, ...created]);
    return created;
  }

  Future<void> patch(String id, Map<String, dynamic> data) async {
    final before = items;
    state = AsyncData([for (final x in before) x.id == id ? spec.create({...x.raw, ...data}) : x]);
    try {
      final row = await _db.from(spec.table).update(data).eq('id', id).select().single();
      state = AsyncData([for (final x in items) x.id == id ? spec.create(row) : x]);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    final before = items;
    state = AsyncData(before.where((x) => x.id != id).toList());
    try {
      await _db.from(spec.table).delete().eq('id', id);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

typedef TableProvider<T extends Entity> = AsyncNotifierProvider<TableNotifier<T>, List<T>>;

TableProvider<T> _table<T extends Entity>(TableSpec<T> spec) =>
    AsyncNotifierProvider<TableNotifier<T>, List<T>>(() => TableNotifier<T>(spec));

final areasProvider = _table(TableSpec('life_areas', LifeArea.new, orderBy: 'sort_order'));
final categoriesProvider = _table(TableSpec('categories', ItemCategory.new, orderBy: 'sort_order'));
final visionsProvider = _table(TableSpec('visions', Vision.new));
final goalsProvider = _table(TableSpec('goals', Goal.new));
final projectsProvider = _table(TableSpec('projects', Project.new));
final milestonesProvider = _table(TableSpec('milestones', Milestone.new, orderBy: 'sort_order'));
final projectNotesProvider = _table(TableSpec('project_notes', ProjectNote.new, ascending: false));
final tasksProvider = _table(TableSpec('tasks', Task.new));
final habitsProvider = _table(TableSpec('habits', Habit.new, orderBy: 'sort_order'));
final habitLogsProvider = _table(TableSpec('habit_logs', HabitLog.new, orderBy: 'date'));
final planItemsProvider = _table(TableSpec('plan_items', PlanItem.new, orderBy: 'date'));
final ideaStagesProvider = _table(TableSpec('idea_stages', IdeaStage.new, orderBy: 'sort_order'));
final ideasProvider = _table(TableSpec('ideas', Idea.new));
final wisdomProvider = _table(TableSpec('wisdom_entries', WisdomEntry.new, ascending: false));
final shoppingProvider = _table(TableSpec('shopping_items', ShoppingItem.new));
final timeEntriesProvider = _table(TableSpec('time_entries', TimeEntry.new, orderBy: 'started_at', ascending: false));
final journalProvider = _table(TableSpec('journal_entries', JournalEntry.new, orderBy: 'date', ascending: false));
final reviewsProvider = _table(TableSpec('weekly_reviews', WeeklyReview.new, orderBy: 'week_start', ascending: false));

/// Read a table's current rows (empty while loading).
List<T> watchList<T extends Entity>(WidgetRef ref, TableProvider<T> p) => ref.watch(p).valueOrNull ?? <T>[];

/// Same as [watchList] but without subscribing (use in callbacks).
List<T> readList<T extends Entity>(WidgetRef ref, TableProvider<T> p) => ref.read(p).valueOrNull ?? <T>[];

// ------------------------------------------------------------ shared actions
Future<void> toggleTask(WidgetRef ref, Task t) => ref.read(tasksProvider.notifier).patch(t.id, {
      'status': t.isDone ? 'todo' : 'done',
      'completed_at': t.isDone ? null : isoUtc(DateTime.now()),
    });

Future<void> setTaskStatus(WidgetRef ref, Task t, String status) =>
    ref.read(tasksProvider.notifier).patch(t.id, {
      'status': status,
      'completed_at': status == 'done' ? isoUtc(DateTime.now()) : null,
    });

Future<void> toggleHabitLog(WidgetRef ref, Habit h, DateTime day) async {
  final n = ref.read(habitLogsProvider.notifier);
  final existing = n.items.where((l) => l.habitId == h.id && sameDay(l.date, day)).firstOrNull;
  if (existing != null) {
    await n.remove(existing.id);
  } else {
    await n.add({'habit_id': h.id, 'date': ymd(day)});
  }
}

bool habitDoneOn(List<HabitLog> logs, String habitId, DateTime day) =>
    logs.any((l) => l.habitId == habitId && sameDay(l.date, day));
