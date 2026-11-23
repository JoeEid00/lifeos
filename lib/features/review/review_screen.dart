import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../core/utils.dart';
import '../../data/derived.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

WeekStats computeWeek(WidgetRef ref, DateTime start) => weekStats(
      start,
      weekStartDay: ref.watch(weekStartProvider),
      tasks: watchList(ref, tasksProvider),
      projects: watchList(ref, projectsProvider),
      goals: watchList(ref, goalsProvider),
      habits: watchList(ref, habitsProvider),
      logs: watchList(ref, habitLogsProvider),
      entries: watchList(ref, timeEntriesProvider),
      journal: watchList(ref, journalProvider),
    );

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  DateTime? _week;

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(weekStartProvider);
    final week = _week ?? startOfWeek(DateTime.now(), ws);
    final asyncs = <AsyncValue<dynamic>>[
      ref.watch(tasksProvider),
      ref.watch(habitsProvider),
      ref.watch(habitLogsProvider),
      ref.watch(timeEntriesProvider),
      ref.watch(journalProvider),
      ref.watch(reviewsProvider),
    ];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: lifeAppBar(context, context.t('Weekly Review'), subtitle: context.t('Turn your data into decisions')),
      body: asyncGate(context, asyncs, () {
        final s = computeWeek(ref, week);
        final prev = computeWeek(ref, addDays(week, -7));
        final areas = watchList(ref, areasProvider);
        final neglected = areas.where((a) => !s.areaActivity.contains(a.id)).toList();
        final review = watchList(ref, reviewsProvider).where((r) => sameDay(r.weekStart, week)).firstOrNull;
        final completed = watchList(ref, tasksProvider)
            .where((t) => t.isDone && t.completedAt != null && inRange(t.completedAt!, week, addDays(week, 7)))
            .toList();

        Widget delta(num now, num before, {bool higherIsBetter = true}) {
          if (now == before) return const SizedBox.shrink();
          final up = now > before;
          final good = up == higherIsBetter;
          return Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 16, color: good ? Colors.green : cs.error);
        }

        final cards = [
          (Icons.task_alt_rounded, context.t('Tasks completed'), '${s.tasksDone}', delta(s.tasksDone, prev.tasksDone), cs.primary),
          (Icons.warning_amber_rounded, context.t('Open & due'), '${s.tasksOpenDue}', delta(s.tasksOpenDue, prev.tasksOpenDue, higherIsBetter: false), cs.error),
          (Icons.repeat_rounded, context.t('Habit adherence'), s.habitRate == null ? '—' : pct(s.habitRate!), delta(s.habitRate ?? 0, prev.habitRate ?? 0), Colors.green),
          (Icons.timer_rounded, context.t('Tracked time'), fmtMinutes(context, s.minutes), delta(s.minutes, prev.minutes), const Color(0xFF8B5CF6)),
          (Icons.mood_rounded, context.t('Average mood'), s.mood == null ? '—' : '${s.mood!.toStringAsFixed(1)} / 5', delta(s.mood ?? 0, prev.mood ?? 0), const Color(0xFFF59E0B)),
          (Icons.edit_note_rounded, context.t('Journal entries'), '${s.journalCount}', delta(s.journalCount, prev.journalCount), const Color(0xFF0EA5E9)),
        ];

        return ListView(
          padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 100),
          children: [
            Row(children: [
              IconButton(onPressed: () => setState(() => _week = addDays(week, -7)), icon: const Icon(Icons.chevron_left_rounded)),
              Expanded(
                child: Text(
                  '${fmtDate(context, week, 'd MMM')} – ${fmtDate(context, addDays(week, 6), 'd MMM y')}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(onPressed: () => setState(() => _week = addDays(week, 7)), icon: const Icon(Icons.chevron_right_rounded)),
            ]),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (c, box) {
              final cols = box.maxWidth >= 900 ? 3 : (box.maxWidth >= 520 ? 2 : 1);
              final w = (box.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final k in cards)
                  SizedBox(
                    width: w,
                    child: Stack(children: [
                      StatCard(icon: k.$1, label: k.$2, value: k.$3, color: k.$5),
                      PositionedDirectional(top: 12, end: 12, child: k.$4),
                    ]),
                  ),
              ]);
            }),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (c, box) {
              final timeCard = AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SectionHeader(context.t('Where did my time go?'), icon: Icons.pie_chart_outline_rounded),
                  if (s.byArea.isEmpty) Text(context.t('No tracked time this week.')),
                  for (final e in s.byArea.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                    Builder(builder: (_) {
                      final a = areas.where((x) => x.id == e.key).firstOrNull;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          SizedBox(width: 120, child: Text(a?.name ?? context.t('Unassigned'), overflow: TextOverflow.ellipsis)),
                          Expanded(child: ProgressBar(s.minutes == 0 ? 0 : e.value / s.minutes, color: hexColor(a?.color, Colors.grey))),
                          const SizedBox(width: 8),
                          Text(fmtMinutes(context, e.value)),
                        ]),
                      );
                    }),
                ]),
              );
              final neglectCard = AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SectionHeader(context.t('Neglected life areas'), icon: Icons.visibility_off_outlined),
                  if (neglected.isEmpty)
                    Text(context.t('Every life area got attention this week. 👏'))
                  else
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final a in neglected) Pill(a.name, icon: areaIcon(a.icon), color: hexColor(a.color)),
                    ]),
                  const SizedBox(height: 16),
                  SectionHeader(context.t('Completed this week'), icon: Icons.emoji_events_outlined, trailing: '${completed.length}'),
                  for (final t in completed.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.check_rounded, size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Expanded(child: Text(t.title, overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                ]),
              );
              if (box.maxWidth >= 860) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: timeCard),
                  const SizedBox(width: 12),
                  Expanded(child: neglectCard),
                ]);
              }
              return Column(children: [timeCard, const SizedBox(height: 12), neglectCard]);
            }),
            const SizedBox(height: 20),
            _GuidedReview(key: ValueKey(ymd(week)), week: week, review: review),
            const SizedBox(height: 20),
            _PastReviews(onOpen: (d) => setState(() => _week = d)),
          ],
        );
      }),
    );
  }
}

class _GuidedReview extends ConsumerStatefulWidget {
  const _GuidedReview({super.key, required this.week, this.review});
  final DateTime week;
  final WeeklyReview? review;
  @override
  ConsumerState<_GuidedReview> createState() => _GuidedReviewState();
}

class _GuidedReviewState extends ConsumerState<_GuidedReview> {
  late final _wins = TextEditingController(text: widget.review?.wins ?? '');
  late final _challenges = TextEditingController(text: widget.review?.challenges ?? '');
  late final _lessons = TextEditingController(text: widget.review?.lessons ?? '');
  late final _next = TextEditingController(text: widget.review?.nextPriorities ?? '');
  late double _rating = (widget.review?.rating ?? 7).toDouble();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_wins, _challenges, _lessons, _next]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = {
      'week_start': ymd(widget.week),
      'wins': _wins.text.trim(),
      'challenges': _challenges.text.trim(),
      'lessons': _lessons.text.trim(),
      'next_priorities': _next.text.trim(),
      'rating': _rating.round(),
    };
    final n = ref.read(reviewsProvider.notifier);
    final existing = n.items.where((r) => sameDay(r.weekStart, widget.week)).firstOrNull;
    await runSafe(context, () async {
      if (existing == null) {
        await n.add(data);
      } else {
        await n.patch(existing.id, data);
      }
    }, success: context.t('Review saved'));
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _createTasks() async {
    final lines = splitLines(_next.text);
    if (lines.isEmpty) {
      toast(context, context.t('Write next week\'s priorities first (one per line).'));
      return;
    }
    final nextWeek = addDays(widget.week, 7);
    await runSafe(context, () async {
      await ref.read(tasksProvider.notifier).addMany([
        for (final l in lines) {'title': l.replaceFirst(RegExp(r'^[-•*\d.)\s]+'), ''), 'due_date': ymd(addDays(nextWeek, 6)), 'priority': 2},
      ]);
    }, success: '${lines.length} ${context.t('tasks created for next week')}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget q(String label, String hint, TextEditingController c, IconData icon) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: c,
            minLines: 2,
            maxLines: 6,
            decoration: deco(context, context.t(label), hint: context.t(hint), icon: icon),
          ),
        );
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionHeader(context.t('Guided review'), icon: Icons.psychology_alt_rounded,
            trailing: widget.review == null ? context.t('Not saved yet') : context.t('Saved')),
        q('1. What went well?', 'Wins, progress, things you are proud of', _wins, Icons.emoji_events_outlined),
        q('2. What didn\'t go as planned?', 'Unfinished tasks, missed habits, blockers', _challenges, Icons.report_gmailerrorred_rounded),
        q('3. What did I learn?', 'Lessons to keep', _lessons, Icons.lightbulb_outline),
        q('4. Top priorities for next week', 'One per line', _next, Icons.flag_outlined),
        Text('${context.t('5. Rate the week')}: ${_rating.round()}/10', style: theme.textTheme.titleSmall),
        Slider(value: _rating, min: 1, max: 10, divisions: 9, label: '${_rating.round()}', onChanged: (v) => setState(() => _rating = v)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.end, children: [
          OutlinedButton.icon(
            onPressed: _createTasks,
            icon: const Icon(Icons.playlist_add_rounded),
            label: Text(context.t('Create tasks from priorities')),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: Text(context.t('Save review')),
          ),
        ]),
      ]),
    );
  }
}

class _PastReviews extends ConsumerWidget {
  const _PastReviews({required this.onOpen});
  final ValueChanged<DateTime> onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = watchList(ref, reviewsProvider);
    if (reviews.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(context.t('Past reviews'), icon: Icons.history_rounded),
      for (final r in reviews.take(12))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            onTap: () => onOpen(r.weekStart),
            child: Row(children: [
              CircleAvatar(child: Text('${r.rating ?? '–'}')),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${context.t('Week of')} ${fmtDate(context, r.weekStart, 'd MMM y')}', style: theme.textTheme.titleSmall),
                  if (r.wins.isNotEmpty) Text(r.wins, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }
}
