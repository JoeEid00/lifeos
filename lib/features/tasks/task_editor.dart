import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

Future<void> showTaskEditor(BuildContext context, {Task? task, Map<String, dynamic> defaults = const {}}) =>
    showAdaptiveSheet(context, TaskEditor(task: task, defaults: defaults));

class TaskEditor extends ConsumerStatefulWidget {
  const TaskEditor({super.key, this.task, this.defaults = const {}});
  final Task? task;
  final Map<String, dynamic> defaults;
  @override
  ConsumerState<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _estimate;
  DateTime? _due;
  int _priority = 0;
  String _status = 'todo';
  String? _projectId, _milestoneId, _goalId, _categoryId;
  List<TaskStep> _steps = [];
  List<String> _links = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final d = widget.defaults;
    _title = TextEditingController(text: t?.title ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    _estimate = TextEditingController(text: t?.estimate?.toString() ?? '');
    _due = t?.dueDate ?? parseDateTime(d['due_date']);
    _priority = t?.priority ?? 0;
    _status = t?.status ?? 'todo';
    _projectId = t?.projectId ?? d['project_id'] as String?;
    _milestoneId = t?.milestoneId ?? d['milestone_id'] as String?;
    _goalId = t?.goalId ?? d['goal_id'] as String?;
    _categoryId = t?.categoryId ?? d['category_id'] as String?;
    _steps = [...?t?.steps];
    _links = [...?t?.links];
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _estimate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      toast(context, context.t('Title is required'), error: true);
      return;
    }
    setState(() => _saving = true);
    final wasDone = widget.task?.isDone ?? false;
    final data = <String, dynamic>{
      'title': _title.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'due_date': _due == null ? null : ymd(_due!),
      'priority': _priority,
      'status': _status,
      'project_id': _projectId,
      'milestone_id': _projectId == null ? null : _milestoneId,
      'goal_id': _goalId,
      'category_id': _categoryId,
      'steps': _steps.map((s) => s.toJson()).toList(),
      'links': _links,
      'estimate_minutes': int.tryParse(_estimate.text.trim()),
      if (_status == 'done' && !wasDone) 'completed_at': isoUtc(DateTime.now()),
      if (_status != 'done') 'completed_at': null,
    };
    final n = ref.read(tasksProvider.notifier);
    final ok = await runSafe(context, () async {
      if (widget.task == null) {
        await n.add(data);
      } else {
        await n.patch(widget.task!.id, data);
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, context.t('Delete this task?'))) return;
    final ok = await runSafe(context, () => ref.read(tasksProvider.notifier).remove(widget.task!.id));
    if (ok && mounted) Navigator.pop(context);
  }

  Future<void> _schedule() async {
    final t = widget.task;
    if (t == null) return;
    final day = _due ?? today();
    await runSafe(context, () async {
      await ref.read(planItemsProvider.notifier).add({
        'task_id': t.id,
        'date': ymd(day),
        'start_time': '09:00',
        'duration_minutes': t.estimate ?? 30,
      });
    }, success: '${context.t('Added to planner')} · ${fmtRelDate(context, day)}');
  }

  @override
  Widget build(BuildContext context) {
    final projects = watchList(ref, projectsProvider).where((p) => !p.isClosed || p.id == _projectId).toList();
    final milestones = watchList(ref, milestonesProvider).where((m) => m.projectId == _projectId).toList();
    final goals = watchList(ref, goalsProvider);
    final cats = watchList(ref, categoriesProvider).where((c) => c.kind == 'task').toList();
    final done = _steps.where((s) => s.done).length;

    return EditorFrame(
      title: context.t(widget.task == null ? 'New task' : 'Edit task'),
      saving: _saving,
      onSave: _save,
      onDelete: widget.task == null ? null : _delete,
      extraActions: [
        if (widget.task != null)
          IconButton(
            tooltip: context.t('Schedule in planner'),
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: _schedule,
          ),
      ],
      children: [
        TextField(
          controller: _title,
          autofocus: widget.task == null,
          textInputAction: TextInputAction.next,
          decoration: deco(context, context.t('Title')),
        ),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'todo', label: Text(context.t('To do')), icon: const Icon(Icons.radio_button_unchecked, size: 16)),
            ButtonSegment(value: 'doing', label: Text(context.t('Doing')), icon: const Icon(Icons.timelapse_rounded, size: 16)),
            ButtonSegment(value: 'done', label: Text(context.t('Done')), icon: const Icon(Icons.check_circle_outline, size: 16)),
          ],
          selected: {_status},
          onSelectionChanged: (s) => setState(() => _status = s.first),
        ),
        DateField(label: context.t('Due date'), value: _due, onChanged: (d) => setState(() => _due = d)),
        Row(children: [
          Expanded(
            child: choiceDropdown(
              context: context,
              label: context.t('Priority'),
              icon: Icons.outlined_flag_rounded,
              value: '$_priority',
              options: {for (var i = 0; i < 4; i++) '$i': context.t(kPriorityLabels[i])},
              onChanged: (v) => setState(() => _priority = int.parse(v)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _estimate,
              keyboardType: TextInputType.number,
              decoration: deco(context, context.t('Estimate (min)'), icon: Icons.timer_outlined),
            ),
          ),
        ]),
        idDropdown<Project>(
          context: context,
          label: context.t('Project'),
          icon: Icons.folder_outlined,
          value: _projectId,
          items: projects,
          labelOf: (p) => p.name,
          onChanged: (v) => setState(() {
            _projectId = v;
            _milestoneId = null;
          }),
        ),
        if (_projectId != null && milestones.isNotEmpty)
          idDropdown<Milestone>(
            key: ValueKey('ms-$_projectId'),
            context: context,
            label: context.t('Milestone'),
            icon: Icons.flag_circle_outlined,
            value: _milestoneId,
            items: milestones,
            labelOf: (m) => m.title,
            onChanged: (v) => setState(() => _milestoneId = v),
          ),
        Row(children: [
          Expanded(
            child: idDropdown<Goal>(
              context: context,
              label: context.t('Goal'),
              icon: Icons.flag_outlined,
              value: _goalId,
              items: goals,
              labelOf: (g) => g.title,
              onChanged: (v) => setState(() => _goalId = v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: idDropdown<ItemCategory>(
              context: context,
              label: context.t('Category'),
              icon: Icons.label_outline_rounded,
              value: _categoryId,
              items: cats,
              labelOf: (c) => c.name,
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ),
        ]),
        TextField(
          controller: _notes,
          minLines: 3,
          maxLines: 8,
          decoration: deco(context, context.t('Notes')),
        ),
        FieldLabel('${context.t('Steps')}${_steps.isEmpty ? '' : '  ($done/${_steps.length})'}'),
        StringListEditor(
          items: _steps.map((s) => s.title).toList(),
          checked: _steps.map((s) => s.done).toList(),
          hint: context.t('Add a step'),
          onToggle: (i) => setState(() => _steps[i] = TaskStep(_steps[i].title, !_steps[i].done)),
          onChanged: (titles) => setState(() {
            final old = {for (final s in _steps) s.title: s.done};
            _steps = [for (final t in titles) TaskStep(t, old[t] ?? false)];
          }),
        ),
        FieldLabel(context.t('Links (images, videos, resources)')),
        StringListEditor(
          items: _links,
          icon: Icons.link_rounded,
          hint: 'https://…',
          onChanged: (l) => setState(() => _links = l),
        ),
      ],
    );
  }
}

/// Compact, reusable task row.
class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, this.showProject = true, this.dense = false});
  final Task task;
  final bool showProject;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final project = task.projectId == null
        ? null
        : watchList(ref, projectsProvider).where((p) => p.id == task.projectId).firstOrNull;
    final cat = watchList(ref, categoriesProvider).where((c) => c.id == task.categoryId).firstOrNull;
    final steps = task.steps;
    final stepsDone = steps.where((s) => s.done).length;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showTaskEditor(context, task: task),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 4 : 8, horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            value: task.isDone,
            shape: const CircleBorder(),
            activeColor: Colors.green,
            side: BorderSide(color: task.priority > 0 ? kPriorityColors[task.priority] : cs.outline, width: 1.8),
            onChanged: (_) => runSafe(context, () => toggleTask(ref, task)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  task.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: task.isDone ? TextDecoration.lineThrough : null,
                    color: task.isDone ? cs.onSurfaceVariant : null,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (task.dueDate != null)
                    Pill(fmtRelDate(context, task.dueDate!),
                        icon: Icons.event_rounded, color: task.isOverdue ? cs.error : cs.onSurfaceVariant),
                  if (task.status == 'doing') Pill(context.t('Doing'), color: const Color(0xFF0EA5E9)),
                  if (steps.isNotEmpty) Pill('$stepsDone/${steps.length}', icon: Icons.checklist_rounded),
                  if (showProject && task.projectId != null)
                    Pill(
                      project?.name ?? context.t('Deleted project'),
                      icon: Icons.folder_outlined,
                      color: project == null ? cs.error : hexColor(project.color),
                      onTap: project == null ? null : () => context.go('/projects/${project.id}'),
                    ),
                  if (cat != null) Pill(cat.name, color: hexColor(cat.color)),
                  if (task.links.isNotEmpty) Pill('${task.links.length}', icon: Icons.link_rounded),
                ]),
              ]),
            ),
          ),
          if (task.priority >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Icon(Icons.flag_rounded, size: 18, color: kPriorityColors[task.priority]),
            ),
        ]),
      ),
    );
  }
}
