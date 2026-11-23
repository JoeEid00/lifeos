import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../core/utils.dart';
import '../../data/derived.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

const kCategoryKinds = {'task': 'Tasks', 'habit': 'Habits', 'idea': 'Ideas', 'shopping': 'Shopping'};

class AreasScreen extends ConsumerWidget {
  const AreasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: lifeAppBar(
          context,
          context.t('Life Areas'),
          subtitle: context.t('Life areas are separate from operational categories'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: context.t('Life Areas')), Tab(text: context.t('Categories'))],
          ),
        ),
        body: const TabBarView(children: [_AreasTab(), _CategoriesTab()]),
      ),
    );
  }
}

// ------------------------------------------------------------------ areas
class _AreasTab extends ConsumerWidget {
  const _AreasTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, [LifeArea? a]) async {
    final name = TextEditingController(text: a?.name ?? '');
    final desc = TextEditingController(text: a?.description ?? '');
    var color = a?.color.toUpperCase() ?? kPalette.first;
    var icon = a?.icon ?? 'growth';
    await showAdaptiveSheet(
      context,
      StatefulBuilder(
        builder: (ctx, setS) => EditorFrame(
          title: context.t(a == null ? 'New life area' : 'Edit life area'),
          onDelete: a == null ? null : () => _delete(ctx, ref, a),
          onSave: () async {
            if (name.text.trim().isEmpty) return;
            final n = ref.read(areasProvider.notifier);
            final data = {
              'name': name.text.trim(),
              'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
              'color': color,
              'icon': icon,
              if (a == null) 'sort_order': n.items.length,
            };
            final ok = await runSafe(ctx, () async {
              if (a == null) {
                await n.add(data);
              } else {
                await n.patch(a.id, data);
              }
            });
            if (ok && ctx.mounted) Navigator.pop(ctx);
          },
          children: [
            TextField(controller: name, autofocus: a == null, decoration: deco(ctx, context.t('Name'))),
            TextField(controller: desc, maxLines: 3, minLines: 1, decoration: deco(ctx, context.t('Description'))),
            FieldLabel(context.t('Icon')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in kAreaIcons.entries)
                ChoiceChip(
                  label: Icon(e.value, size: 20),
                  selected: icon == e.key,
                  onSelected: (_) => setS(() => icon = e.key),
                ),
            ]),
            FieldLabel(context.t('Color')),
            ColorPicker(value: color, onChanged: (c) => setS(() => color = c)),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, LifeArea a) async {
    final others = ref.read(areasProvider.notifier).items.where((x) => x.id != a.id).toList();
    final linked = [
      ...watchListRead(ref, goalsProvider).where((g) => g.areaId == a.id),
      ...watchListRead(ref, projectsProvider).where((p) => p.areaId == a.id),
      ...watchListRead(ref, habitsProvider).where((h) => h.areaId == a.id),
      ...watchListRead(ref, visionsProvider).where((v) => v.areaId == a.id),
    ].length;
    String? moveTo;
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text('${context.t('Delete')} "${a.name}"?'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(linked == 0
                  ? context.t('Nothing is linked to this area.')
                  : '$linked ${context.t('items are linked to this area. Move them to:')}'),
              if (linked > 0) ...[
                const SizedBox(height: 12),
                idDropdown<LifeArea>(
                  context: d,
                  label: context.t('Move to'),
                  value: moveTo,
                  items: others,
                  noneLabel: context.t('Leave without area'),
                  labelOf: (x) => x.name,
                  onChanged: (v) => setS(() => moveTo = v),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(context.t('Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(d, true),
              child: Text(context.t('Delete')),
            ),
          ],
        ),
      ),
    );
    if (go != true) return;
    final ok = await runSafe(context, () async {
      if (moveTo != null) {
        final db = ref.read(supabaseProvider);
        for (final t in ['goals', 'projects', 'habits', 'visions', 'time_entries']) {
          await db.from(t).update({'area_id': moveTo}).eq('area_id', a.id);
        }
      }
      await ref.read(areasProvider.notifier).remove(a.id);
      ref
        ..invalidate(goalsProvider)
        ..invalidate(projectsProvider)
        ..invalidate(habitsProvider)
        ..invalidate(visionsProvider)
        ..invalidate(timeEntriesProvider);
    });
    if (ok && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(areasProvider);
    final theme = Theme.of(context);
    return asyncGate(context, [async], () {
      final areas = [...async.value!]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final goals = watchList(ref, goalsProvider);
      final projects = watchList(ref, projectsProvider);
      final habits = watchList(ref, habitsProvider);
      final ws = ref.watch(weekStartProvider);
      final weekStart = startOfWeek(DateTime.now(), ws);
      final minutes = minutesByArea(watchList(ref, timeEntriesProvider), projects, weekStart, addDays(weekStart, 7));
      final maxMin = minutes.values.fold<int>(1, (a, b) => b > a ? b : a);

      return Stack(children: [
        ReorderableListView.builder(
          padding: EdgeInsets.fromLTRB(pagePad(context), 12, pagePad(context), 100),
          buildDefaultDragHandles: false,
          itemCount: areas.length,
          onReorder: (from, to) async {
            if (to > from) to--;
            final l = [...areas];
            final x = l.removeAt(from);
            l.insert(to, x);
            final n = ref.read(areasProvider.notifier);
            await runSafe(context, () async {
              for (var i = 0; i < l.length; i++) {
                if (l[i].sortOrder != i) await n.patch(l[i].id, {'sort_order': i});
              }
            });
          },
          itemBuilder: (c, i) {
            final a = areas[i];
            final color = hexColor(a.color);
            final m = minutes[a.id] ?? 0;
            return Padding(
              key: ValueKey(a.id),
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () => _edit(context, ref, a),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.drag_indicator_rounded)),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
                    child: Icon(areaIcon(a.icon), color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Wrap(spacing: 10, children: [
                        Text('${goals.where((g) => g.areaId == a.id).length} ${context.t('goals')}', style: theme.textTheme.bodySmall),
                        Text('${projects.where((p) => p.areaId == a.id && !p.isClosed).length} ${context.t('projects')}', style: theme.textTheme.bodySmall),
                        Text('${habits.where((h) => h.areaId == a.id && !h.archived).length} ${context.t('habits')}', style: theme.textTheme.bodySmall),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: ProgressBar(m / maxMin, color: color, height: 6)),
                        const SizedBox(width: 8),
                        Text('${fmtMinutes(context, m)} ${context.t('this week')}', style: theme.textTheme.labelSmall),
                      ]),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
        PositionedDirectional(
          end: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'area-fab',
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: Text(context.t('Life area')),
          ),
        ),
      ]);
    });
  }
}

List<T> watchListRead<T extends Entity>(WidgetRef ref, TableProvider<T> p) => ref.read(p).valueOrNull ?? <T>[];

// ------------------------------------------------------------------ categories
class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, String kind, [ItemCategory? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    var color = c?.color.toUpperCase() ?? kPalette[11];
    await showAdaptiveSheet(
      context,
      StatefulBuilder(
        builder: (ctx, setS) => EditorFrame(
          title: context.t(c == null ? 'New category' : 'Edit category'),
          onDelete: c == null ? null : () => _delete(ctx, ref, c),
          onSave: () async {
            if (name.text.trim().isEmpty) return;
            final n = ref.read(categoriesProvider.notifier);
            final ok = await runSafe(ctx, () async {
              if (c == null) {
                await n.add({'kind': kind, 'name': name.text.trim(), 'color': color, 'sort_order': n.items.length});
              } else {
                await n.patch(c.id, {'name': name.text.trim(), 'color': color});
              }
            });
            if (ok && ctx.mounted) Navigator.pop(ctx);
          },
          children: [
            TextField(controller: name, autofocus: c == null, decoration: deco(ctx, context.t('Name'))),
            FieldLabel(context.t('Color')),
            ColorPicker(value: color, onChanged: (v) => setS(() => color = v)),
          ],
        ),
      ),
    );
  }

  static const _tables = {'task': 'tasks', 'habit': 'habits', 'idea': 'ideas', 'shopping': 'shopping_items'};

  int _count(WidgetRef ref, ItemCategory c) => switch (c.kind) {
        'task' => watchListRead(ref, tasksProvider).where((x) => x.categoryId == c.id).length,
        'habit' => watchListRead(ref, habitsProvider).where((x) => x.categoryId == c.id).length,
        'idea' => watchListRead(ref, ideasProvider).where((x) => x.categoryId == c.id).length,
        _ => watchListRead(ref, shoppingProvider).where((x) => x.categoryId == c.id).length,
      };

  Future<void> _delete(BuildContext context, WidgetRef ref, ItemCategory c) async {
    final count = _count(ref, c);
    final others = ref.read(categoriesProvider.notifier).items.where((x) => x.kind == c.kind && x.id != c.id).toList();
    String? moveTo;
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text('${context.t('Delete')} "${c.name}"?'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(count == 0
                  ? context.t('No items use this category.')
                  : '$count ${context.t('items use this category. Move them to:')}'),
              if (count > 0) ...[
                const SizedBox(height: 12),
                idDropdown<ItemCategory>(
                  context: d,
                  label: context.t('Move to'),
                  value: moveTo,
                  items: others,
                  noneLabel: context.t('No category'),
                  labelOf: (x) => x.name,
                  onChanged: (v) => setS(() => moveTo = v),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(context.t('Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(d, true),
              child: Text(context.t('Delete')),
            ),
          ],
        ),
      ),
    );
    if (go != true) return;
    final ok = await runSafe(context, () async {
      if (moveTo != null) {
        await ref.read(supabaseProvider).from(_tables[c.kind]!).update({'category_id': moveTo}).eq('category_id', c.id);
      }
      await ref.read(categoriesProvider.notifier).remove(c.id);
      ref
        ..invalidate(tasksProvider)
        ..invalidate(habitsProvider)
        ..invalidate(ideasProvider)
        ..invalidate(shoppingProvider);
    });
    if (ok && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoriesProvider);
    final theme = Theme.of(context);
    return asyncGate(context, [async], () {
      final cats = async.value!;
      return ListView(
        padding: EdgeInsets.fromLTRB(pagePad(context), 12, pagePad(context), 100),
        children: [
          for (final k in kCategoryKinds.entries) ...[
            SectionHeader(
              context.t(k.value),
              action: TextButton.icon(
                onPressed: () => _edit(context, ref, k.key),
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.t('Add')),
              ),
            ),
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in cats.where((c) => c.kind == k.key))
                  ActionChip(
                    avatar: CircleAvatar(backgroundColor: hexColor(c.color), radius: 6),
                    label: Text('${c.name}  ·  ${_count(ref, c)}'),
                    onPressed: () => _edit(context, ref, k.key, c),
                  ),
                if (!cats.any((c) => c.kind == k.key))
                  Text(context.t('No categories yet.'), style: theme.textTheme.bodySmall),
              ]),
            ),
            const SizedBox(height: 18),
          ],
        ],
      );
    });
  }
}
