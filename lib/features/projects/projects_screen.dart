import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/utils.dart';
import '../../data/derived.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

const kProjectStatuses = ['planning', 'active', 'on_hold', 'done', 'archived'];
const kProjectStatusLabels = {
  'planning': 'Planning',
  'active': 'Active',
  'on_hold': 'On hold',
  'done': 'Done',
  'archived': 'Archived',
};
const kProjectStatusColors = {
  'planning': Color(0xFFF59E0B),
  'active': Color(0xFF4F46E5),
  'on_hold': Color(0xFF64748B),
  'done': Color(0xFF10B981),
  'archived': Color(0xFF94A3B8),
};

Future<void> showProjectEditor(BuildContext context, {Project? project, Map<String, dynamic> defaults = const {}}) =>
    showAdaptiveSheet(context, ProjectEditor(project: project, defaults: defaults));

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key, this.goalFilter});
  final String? goalFilter;
  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  String _status = 'open';
  String? _goalId;
  String? _areaId;

  @override
  void initState() {
    super.initState();
    _goalId = widget.goalFilter;
  }

  @override
  void didUpdateWidget(covariant ProjectsScreen old) {
    super.didUpdateWidget(old);
    if (old.goalFilter != widget.goalFilter) _goalId = widget.goalFilter;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(projectsProvider);
    final goals = watchList(ref, goalsProvider);
    final areas = watchList(ref, areasProvider);
    final all = async.valueOrNull ?? <Project>[];
    final list = all.where((p) {
      if (_status == 'open' && p.isClosed) return false;
      if (_status != 'open' && _status != 'all' && p.status != _status) return false;
      if (_goalId != null && p.goalId != _goalId) return false;
      if (_areaId != null && p.areaId != _areaId) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: lifeAppBar(context, context.t('Projects'), subtitle: '${all.where((p) => !p.isClosed).length} ${context.t('active')}'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showProjectEditor(context, defaults: {if (_goalId != null) 'goal_id': _goalId}),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('Project')),
      ),
      body: asyncGate(context, [async], () {
        return CustomScrollView(slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 12),
            sliver: SliverToBoxAdapter(
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final s in ['open', 'all', ...kProjectStatuses])
                  ChoiceChip(
                    label: Text(context.t(s == 'open' ? 'Open' : s == 'all' ? 'All' : kProjectStatusLabels[s]!)),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
                SizedBox(
                  width: 220,
                  child: idDropdown<Goal>(
                    context: context,
                    label: context.t('Goal'),
                    value: _goalId,
                    items: goals,
                    noneLabel: context.t('All goals'),
                    labelOf: (g) => g.title,
                    onChanged: (v) => setState(() => _goalId = v),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: idDropdown<LifeArea>(
                    context: context,
                    label: context.t('Life area'),
                    value: _areaId,
                    items: areas,
                    noneLabel: context.t('All areas'),
                    labelOf: (a) => a.name,
                    onChanged: (v) => setState(() => _areaId = v),
                  ),
                ),
              ]),
            ),
          ),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.folder_open_rounded,
                title: context.t('No projects yet'),
                subtitle: context.t('Turn a goal into a project with milestones and tasks.'),
                action: FilledButton.icon(
                  onPressed: () => showProjectEditor(context),
                  icon: const Icon(Icons.add),
                  label: Text(context.t('New project')),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pagePad(context), 0, pagePad(context), 100),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 420,
                  mainAxisExtent: 236,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                delegate: SliverChildBuilderDelegate((c, i) => ProjectCard(project: list[i]), childCount: list.length),
              ),
            ),
        ]);
      }, onRetry: () => ref.invalidate(projectsProvider)),
    );
  }
}

class ProjectCard extends ConsumerWidget {
  const ProjectCard({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tasks = watchList(ref, tasksProvider);
    final ms = watchList(ref, milestonesProvider);
    final goal = watchList(ref, goalsProvider).where((g) => g.id == project.goalId).firstOrNull;
    final area = watchList(ref, areasProvider).where((a) => a.id == project.areaId).firstOrNull;
    final progress = projectProgress(project.id, tasks, ms);
    final pt = tasks.where((t) => t.projectId == project.id).toList();
    final overdue = pt.where((t) => t.isOverdue).length;
    final next = (pt.where((t) => !t.isDone).toList()
          ..sort((a, b) => (a.dueDate ?? DateTime(2999)).compareTo(b.dueDate ?? DateTime(2999))))
        .firstOrNull;
    final color = hexColor(project.color);
    final statusColor = kProjectStatusColors[project.status] ?? cs.primary;

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => context.go('/projects/${project.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 5, color: color),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(project.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                ),
                Pill(context.t(kProjectStatusLabels[project.status] ?? project.status), color: statusColor),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (goal != null) Pill(goal.title, icon: Icons.flag_outlined, color: cs.primary),
                if (area != null) Pill(area.name, icon: areaIcon(area.icon), color: hexColor(area.color)),
                if (project.dueDate != null)
                  Pill(fmtRelDate(context, project.dueDate!), icon: Icons.event_rounded),
              ]),
              const Spacer(),
              if (next != null)
                Row(children: [
                  Icon(Icons.arrow_forward_rounded, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(next.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: ProgressBar(progress, color: color)),
                const SizedBox(width: 10),
                Text(pct(progress), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Text('${pt.where((t) => t.isDone).length}/${pt.length} ${context.t('tasks')}',
                    style: theme.textTheme.bodySmall),
                const Spacer(),
                if (overdue > 0)
                  Pill('$overdue ${context.t('overdue')}', color: cs.error, icon: Icons.warning_amber_rounded),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class ProjectEditor extends ConsumerStatefulWidget {
  const ProjectEditor({super.key, this.project, this.defaults = const {}});
  final Project? project;
  final Map<String, dynamic> defaults;
  @override
  ConsumerState<ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends ConsumerState<ProjectEditor> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  String _status = 'active';
  String? _goalId, _areaId, _parentId;
  DateTime? _due;
  String _color = kPalette.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    final d = widget.defaults;
    _name = TextEditingController(text: p?.name ?? d['name'] as String? ?? '');
    _desc = TextEditingController(text: p?.description ?? d['description'] as String? ?? '');
    _status = p?.status ?? 'active';
    _goalId = p?.goalId ?? d['goal_id'] as String?;
    _areaId = p?.areaId ?? d['area_id'] as String?;
    _parentId = p?.parentId ?? d['parent_id'] as String?;
    _due = p?.dueDate;
    _color = p?.color.toUpperCase() ?? kPalette.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, context.t('Name is required'), error: true);
      return;
    }
    setState(() => _saving = true);
    // Inherit the life area from the goal when not set.
    final goal = ref.read(goalsProvider.notifier).byId(_goalId);
    final data = {
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'status': _status,
      'goal_id': _goalId,
      'area_id': _areaId ?? goal?.areaId,
      'parent_id': _parentId,
      'due_date': _due == null ? null : ymd(_due!),
      'color': _color,
    };
    final n = ref.read(projectsProvider.notifier);
    Project? created;
    final ok = await runSafe(context, () async {
      if (widget.project == null) {
        created = await n.add(data);
      } else {
        await n.patch(widget.project!.id, data);
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, created);
    }
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, context.t('Delete this project?'),
        message: context.t('Milestones and notes are deleted. Tasks are kept without a project.'))) {
      return;
    }
    final ok = await runSafe(context, () async {
      await ref.read(projectsProvider.notifier).remove(widget.project!.id);
      ref.invalidate(tasksProvider);
      ref.invalidate(milestonesProvider);
    });
    if (ok && mounted) {
      Navigator.pop(context);
      if (GoRouter.of(context).canPop()) context.go('/projects');
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = watchList(ref, goalsProvider);
    final areas = watchList(ref, areasProvider);
    final parents = watchList(ref, projectsProvider).where((p) => p.id != widget.project?.id).toList();
    return EditorFrame(
      title: context.t(widget.project == null ? 'New project' : 'Edit project'),
      saving: _saving,
      onSave: _save,
      onDelete: widget.project == null ? null : _delete,
      children: [
        TextField(controller: _name, autofocus: widget.project == null, decoration: deco(context, context.t('Name'))),
        TextField(
          controller: _desc,
          minLines: 3,
          maxLines: 8,
          decoration: deco(context, context.t('Description & resource links')),
        ),
        choiceDropdown(
          context: context,
          label: context.t('Status'),
          value: _status,
          options: {for (final s in kProjectStatuses) s: context.t(kProjectStatusLabels[s]!)},
          onChanged: (v) => setState(() => _status = v),
        ),
        idDropdown<Goal>(
          context: context,
          label: context.t('Goal'),
          icon: Icons.flag_outlined,
          value: _goalId,
          items: goals,
          labelOf: (g) => g.title,
          onChanged: (v) => setState(() => _goalId = v),
        ),
        idDropdown<LifeArea>(
          context: context,
          label: context.t('Life area'),
          icon: Icons.donut_large_rounded,
          value: _areaId,
          items: areas,
          labelOf: (a) => a.name,
          onChanged: (v) => setState(() => _areaId = v),
        ),
        idDropdown<Project>(
          context: context,
          label: context.t('Parent project'),
          icon: Icons.account_tree_outlined,
          value: _parentId,
          items: parents,
          labelOf: (p) => p.name,
          onChanged: (v) => setState(() => _parentId = v),
        ),
        DateField(label: context.t('Due date'), value: _due, onChanged: (d) => setState(() => _due = d)),
        FieldLabel(context.t('Color')),
        ColorPicker(value: _color, onChanged: (c) => setState(() => _color = c)),
      ],
    );
  }
}
