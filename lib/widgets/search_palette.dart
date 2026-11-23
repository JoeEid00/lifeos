import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../features/goals/goals_screen.dart';
import '../features/habits/habits_screen.dart';
import '../features/ideas/ideas_screen.dart';
import '../features/journal/journal_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/shopping/shopping_screen.dart';
import '../features/tasks/task_editor.dart';
import '../features/wisdom/wisdom_screen.dart';
import '../router.dart';
import 'common.dart';

Future<void> openSearch(BuildContext context) =>
    showDialog(context: context, builder: (_) => const SearchPalette());

class _Result {
  _Result(this.kind, this.icon, this.title, this.preview, this.open);
  final String kind;
  final IconData icon;
  final String title;
  final String preview;
  final void Function(BuildContext ctx, WidgetRef ref) open;
}

class SearchPalette extends ConsumerStatefulWidget {
  const SearchPalette({super.key});
  @override
  ConsumerState<SearchPalette> createState() => _SearchPaletteState();
}

class _SearchPaletteState extends ConsumerState<SearchPalette> {
  final _q = TextEditingController();
  int _sel = 0;

  String _preview(String text, String q) {
    final t = text.replaceAll('\n', ' ').trim();
    if (t.length <= 90) return t;
    final words = normalizeText(q).split(' ').where((w) => w.isNotEmpty);
    final n = normalizeText(t);
    var i = words.isEmpty ? -1 : n.indexOf(words.first);
    if (i < 0) i = 0;
    final s = (i - 30).clamp(0, t.length);
    final e = (s + 90).clamp(0, t.length);
    return '${s > 0 ? '…' : ''}${t.substring(s, e)}${e < t.length ? '…' : ''}';
  }

  List<_Result> _search(String q) {
    if (q.trim().isEmpty) return [];
    final out = <_Result>[];
    void go(String path) => ref.read(routerProvider).go(path);

    for (final t in watchList(ref, tasksProvider)) {
      final hay = '${t.title} ${t.notes ?? ''} ${t.steps.map((s) => s.title).join(' ')}';
      if (matchesQuery(hay, q)) {
        out.add(_Result('Tasks', Icons.check_circle_outline, t.title, _preview(t.notes ?? '', q),
            (c, r) => showTaskEditor(c, task: t)));
      }
    }
    for (final p in watchList(ref, projectsProvider)) {
      if (matchesQuery('${p.name} ${p.description ?? ''}', q)) {
        out.add(_Result('Projects', Icons.folder_open_rounded, p.name, _preview(p.description ?? '', q),
            (c, r) => go('/projects/${p.id}')));
      }
    }
    for (final g in watchList(ref, goalsProvider)) {
      if (matchesQuery('${g.title} ${g.description ?? ''}', q)) {
        out.add(_Result('Goals', Icons.flag_outlined, g.title, _preview(g.description ?? '', q), (c, r) {
          go('/goals');
          showGoalEditor(c, goal: g);
        }));
      }
    }
    for (final v in watchList(ref, visionsProvider)) {
      if (matchesQuery('${v.title} ${v.description ?? ''}', q)) {
        out.add(_Result('Vision', Icons.visibility_outlined, v.title, _preview(v.description ?? '', q), (c, r) {
          go('/goals');
          showVisionEditor(c, vision: v);
        }));
      }
    }
    for (final i in watchList(ref, ideasProvider)) {
      final hay = '${i.title} ${i.content ?? ''} ${i.updates.map((u) => u.text).join(' ')}';
      if (matchesQuery(hay, q)) {
        out.add(_Result('Ideas', Icons.lightbulb_outline, i.title, _preview(i.content ?? '', q), (c, r) {
          go('/ideas');
          showIdeaEditor(c, idea: i);
        }));
      }
    }
    for (final h in watchList(ref, habitsProvider)) {
      if (matchesQuery('${h.title} ${h.description ?? ''} ${h.steps.join(' ')}', q)) {
        out.add(_Result('Habits', Icons.repeat_rounded, h.title, _preview(h.description ?? '', q), (c, r) {
          go('/habits');
          showHabitEditor(c, habit: h);
        }));
      }
    }
    for (final w in watchList(ref, wisdomProvider)) {
      if (matchesQuery('${w.title ?? ''} ${w.content} ${w.tags.join(' ')} ${w.collection ?? ''}', q)) {
        out.add(_Result('Wisdom', Icons.auto_stories_outlined, w.title ?? w.content.split('\n').first,
            _preview(w.content, q), (c, r) {
          go('/wisdom');
          showWisdomEditor(c, entry: w);
        }));
      }
    }
    for (final j in watchList(ref, journalProvider)) {
      if (matchesQuery('${j.content} ${j.tags.join(' ')}', q)) {
        out.add(_Result('Journal', Icons.edit_note_rounded, fmtDate(context, j.date, 'EEEE d MMM y'),
            _preview(j.content, q), (c, r) {
          go('/journal');
          showJournalEditor(c, date: j.date);
        }));
      }
    }
    for (final s in watchList(ref, shoppingProvider)) {
      if (matchesQuery('${s.name} ${s.notes ?? ''}', q)) {
        out.add(_Result('Shopping', Icons.shopping_bag_outlined, s.name, _preview(s.notes ?? '', q), (c, r) {
          go('/shopping');
          showShoppingEditor(c, item: s);
        }));
      }
    }
    return out.take(60).toList();
  }

  void _open(_Result r) {
    Navigator.pop(context);
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null) r.open(ctx, ref);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _search(_q.text);
    if (_sel >= results.length) _sel = 0;
    return Dialog(
      alignment: const Alignment(0, -0.6),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: CallbackShortcutsField(
              controller: _q,
              hint: context.t('Search tasks, projects, goals, ideas, notes…'),
              onChanged: (_) => setState(() => _sel = 0),
              onDown: () => setState(() => _sel = results.isEmpty ? 0 : (_sel + 1) % results.length),
              onUp: () => setState(() => _sel = results.isEmpty ? 0 : (_sel - 1 + results.length) % results.length),
              onEnter: () {
                if (results.isNotEmpty) _open(results[_sel]);
              },
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: _q.text.trim().isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(context.t('Type to search everything in LifeOS'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  )
                : results.isEmpty
                    ? Padding(padding: const EdgeInsets.all(28), child: Text(context.t('No results')))
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: results.length,
                        itemBuilder: (c, i) {
                          final r = results[i];
                          return ListTile(
                            selected: i == _sel,
                            selectedTileColor: theme.colorScheme.primary.withValues(alpha: .08),
                            leading: Icon(r.icon, color: theme.colorScheme.primary),
                            title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: r.preview.isEmpty
                                ? null
                                : Text(r.preview, maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: Pill(context.t(r.kind)),
                            onTap: () => _open(r),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

/// Search text field that also handles ↑ ↓ Enter.
class CallbackShortcutsField extends StatelessWidget {
  const CallbackShortcutsField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onUp,
    required this.onDown,
    required this.onEnter,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onUp, onDown, onEnter;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): onDown,
        const SingleActivator(LogicalKeyboardKey.arrowUp): onUp,
      },
      child: TextField(
        controller: controller,
        autofocus: true,
        onChanged: onChanged,
        onSubmitted: (_) => onEnter(),
        decoration: deco(context, hint, icon: Icons.search_rounded),
      ),
    );
  }
}
