import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../core/utils.dart';
import '../../data/derived.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';
import '../habits/habits_screen.dart';
import '../ideas/ideas_screen.dart';
import '../journal/journal_screen.dart';
import '../planner/planner_screen.dart';
import '../review/review_screen.dart';
import '../tasks/task_editor.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncs = <AsyncValue<dynamic>>[
      ref.watch(tasksProvider),
      ref.watch(habitsProvider),
      ref.watch(habitLogsProvider),
      ref.watch(planItemsProvider),
      ref.watch(timeEntriesProvider),
      ref.watch(projectsProvider),
    ];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final email = ref.watch(supabaseProvider).auth.currentUser?.email ?? '';
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'Good morning' : (hour < 18 ? 'Good afternoon' : 'Good evening');

    return Scaffold(
      appBar: lifeAppBar(context, '${context.t(greet)} 👋', subtitle: fmtDate(context, DateTime.now(), 'EEEE d MMMM y')),
      body: asyncGate(context, asyncs, () {
        final ws = ref.watch(weekStartProvider);
        final t0 = today();
        final tasks = watchList(ref, tasksProvider);
        final habits = watchList(ref, habitsProvider);
        final logs = watchList(ref, habitLogsProvider);
        final projects = watchList(ref, projectsProvider);
        final ms = watchList(ref, milestonesProvider);
        final goals = watchList(ref, goalsProvider);
        final areas = [...watchList(ref, areasProvider)]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        final entries = watchList(ref, timeEntriesProvider);

        final todayTasks = tasks.where((t) => sameDay(t.dueDate, t0) || (t.isDone && t.completedAt != null && sameDay(t.completedAt, t0) && t.dueDate == null)).toList();
        final overdue = tasks.where((t) => t.isOverdue).toList();
        final dueHabits = habits.where((h) => habitDueOn(h, t0, logs, ws)).toList()
          ..sort((a, b) => (a.preferredMinutes ?? 9999).compareTo(b.preferredMinutes ?? 9999));
        final habitsDone = dueHabits.where((h) => habitDoneOn(logs, h.id, t0)).length;
        final focusToday = minutesBetween(entries, t0, addDays(t0, 1));
        final week = computeWeek(ref, startOfWeek(t0, ws));
        final lastWeek = computeWeek(ref, addDays(startOfWeek(t0, ws), -7));
        final plan = planEntriesFor(t0,
            items: watchList(ref, planItemsProvider),
            tasks: tasks,
            habits: habits,
            logs: logs,
            projects: projects,
            weekStartDay: ws,
            fallback: cs.primary);
        final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
        final upcoming = plan.where((e) => e.end >= nowMin && !e.done).take(5).toList();
        final activeProjects = projects.where((p) => p.status == 'active').toList()
          ..sort((a, b) => (a.dueDate ?? DateTime(2999)).compareTo(b.dueDate ?? DateTime(2999)));
        final activeGoals = goals.where((g) => g.status == 'active').toList();
        final wStart = startOfWeek(t0, ws);
        final areaMin = minutesByArea(entries, projects, wStart, addDays(wStart, 7));
        final maxArea = areaMin.values.fold<int>(1, (a, b) => b > a ? b : a);

        final kpis = [
          StatCard(
            icon: Icons.check_circle_rounded,
            label: context.t('Tasks today'),
            value: '${todayTasks.where((t) => t.isDone).length}/${todayTasks.length}',
            sub: overdue.isEmpty ? null : '${overdue.length} ${context.t('overdue')}',
            onTap: () => context.go('/tasks'),
          ),
          StatCard(
            icon: Icons.repeat_rounded,
            label: context.t('Habits today'),
            value: '$habitsDone/${dueHabits.length}',
            color: Colors.green,
            onTap: () => context.go('/habits'),
          ),
          StatCard(
            icon: Icons.timer_rounded,
            label: context.t('Focus time today'),
            value: fmtMinutes(context, focusToday),
            color: const Color(0xFF8B5CF6),
            onTap: () => context.go('/time'),
          ),
          StatCard(
            icon: Icons.insights_rounded,
            label: context.t('Done this week'),
            value: '${week.tasksDone}',
            sub: '${context.t('last week')}: ${lastWeek.tasksDone}',
            color: const Color(0xFFF59E0B),
            onTap: () => context.go('/review'),
          ),
        ];

        final quick = Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: () => showTaskEditor(context, defaults: {'due_date': ymd(t0)}), icon: const Icon(Icons.add_task_rounded, size: 18), label: Text(context.t('Task'))),
          FilledButton.tonalIcon(onPressed: () => showJournalEditor(context), icon: const Icon(Icons.edit_note_rounded, size: 18), label: Text(context.t('Journal'))),
          FilledButton.tonalIcon(onPressed: () => showIdeaEditor(context), icon: const Icon(Icons.lightbulb_outline, size: 18), label: Text(context.t('Idea'))),
          FilledButton.tonalIcon(onPressed: () => context.go('/time'), icon: const Icon(Icons.play_arrow_rounded, size: 18), label: Text(context.t('Start timer'))),
        ]);

        final planCard = AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(context.t('Up next'), icon: Icons.schedule_rounded,
                action: TextButton(onPressed: () => context.go('/planner'), child: Text(context.t('Planner')))),
            if (upcoming.isEmpty)
              Text(context.t('Nothing else planned today.'), style: theme.textTheme.bodySmall)
            else
              for (final e in upcoming)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    SizedBox(width: 48, child: Text(hm(e.start), style: theme.textTheme.labelLarge)),
                    Container(width: 4, height: 30, decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e.title, overflow: TextOverflow.ellipsis)),
                    Text(fmtMinutes(context, e.duration), style: theme.textTheme.labelSmall),
                  ]),
                ),
          ]),
        );

        final tasksCard = AppCard(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SectionHeader(context.t('Today\'s tasks'), icon: Icons.today_rounded, trailing: '${todayTasks.length}'),
            ),
            if (todayTasks.isEmpty && overdue.isEmpty)
              Padding(padding: const EdgeInsets.all(8), child: Text(context.t('No tasks due today 🎉'), style: theme.textTheme.bodySmall)),
            for (final t in [...overdue.take(3), ...todayTasks]) TaskTile(task: t, dense: true),
          ]),
        );

        final habitsCard = AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(context.t('Habits due'), icon: Icons.repeat_rounded, trailing: '$habitsDone/${dueHabits.length}'),
            if (dueHabits.isEmpty) Text(context.t('No habits due today.'), style: theme.textTheme.bodySmall),
            for (final h in dueHabits)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: HabitCheckTile(habit: h, day: t0, compact: true)),
          ]),
        );

        final projectsCard = AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(context.t('Active projects'), icon: Icons.folder_rounded,
                action: TextButton(onPressed: () => context.go('/projects'), child: Text(context.t('All')))),
            if (activeProjects.isEmpty) Text(context.t('No active projects.'), style: theme.textTheme.bodySmall),
            for (final p in activeProjects.take(5))
              InkWell(
                onTap: () => context.go('/projects/${p.id}'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Builder(builder: (_) {
                    final prog = projectProgress(p.id, tasks, ms);
                    return Row(children: [
                      Icon(Icons.folder_rounded, color: hexColor(p.color), size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 90, child: ProgressBar(prog, color: hexColor(p.color), height: 6)),
                      SizedBox(width: 44, child: Text(pct(prog), textAlign: TextAlign.end, style: theme.textTheme.labelMedium)),
                    ]);
                  }),
                ),
              ),
          ]),
        );

        final goalsCard = AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(context.t('Goals'), icon: Icons.flag_rounded,
                action: TextButton(onPressed: () => context.go('/goals'), child: Text(context.t('All')))),
            if (activeGoals.isEmpty) Text(context.t('Set a goal to connect your projects to a purpose.'), style: theme.textTheme.bodySmall),
            for (final g in activeGoals.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Builder(builder: (_) {
                  final prog = effectiveGoalProgress(g, projects, tasks, ms);
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(g.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(pct(prog), style: theme.textTheme.labelMedium),
                    ]),
                    const SizedBox(height: 4),
                    ProgressBar(prog, height: 6),
                  ]);
                }),
              ),
          ]),
        );

        final balanceCard = AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(context.t('Life balance this week'), icon: Icons.donut_large_rounded,
                action: TextButton(onPressed: () => context.go('/review'), child: Text(context.t('Review')))),
            for (final a in areas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(areaIcon(a.icon), size: 18, color: hexColor(a.color)),
                  const SizedBox(width: 8),
                  SizedBox(width: 110, child: Text(a.name, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
                  Expanded(child: ProgressBar((areaMin[a.id] ?? 0) / maxArea, color: hexColor(a.color), height: 6)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 52,
                    child: Text(
                      week.areaActivity.contains(a.id) ? fmtMinutes(context, areaMin[a.id] ?? 0) : '—',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ]),
              ),
          ]),
        );

        return LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final cols = w >= 1200 ? 3 : (w >= 760 ? 2 : 1);
          final pad = pagePad(context);
          final inner = w - pad * 2;
          final kpiCols = w >= 1000 ? 4 : 2;
          final kpiW = (inner - (kpiCols - 1) * 12) / kpiCols;

          final cards = [planCard, tasksCard, habitsCard, projectsCard, goalsCard, balanceCard];
          final columns = List.generate(cols, (_) => <Widget>[]);
          for (var i = 0; i < cards.length; i++) {
            columns[i % cols].add(Padding(padding: const EdgeInsets.only(bottom: 14), child: cards[i]));
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 40),
            children: [
              if (email.isNotEmpty && w >= 760)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(context.t('Here is your day at a glance.'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ),
              quick,
              const SizedBox(height: 14),
              Wrap(spacing: 12, runSpacing: 12, children: [for (final k in kpis) SizedBox(width: kpiW, child: k)]),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var k = 0; k < cols; k++) ...[
                  if (k > 0) const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: columns[k])),
                ],
              ]),
            ],
          );
        });
      }),
    );
  }
}
