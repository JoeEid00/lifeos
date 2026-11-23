import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/utils.dart';
import '../../data/derived.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';
import '../goals/goals_screen.dart';
import '../habits/habits_screen.dart';
import '../tasks/task_editor.dart';

/// Interactive tree: Life area → Vision → Goal → Project → Milestone → Task (+ habits).
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  bool _expandAll = false;
  bool _showDone = false;
  int _gen = 0;

  @override
  Widget build(BuildContext context) {
    final asyncs = <AsyncValue<dynamic>>[
      ref.watch(areasProvider),
      ref.watch(visionsProvider),
      ref.watch(goalsProvider),
      ref.watch(projectsProvider),
      ref.watch(milestonesProvider),
      ref.watch(tasksProvider),
      ref.watch(habitsProvider),
    ];
    return Scaffold(
      appBar: lifeAppBar(context, context.t('Life Map'), subtitle: context.t('How everything in your life connects'), actions: [
        IconButton(
          tooltip: context.t(_expandAll ? 'Collapse all' : 'Expand all'),
          icon: Icon(_expandAll ? Icons.unfold_less_rounded : Icons.unfold_more_rounded),
          onPressed: () => setState(() {
            _expandAll = !_expandAll;
            _gen++;
          }),
        ),
      ]),
      body: asyncGate(context, asyncs, () {
        final areas = [...watchList(ref, areasProvider)]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        final visions = watchList(ref, visionsProvider);
        final goals = watchList(ref, goalsProvider);
        final projects = watchList(ref, projectsProvider);
        final ms = watchList(ref, milestonesProvider);
        final tasks = watchList(ref, tasksProvider).where((t) => _showDone || !t.isDone).toList();
        final allTasks = watchList(ref, tasksProvider);
        final habits = watchList(ref, habitsProvider).where((h) => !h.archived).toList();

        Widget taskNode(Task t) => _Node(
              icon: t.isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: t.isDone ? Colors.green : null,
              title: t.title,
              trailing: t.isOverdue ? Pill(context.t('overdue'), color: Theme.of(context).colorScheme.error) : null,
              onTap: () => showTaskEditor(context, task: t),
            );

        Widget projectNode(Project p) {
          final pm = ms.where((m) => m.projectId == p.id).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          final pt = tasks.where((t) => t.projectId == p.id).toList();
          final loose = pt.where((t) => t.milestoneId == null || !pm.any((m) => m.id == t.milestoneId)).toList();
          final subs = projects.where((x) => x.parentId == p.id).toList();
          return _Branch(
            key: ValueKey('p${p.id}$_gen'),
            expanded: _expandAll,
            icon: Icons.folder_rounded,
            color: hexColor(p.color),
            title: p.name,
            progress: projectProgress(p.id, allTasks, ms),
            onOpen: () => context.go('/projects/${p.id}'),
            children: [
              for (final s in subs) projectNode(s),
              for (final m in pm)
                Builder(builder: (_) {
                  final mt = allTasks.where((t) => t.milestoneId == m.id).toList();
                  final done = mt.where((t) => t.isDone).length;
                  return _Branch(
                    key: ValueKey('m${m.id}$_gen'),
                    expanded: _expandAll,
                    icon: Icons.flag_circle_outlined,
                    title: m.title,
                    badge: mt.isEmpty ? null : '$done/${mt.length}',
                    progress: mt.isEmpty ? (m.done ? 1.0 : 0.0) : done / mt.length,
                    children: [for (final t in pt.where((t) => t.milestoneId == m.id)) taskNode(t)],
                  );
                }),
              for (final t in loose) taskNode(t),
            ],
          );
        }

        Widget goalNode(Goal g) {
          final gp = projects.where((p) => p.goalId == g.id && p.parentId == null && (_showDone || !p.isClosed)).toList();
          final direct = tasks.where((t) => t.goalId == g.id && t.projectId == null).toList();
          return _Branch(
            key: ValueKey('g${g.id}$_gen'),
            expanded: _expandAll,
            icon: Icons.flag_rounded,
            color: Theme.of(context).colorScheme.primary,
            title: g.title,
            progress: effectiveGoalProgress(g, projects, allTasks, ms),
            onOpen: () => showGoalEditor(context, goal: g),
            children: [for (final p in gp) projectNode(p), for (final t in direct) taskNode(t)],
          );
        }

        List<Widget> areaChildren(String? areaId) {
          final av = visions.where((v) => v.areaId == areaId).toList();
          final ag = goals.where((g) =>
              (g.areaId == areaId || (areaId == null && g.areaId == null)) &&
              (g.visionId == null || !visions.any((v) => v.id == g.visionId && v.areaId == areaId)) &&
              (_showDone || g.status == 'active' || g.status == 'paused')).toList();
          final ap = projects.where((p) => p.areaId == areaId && p.goalId == null && p.parentId == null && (_showDone || !p.isClosed)).toList();
          final ah = habits.where((h) => h.areaId == areaId).toList();
          return [
            for (final v in av)
              _Branch(
                key: ValueKey('v${v.id}$_gen'),
                expanded: _expandAll,
                icon: Icons.visibility_rounded,
                color: const Color(0xFF8B5CF6),
                title: v.title,
                progress: visionProgress(v.id, goals, projects, allTasks, ms),
                onOpen: () => showVisionEditor(context, vision: v),
                children: [for (final g in goals.where((g) => g.visionId == v.id)) goalNode(g)],
              ),
            for (final g in ag) goalNode(g),
            for (final p in ap) projectNode(p),
            if (ah.isNotEmpty)
              _Branch(
                key: ValueKey('h$areaId$_gen'),
                expanded: _expandAll,
                icon: Icons.repeat_rounded,
                color: Colors.green,
                title: '${context.t('Habits')} (${ah.length})',
                children: [
                  for (final h in ah)
                    _Node(icon: Icons.repeat_rounded, color: hexColor(h.color), title: h.title, onTap: () => showHabitEditor(context, habit: h)),
                ],
              ),
          ];
        }

        final unassigned = areaChildren(null);
        return ListView(
          padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 60),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilterChip(
                label: Text(context.t('Include completed')),
                selected: _showDone,
                onSelected: (v) => setState(() => _showDone = v),
              ),
            ),
            const SizedBox(height: 10),
            for (final a in areas)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  borderColor: hexColor(a.color).withValues(alpha: .35),
                  child: Builder(builder: (_) {
                    final kids = areaChildren(a.id);
                    return _Branch(
                      key: ValueKey('a${a.id}$_gen'),
                      expanded: true,
                      icon: areaIcon(a.icon),
                      color: hexColor(a.color),
                      title: a.name,
                      big: true,
                      badge: kids.isEmpty ? context.t('empty') : null,
                      children: kids,
                    );
                  }),
                ),
              ),
            if (unassigned.isNotEmpty)
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _Branch(
                  key: ValueKey('none$_gen'),
                  expanded: _expandAll,
                  icon: Icons.help_outline_rounded,
                  title: context.t('Not linked to a life area'),
                  big: true,
                  children: unassigned,
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _Branch extends StatefulWidget {
  const _Branch({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.color,
    this.progress,
    this.onOpen,
    this.expanded = false,
    this.big = false,
    this.badge,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;
  final Color? color;
  final double? progress;
  final VoidCallback? onOpen;
  final bool expanded;
  final bool big;
  final String? badge;
  @override
  State<_Branch> createState() => _BranchState();
}

class _BranchState extends State<_Branch> {
  late bool _open = widget.expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.color ?? theme.colorScheme.onSurfaceVariant;
    final has = widget.children.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: has ? () => setState(() => _open = !_open) : widget.onOpen,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: widget.big ? 10 : 6),
          child: Row(children: [
            SizedBox(
              width: 24,
              child: has
                  ? Icon(_open ? Icons.expand_more_rounded : (context.isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded), size: 20)
                  : null,
            ),
            Icon(widget.icon, color: c, size: widget.big ? 22 : 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(widget.title,
                  overflow: TextOverflow.ellipsis,
                  style: widget.big ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (widget.badge != null) Pill(widget.badge!),
            if (widget.progress != null) ...[
              const SizedBox(width: 8),
              SizedBox(width: 60, child: ProgressBar(widget.progress!, color: c, height: 5)),
              const SizedBox(width: 6),
              SizedBox(width: 38, child: Text(pct(widget.progress!), style: theme.textTheme.labelSmall)),
            ],
            if (widget.onOpen != null && has)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                onPressed: widget.onOpen,
              ),
          ]),
        ),
      ),
      if (_open && has)
        Container(
          margin: const EdgeInsetsDirectional.only(start: 20),
          decoration: BoxDecoration(
            border: BorderDirectional(start: BorderSide(color: c.withValues(alpha: .3), width: 2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children),
        ),
    ]);
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.icon, required this.title, this.color, this.onTap, this.trailing});
  final IconData icon;
  final String title;
  final Color? color;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(32, 5, 8, 5),
        child: Row(children: [
          Icon(icon, size: 16, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}
