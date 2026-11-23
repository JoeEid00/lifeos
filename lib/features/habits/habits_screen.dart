import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../core/utils.dart';
import '../../data/derived.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

const kFrequencies = {'daily': 'Daily', 'weekly': 'Weekly', 'monthly': 'Monthly'};

Future<void> showHabitEditor(BuildContext context, {Habit? habit}) =>
    showAdaptiveSheet(context, HabitEditor(habit: habit));

class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});
  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen> {
  bool _showArchived = false;

  Future<void> _bulk() async {
    final text = await promptText(context, context.t('Add several habits'), hint: context.t('One habit per line'), maxLines: 8);
    if (text == null) return;
    final lines = splitLines(text);
    final n = ref.read(habitsProvider.notifier);
    await runSafe(context, () async {
      await n.addMany([
        for (var i = 0; i < lines.length; i++) {'title': lines[i], 'sort_order': n.items.length + i},
      ]);
    }, success: '${lines.length} ${context.t('habits added')}');
  }

  @override
  Widget build(BuildContext context) {
    final hAsync = ref.watch(habitsProvider);
    final lAsync = ref.watch(habitLogsProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: lifeAppBar(
          context,
          context.t('Habits & Routines'),
          actions: [
            IconButton(tooltip: context.t('Add several habits'), onPressed: _bulk, icon: const Icon(Icons.playlist_add_rounded)),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: context.t('Today')), Tab(text: context.t('All habits'))],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showHabitEditor(context),
          icon: const Icon(Icons.add_rounded),
          label: Text(context.t('Habit')),
        ),
        body: asyncGate(context, [hAsync, lAsync], () {
          final habits = hAsync.value!;
          final logs = lAsync.value!;
          return TabBarView(children: [
            _today(habits, logs),
            _all(habits, logs),
          ]);
        }, onRetry: () {
          ref.invalidate(habitsProvider);
          ref.invalidate(habitLogsProvider);
        }),
      ),
    );
  }

  Widget _today(List<Habit> habits, List<HabitLog> logs) {
    final ws = ref.watch(weekStartProvider);
    final t0 = today();
    final due = habits.where((h) => habitDueOn(h, t0, logs, ws)).toList()
      ..sort((a, b) => (a.preferredMinutes ?? 9999).compareTo(b.preferredMinutes ?? 9999));
    if (habits.isEmpty) {
      return EmptyState(
        icon: Icons.repeat_rounded,
        title: context.t('No habits yet'),
        subtitle: context.t('Create routines like a morning routine with steps.'),
      );
    }
    final done = due.where((h) => habitDoneOn(logs, h.id, t0)).length;
    final groups = <String, List<Habit>>{};
    for (final h in due) {
      groups.putIfAbsent(dayPartOf(h.preferredMinutes), () => []).add(h);
    }
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(pagePad(context), 12, pagePad(context), 100),
      children: [
        AppCard(
          child: Row(children: [
            ProgressRing(due.isEmpty ? 0 : done / due.length, size: 64, color: Colors.green),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fmtDate(context, t0, 'EEEE d MMMM'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('$done / ${due.length} ${context.t('habits done today')}', style: theme.textTheme.bodyMedium),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        for (final part in kDayParts)
          if (groups[part] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(context.t(part), style: theme.textTheme.titleSmall),
            ),
            for (final h in groups[part]!)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HabitCheckTile(habit: h, day: t0),
              ),
          ],
      ],
    );
  }

  Widget _all(List<Habit> habits, List<HabitLog> logs) {
    final list = habits.where((h) => _showArchived || !h.archived).toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(pagePad(context), 12, pagePad(context), 100),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilterChip(
            label: Text(context.t('Show archived')),
            selected: _showArchived,
            onSelected: (v) => setState(() => _showArchived = v),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (c, box) {
          final cols = (box.maxWidth / 380).floor().clamp(1, 3);
          final w = (box.maxWidth - (cols - 1) * 12) / cols;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final h in list) SizedBox(width: w, child: _HabitCard(habit: h, logs: logs)),
          ]);
        }),
      ],
    );
  }
}

/// Check-in row with optional routine steps (used in Habits and Dashboard).
class HabitCheckTile extends ConsumerStatefulWidget {
  const HabitCheckTile({super.key, required this.habit, required this.day, this.compact = false});
  final Habit habit;
  final DateTime day;
  final bool compact;
  @override
  ConsumerState<HabitCheckTile> createState() => _HabitCheckTileState();
}

class _HabitCheckTileState extends ConsumerState<HabitCheckTile> {
  final _stepDone = <int>{};
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.habit;
    final theme = Theme.of(context);
    final logs = watchList(ref, habitLogsProvider);
    final ws = ref.watch(weekStartProvider);
    final done = habitDoneOn(logs, h.id, widget.day);
    final stats = habitStats(h, logs, ws);
    final color = hexColor(h.color);
    final steps = h.steps;

    Future<void> toggle() => runSafe(context, () => toggleHabitLog(ref, h, widget.day));

    final row = Row(children: [
      InkWell(
        customBorder: const CircleBorder(),
        onTap: toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: done ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: done ? const Icon(Icons.check_rounded, color: Colors.white, size: 22) : null,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(h.title,
              style: theme.textTheme.titleSmall?.copyWith(
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? theme.colorScheme.onSurfaceVariant : null,
              )),
          const SizedBox(height: 3),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (h.preferredTime != null) Pill(h.preferredTime!, icon: Icons.schedule_rounded),
            if (h.frequency != 'daily')
              Pill('${stats.periodCount}/${stats.target} ${context.t(h.frequency == 'weekly' ? 'this week' : 'this month')}',
                  color: stats.periodComplete ? Colors.green : null),
            if (stats.streak > 0) Pill('${stats.streak}', icon: Icons.local_fire_department_rounded, color: Colors.orange),
            if (steps.isNotEmpty) Pill('${steps.length} ${context.t('steps')}', icon: Icons.checklist_rounded),
          ]),
        ]),
      ),
      if (steps.isNotEmpty && !widget.compact)
        IconButton(
          icon: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
          onPressed: () => setState(() => _open = !_open),
        ),
    ]);

    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: widget.compact ? toggle : () => showHabitEditor(context, habit: h),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row,
        if (_open && steps.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (var i = 0; i < steps.length; i++)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: done || _stepDone.contains(i),
              title: Text(steps[i]),
              onChanged: done
                  ? null
                  : (v) {
                      setState(() => v == true ? _stepDone.add(i) : _stepDone.remove(i));
                      if (_stepDone.length == steps.length) toggle();
                    },
            ),
        ],
      ]),
    );
  }
}

class _HabitCard extends ConsumerWidget {
  const _HabitCard({required this.habit, required this.logs});
  final Habit habit;
  final List<HabitLog> logs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ws = ref.watch(weekStartProvider);
    final s = habitStats(habit, logs, ws);
    final color = hexColor(habit.color);
    final t0 = today();
    final start = addDays(t0, -27);
    final cat = watchList(ref, categoriesProvider).where((c) => c.id == habit.categoryId).firstOrNull;
    return AppCard(
      onTap: () => showHabitEditor(context, habit: habit),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(habit.title, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
          Pill(context.t(kFrequencies[habit.frequency]!) + (habit.frequency == 'daily' ? '' : ' ×${habit.target}')),
        ]),
        if (habit.archived || cat != null) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            if (habit.archived) Pill(context.t('Archived')),
            if (cat != null) Pill(cat.name, color: hexColor(cat.color)),
          ]),
        ],
        const SizedBox(height: 14),
        Row(children: [
          _stat(context, Icons.local_fire_department_rounded, '${s.streak}', context.t('Streak'), Colors.orange),
          _stat(context, Icons.emoji_events_rounded, '${s.best}', context.t('Best'), Colors.amber.shade700),
          _stat(context, Icons.percent_rounded, pct(s.rate), context.t('Rate'), color),
        ]),
        const SizedBox(height: 14),
        Text(context.t('Last 28 days — tap a day to log it'), style: theme.textTheme.labelSmall),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (c, box) {
          final size = ((box.maxWidth - 13 * 4) / 14).clamp(10.0, 26.0);
          return Wrap(spacing: 4, runSpacing: 4, children: [
            for (var i = 0; i < 28; i++)
              Builder(builder: (_) {
                final d = addDays(start, i);
                final on = habitDoneOn(logs, habit.id, d);
                return Tooltip(
                  message: fmtDate(context, d, 'EEE d MMM'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => runSafe(context, () => toggleHabitLog(ref, habit, d)),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: on ? color : color.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(5),
                        border: sameDay(d, t0) ? Border.all(color: theme.colorScheme.onSurface, width: 1.4) : null,
                      ),
                    ),
                  ),
                );
              }),
          ]);
        }),
      ]),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String value, String label, Color c) => Expanded(
        child: Row(children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ]),
        ]),
      );
}

class HabitEditor extends ConsumerStatefulWidget {
  const HabitEditor({super.key, this.habit});
  final Habit? habit;
  @override
  ConsumerState<HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends ConsumerState<HabitEditor> {
  late final TextEditingController _title, _desc;
  String _freq = 'daily';
  int _target = 1;
  String? _time;
  int _duration = 30;
  String? _areaId, _categoryId;
  String _color = '#10B981';
  List<String> _steps = [];
  bool _archived = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _title = TextEditingController(text: h?.title ?? '');
    _desc = TextEditingController(text: h?.description ?? '');
    _freq = h?.frequency ?? 'daily';
    _target = h == null ? 1 : h.integer('target', 1);
    _time = h?.preferredTime;
    _duration = h?.duration ?? 30;
    _areaId = h?.areaId;
    _categoryId = h?.categoryId;
    _color = h?.color.toUpperCase() ?? '#10B981';
    _steps = [...?h?.steps];
    _archived = h?.archived ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      toast(context, context.t('Title is required'), error: true);
      return;
    }
    setState(() => _saving = true);
    final n = ref.read(habitsProvider.notifier);
    // Editing keeps the habit's preferred time unless changed here.
    final data = {
      'title': _title.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'frequency': _freq,
      'target': _freq == 'daily' ? 1 : _target,
      'preferred_time': _time,
      'duration_minutes': _duration,
      'area_id': _areaId,
      'category_id': _categoryId,
      'color': _color,
      'steps': [for (final s in _steps) {'title': s}],
      'archived': _archived,
      if (widget.habit == null) 'sort_order': n.items.length,
    };
    final ok = await runSafe(context, () async {
      if (widget.habit == null) {
        await n.add(data);
      } else {
        await n.patch(widget.habit!.id, data);
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.habit;
    return EditorFrame(
      title: context.t(h == null ? 'New habit' : 'Edit habit'),
      saving: _saving,
      onSave: _save,
      onDelete: h == null
          ? null
          : () async {
              if (!await confirmDialog(context, context.t('Delete this habit and its history?'),
                  message: context.t('Tip: archive it instead to keep the history.'))) {
                return;
              }
              final ok = await runSafe(context, () async {
                await ref.read(habitsProvider.notifier).remove(h.id);
                ref.invalidate(habitLogsProvider);
                ref.invalidate(planItemsProvider);
              });
              if (ok && mounted) Navigator.pop(context);
            },
      children: [
        TextField(controller: _title, autofocus: h == null, decoration: deco(context, context.t('Habit'), hint: context.t('e.g. Morning routine'))),
        TextField(controller: _desc, minLines: 1, maxLines: 4, decoration: deco(context, context.t('Description'))),
        SegmentedButton<String>(
          segments: [for (final e in kFrequencies.entries) ButtonSegment(value: e.key, label: Text(context.t(e.value)))],
          selected: {_freq},
          onSelectionChanged: (s) => setState(() => _freq = s.first),
        ),
        if (_freq != 'daily')
          Row(children: [
            Expanded(child: Text('${context.t('Times per')} ${context.t(_freq == 'weekly' ? 'week' : 'month')}: $_target')),
            IconButton(onPressed: _target > 1 ? () => setState(() => _target--) : null, icon: const Icon(Icons.remove_circle_outline)),
            IconButton(onPressed: _target < 31 ? () => setState(() => _target++) : null, icon: const Icon(Icons.add_circle_outline)),
          ]),
        Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final m = parseHm(_time) ?? 7 * 60;
                final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
                if (t != null) setState(() => _time = hm(t.hour * 60 + t.minute));
              },
              child: InputDecorator(
                decoration: deco(context, context.t('Preferred time'),
                    icon: Icons.schedule_rounded,
                    suffix: _time == null
                        ? null
                        : IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _time = null))),
                child: Text(_time ?? context.t('Anytime')),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: choiceDropdown(
              context: context,
              label: context.t('Duration'),
              icon: Icons.timer_outlined,
              value: '$_duration',
              options: {for (final m in [5, 10, 15, 20, 30, 45, 60, 90, 120]) '$m': fmtMinutes(context, m)},
              onChanged: (v) => setState(() => _duration = int.parse(v)),
            ),
          ),
        ]),
        Row(children: [
          Expanded(
            child: idDropdown<LifeArea>(
              context: context,
              label: context.t('Life area'),
              value: _areaId,
              items: watchList(ref, areasProvider),
              labelOf: (a) => a.name,
              onChanged: (v) => setState(() => _areaId = v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: idDropdown<ItemCategory>(
              context: context,
              label: context.t('Category'),
              value: _categoryId,
              items: watchList(ref, categoriesProvider).where((c) => c.kind == 'habit').toList(),
              labelOf: (c) => c.name,
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ),
        ]),
        FieldLabel(context.t('Routine steps (optional)')),
        StringListEditor(
          items: _steps,
          hint: context.t('e.g. Drink water → Meditate → Exercise'),
          onChanged: (l) => setState(() => _steps = l),
        ),
        FieldLabel(context.t('Color')),
        ColorPicker(value: _color, onChanged: (c) => setState(() => _color = c)),
        if (h != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.t('Archived')),
            value: _archived,
            onChanged: (v) => setState(() => _archived = v),
          ),
      ],
    );
  }
}
