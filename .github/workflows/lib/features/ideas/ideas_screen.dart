import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

Future<void> showIdeaEditor(BuildContext context, {Idea? idea, String? stageId}) =>
    showAdaptiveSheet(context, IdeaEditor(idea: idea, stageId: stageId));

class IdeasScreen extends ConsumerWidget {
  const IdeasScreen({super.key});

  Future<void> _stageEditor(BuildContext context, WidgetRef ref, [IdeaStage? s]) async {
    final name = TextEditingController(text: s?.name ?? '');
    var color = s?.color.toUpperCase() ?? kPalette[11];
    await showAdaptiveSheet(
      context,
      StatefulBuilder(
        builder: (ctx, setS) => EditorFrame(
          title: context.t(s == null ? 'New stage' : 'Edit stage'),
          onSave: () async {
            if (name.text.trim().isEmpty) return;
            final n = ref.read(ideaStagesProvider.notifier);
            final ok = await runSafe(ctx, () async {
              if (s == null) {
                await n.add({'name': name.text.trim(), 'color': color, 'sort_order': n.items.length});
              } else {
                await n.patch(s.id, {'name': name.text.trim(), 'color': color});
              }
            });
            if (ok && ctx.mounted) Navigator.pop(ctx);
          },
          children: [
            TextField(controller: name, autofocus: true, decoration: deco(ctx, context.t('Name'))),
            FieldLabel(context.t('Color')),
            ColorPicker(value: color, onChanged: (c) => setS(() => color = c)),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteStage(BuildContext context, WidgetRef ref, IdeaStage s, List<IdeaStage> stages) async {
    final others = stages.where((x) => x.id != s.id).toList();
    final ideas = ref.read(ideasProvider).valueOrNull?.where((i) => i.stageId == s.id).toList() ?? [];
    String? moveTo = others.isEmpty ? null : others.first.id;
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text('${context.t('Delete')} "${s.name}"?'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(ideas.isEmpty ? context.t('This stage is empty.') : '${ideas.length} ${context.t('ideas will be moved to:')}'),
              if (ideas.isNotEmpty && others.isNotEmpty) ...[
                const SizedBox(height: 12),
                idDropdown<IdeaStage>(
                  context: d,
                  label: context.t('Move to'),
                  value: moveTo,
                  items: others,
                  labelOf: (x) => x.name,
                  onChanged: (v) => setS(() => moveTo = v),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(context.t('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(context.t('Delete'))),
          ],
        ),
      ),
    );
    if (go != true) return;
    await runSafe(context, () async {
      final n = ref.read(ideasProvider.notifier);
      for (final i in ideas) {
        await n.patch(i.id, {'stage_id': moveTo});
      }
      await ref.read(ideaStagesProvider.notifier).remove(s.id);
    });
  }

  Future<void> _moveStage(WidgetRef ref, List<IdeaStage> stages, int i, int dir) async {
    final j = i + dir;
    if (j < 0 || j >= stages.length) return;
    final n = ref.read(ideaStagesProvider.notifier);
    await n.patch(stages[i].id, {'sort_order': j});
    await n.patch(stages[j].id, {'sort_order': i});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sAsync = ref.watch(ideaStagesProvider);
    final iAsync = ref.watch(ideasProvider);
    final wide = isWide(context);
    return Scaffold(
      appBar: lifeAppBar(context, context.t('Ideas Box'),
          subtitle: context.t('Capture → develop → turn into a task or project'),
          actions: [
            IconButton(
              tooltip: context.t('Add stage'),
              onPressed: () => _stageEditor(context, ref),
              icon: const Icon(Icons.view_column_outlined),
            ),
          ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showIdeaEditor(context),
        icon: const Icon(Icons.lightbulb_outline),
        label: Text(context.t('Idea')),
      ),
      body: asyncGate(context, [sAsync, iAsync], () {
        final stages = [...sAsync.value!]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        final ideas = iAsync.value!;
        final orphan = ideas.where((i) => !stages.any((s) => s.id == i.stageId)).toList();
        if (stages.isEmpty) {
          return EmptyState(
            icon: Icons.view_column_outlined,
            title: context.t('Create your first stage'),
            action: FilledButton(onPressed: () => _stageEditor(context, ref), child: Text(context.t('Add stage'))),
          );
        }
        return ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 90),
          children: [
            for (var si = 0; si < stages.length; si++)
              Builder(builder: (context) {
                final s = stages[si];
                final items = [
                  ...ideas.where((i) => i.stageId == s.id),
                  if (si == 0) ...orphan,
                ];
                final color = hexColor(s.color);
                return Container(
                  width: wide ? 310 : MediaQuery.sizeOf(context).width * .8,
                  margin: const EdgeInsetsDirectional.only(end: 14),
                  child: DragTarget<Idea>(
                    onWillAcceptWithDetails: (d) => d.data.stageId != s.id,
                    onAcceptWithDetails: (d) =>
                        runSafe(context, () => ref.read(ideasProvider.notifier).patch(d.data.id, {'stage_id': s.id})),
                    builder: (c, cand, _) => AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cand.isNotEmpty
                            ? color.withValues(alpha: .12)
                            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border(top: BorderSide(color: color, width: 3)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(child: Text(s.name, style: Theme.of(context).textTheme.titleSmall)),
                          Text('${items.length}'),
                          PopupMenuButton<String>(
                            iconSize: 20,
                            onSelected: (v) {
                              if (v == 'edit') _stageEditor(context, ref, s);
                              if (v == 'left') _moveStage(ref, stages, si, -1);
                              if (v == 'right') _moveStage(ref, stages, si, 1);
                              if (v == 'delete') _deleteStage(context, ref, s, stages);
                              if (v == 'add') showIdeaEditor(context, stageId: s.id);
                            },
                            itemBuilder: (c) => [
                              PopupMenuItem(value: 'add', child: Text(context.t('Add idea here'))),
                              PopupMenuItem(value: 'edit', child: Text(context.t('Rename / color'))),
                              if (si > 0) PopupMenuItem(value: 'left', child: Text(context.t('Move earlier'))),
                              if (si < stages.length - 1) PopupMenuItem(value: 'right', child: Text(context.t('Move later'))),
                              PopupMenuItem(value: 'delete', child: Text(context.t('Delete stage'))),
                            ],
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView(children: [
                            for (final i in items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _drag(wide, i, _IdeaCard(idea: i)),
                              ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                );
              }),
          ],
        );
      }, onRetry: () {
        ref.invalidate(ideaStagesProvider);
        ref.invalidate(ideasProvider);
      }),
    );
  }

  Widget _drag(bool wide, Idea i, Widget child) {
    final fb = Material(color: Colors.transparent, child: SizedBox(width: 280, child: Opacity(opacity: .9, child: child)));
    final ghost = Opacity(opacity: .3, child: child);
    return wide
        ? Draggable<Idea>(data: i, feedback: fb, childWhenDragging: ghost, child: child)
        : LongPressDraggable<Idea>(data: i, feedback: fb, childWhenDragging: ghost, child: child);
  }
}

class _IdeaCard extends ConsumerWidget {
  const _IdeaCard({required this.idea});
  final Idea idea;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cat = watchList(ref, categoriesProvider).where((c) => c.id == idea.categoryId).firstOrNull;
    final ups = idea.updates;
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => showIdeaEditor(context, idea: idea),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(idea.title, style: theme.textTheme.titleSmall),
        if (idea.content != null) ...[
          const SizedBox(height: 4),
          Text(idea.content!, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (cat != null) Pill(cat.name, color: hexColor(cat.color)),
          if (ups.isNotEmpty)
            Pill('${ups.length} · ${fmtRelDate(context, ups.last.date)}', icon: Icons.update_rounded),
          if (idea.convertedProjectId != null) Pill(context.t('Project'), icon: Icons.folder_outlined, color: Colors.green),
          if (idea.convertedTaskId != null) Pill(context.t('Task'), icon: Icons.check_circle_outline, color: Colors.green),
        ]),
      ]),
    );
  }
}

class IdeaEditor extends ConsumerStatefulWidget {
  const IdeaEditor({super.key, this.idea, this.stageId});
  final Idea? idea;
  final String? stageId;
  @override
  ConsumerState<IdeaEditor> createState() => _IdeaEditorState();
}

class _IdeaEditorState extends ConsumerState<IdeaEditor> {
  late final TextEditingController _title, _content;
  final _update = TextEditingController();
  String? _stageId, _categoryId;
  List<IdeaUpdate> _updates = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.idea;
    _title = TextEditingController(text: i?.title ?? '');
    _content = TextEditingController(text: i?.content ?? '');
    _stageId = i?.stageId ?? widget.stageId;
    _categoryId = i?.categoryId;
    _updates = [...?i?.updates];
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _update.dispose();
    super.dispose();
  }

  Map<String, dynamic> _data() => {
        'title': _title.text.trim(),
        'content': _content.text.trim().isEmpty ? null : _content.text.trim(),
        'stage_id': _stageId,
        'category_id': _categoryId,
        'updates': _updates.map((u) => u.toJson()).toList(),
      };

  Future<Idea?> _persist() async {
    if (_title.text.trim().isEmpty) {
      toast(context, context.t('Title is required'), error: true);
      return null;
    }
    final n = ref.read(ideasProvider.notifier);
    if (widget.idea == null) return n.add(_data());
    await n.patch(widget.idea!.id, _data());
    return n.byId(widget.idea!.id);
  }

  Future<void> _convert(String to) async {
    Idea? idea;
    final ok = await runSafe(context, () async {
      idea = await _persist();
      if (idea == null) return;
      if (to == 'task') {
        final t = await ref.read(tasksProvider.notifier).add({'title': idea!.title, 'notes': idea!.content});
        await ref.read(ideasProvider.notifier).patch(idea!.id, {'converted_task_id': t.id});
      } else {
        final p = await ref.read(projectsProvider.notifier).add({'name': idea!.title, 'description': idea!.content});
        await ref.read(ideasProvider.notifier).patch(idea!.id, {'converted_project_id': p.id});
        if (mounted) {
          Navigator.pop(context);
          context.go('/projects/${p.id}');
        }
        return;
      }
    }, success: context.t(to == 'task' ? 'Task created from idea' : 'Project created from idea'));
    if (ok && to == 'task' && idea != null && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i = widget.idea;
    return EditorFrame(
      title: context.t(i == null ? 'New idea' : 'Idea'),
      saving: _saving,
      onSave: () async {
        setState(() => _saving = true);
        final ok = await runSafe(context, () async {
          await _persist();
        });
        if (!mounted) return;
        setState(() => _saving = false);
        if (ok && _title.text.trim().isNotEmpty) Navigator.pop(context);
      },
      onDelete: i == null
          ? null
          : () async {
              if (!await confirmDialog(context, context.t('Delete this idea?'))) return;
              final ok = await runSafe(context, () => ref.read(ideasProvider.notifier).remove(i.id));
              if (ok && mounted) Navigator.pop(context);
            },
      children: [
        TextField(controller: _title, autofocus: i == null, decoration: deco(context, context.t('Idea'))),
        TextField(
          controller: _content,
          minLines: 3,
          maxLines: 10,
          decoration: deco(context, context.t('Original description (kept as written)')),
        ),
        Row(children: [
          Expanded(
            child: idDropdown<IdeaStage>(
              context: context,
              label: context.t('Stage'),
              value: _stageId,
              items: watchList(ref, ideaStagesProvider),
              labelOf: (s) => s.name,
              onChanged: (v) => setState(() => _stageId = v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: idDropdown<ItemCategory>(
              context: context,
              label: context.t('Category'),
              value: _categoryId,
              items: watchList(ref, categoriesProvider).where((c) => c.kind == 'idea').toList(),
              labelOf: (c) => c.name,
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ),
        ]),
        FieldLabel('${context.t('Updates')} (${_updates.length})'),
        for (final u in _updates.reversed)
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fmtDate(context, u.date, 'd MMM y · HH:mm'),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 4),
              Text(u.text),
            ]),
          ),
        TextField(
          controller: _update,
          minLines: 1,
          maxLines: 4,
          decoration: deco(context, context.t('Add a dated update'),
              suffix: IconButton(
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: () {
                  final t = _update.text.trim();
                  if (t.isEmpty) return;
                  setState(() {
                    _updates = [..._updates, IdeaUpdate(DateTime.now(), t)];
                    _update.clear();
                  });
                },
              )),
        ),
        const Divider(),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: i?.convertedTaskId != null ? null : () => _convert('task'),
            icon: const Icon(Icons.check_circle_outline),
            label: Text(context.t(i?.convertedTaskId != null ? 'Converted to task' : 'Convert to task')),
          ),
          OutlinedButton.icon(
            onPressed: i?.convertedProjectId != null
                ? () {
                    Navigator.pop(context);
                    context.go('/projects/${i!.convertedProjectId}');
                  }
                : () => _convert('project'),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: Text(context.t(i?.convertedProjectId != null ? 'Open project' : 'Convert to project')),
          ),
        ]),
      ],
    );
  }
}
