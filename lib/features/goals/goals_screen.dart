import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/utils.dart';
import '../../data/derived.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

const kGoalStatuses = {'active': 'Active', 'achieved': 'Achieved', 'paused': 'Paused', 'dropped': 'Dropped'};
const kGoalStatusColors = {
  'active': Color(0xFF4F46E5),
  'achieved': Color(0xFF10B981),
  'paused': Color(0xFFF59E0B),
  'dropped': Color(0xFF94A3B8),
};

Future<void> showGoalEditor(BuildContext context, {Goal? goal, String? visionId}) =>
    showAdaptiveSheet(context, GoalEditor(goal: goal, visionId: visionId));

Future<void> showVisionEditor(BuildContext context, {Vision? vision}) =>
    showAdaptiveSheet(context, VisionEditor(vision: vision));

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vAsync = ref.watch(visionsProvider);
    final gAsync = ref.watch(goalsProvider);
    return Scaffold(
      appBar: lifeAppBar(context, context.t('Vision & Goals'),
          subtitle: context.t('Vision → Goals → Projects → Milestones → Tasks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showGoalEditor(context),
        icon: const Icon(Icons.flag_rounded),
        label: Text(context.t('Goal')),
      ),
      body: asyncGate(context, [vAsync, gAsync], () {
        final visions = vAsync.value!;
        final goals = gAsync.value!;
        final orphan = goals.where((g) => g.visionId == null || !visions.any((v) => v.id == g.visionId)).toList();
        if (visions.isEmpty && goals.isEmpty) {
          return EmptyState(
            icon: Icons.visibility_outlined,
            title: context.t('Start with your vision'),
            subtitle: context.t('Describe the life you want, then add concrete goals under it.'),
            action: FilledButton.icon(
              onPressed: () => showVisionEditor(context),
              icon: const Icon(Icons.add),
              label: Text(context.t('New vision')),
            ),
          );
        }
        return ListView(
          padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 100),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => showVisionEditor(context),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(context.t('New vision')),
              ),
            ),
            const SizedBox(height: 14),
            for (final v in visions) ...[
              _VisionBlock(vision: v, goals: goals.where((g) => g.visionId == v.id).toList()),
              const SizedBox(height: 18),
            ],
            if (orphan.isNotEmpty) ...[
              SectionHeader(context.t('Goals without a vision'), icon: Icons.flag_outlined, trailing: '${orphan.length}'),
              _GoalGrid(goals: orphan),
            ],
          ],
        );
      }, onRetry: () {
        ref.invalidate(visionsProvider);
        ref.invalidate(goalsProvider);
      }),
    );
  }
}

class _VisionBlock extends ConsumerWidget {
  const _VisionBlock({required this.vision, required this.goals});
  final Vision vision;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final area = watchList(ref, areasProvider).where((a) => a.id == vision.areaId).firstOrNull;
    final prog = visionProgress(vision.id, watchList(ref, goalsProvider), watchList(ref, projectsProvider),
        watchList(ref, tasksProvider), watchList(ref, milestonesProvider));
    final c = area == null ? cs.primary : hexColor(area.color);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: [c, Color.lerp(c, const Color(0xFF8B5CF6), .5)!]),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.visibility_rounded, color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                Text(context.t('VISION'), style: const TextStyle(color: Colors.white70, letterSpacing: 1.4, fontSize: 12, fontWeight: FontWeight.w700)),
                if (area != null) ...[
                  const SizedBox(width: 10),
                  Icon(areaIcon(area.icon), color: Colors.white70, size: 16),
                  const SizedBox(width: 4),
                  Text(area.name, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ]),
              const SizedBox(height: 8),
              Text(vision.title, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white)),
              if (vision.description != null) ...[
                const SizedBox(height: 6),
                Text(vision.description!, style: TextStyle(color: Colors.white.withValues(alpha: .9), height: 1.5)),
              ],
              const SizedBox(height: 14),
              Wrap(spacing: 8, children: [
                FilledButton.tonalIcon(
                  onPressed: () => showGoalEditor(context, visionId: vision.id),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(context.t('Add goal')),
                ),
                IconButton(
                  onPressed: () => showVisionEditor(context, vision: vision),
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                ),
              ]),
            ]),
          ),
          if (prog != null) ProgressRing(prog, color: Colors.white, size: 64),
        ]),
      ),
      const SizedBox(height: 12),
      if (goals.isEmpty)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(context.t('No goals under this vision yet.'), style: theme.textTheme.bodySmall),
        )
      else
        _GoalGrid(goals: goals),
    ]);
  }
}

class _GoalGrid extends StatelessWidget {
  const _GoalGrid({required this.goals});
  final List<Goal> goals;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (c, box) {
      final cols = (box.maxWidth / 360).floor().clamp(1, 4);
      final w = (box.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final g in goals) SizedBox(width: w, child: GoalCard(goal: g)),
      ]);
    });
  }
}

class GoalCard extends ConsumerWidget {
  const GoalCard({super.key, required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final projects = watchList(ref, projectsProvider);
    final tasks = watchList(ref, tasksProvider);
    final ms = watchList(ref, milestonesProvider);
    final computed = goalProgress(goal.id, projects, tasks, ms);
    final linked = projects.where((p) => p.goalId == goal.id).length;
    final area = watchList(ref, areasProvider).where((a) => a.id == goal.areaId).firstOrNull;
    final sc = kGoalStatusColors[goal.status] ?? cs.primary;
    return AppCard(
      onTap: () => showGoalEditor(context, goal: goal),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(goal.title, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
          Pill(context.t(kGoalStatuses[goal.status] ?? goal.status), color: sc),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (area != null) Pill(area.name, icon: areaIcon(area.icon), color: hexColor(area.color)),
          if (goal.targetDate != null) Pill(fmtRelDate(context, goal.targetDate!), icon: Icons.event_rounded),
          Pill('$linked ${context.t('projects')}', icon: Icons.folder_outlined,
              onTap: () => context.go('/projects?goal=${goal.id}')),
        ]),
        const SizedBox(height: 14),
        if (computed != null) ...[
          Row(children: [
            Text(context.t('From data'), style: theme.textTheme.labelSmall),
            const Spacer(),
            Text(pct(computed), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          ProgressBar(computed, color: sc),
          const SizedBox(height: 8),
        ],
        Row(children: [
          Text(context.t('Your estimate'), style: theme.textTheme.labelSmall),
          const Spacer(),
          Text('${goal.manualProgress}%', style: theme.textTheme.labelMedium),
        ]),
        const SizedBox(height: 4),
        ProgressBar(goal.manualProgress / 100, color: cs.onSurfaceVariant, height: 5),
      ]),
    );
  }
}

class GoalEditor extends ConsumerStatefulWidget {
  const GoalEditor({super.key, this.goal, this.visionId});
  final Goal? goal;
  final String? visionId;
  @override
  ConsumerState<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<GoalEditor> {
  late final TextEditingController _title, _desc;
  String? _visionId, _areaId;
  DateTime? _target;
  String _status = 'active';
  double _manual = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _title = TextEditingController(text: g?.title ?? '');
    _desc = TextEditingController(text: g?.description ?? '');
    _visionId = g?.visionId ?? widget.visionId;
    _areaId = g?.areaId;
    _target = g?.targetDate;
    _status = g?.status ?? 'active';
    _manual = (g?.manualProgress ?? 0).toDouble();
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
    final vision = ref.read(visionsProvider.notifier).byId(_visionId);
    final data = {
      'title': _title.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'vision_id': _visionId,
      'area_id': _areaId ?? vision?.areaId,
      'target_date': _target == null ? null : ymd(_target!),
      'status': _status,
      'manual_progress': _manual.round(),
    };
    final n = ref.read(goalsProvider.notifier);
    final ok = await runSafe(context, () async {
      if (widget.goal == null) {
        await n.add(data);
      } else {
        await n.patch(widget.goal!.id, data);
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.goal;
    final computed = g == null
        ? null
        : goalProgress(g.id, watchList(ref, projectsProvider), watchList(ref, tasksProvider), watchList(ref, milestonesProvider));
    return EditorFrame(
      title: context.t(g == null ? 'New goal' : 'Edit goal'),
      saving: _saving,
      onSave: _save,
      onDelete: g == null
          ? null
          : () async {
              if (!await confirmDialog(context, context.t('Delete this goal?'),
                  message: context.t('Linked projects and tasks are kept.'))) {
                return;
              }
              final ok = await runSafe(context, () async {
                await ref.read(goalsProvider.notifier).remove(g.id);
                ref.invalidate(projectsProvider);
                ref.invalidate(tasksProvider);
              });
              if (ok && mounted) Navigator.pop(context);
            },
      extraActions: [
        if (g != null)
          IconButton(
            tooltip: context.t('Create project for this goal'),
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () {
              Navigator.pop(context);
              context.go('/projects?goal=${g.id}');
            },
          ),
      ],
      children: [
        TextField(controller: _title, autofocus: g == null, decoration: deco(context, context.t('Goal'), hint: context.t('e.g. Move into Data Analysis'))),
        TextField(controller: _desc, minLines: 2, maxLines: 6, decoration: deco(context, context.t('Why it matters / definition of done'))),
        idDropdown<Vision>(
          context: context,
          label: context.t('Vision'),
          icon: Icons.visibility_outlined,
          value: _visionId,
          items: watchList(ref, visionsProvider),
          labelOf: (v) => v.title,
          onChanged: (v) => setState(() => _visionId = v),
        ),
        idDropdown<LifeArea>(
          context: context,
          label: context.t('Life area'),
          icon: Icons.donut_large_rounded,
          value: _areaId,
          items: watchList(ref, areasProvider),
          labelOf: (a) => a.name,
          onChanged: (v) => setState(() => _areaId = v),
        ),
        choiceDropdown(
          context: context,
          label: context.t('Status'),
          value: _status,
          options: {for (final e in kGoalStatuses.entries) e.key: context.t(e.value)},
          onChanged: (v) => setState(() => _status = v),
        ),
        DateField(label: context.t('Target date'), value: _target, onChanged: (d) => setState(() => _target = d)),
        if (computed != null)
          AppCard(
            child: Row(children: [
              const Icon(Icons.insights_rounded),
              const SizedBox(width: 10),
              Expanded(child: Text(context.t('Progress calculated from linked projects and tasks'))),
              Text(pct(computed), style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        FieldLabel('${context.t('Your estimate')}: ${_manual.round()}%'),
        Slider(value: _manual, min: 0, max: 100, divisions: 20, label: '${_manual.round()}%', onChanged: (v) => setState(() => _manual = v)),
      ],
    );
  }
}

class VisionEditor extends ConsumerStatefulWidget {
  const VisionEditor({super.key, this.vision});
  final Vision? vision;
  @override
  ConsumerState<VisionEditor> createState() => _VisionEditorState();
}

class _VisionEditorState extends ConsumerState<VisionEditor> {
  late final TextEditingController _title, _desc;
  String? _areaId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.vision?.title ?? '');
    _desc = TextEditingController(text: widget.vision?.description ?? '');
    _areaId = widget.vision?.areaId;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vision;
    return EditorFrame(
      title: context.t(v == null ? 'New vision' : 'Edit vision'),
      saving: _saving,
      onDelete: v == null
          ? null
          : () async {
              if (!await confirmDialog(context, context.t('Delete this vision?'), message: context.t('Its goals are kept.'))) return;
              final ok = await runSafe(context, () async {
                await ref.read(visionsProvider.notifier).remove(v.id);
                ref.invalidate(goalsProvider);
              });
              if (ok && mounted) Navigator.pop(context);
            },
      onSave: () async {
        if (_title.text.trim().isEmpty) return;
        setState(() => _saving = true);
        final data = {
          'title': _title.text.trim(),
          'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          'area_id': _areaId,
        };
        final n = ref.read(visionsProvider.notifier);
        final ok = await runSafe(context, () async {
          if (v == null) {
            await n.add(data);
          } else {
            await n.patch(v.id, data);
          }
        });
        if (!mounted) return;
        setState(() => _saving = false);
        if (ok) Navigator.pop(context);
      },
      children: [
        TextField(controller: _title, autofocus: v == null, decoration: deco(context, context.t('Vision'), hint: context.t('e.g. Build a strong, independent career'))),
        TextField(controller: _desc, minLines: 3, maxLines: 8, decoration: deco(context, context.t('Describe it in detail'))),
        idDropdown<LifeArea>(
          context: context,
          label: context.t('Life area'),
          icon: Icons.donut_large_rounded,
          value: _areaId,
          items: watchList(ref, areasProvider),
          labelOf: (a) => a.name,
          onChanged: (x) => setState(() => _areaId = x),
        ),
      ],
    );
  }
}
