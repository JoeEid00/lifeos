import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/utils.dart';
import '../../data/derived.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';
import '../tasks/task_editor.dart';
import 'projects_screen.dart';

class ProjectWorkspace extends ConsumerWidget {
  const ProjectWorkspace({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(projectsProvider);
    return asyncGate(context, [async, ref.watch(tasksProvider), ref.watch(milestonesProvider)], () {
      final project = (async.valueOrNull ?? []).where((p) => p.id == projectId).firstOrNull;
      if (project == null) {
        return Scaffold(
          appBar: lifeAppBar(context, context.t('Project')),
          body: EmptyState(
            icon: Icons.folder_off_outlined,
            title: context.t('This project was deleted'),
            action: FilledButton(onPressed: () => context.go('/projects'), child: Text(context.t('Back to projects'))),
          ),
        );
      }
      return _Workspace(project: project);
    });
  }
}

class _Workspace extends ConsumerWidget {
  const _Workspace({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tasks = watchList(ref, tasksProvider);
    final ms = watchList(ref, milestonesProvider).where((m) => m.projectId == project.id).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final goal = watchList(ref, goalsProvider).where((g) => g.id == project.goalId).firstOrNull;
    final area = watchList(ref, areasProvider).where((a) => a.id == project.areaId).firstOrNull;
    final allProjects = watchList(ref, projectsProvider);
    final parent = allProjects.where((p) => p.id == project.parentId).firstOrNull;
    final subs = allProjects.where((p) => p.parentId == project.id).toList();
    final pt = tasks.where((t) => t.projectId == project.id).toList();
    final progress = projectProgress(project.id, tasks, watchList(ref, milestonesProvider));
    final overdue = pt.where((t) => t.isOverdue).length;
    final next = (pt.where((t) => !t.isDone).toList()
          ..sort((a, b) => (a.dueDate ?? DateTime(2999)).compareTo(b.dueDate ?? DateTime(2999))))
        .firstOrNull;
    final color = hexColor(project.color);
    final links = urlRegex.allMatches(project.description ?? '').map((m) => m.group(0)!).toList();

    final header = AppCard(
      padding: const EdgeInsets.all(20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProgressRing(progress, size: 76, color: color, stroke: 7),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(project.name, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              PopupMenuButton<String>(
                tooltip: context.t('Status'),
                onSelected: (s) => runSafe(context, () => ref.read(projectsProvider.notifier).patch(project.id, {'status': s})),
                itemBuilder: (c) => [
                  for (final s in kProjectStatuses)
                    PopupMenuItem(value: s, child: Text(context.t(kProjectStatusLabels[s]!))),
                ],
                child: Pill('${context.t(kProjectStatusLabels[project.status] ?? project.status)} ▾',
                    color: kProjectStatusColors[project.status]),
              ),
              if (goal != null) Pill(goal.title, icon: Icons.flag_outlined, color: cs.primary, onTap: () => context.go('/goals')),
              if (area != null) Pill(area.name, icon: areaIcon(area.icon), color: hexColor(area.color)),
              if (parent != null)
                Pill(parent.name, icon: Icons.account_tree_outlined, onTap: () => context.go('/projects/${parent.id}')),
              if (project.dueDate != null) Pill(fmtRelDate(context, project.dueDate!), icon: Icons.event_rounded),
            ]),
          ]),
        ),
      ]),
    );

    final stats = Wrap(spacing: 12, runSpacing: 12, children: [
      for (final s in [
        (Icons.checklist_rounded, context.t('Tasks'), '${pt.where((t) => t.isDone).length}/${pt.length}', cs.primary),
        (Icons.flag_circle_outlined, context.t('Milestones'), '${ms.where((m) => m.done).length}/${ms.length}', const Color(0xFF8B5CF6)),
        (Icons.warning_amber_rounded, context.t('Overdue'), '$overdue', overdue > 0 ? cs.error : Colors.green),
      ])
        SizedBox(width: 200, child: StatCard(icon: s.$1, label: s.$2, value: s.$3, color: s.$4)),
    ]);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: lifeAppBar(context, project.name, actions: [
          IconButton(
            tooltip: context.t('Edit project'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showProjectEditor(context, project: project),
          ),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showTaskEditor(context, defaults: {'project_id': project.id, 'goal_id': project.goalId}),
          icon: const Icon(Icons.add_task_rounded),
          label: Text(context.t('Task')),
        ),
        body: NestedScrollView(
          headerSliverBuilder: (c, _) => [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  header,
                  const SizedBox(height: 12),
                  stats,
                  const SizedBox(height: 8),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: context.t('Overview')),
                  Tab(text: context.t('Milestones')),
                  Tab(text: context.t('All tasks')),
                  Tab(text: context.t('Notes')),
                ],
              ),
            ),
          ],
          body: TabBarView(children: [
            _overview(context, ref, next, links, subs),
            _MilestonesTab(project: project, milestones: ms, tasks: pt),
            _taskList(context, pt),
            _NotesTab(project: project),
          ]),
        ),
      ),
    );
  }

  Widget _overview(BuildContext context, WidgetRef ref, Task? next, List<String> links, List<Project> subs) {
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(pagePad(context), 16, pagePad(context), 100),
      children: [
        if (next != null) ...[
          SectionHeader(context.t('Next task'), icon: Icons.arrow_circle_right_outlined),
          AppCard(padding: const EdgeInsets.symmetric(horizontal: 6), child: TaskTile(task: next, showProject: false)),
          const SizedBox(height: 18),
        ],
        SectionHeader(context.t('Description'), icon: Icons.notes_rounded),
        AppCard(
          child: SelectableText(
            project.description ?? context.t('No description yet.'),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ),
        if (links.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionHeader(context.t('Resources'), icon: Icons.link_rounded),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final l in links)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.open_in_new_rounded, size: 18),
                  title: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                  trailing: const Icon(Icons.copy_rounded, size: 16),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: l));
                    toast(context, context.t('Link copied'));
                  },
                ),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        SectionHeader(
          context.t('Sub-projects'),
          icon: Icons.account_tree_outlined,
          action: TextButton.icon(
            onPressed: () => showProjectEditor(context,
                defaults: {'goal_id': project.goalId, 'area_id': project.areaId, 'parent_id': project.id}),
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.t('Add')),
          ),
        ),
        if (subs.isEmpty)
          Text(context.t('No sub-projects. Set "Parent project" on another project to nest it here.'),
              style: theme.textTheme.bodySmall)
        else
          for (final s in subs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: () => context.go('/projects/${s.id}'),
                child: Row(children: [
                  Icon(Icons.folder_rounded, color: hexColor(s.color)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.name, style: theme.textTheme.titleSmall)),
                  SizedBox(
                    width: 100,
                    child: ProgressBar(
                      projectProgress(s.id, watchList(ref, tasksProvider), watchList(ref, milestonesProvider)),
                      color: hexColor(s.color),
                    ),
                  ),
                ]),
              ),
            ),
      ],
    );
  }

  Widget _taskList(BuildContext context, List<Task> pt) {
    if (pt.isEmpty) {
      return EmptyState(icon: Icons.task_alt_rounded, title: context.t('No tasks in this project yet'));
    }
    final sorted = [...pt]..sort((a, b) => (a.isDone ? 1 : 0).compareTo(b.isDone ? 1 : 0));
    return ListView(
      padding: EdgeInsets.fromLTRB(pagePad(context), 16, pagePad(context), 100),
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(children: [
            for (var i = 0; i < sorted.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 48),
              TaskTile(task: sorted[i], showProject: false),
            ],
          ]),
        ),
      ],
    );
  }
}

class _MilestonesTab extends ConsumerWidget {
  const _MilestonesTab({required this.project, required this.milestones, required this.tasks});
  final Project project;
  final List<Milestone> milestones;
  final List<Task> tasks;

  Future<void> _editMilestone(BuildContext context, WidgetRef ref, [Milestone? m]) async {
    final title = TextEditingController(text: m?.title ?? '');
    final desc = TextEditingController(text: m?.description ?? '');
    DateTime? due = m?.dueDate;
    await showAdaptiveSheet(
      context,
      StatefulBuilder(
        builder: (ctx, setS) => EditorFrame(
          title: context.t(m == null ? 'New milestone' : 'Edit milestone'),
          onDelete: m == null
              ? null
              : () async {
                  if (!await confirmDialog(ctx, context.t('Delete this milestone?'))) return;
                  final ok = await runSafe(ctx, () => ref.read(milestonesProvider.notifier).remove(m.id));
                  if (ok && ctx.mounted) Navigator.pop(ctx);
                },
          onSave: () async {
            if (title.text.trim().isEmpty) return;
            final data = {
              'project_id': project.id,
              'title': title.text.trim(),
              'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
              'due_date': due == null ? null : ymd(due!),
              if (m == null) 'sort_order': milestones.length,
            };
            final n = ref.read(milestonesProvider.notifier);
            final ok = await runSafe(ctx, () async {
              if (m == null) {
                await n.add(data);
              } else {
                await n.patch(m.id, data);
              }
            });
            if (ok && ctx.mounted) Navigator.pop(ctx);
          },
          children: [
            TextField(controller: title, autofocus: m == null, decoration: deco(ctx, context.t('Title'))),
            TextField(controller: desc, minLines: 2, maxLines: 6, decoration: deco(ctx, context.t('Description & references'))),
            DateField(label: context.t('Due date'), value: due, onChanged: (d) => setS(() => due = d)),
          ],
        ),
      ),
    );
  }

  Future<void> _move(WidgetRef ref, int i, int dir) async {
    final j = i + dir;
    if (j < 0 || j >= milestones.length) return;
    final n = ref.read(milestonesProvider.notifier);
    await n.patch(milestones[i].id, {'sort_order': j});
    await n.patch(milestones[j].id, {'sort_order': i});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loose = tasks.where((t) => t.milestoneId == null || !milestones.any((m) => m.id == t.milestoneId)).toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(pagePad(context), 16, pagePad(context), 100),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => _editMilestone(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: Text(context.t('Add milestone')),
          ),
        ),
        const SizedBox(height: 12),
        if (milestones.isEmpty)
          Text(context.t('Split the project into stages, e.g. Data collection → Cleaning → Dashboard.'),
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        for (var i = 0; i < milestones.length; i++) ...[
          Builder(builder: (context) {
            final m = milestones[i];
            final mt = tasks.where((t) => t.milestoneId == m.id).toList();
            final done = mt.where((t) => t.isDone).length;
            final prog = mt.isEmpty ? (m.done ? 1.0 : 0.0) : done / mt.length;
            return AppCard(
              padding: EdgeInsets.zero,
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: !m.done && prog < 1,
                  leading: CircleAvatar(
                    radius: 15,
                    backgroundColor: (prog >= 1 ? Colors.green : cs.primary).withValues(alpha: .12),
                    child: prog >= 1
                        ? const Icon(Icons.check_rounded, size: 18, color: Colors.green)
                        : Text('${i + 1}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800)),
                  ),
                  title: Text(m.title, style: theme.textTheme.titleSmall),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Expanded(child: ProgressBar(prog, height: 5)),
                      const SizedBox(width: 8),
                      Text(mt.isEmpty ? '' : '$done/${mt.length}', style: theme.textTheme.labelSmall),
                      if (m.dueDate != null) ...[
                        const SizedBox(width: 8),
                        Text(fmtRelDate(context, m.dueDate!), style: theme.textTheme.labelSmall),
                      ],
                    ]),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _editMilestone(context, ref, m);
                      if (v == 'up') _move(ref, i, -1);
                      if (v == 'down') _move(ref, i, 1);
                      if (v == 'done') {
                        runSafe(context, () => ref.read(milestonesProvider.notifier).patch(m.id, {'done': !m.done}));
                      }
                    },
                    itemBuilder: (c) => [
                      PopupMenuItem(value: 'edit', child: Text(context.t('Edit'))),
                      PopupMenuItem(value: 'done', child: Text(context.t(m.done ? 'Mark as open' : 'Mark as done'))),
                      if (i > 0) PopupMenuItem(value: 'up', child: Text(context.t('Move up'))),
                      if (i < milestones.length - 1) PopupMenuItem(value: 'down', child: Text(context.t('Move down'))),
                    ],
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  children: [
                    if (m.description != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(m.description!, style: theme.textTheme.bodySmall),
                        ),
                      ),
                    for (final t in mt) TaskTile(task: t, showProject: false, dense: true),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => showTaskEditor(context, defaults: {
                          'project_id': project.id,
                          'milestone_id': m.id,
                          'goal_id': project.goalId,
                        }),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(context.t('Add task to this milestone')),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 10),
        ],
        if (loose.isNotEmpty) ...[
          const SizedBox(height: 8),
          SectionHeader(context.t('Tasks without milestone'), trailing: '${loose.length}'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(children: [for (final t in loose) TaskTile(task: t, showProject: false, dense: true)]),
          ),
        ],
      ],
    );
  }
}

class _NotesTab extends ConsumerStatefulWidget {
  const _NotesTab({required this.project});
  final Project project;
  @override
  ConsumerState<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<_NotesTab> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    final ok = await runSafe(context,
        () => ref.read(projectNotesProvider.notifier).add({'project_id': widget.project.id, 'content': text}));
    if (ok) _c.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = watchList(ref, projectNotesProvider).where((n) => n.projectId == widget.project.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView(
      padding: EdgeInsets.fromLTRB(pagePad(context), 16, pagePad(context), 100),
      children: [
        TextField(
          controller: _c,
          minLines: 2,
          maxLines: 6,
          decoration: deco(context, context.t('Add a note, update or comment'),
              suffix: IconButton(icon: const Icon(Icons.send_rounded), onPressed: _add)),
        ),
        const SizedBox(height: 16),
        if (notes.isEmpty) Text(context.t('No notes yet.'), style: theme.textTheme.bodySmall),
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.schedule_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(fmtDate(context, n.createdAt, 'd MMM y · HH:mm'), style: theme.textTheme.labelSmall),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    onPressed: () async {
                      if (await confirmDialog(context, context.t('Delete this note?'))) {
                        await runSafe(context, () => ref.read(projectNotesProvider.notifier).remove(n.id));
                      }
                    },
                  ),
                ]),
                SelectableText(n.content, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
              ]),
            ),
          ),
      ],
    );
  }
}
