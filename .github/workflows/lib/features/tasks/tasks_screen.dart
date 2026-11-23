import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';
import 'task_editor.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});
  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String _view = 'list';
  String _query = '';
  String? _categoryId;
  bool _showDone = false;
  DateTime _month = startOfMonth(DateTime.now());
  DateTime? _selectedDay;

  List<Task> _filtered(List<Task> all) => all.where((t) {
        if (_categoryId != null && t.categoryId != _categoryId) return false;
        if (_query.isNotEmpty) {
          final hay = '${t.title} ${t.notes ?? ''} ${t.steps.map((s) => s.title).join(' ')}';
          if (!matchesQuery(hay, _query)) return false;
        }
        return true;
      }).toList();

  Future<void> _bulkAdd() async {
    final text = await promptText(context, context.t('Add several tasks'),
        hint: context.t('One task per line'), maxLines: 10);
    if (text == null) return;
    final lines = splitLines(text);
    if (lines.isEmpty) return;
    await runSafe(context, () async {
      await ref.read(tasksProvider.notifier).addMany([
        for (final l in lines) {'title': l, if (_categoryId != null) 'category_id': _categoryId},
      ]);
    }, success: '${lines.length} ${context.t('tasks added')}');
  }

  Future<void> _exportCsv(List<Task> tasks) async {
    String esc(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    final projects = readList(ref, projectsProvider);
    final b = StringBuffer('title,status,due_date,priority,project,notes\n');
    for (final t in tasks) {
      final p = projects.where((p) => p.id == t.projectId).firstOrNull;
      b.writeln([esc(t.title), t.status, t.dueDate == null ? '' : ymd(t.dueDate!), t.priority, esc(p?.name), esc(t.notes)].join(','));
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (mounted) toast(context, context.t('CSV copied to clipboard'));
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);
    final cats = watchList(ref, categoriesProvider).where((c) => c.kind == 'task').toList();
    final all = tasksAsync.valueOrNull ?? <Task>[];
    final tasks = _filtered(all);
    final open = all.where((t) => !t.isDone).length;

    return Scaffold(
      appBar: lifeAppBar(context, context.t('Tasks'),
          subtitle: '$open ${context.t('open')}',
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) {
                if (v == 'bulk') _bulkAdd();
                if (v == 'csv') _exportCsv(tasks);
                if (v == 'cats') context.go('/areas');
              },
              itemBuilder: (c) => [
                PopupMenuItem(value: 'bulk', child: Text(context.t('Add several tasks'))),
                PopupMenuItem(value: 'csv', child: Text(context.t('Export CSV'))),
                PopupMenuItem(value: 'cats', child: Text(context.t('Manage categories'))),
              ],
            ),
          ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTaskEditor(context, defaults: {
          if (_selectedDay != null && _view == 'calendar') 'due_date': ymd(_selectedDay!),
          if (_categoryId != null) 'category_id': _categoryId,
        }),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('Task')),
      ),
      body: asyncGate(context, [tasksAsync], () {
        return Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 8),
            child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'list', icon: const Icon(Icons.view_list_rounded, size: 18), label: Text(context.t('List'))),
                  ButtonSegment(value: 'board', icon: const Icon(Icons.view_kanban_rounded, size: 18), label: Text(context.t('Board'))),
                  ButtonSegment(value: 'calendar', icon: const Icon(Icons.calendar_view_month_rounded, size: 18), label: Text(context.t('Calendar'))),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: deco(context, context.t('Search tasks'), icon: Icons.search_rounded),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (cats.isNotEmpty)
                SizedBox(
                  width: 190,
                  child: idDropdown<ItemCategory>(
                    context: context,
                    label: context.t('Category'),
                    value: _categoryId,
                    items: cats,
                    noneLabel: context.t('All'),
                    labelOf: (c) => c.name,
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
              if (_view == 'list')
                FilterChip(
                  label: Text(context.t('Show completed')),
                  selected: _showDone,
                  onSelected: (v) => setState(() => _showDone = v),
                ),
            ]),
          ),
          Expanded(
            child: switch (_view) {
              'board' => _Board(tasks: tasks),
              'calendar' => _calendar(tasks),
              _ => _list(tasks),
            },
          ),
        ]);
      }, onRetry: () => ref.invalidate(tasksProvider)),
    );
  }

  Widget _list(List<Task> tasks) {
    final t0 = today();
    final ws = ref.watch(weekStartProvider);
    final endOfWeek = addDays(startOfWeek(t0, ws), 7);
    final open = tasks.where((t) => !t.isDone).toList()
      ..sort((a, b) {
        final c = (a.dueDate ?? DateTime(2999)).compareTo(b.dueDate ?? DateTime(2999));
        return c != 0 ? c : b.priority.compareTo(a.priority);
      });
    final groups = <String, List<Task>>{
      'Overdue': open.where((t) => t.isOverdue).toList(),
      'Today': open.where((t) => sameDay(t.dueDate, t0)).toList(),
      'This week': open.where((t) => t.dueDate != null && t.dueDate!.isAfter(t0) && t.dueDate!.isBefore(endOfWeek)).toList(),
      'Later': open.where((t) => t.dueDate != null && !t.dueDate!.isBefore(endOfWeek)).toList(),
      'Unscheduled': open.where((t) => t.dueDate == null).toList(),
      if (_showDone)
        'Completed': tasks.where((t) => t.isDone).toList()
          ..sort((a, b) => (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt)),
    };
    if (groups.values.every((g) => g.isEmpty)) {
      return EmptyState(
        icon: Icons.task_alt_rounded,
        title: context.t('No tasks here'),
        subtitle: context.t('Add a task or change the filters.'),
      );
    }
    final colors = {
      'Overdue': Theme.of(context).colorScheme.error,
      'Today': Theme.of(context).colorScheme.primary,
      'Completed': Colors.green,
    };
    return ListView(
      padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 100),
      children: [
        for (final g in groups.entries)
          if (g.value.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[g.key] ?? Colors.grey, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(context.t(g.key), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 6),
                Text('${g.value.length}', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Column(children: [
                for (var i = 0; i < g.value.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 48),
                  TaskTile(task: g.value[i]),
                ],
              ]),
            ),
          ],
      ],
    );
  }

  Widget _calendar(List<Task> tasks) {
    final theme = Theme.of(context);
    final ws = ref.watch(weekStartProvider);
    final first = startOfWeek(_month, ws);
    final weeks = ((first.difference(_month).inDays.abs() + daysInMonth(_month)) / 7).ceil();
    final sel = _selectedDay;
    final dayTasks = sel == null ? <Task>[] : tasks.where((t) => sameDay(t.dueDate, sel)).toList();

    final grid = AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          IconButton(
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1, 1)),
              icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
              child: Text(fmtDate(context, _month, 'MMMM y'),
                  textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
          IconButton(
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1, 1)),
              icon: const Icon(Icons.chevron_right_rounded)),
        ]),
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(fmtDate(context, addDays(first, i), 'E'),
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        for (var w = 0; w < weeks; w++)
          Row(children: [
            for (var d = 0; d < 7; d++) Expanded(child: _dayCell(addDays(first, w * 7 + d), tasks)),
          ]),
      ]),
    );

    final list = AppCard(
      padding: const EdgeInsets.all(8),
      child: sel == null
          ? Padding(padding: const EdgeInsets.all(16), child: Text(context.t('Select a day to see its tasks')))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(fmtDate(context, sel, 'EEEE d MMMM'), style: theme.textTheme.titleMedium),
              ),
              if (dayTasks.isEmpty)
                Padding(padding: const EdgeInsets.all(8), child: Text(context.t('No tasks due')))
              else
                for (final t in dayTasks) TaskTile(task: t, dense: true),
            ]),
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 100),
      children: [
        if (isWide(context))
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: grid),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: list),
          ])
        else ...[
          grid,
          const SizedBox(height: 12),
          list,
        ],
      ],
    );
  }

  Widget _dayCell(DateTime day, List<Task> tasks) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final inMonth = day.month == _month.month;
    final dt = tasks.where((t) => sameDay(t.dueDate, day)).toList();
    final done = dt.where((t) => t.isDone).length;
    final overdue = dt.any((t) => t.isOverdue);
    final selected = sameDay(day, _selectedDay);
    final isToday = sameDay(day, today());
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selectedDay = day),
      child: Container(
        height: 62,
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: .12) : null,
          borderRadius: BorderRadius.circular(10),
          border: isToday ? Border.all(color: cs.primary, width: 1.5) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${day.day}',
              style: TextStyle(
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: inMonth ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: .4),
              )),
          const Spacer(),
          if (dt.isNotEmpty) ...[
            Text('$done/${dt.length}',
                style: theme.textTheme.labelSmall?.copyWith(color: overdue ? cs.error : cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            ProgressBar(done / dt.length, height: 4, color: overdue ? cs.error : Colors.green),
          ],
        ]),
      ),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.tasks});
  final List<Task> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cols = {
      'todo': (context.t('To do'), const Color(0xFF64748B)),
      'doing': (context.t('Doing'), const Color(0xFF0EA5E9)),
      'done': (context.t('Done'), const Color(0xFF10B981)),
    };
    final wide = isWide(context);
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 90),
      children: [
        for (final c in cols.entries)
          Container(
            width: wide ? 340 : MediaQuery.sizeOf(context).width * .82,
            margin: const EdgeInsetsDirectional.only(end: 14),
            child: DragTarget<Task>(
              onWillAcceptWithDetails: (d) => d.data.status != c.key,
              onAcceptWithDetails: (d) => runSafe(context, () => setTaskStatus(ref, d.data, c.key)),
              builder: (ctx, cand, rej) {
                final items = tasks.where((t) => t.status == c.key).toList();
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: cand.isNotEmpty
                        ? c.value.$2.withValues(alpha: .10)
                        : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Row(children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: c.value.$2, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(c.value.$1, style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        Text('${items.length}'),
                      ]),
                    ),
                    Expanded(
                      child: ListView(children: [
                        for (final t in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _draggable(
                              wide,
                              t,
                              AppCard(padding: const EdgeInsets.symmetric(horizontal: 4), child: TaskTile(task: t, dense: true)),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _draggable(bool wide, Task t, Widget child) {
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(width: 300, child: Opacity(opacity: .9, child: child)),
    );
    final ghost = Opacity(opacity: .35, child: child);
    return wide
        ? Draggable<Task>(data: t, feedback: feedback, childWhenDragging: ghost, child: child)
        : LongPressDraggable<Task>(data: t, feedback: feedback, childWhenDragging: ghost, child: child);
  }
}
