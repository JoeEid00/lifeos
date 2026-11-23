import 'dart:math' as math;

import '../core/utils.dart';
import 'models.dart';

// ------------------------------------------------------------ progress
/// Project progress = done units / all units, where a unit is a task linked to
/// the project, or a milestone that has no tasks (counted by its own flag).
double projectProgress(String projectId, List<Task> tasks, List<Milestone> milestones) {
  final pt = tasks.where((t) => t.projectId == projectId).toList();
  var total = 0, done = 0;
  for (final t in pt) {
    total++;
    if (t.isDone) done++;
  }
  for (final m in milestones.where((m) => m.projectId == projectId)) {
    if (!pt.any((t) => t.milestoneId == m.id)) {
      total++;
      if (m.done) done++;
    }
  }
  return total == 0 ? 0 : done / total;
}

/// Goal progress from data: average of linked projects + direct tasks. Null when nothing is linked.
double? goalProgress(String goalId, List<Project> projects, List<Task> tasks, List<Milestone> milestones) {
  final parts = <double>[];
  for (final p in projects.where((p) => p.goalId == goalId && p.status != 'archived')) {
    parts.add(p.status == 'done' ? 1 : projectProgress(p.id, tasks, milestones));
  }
  for (final t in tasks.where((t) => t.goalId == goalId && t.projectId == null)) {
    parts.add(t.isDone ? 1 : 0);
  }
  if (parts.isEmpty) return null;
  return parts.reduce((a, b) => a + b) / parts.length;
}

double effectiveGoalProgress(Goal g, List<Project> projects, List<Task> tasks, List<Milestone> ms) {
  if (g.status == 'achieved') return 1;
  return goalProgress(g.id, projects, tasks, ms) ?? g.manualProgress / 100;
}

double? visionProgress(String visionId, List<Goal> goals, List<Project> projects, List<Task> tasks, List<Milestone> ms) {
  final gs = goals.where((g) => g.visionId == visionId && g.status != 'dropped').toList();
  if (gs.isEmpty) return null;
  return gs.map((g) => effectiveGoalProgress(g, projects, tasks, ms)).reduce((a, b) => a + b) / gs.length;
}

// ------------------------------------------------------------ habits
DateTime periodStart(String freq, DateTime d, int weekStartDay) => switch (freq) {
      'weekly' => startOfWeek(d, weekStartDay),
      'monthly' => startOfMonth(d),
      _ => dateOnly(d),
    };

DateTime previousPeriod(String freq, DateTime start) => switch (freq) {
      'weekly' => addDays(start, -7),
      'monthly' => DateTime(start.year, start.month - 1, 1),
      _ => addDays(start, -1),
    };

DateTime nextPeriod(String freq, DateTime start) => switch (freq) {
      'weekly' => addDays(start, 7),
      'monthly' => DateTime(start.year, start.month + 1, 1),
      _ => addDays(start, 1),
    };

class HabitStats {
  const HabitStats({
    required this.streak,
    required this.best,
    required this.rate,
    required this.periodCount,
    required this.target,
    required this.doneToday,
  });
  final int streak;
  final int best;
  final double rate;
  final int periodCount; // check-ins in the current period
  final int target;
  final bool doneToday;
  bool get periodComplete => periodCount >= target;
}

HabitStats habitStats(Habit h, List<HabitLog> allLogs, int weekStartDay, [DateTime? now]) {
  now ??= DateTime.now();
  final f = h.frequency;
  final logs = allLogs.where((l) => l.habitId == h.id).toList();
  final counts = <DateTime, int>{};
  for (final l in logs) {
    final k = periodStart(f, l.date, weekStartDay);
    counts[k] = (counts[k] ?? 0) + 1;
  }
  final target = h.target;
  bool complete(DateTime p) => (counts[p] ?? 0) >= target;
  final current = periodStart(f, now, weekStartDay);

  // Current streak (an unfinished current period doesn't break it).
  var p = complete(current) ? current : previousPeriod(f, current);
  var streak = 0;
  while (complete(p)) {
    streak++;
    p = previousPeriod(f, p);
  }

  // Best streak.
  var best = 0, run = 0;
  if (logs.isNotEmpty) {
    final first = logs.map((l) => l.date).reduce((a, b) => a.isBefore(b) ? a : b);
    var q = periodStart(f, first, weekStartDay);
    var guard = 0;
    while (!q.isAfter(current) && guard++ < 3000) {
      if (complete(q)) {
        run++;
        best = math.max(best, run);
      } else if (q != current) {
        run = 0;
      }
      q = nextPeriod(f, q);
    }
  }

  // Completion rate over recent periods (28 days / 8 weeks / 6 months), from creation.
  final n = switch (f) { 'weekly' => 8, 'monthly' => 6, _ => 28 };
  final created = periodStart(f, h.createdAt, weekStartDay);
  var considered = 0, ok = 0;
  var r = current;
  for (var i = 0; i < n; i++) {
    if (r.isBefore(created)) break;
    final isCurrent = r == current;
    if (!isCurrent || complete(r)) {
      considered++;
      if (complete(r)) ok++;
    }
    r = previousPeriod(f, r);
  }

  return HabitStats(
    streak: streak,
    best: math.max(best, streak),
    rate: considered == 0 ? 0 : ok / considered,
    periodCount: counts[current] ?? 0,
    target: target,
    doneToday: logs.any((l) => sameDay(l.date, now)),
  );
}

/// Should the habit appear in the "due" list for [day]?
bool habitDueOn(Habit h, DateTime day, List<HabitLog> logs, int weekStartDay) {
  if (h.archived) return false;
  if (dateOnly(h.createdAt).isAfter(dateOnly(day))) return false;
  if (h.frequency == 'daily') return true;
  final ps = periodStart(h.frequency, day, weekStartDay);
  final pe = nextPeriod(h.frequency, ps);
  final mine = logs.where((l) => l.habitId == h.id && inRange(l.date, ps, pe));
  if (mine.any((l) => sameDay(l.date, day))) return true;
  return mine.length < h.target;
}

const kDayParts = ['Morning', 'Noon', 'Afternoon', 'Evening', 'Before bed', 'Anytime'];

String dayPartOf(int? minutes) {
  if (minutes == null) return 'Anytime';
  final h = minutes ~/ 60;
  if (h >= 5 && h < 12) return 'Morning';
  if (h >= 12 && h < 14) return 'Noon';
  if (h >= 14 && h < 18) return 'Afternoon';
  if (h >= 18 && h < 22) return 'Evening';
  return 'Before bed';
}

// ------------------------------------------------------------ time
String? entryAreaId(TimeEntry e, List<Project> projects) =>
    e.areaId ?? projects.where((p) => p.id == e.projectId).firstOrNull?.areaId;

int minutesBetween(List<TimeEntry> entries, DateTime start, DateTime endExclusive) => entries
    .where((e) => e.isValid && inRange(e.startedAt, start, endExclusive))
    .fold(0, (s, e) => s + e.minutes);

Map<String?, int> minutesByArea(List<TimeEntry> entries, List<Project> projects, DateTime start, DateTime end) {
  final m = <String?, int>{};
  for (final e in entries.where((e) => e.isValid && inRange(e.startedAt, start, end))) {
    final a = entryAreaId(e, projects);
    m[a] = (m[a] ?? 0) + e.minutes;
  }
  return m;
}

// ------------------------------------------------------------ weekly stats
class WeekStats {
  const WeekStats({
    required this.tasksDone,
    required this.tasksOpenDue,
    required this.habitRate,
    required this.minutes,
    required this.byArea,
    required this.mood,
    required this.journalCount,
    required this.areaActivity,
  });
  final int tasksDone;
  final int tasksOpenDue; // due this week (or earlier) and still open
  final double? habitRate;
  final int minutes;
  final Map<String?, int> byArea;
  final double? mood;
  final int journalCount;
  final Set<String> areaActivity; // areas that saw time, tasks or habits
}

WeekStats weekStats(
  DateTime start, {
  required int weekStartDay,
  required List<Task> tasks,
  required List<Project> projects,
  required List<Goal> goals,
  required List<Habit> habits,
  required List<HabitLog> logs,
  required List<TimeEntry> entries,
  required List<JournalEntry> journal,
}) {
  final end = addDays(start, 7);
  final now = DateTime.now();
  final lastDay = dateOnly(now).isBefore(end) ? addDays(today(), 1) : end;

  final done = tasks.where((t) => t.isDone && t.completedAt != null && inRange(t.completedAt!, start, end)).toList();
  final openDue = tasks.where((t) => !t.isDone && t.dueDate != null && t.dueDate!.isBefore(end)).length;

  // Habit adherence: daily habits count per elapsed day; weekly habits by target.
  var possible = 0.0, achieved = 0.0;
  for (final h in habits.where((h) => !h.archived)) {
    final hl = logs.where((l) => l.habitId == h.id && inRange(l.date, start, lastDay)).length;
    if (h.frequency == 'daily') {
      for (var d = start; d.isBefore(lastDay); d = addDays(d, 1)) {
        if (!dateOnly(h.createdAt).isAfter(d)) possible++;
      }
      achieved += hl;
    } else if (h.frequency == 'weekly') {
      possible += h.target;
      achieved += math.min(hl, h.target);
    }
  }

  final byArea = minutesByArea(entries, projects, start, end);
  final moods = journal.where((j) => j.mood != null && inRange(j.date, start, end)).map((j) => j.mood!).toList();

  final activity = <String>{...byArea.keys.whereType<String>()};
  for (final t in done) {
    final p = projects.where((p) => p.id == t.projectId).firstOrNull;
    final a = p?.areaId ?? goals.where((g) => g.id == t.goalId).firstOrNull?.areaId;
    if (a != null) activity.add(a);
  }
  for (final h in habits) {
    if (h.areaId != null && logs.any((l) => l.habitId == h.id && inRange(l.date, start, end))) activity.add(h.areaId!);
  }

  return WeekStats(
    tasksDone: done.length,
    tasksOpenDue: openDue,
    habitRate: possible == 0 ? null : math.min(1.0, achieved / possible),
    minutes: byArea.values.fold(0, (a, b) => a + b),
    byArea: byArea,
    mood: moods.isEmpty ? null : moods.reduce((a, b) => a + b) / moods.length,
    journalCount: journal.where((j) => inRange(j.date, start, end)).length,
    areaActivity: activity,
  );
}
