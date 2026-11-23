import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../core/utils.dart';
import '../../data/derived.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

// ======================================================================
//  Plan entries: real plan_items + "virtual" recurring habits
// ======================================================================
class PlanEntry {
  PlanEntry({
    this.item,
    this.habit,
    this.task,
    required this.date,
    required this.start,
    required this.duration,
    required this.title,
    required this.color,
    required this.done,
  });

  final PlanItem? item;
  final Habit? habit;
  final Task? task;
  final DateTime date;
  final int start;
  final int duration;
  final String title;
  final Color color;
  final bool done;

  bool get isVirtual => item == null;
  int get end => start + duration;
  String get key => item?.id ?? 'h-${habit!.id}-${ymd(date)}';
}

List<PlanEntry> planEntriesFor(
  DateTime day, {
  required List<PlanItem> items,
  required List<Task> tasks,
  required List<Habit> habits,
  required List<HabitLog> logs,
  required List<Project> projects,
  required int weekStartDay,
  Color fallback = const Color(0xFF4F46E5),
}) {
  final out = <PlanEntry>[];
  final dayItems = items.where((i) => sameDay(i.date, day)).toList();
  for (final it in dayItems) {
    if (it.skipped) continue;
    final task = it.taskId == null ? null : tasks.where((t) => t.id == it.taskId).firstOrNull;
    final habit = it.habitId == null ? null : habits.where((h) => h.id == it.habitId).firstOrNull;
    if (it.taskId != null && task == null) continue;
    if (it.habitId != null && habit == null) continue;
    final project = task?.projectId == null ? null : projects.where((p) => p.id == task!.projectId).firstOrNull;
    out.add(PlanEntry(
      item: it,
      habit: habit,
      task: task,
      date: day,
      start: it.startMinutes,
      duration: it.duration,
      title: it.title ?? task?.title ?? habit?.title ?? '—',
      color: habit != null ? hexColor(habit.color) : project != null ? hexColor(project.color) : fallback,
      done: habit != null ? habitDoneOn(logs, habit.id, day) : task != null ? task.isDone : it.done,
    ));
  }
  for (final h in habits) {
    if (h.preferredMinutes == null) continue;
    if (dayItems.any((i) => i.habitId == h.id)) continue;
    if (!habitDueOn(h, day, logs, weekStartDay)) continue;
    out.add(PlanEntry(
      habit: h,
      date: day,
      start: h.preferredMinutes!,
      duration: h.duration,
      title: h.title,
      color: hexColor(h.color),
      done: habitDoneOn(logs, h.id, day),
    ));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// Shared mutations used by every view.
class PlannerActions {
  PlannerActions(this.ref, this.context);
  final WidgetRef ref;
  final BuildContext context;

  TableNotifier<PlanItem> get _n => ref.read(planItemsProvider.notifier);

  /// Moves/edits a block. Never touches the task due date or the habit default time.
  Future<void> save(PlanEntry e, {DateTime? date, int? start, int? duration, String? notes, String? title}) async {
    final newDate = dateOnly(date ?? e.date);
    final data = <String, dynamic>{
      'date': ymd(newDate),
      'start_time': hm(start ?? e.start),
      'duration_minutes': math.max(5, duration ?? e.duration),
      if (notes != null) 'notes': notes.trim().isEmpty ? null : notes.trim(),
      if (title != null && e.task == null && e.habit == null) 'title': title.trim(),
    };
    await runSafe(context, () async {
      if (e.isVirtual) {
        if (!sameDay(newDate, e.date)) await _skip(e.habit!, e.date);
        await _n.add({...data, 'habit_id': e.habit!.id});
      } else {
        await _n.patch(e.item!.id, data);
        if (e.habit != null && !sameDay(newDate, e.date)) await _skip(e.habit!, e.date);
      }
    });
  }

  Future<void> _skip(Habit h, DateTime day) async {
    final existing = _n.items.where((i) => i.habitId == h.id && sameDay(i.date, day)).toList();
    if (existing.any((i) => i.skipped)) return;
    await _n.add({'habit_id': h.id, 'date': ymd(day), 'start_time': h.preferredTime ?? '09:00', 'skipped': true});
  }

  Future<void> remove(PlanEntry e) => runSafe(context, () async {
        if (e.habit != null) {
          if (e.item != null) {
            await _n.patch(e.item!.id, {'skipped': true});
          } else {
            await _skip(e.habit!, e.date);
          }
        } else {
          await _n.remove(e.item!.id);
        }
      });

  Future<void> toggleDone(PlanEntry e) => runSafe(context, () async {
        if (e.habit != null) {
          await toggleHabitLog(ref, e.habit!, e.date);
        } else if (e.task != null) {
          await toggleTask(ref, e.task!);
          await _n.patch(e.item!.id, {'done': !e.task!.isDone});
        } else {
          await _n.patch(e.item!.id, {'done': !e.item!.done});
        }
      });
}

// ======================================================================
//  Screen
// ======================================================================
class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key});
  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  String _view = 'day';
  DateTime _date = today();

  int get _ws => ref.read(weekStartProvider);

  List<PlanEntry> _entries(DateTime day) => planEntriesFor(
        day,
        items: watchList(ref, planItemsProvider),
        tasks: watchList(ref, tasksProvider),
        habits: watchList(ref, habitsProvider),
        logs: watchList(ref, habitLogsProvider),
        projects: watchList(ref, projectsProvider),
        weekStartDay: ref.watch(weekStartProvider),
        fallback: Theme.of(context).colorScheme.primary,
      );

  void _shift(int dir) => setState(() {
        _date = switch (_view) {
          'week' => addDays(_date, 7 * dir),
          'month' => DateTime(_date.year, _date.month + dir, 1),
          'list' => addDays(_date, 14 * dir),
          _ => addDays(_date, dir),
        };
      });

  String _title() {
    switch (_view) {
      case 'week':
        final s = startOfWeek(_date, _ws);
        return '${fmtDate(context, s, 'd MMM')} – ${fmtDate(context, addDays(s, 6), 'd MMM')}';
      case 'month':
        return fmtDate(context, _date, 'MMMM y');
      default:
        return fmtRelDate(context, _date);
    }
  }

  Future<void> _planDueTasks() async {
    final day = _date;
    final items = readList(ref, planItemsProvider);
    final candidates = readList(ref, tasksProvider)
        .where((t) =>
            !t.isDone &&
            (t.dueDate == null || !t.dueDate!.isAfter(day)) &&
            !items.any((i) => i.taskId == t.id && sameDay(i.date, day)))
        .toList()
      ..sort((a, b) => (a.dueDate ?? DateTime(2999)).compareTo(b.dueDate ?? DateTime(2999)));
    final selected = <String>{for (final t in candidates.where((t) => t.dueDate != null)) t.id};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text('${context.t('Plan tasks for')} ${fmtRelDate(context, day)}'),
          content: SizedBox(
            width: 460,
            height: 420,
            child: candidates.isEmpty
                ? Center(child: Text(context.t('No due or unscheduled tasks to plan.')))
                : ListView(children: [
                    for (final t in candidates)
                      CheckboxListTile(
                        value: selected.contains(t.id),
                        onChanged: (v) => setS(() => v == true ? selected.add(t.id) : selected.remove(t.id)),
                        title: Text(t.title),
                        subtitle: Text(t.dueDate == null
                            ? context.t('Unscheduled')
                            : '${context.t('Due')} ${fmtRelDate(context, t.dueDate!)}'),
                        secondary: t.isOverdue ? Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error) : null,
                      ),
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(context.t('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(context.t('Add to plan'))),
          ],
        ),
      ),
    );
    if (ok != true || selected.isEmpty) return;
    final existing = planEntriesFor(
      day,
      items: readList(ref, planItemsProvider),
      tasks: readList(ref, tasksProvider),
      habits: readList(ref, habitsProvider),
      logs: readList(ref, habitLogsProvider),
      projects: readList(ref, projectsProvider),
      weekStartDay: _ws,
    );
    var cursor = existing.isEmpty ? 9 * 60 : math.max(9 * 60, existing.map((e) => e.end).reduce(math.max));
    final rows = <Map<String, dynamic>>[];
    for (final t in candidates.where((t) => selected.contains(t.id))) {
      final dur = t.estimate ?? 30;
      if (cursor + dur > 24 * 60) cursor = 24 * 60 - dur;
      rows.add({'task_id': t.id, 'date': ymd(day), 'start_time': hm(cursor), 'duration_minutes': dur});
      cursor += dur;
    }
    await runSafe(context, () => ref.read(planItemsProvider.notifier).addMany(rows));
  }

  @override
  Widget build(BuildContext context) {
    final asyncs = <AsyncValue<dynamic>>[
      ref.watch(planItemsProvider),
      ref.watch(habitsProvider),
      ref.watch(habitLogsProvider),
      ref.watch(tasksProvider),
    ];
    final theme = Theme.of(context);
    final wide = isWide(context);
    return Scaffold(
      appBar: lifeAppBar(context, context.t('Planner'), actions: [
        IconButton(
          tooltip: context.t('Plan due tasks'),
          onPressed: _planDueTasks,
          icon: const Icon(Icons.playlist_add_check_rounded),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAdaptiveSheet(context, _NewBlockEditor(date: _date)),
        child: const Icon(Icons.add_rounded),
      ),
      body: asyncGate(context, asyncs, () {
        return Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pagePad(context), 0, pagePad(context), 8),
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'day', label: Text(context.t('Day'))),
                  ButtonSegment(value: 'week', label: Text(context.t('Week'))),
                  ButtonSegment(value: 'month', label: Text(context.t('Month'))),
                  ButtonSegment(value: 'list', label: Text(context.t('List'))),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    final d = await showDatePicker(
                        context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (d != null) setState(() => _date = d);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(_title(), style: theme.textTheme.titleSmall),
                  ),
                ),
                IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
                TextButton(onPressed: () => setState(() => _date = today()), child: Text(context.t('Today'))),
              ]),
            ]),
          ),
          Expanded(
            child: switch (_view) {
              'week' => _WeekView(
                  start: startOfWeek(_date, ref.watch(weekStartProvider)),
                  entriesFor: _entries,
                  wide: wide,
                  onOpenDay: (d) => setState(() {
                    _date = d;
                    _view = 'day';
                  }),
                ),
              'month' => _monthView(),
              'list' => _listView(),
              _ => _DayView(date: _date, entries: _entries(_date)),
            },
          ),
        ]);
      }),
    );
  }

  Widget _monthView() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ws = ref.watch(weekStartProvider);
    final m = startOfMonth(_date);
    final first = startOfWeek(m, ws);
    final weeks = ((m.difference(first).inDays + daysInMonth(m)) / 7).ceil();
    return ListView(
      padding: EdgeInsets.fromLTRB(pagePad(context), 0, pagePad(context), 100),
      children: [
        AppCard(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            Row(children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(fmtDate(context, addDays(first, i), 'E'),
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            for (var w = 0; w < weeks; w++)
              Row(children: [
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: Builder(builder: (_) {
                      final day = addDays(first, w * 7 + d);
                      final es = _entries(day);
                      final load = es.fold<int>(0, (s, e) => s + e.duration);
                      final isToday = sameDay(day, today());
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() {
                          _date = day;
                          _view = 'day';
                        }),
                        child: Container(
                          height: 84,
                          margin: const EdgeInsets.all(2),
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: cs.primary.withValues(alpha: (load / 600).clamp(0.0, 1.0) * .18),
                            border: isToday ? Border.all(color: cs.primary, width: 1.5) : null,
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${day.day}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: day.month == m.month ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: .4),
                                )),
                            const Spacer(),
                            for (final e in es.take(2))
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                height: 5,
                                decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(3)),
                              ),
                            if (es.isNotEmpty)
                              Text('${es.length} · ${fmtMinutes(context, load)}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall),
                          ]),
                        ),
                      );
                    }),
                  ),
              ]),
          ]),
        ),
      ],
    );
  }

  Widget _listView() {
    final theme = Theme.of(context);
    final days = [for (var i = 0; i < 14; i++) addDays(_date, i)];
    return ListView(
      padding: EdgeInsets.fromLTRB(pagePad(context), 0, pagePad(context), 100),
      children: [
        for (final d in days)
          Builder(builder: (_) {
            final es = _entries(d);
            if (es.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                  child: Text(fmtRelDate(context, d), style: theme.textTheme.titleSmall),
                ),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [for (final e in es) _EntryRow(entry: e)]),
                ),
              ]),
            );
          }),
      ],
    );
  }
}

// ======================================================================
//  Day view – timeline with drag & resize
// ======================================================================
const double kHourHeight = 64;

class _DayView extends ConsumerStatefulWidget {
  const _DayView({required this.date, required this.entries});
  final DateTime date;
  final List<PlanEntry> entries;
  @override
  ConsumerState<_DayView> createState() => _DayViewState();
}

class _DayViewState extends ConsumerState<_DayView> {
  final _scroll = ScrollController(initialScrollOffset: 6.5 * kHourHeight);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entries = widget.entries;
    final load = entries.fold<int>(0, (s, e) => s + e.duration);
    final doneCount = entries.where((e) => e.done).length;
    final actions = PlannerActions(ref, context);
    final placed = _layout(entries);
    final isToday = sameDay(widget.date, today());
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;

    return Column(children: [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: pagePad(context)),
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(Icons.work_history_outlined, color: cs.primary),
            const SizedBox(width: 10),
            Text('${context.t('Workload')}: ${fmtMinutes(context, load)}', style: theme.textTheme.titleSmall),
            const SizedBox(width: 12),
            Expanded(child: ProgressBar(load / 480, color: load > 600 ? cs.error : cs.primary)),
            const SizedBox(width: 12),
            Text('$doneCount/${entries.length} ${context.t('done')}', style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(pagePad(context), 0, pagePad(context), 100),
          child: LayoutBuilder(builder: (context, box) {
            const gutter = 52.0;
            final colW = box.maxWidth - gutter - 4;
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (d) {
                if (d.localPosition.dx < gutter) return;
                final m = ((d.localPosition.dy / kHourHeight * 60) ~/ 30) * 30;
                showAdaptiveSheet(context, _NewBlockEditor(date: widget.date, start: m));
              },
              child: SizedBox(
                height: 24 * kHourHeight,
                child: Stack(children: [
                  for (var h = 0; h < 24; h++)
                    Positioned(
                      top: h * kHourHeight,
                      left: 0,
                      right: 0,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          width: gutter,
                          child: Transform.translate(
                            offset: const Offset(0, -8),
                            child: Text(h == 0 ? '' : hm(h * 60),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                        ),
                        Expanded(child: Divider(height: 1, color: cs.outlineVariant.withValues(alpha: .5))),
                      ]),
                    ),
                  for (final p in placed)
                    PositionedDirectional(
                      key: ValueKey(p.entry.key),
                      top: p.entry.start / 60 * kHourHeight,
                      start: gutter + 4 + p.lane * (colW / p.lanes),
                      width: colW / p.lanes - 4,
                      height: math.max(22.0, p.entry.duration / 60 * kHourHeight - 2),
                      child: _TimelineBlock(entry: p.entry, actions: actions),
                    ),
                  if (isToday)
                    Positioned(
                      top: nowMin / 60 * kHourHeight,
                      left: gutter - 6,
                      right: 0,
                      child: IgnorePointer(
                        child: Row(children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle)),
                          Expanded(child: Container(height: 2, color: cs.error)),
                        ]),
                      ),
                    ),
                ]),
              ),
            );
          }),
        ),
      ),
    ]);
  }
}

class _Placed {
  _Placed(this.entry, this.lane);
  final PlanEntry entry;
  final int lane;
  int lanes = 1;
}

/// Overlapping blocks are spread into side-by-side lanes.
List<_Placed> _layout(List<PlanEntry> entries) {
  final sorted = [...entries]..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : b.duration.compareTo(a.duration);
    });
  final out = <_Placed>[];
  var cluster = <_Placed>[];
  var laneEnds = <int>[];
  var clusterEnd = -1;
  void flush() {
    for (final p in cluster) {
      p.lanes = laneEnds.length;
    }
    out.addAll(cluster);
    cluster = [];
    laneEnds = [];
    clusterEnd = -1;
  }

  for (final e in sorted) {
    if (cluster.isNotEmpty && e.start >= clusterEnd) flush();
    var lane = laneEnds.indexWhere((end) => end <= e.start);
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(e.end);
    } else {
      laneEnds[lane] = e.end;
    }
    cluster.add(_Placed(e, lane));
    clusterEnd = math.max(clusterEnd, e.end);
  }
  flush();
  return out;
}

class _TimelineBlock extends StatefulWidget {
  const _TimelineBlock({required this.entry, required this.actions});
  final PlanEntry entry;
  final PlannerActions actions;
  @override
  State<_TimelineBlock> createState() => _TimelineBlockState();
}

class _TimelineBlockState extends State<_TimelineBlock> {
  double _dy = 0; // move offset
  double _dh = 0; // resize offset
  bool _active = false;

  int _snap(double minutes) => (minutes / 15).round() * 15;

  void _commitMove() {
    final e = widget.entry;
    final start = _snap(e.start + _dy / kHourHeight * 60).clamp(0, math.max(0, 24 * 60 - e.duration));
    setState(() {
      _dy = 0;
      _active = false;
    });
    if (start != e.start) widget.actions.save(e, start: start);
  }

  void _commitResize() {
    final e = widget.entry;
    final dur = _snap(e.duration + _dh / kHourHeight * 60).clamp(15, math.max(15, 24 * 60 - e.start));
    setState(() {
      _dh = 0;
      _active = false;
    });
    if (dur != e.duration) widget.actions.save(e, duration: dur);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final wide = isWide(context);
    final previewStart = _snap(e.start + _dy / kHourHeight * 60).clamp(0, math.max(0, 24 * 60 - e.duration));
    final previewDur = _snap(e.duration + _dh / kHourHeight * 60).clamp(15, 24 * 60);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final card = Material(
      color: Color.alphaBlend(e.color.withValues(alpha: e.done ? .10 : .18), dark ? const Color(0xFF161922) : Colors.white),
      borderRadius: BorderRadius.circular(10),
      elevation: _active ? 6 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showAdaptiveSheet(context, _EntryEditor(entry: e)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: BorderDirectional(start: BorderSide(color: e.color, width: 4)),
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 4, 3),
          child: LayoutBuilder(builder: (c, box) {
            final tall = box.maxHeight > 40;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(e.title,
                      maxLines: tall ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        decoration: e.done ? TextDecoration.lineThrough : null,
                      )),
                  if (tall)
                    Text(
                      '${hm(_active ? previewStart : e.start)} – ${hm((_active ? previewStart : e.start) + (_active ? previewDur : e.duration))}'
                      '${e.habit != null ? '  ·  ↻' : ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                ]),
              ),
              if (tall)
                InkWell(
                  onTap: () => widget.actions.toggleDone(e),
                  child: Icon(e.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 20, color: e.color),
                ),
            ]);
          }),
        ),
      ),
    );

    return Transform.translate(
      offset: Offset(0, _dy),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          bottom: -_dh,
          child: GestureDetector(
            onVerticalDragStart: wide ? (_) => setState(() => _active = true) : null,
            onVerticalDragUpdate: wide ? (d) => setState(() => _dy += d.delta.dy) : null,
            onVerticalDragEnd: wide ? (_) => _commitMove() : null,
            onLongPressStart: wide ? null : (_) => setState(() => _active = true),
            onLongPressMoveUpdate: wide ? null : (d) => setState(() => _dy = d.offsetFromOrigin.dy),
            onLongPressEnd: wide ? null : (_) => _commitMove(),
            child: card,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: -_dh - 4,
          height: 12,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) => setState(() => _active = true),
              onVerticalDragUpdate: (d) => setState(() => _dh += d.delta.dy),
              onVerticalDragEnd: (_) => _commitResize(),
              child: Center(
                child: Container(
                  width: 28,
                  height: 4,
                  decoration: BoxDecoration(color: e.color.withValues(alpha: .6), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ======================================================================
//  Week view – drag blocks between days
// ======================================================================
class _WeekView extends ConsumerWidget {
  const _WeekView({required this.start, required this.entriesFor, required this.wide, required this.onOpenDay});
  final DateTime start;
  final List<PlanEntry> Function(DateTime) entriesFor;
  final bool wide;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final actions = PlannerActions(ref, context);
    final days = [for (var i = 0; i < 7; i++) addDays(start, i)];

    Widget dayColumn(DateTime d) {
      final es = entriesFor(d);
      final load = es.fold<int>(0, (s, e) => s + e.duration);
      final isToday = sameDay(d, today());
      return DragTarget<PlanEntry>(
        onWillAcceptWithDetails: (det) => !sameDay(det.data.date, d),
        onAcceptWithDetails: (det) => actions.save(det.data, date: d),
        builder: (c, cand, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: cand.isNotEmpty ? cs.primary.withValues(alpha: .08) : cs.surfaceContainerHighest.withValues(alpha: .25),
            borderRadius: BorderRadius.circular(14),
            border: isToday ? Border.all(color: cs.primary.withValues(alpha: .6)) : null,
          ),
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: () => onOpenDay(d),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(children: [
                  Text(fmtDate(context, d, wide ? 'EEE d' : 'EEEE d MMM'),
                      style: theme.textTheme.titleSmall?.copyWith(color: isToday ? cs.primary : null)),
                  const Spacer(),
                  if (load > 0) Text(fmtMinutes(context, load), style: theme.textTheme.labelSmall),
                ]),
              ),
            ),
            if (load > 0) ...[
              ProgressBar(load / 480, height: 4, color: load > 600 ? cs.error : cs.primary),
              const SizedBox(height: 6),
            ],
            for (final e in es)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _dragChip(context, e),
              ),
            if (es.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(context.t('Free'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
          ]),
        ),
      );
    }

    if (wide) {
      return Padding(
        padding: EdgeInsets.fromLTRB(pagePad(context), 0, pagePad(context), 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final d in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: SingleChildScrollView(child: dayColumn(d)),
              ),
            ),
        ]),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(pagePad(context), 0, pagePad(context), 100),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(context.t('Long-press a block and drop it on another day to move it.'),
              style: theme.textTheme.bodySmall),
        ),
        for (final d in days) Padding(padding: const EdgeInsets.only(bottom: 10), child: dayColumn(d)),
      ],
    );
  }

  Widget _dragChip(BuildContext context, PlanEntry e) {
    final chip = _EntryChip(entry: e);
    final fb = Material(color: Colors.transparent, child: SizedBox(width: 200, child: _EntryChip(entry: e)));
    return wide
        ? Draggable<PlanEntry>(data: e, feedback: fb, childWhenDragging: Opacity(opacity: .3, child: chip), child: chip)
        : LongPressDraggable<PlanEntry>(data: e, feedback: fb, childWhenDragging: Opacity(opacity: .3, child: chip), child: chip);
  }
}

class _EntryChip extends ConsumerWidget {
  const _EntryChip({required this.entry});
  final PlanEntry entry;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Color.alphaBlend(e.color.withValues(alpha: .16), dark ? const Color(0xFF161922) : Colors.white),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showAdaptiveSheet(context, _EntryEditor(entry: e)),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: BorderDirectional(start: BorderSide(color: e.color, width: 3)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700, decoration: e.done ? TextDecoration.lineThrough : null)),
                Text('${hm(e.start)} · ${fmtMinutes(context, e.duration)}', style: const TextStyle(fontSize: 11)),
              ]),
            ),
            if (e.habit != null) const Icon(Icons.repeat_rounded, size: 14),
          ]),
        ),
      ),
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry});
  final PlanEntry entry;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    return ListTile(
      leading: Container(width: 4, height: 36, decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(2))),
      title: Text(e.title, style: TextStyle(decoration: e.done ? TextDecoration.lineThrough : null)),
      subtitle: Text('${hm(e.start)} – ${hm(e.end)}${e.habit != null ? '  ·  ${context.t('Habit')}' : ''}'),
      trailing: IconButton(
        icon: Icon(e.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: e.color),
        onPressed: () => PlannerActions(ref, context).toggleDone(e),
      ),
      onTap: () => showAdaptiveSheet(context, _EntryEditor(entry: e)),
    );
  }
}

// ======================================================================
//  Editors
// ======================================================================
class _EntryEditor extends ConsumerStatefulWidget {
  const _EntryEditor({required this.entry});
  final PlanEntry entry;
  @override
  ConsumerState<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends ConsumerState<_EntryEditor> {
  late DateTime _date;
  late int _start;
  late int _duration;
  late final TextEditingController _notes;
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _date = e.date;
    _start = e.start;
    _duration = e.duration;
    _notes = TextEditingController(text: e.item?.notes ?? '');
    _title = TextEditingController(text: e.title);
  }

  @override
  void dispose() {
    _notes.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final ws = ref.watch(weekStartProvider);
    final theme = Theme.of(context);
    final t0 = today();
    final actions = PlannerActions(ref, context);
    final isFree = e.task == null && e.habit == null;
    final quick = <String, DateTime>{
      'Today': t0,
      'Day before': addDays(_date, -1),
      'Day after': addDays(_date, 1),
      'End of week': addDays(startOfWeek(_date, ws), 6),
      'Next week': addDays(startOfWeek(_date, ws), 7),
    };
    return EditorFrame(
      title: isFree ? context.t('Time block') : e.title,
      onDelete: () async {
        await actions.remove(e);
        if (mounted) Navigator.pop(context);
      },
      onSave: () async {
        await actions.save(e,
            date: _date, start: _start, duration: _duration, notes: _notes.text, title: isFree ? _title.text : null);
        if (mounted) Navigator.pop(context);
      },
      children: [
        if (isFree)
          TextField(controller: _title, decoration: deco(context, context.t('Title')))
        else
          AppCard(
            child: Row(children: [
              Icon(e.habit != null ? Icons.repeat_rounded : Icons.check_circle_outline, color: e.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.habit != null
                      ? context.t('Recurring habit — changing this block does not change the habit\'s default time.')
                      : '${context.t('Task due')}: ${e.task!.dueDate == null ? context.t('No date') : fmtRelDate(context, e.task!.dueDate!)} — ${context.t('planning it does not change the due date.')}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ]),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: e.done,
          title: Text(context.t('Done')),
          onChanged: (_) async {
            await actions.toggleDone(e);
            if (mounted) Navigator.pop(context);
          },
        ),
        DateField(label: context.t('Date'), value: _date, allowNone: false, onChanged: (d) => setState(() => _date = d ?? _date)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final q in quick.entries)
            ActionChip(
              avatar: const Icon(Icons.east_rounded, size: 14),
              label: Text(context.t(q.key)),
              onPressed: () => setState(() => _date = q.value),
            ),
        ]),
        Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _start ~/ 60, minute: _start % 60));
                if (t != null) setState(() => _start = t.hour * 60 + t.minute);
              },
              child: InputDecorator(
                decoration: deco(context, context.t('Start'), icon: Icons.schedule_rounded),
                child: Text(hm(_start)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final end = math.min(_start + _duration, 24 * 60 - 1);
                final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: end ~/ 60, minute: end % 60));
                if (t != null) {
                  final m = t.hour * 60 + t.minute;
                  if (m > _start) setState(() => _duration = m - _start);
                }
              },
              child: InputDecorator(
                decoration: deco(context, context.t('End'), icon: Icons.flag_outlined),
                child: Text(hm(_start + _duration)),
              ),
            ),
          ),
        ]),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in [15, 30, 45, 60, 90, 120, 180])
            ChoiceChip(
              label: Text(fmtMinutes(context, m)),
              selected: _duration == m,
              onSelected: (_) => setState(() => _duration = m),
            ),
        ]),
        TextField(controller: _notes, minLines: 2, maxLines: 5, decoration: deco(context, context.t('Notes for this block'))),
      ],
    );
  }
}

class _NewBlockEditor extends ConsumerStatefulWidget {
  const _NewBlockEditor({required this.date, this.start});
  final DateTime date;
  final int? start;
  @override
  ConsumerState<_NewBlockEditor> createState() => _NewBlockEditorState();
}

class _NewBlockEditorState extends ConsumerState<_NewBlockEditor> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _date = widget.date;
  late int _start = widget.start ?? 9 * 60;
  int _duration = 60;
  String? _taskId;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = watchList(ref, tasksProvider).where((t) => !t.isDone).toList();
    return EditorFrame(
      title: context.t('Add to plan'),
      saving: _saving,
      onSave: () async {
        if (_taskId == null && _title.text.trim().isEmpty) {
          toast(context, context.t('Pick a task or enter a title'), error: true);
          return;
        }
        setState(() => _saving = true);
        final ok = await runSafe(
            context,
            () => ref.read(planItemsProvider.notifier).add({
                  'date': ymd(_date),
                  'start_time': hm(_start),
                  'duration_minutes': _duration,
                  'task_id': _taskId,
                  'title': _taskId == null ? _title.text.trim() : null,
                  'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                }));
        if (!mounted) return;
        setState(() => _saving = false);
        if (ok) Navigator.pop(context);
      },
      children: [
        idDropdown<Task>(
          context: context,
          label: context.t('Task'),
          icon: Icons.check_circle_outline,
          value: _taskId,
          items: tasks,
          noneLabel: context.t('Free time block'),
          labelOf: (t) => t.title,
          onChanged: (v) => setState(() {
            _taskId = v;
            final t = tasks.where((x) => x.id == v).firstOrNull;
            if (t?.estimate != null) _duration = t!.estimate!;
          }),
        ),
        if (_taskId == null) TextField(controller: _title, autofocus: true, decoration: deco(context, context.t('Title'))),
        DateField(label: context.t('Date'), value: _date, allowNone: false, onChanged: (d) => setState(() => _date = d ?? _date)),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _start ~/ 60, minute: _start % 60));
            if (t != null) setState(() => _start = t.hour * 60 + t.minute);
          },
          child: InputDecorator(
            decoration: deco(context, context.t('Start'), icon: Icons.schedule_rounded),
            child: Text(hm(_start)),
          ),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in [15, 30, 45, 60, 90, 120, 180])
            ChoiceChip(label: Text(fmtMinutes(context, m)), selected: _duration == m, onSelected: (_) => setState(() => _duration = m)),
        ]),
        TextField(controller: _notes, minLines: 1, maxLines: 4, decoration: deco(context, context.t('Notes'))),
      ],
    );
  }
}
