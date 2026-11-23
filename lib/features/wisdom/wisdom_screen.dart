import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

const kWisdomCategories = {
  'self': ('Self-Discovery', Icons.person_search_rounded, Color(0xFF8B5CF6)),
  'relationships': ('Relationships', Icons.favorite_rounded, Color(0xFFEC4899)),
  'people': ('People / Psychology', Icons.psychology_rounded, Color(0xFF0EA5E9)),
  'lessons': ('Life Lessons', Icons.auto_awesome_rounded, Color(0xFFF59E0B)),
  'career': ('Work / Career', Icons.work_rounded, Color(0xFF4F46E5)),
  'mindset': ('Mindset', Icons.self_improvement_rounded, Color(0xFF10B981)),
  'affirmations': ('Affirmations', Icons.wb_sunny_rounded, Color(0xFFF97316)),
};

(String, IconData, Color) wisdomCat(String key) => kWisdomCategories[key] ?? kWisdomCategories['mindset']!;

Future<void> showWisdomEditor(BuildContext context, {WisdomEntry? entry}) =>
    showAdaptiveSheet(context, WisdomEditor(entry: entry));

class WisdomScreen extends ConsumerStatefulWidget {
  const WisdomScreen({super.key});
  @override
  ConsumerState<WisdomScreen> createState() => _WisdomScreenState();
}

class _WisdomScreenState extends ConsumerState<WisdomScreen> {
  String _q = '';
  String? _cat;
  String? _tag;
  String? _collection;
  bool _favOnly = false;

  List<WisdomEntry> _filter(List<WisdomEntry> all) => all.where((w) {
        if (_cat != null && w.category != _cat) return false;
        if (_favOnly && !w.favorite) return false;
        if (_tag != null && !w.tags.contains(_tag)) return false;
        if (_collection != null && w.collection != _collection) return false;
        if (_q.isNotEmpty && !matchesQuery('${w.title ?? ''} ${w.content} ${w.tags.join(' ')}', _q)) return false;
        return true;
      }).toList();

  void _openReader(List<WisdomEntry> list, int index) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => WisdomReader(entries: list, initial: index),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(wisdomProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: lifeAppBar(context, context.t('Wisdom & Mindset'), subtitle: context.t('Your personal library of lessons and ideas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showWisdomEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('Entry')),
      ),
      body: asyncGate(context, [async], () {
        final all = async.value!;
        final list = _filter(all);
        final tags = {for (final w in all) ...w.tags}.toList()..sort();
        final collections = {for (final w in all) if (w.collection != null) w.collection!}.toList()..sort();
        final daily = all.isEmpty ? null : all[today().difference(DateTime(2020)).inDays.abs() % all.length];

        return ListView(
          padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 100),
          children: [
            if (daily != null) ...[
              _DailyPick(entry: daily, onOpen: () => _openReader(all, all.indexOf(daily))),
              const SizedBox(height: 16),
            ],
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: deco(context, context.t('Search'), icon: Icons.search_rounded),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              FilterChip(
                avatar: const Icon(Icons.star_rounded, size: 18),
                label: Text(context.t('Favorites')),
                selected: _favOnly,
                onSelected: (v) => setState(() => _favOnly = v),
              ),
              if (collections.isNotEmpty)
                PopupMenuButton<String>(
                  onSelected: (v) => setState(() => _collection = v.isEmpty ? null : v),
                  itemBuilder: (c) => [
                    PopupMenuItem(value: '', child: Text(context.t('All collections'))),
                    for (final c in collections) PopupMenuItem(value: c, child: Text(c)),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.collections_bookmark_outlined, size: 18),
                    label: Text(_collection ?? context.t('Collections')),
                  ),
                ),
              FilledButton.tonalIcon(
                onPressed: list.isEmpty ? null : () => _openReader(list, 0),
                icon: const Icon(Icons.menu_book_rounded),
                label: Text(context.t('Reader')),
              ),
              OutlinedButton.icon(
                onPressed: list.isEmpty ? null : () => _openReader([...list]..shuffle(), 0),
                icon: const Icon(Icons.shuffle_rounded),
                label: Text(context.t('Shuffle')),
              ),
            ]),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ChoiceChip(label: Text(context.t('All')), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
                for (final e in kWisdomCategories.entries)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: ChoiceChip(
                      avatar: Icon(e.value.$2, size: 16, color: e.value.$3),
                      label: Text(context.t(e.value.$1)),
                      selected: _cat == e.key,
                      onSelected: (_) => setState(() => _cat = _cat == e.key ? null : e.key),
                    ),
                  ),
              ]),
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in tags)
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('#$t'),
                    selected: _tag == t,
                    onSelected: (_) => setState(() => _tag = _tag == t ? null : t),
                  ),
              ]),
            ],
            const SizedBox(height: 16),
            if (list.isEmpty)
              EmptyState(
                icon: Icons.auto_stories_outlined,
                title: context.t('Nothing here yet'),
                subtitle: context.t('Save lessons, insights about people, rules to remember and affirmations.'),
              )
            else
              LayoutBuilder(builder: (c, box) {
                final cols = (box.maxWidth / 320).floor().clamp(1, 4);
                final columns = List.generate(cols, (_) => <Widget>[]);
                for (var i = 0; i < list.length; i++) {
                  columns[i % cols].add(Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _WisdomCard(entry: list[i], onRead: () => _openReader(list, i)),
                  ));
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var k = 0; k < cols; k++) ...[
                    if (k > 0) const SizedBox(width: 12),
                    Expanded(child: Column(children: columns[k])),
                  ],
                ]);
              }),
            Text('${list.length} / ${all.length}', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        );
      }, onRetry: () => ref.invalidate(wisdomProvider)),
    );
  }
}

class _DailyPick extends StatelessWidget {
  const _DailyPick({required this.entry, required this.onOpen});
  final WisdomEntry entry;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final c = wisdomCat(entry.category);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: [c.$3, Color.lerp(c.$3, Colors.black, .25)!]),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.wb_twilight_rounded, color: Colors.white70, size: 18),
            const SizedBox(width: 6),
            Text(context.t('Daily pick'),
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: .5)),
          ]),
          const SizedBox(height: 10),
          if (entry.title != null)
            Text(entry.title!, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
          Text(entry.content,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.6)),
        ]),
      ),
    );
  }
}

class _WisdomCard extends ConsumerWidget {
  const _WisdomCard({required this.entry, required this.onRead});
  final WisdomEntry entry;
  final VoidCallback onRead;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = wisdomCat(entry.category);
    return AppCard(
      onTap: onRead,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Pill(context.t(c.$1), icon: c.$2, color: c.$3),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(entry.favorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: entry.favorite ? Colors.amber : null),
            onPressed: () =>
                runSafe(context, () => ref.read(wisdomProvider.notifier).patch(entry.id, {'favorite': !entry.favorite})),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => showWisdomEditor(context, entry: entry),
          ),
        ]),
        if (entry.title != null) ...[
          const SizedBox(height: 6),
          Text(entry.title!, style: theme.textTheme.titleMedium),
        ],
        const SizedBox(height: 6),
        Text(entry.content, maxLines: 8, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
        if (entry.tags.isNotEmpty || entry.collection != null) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (entry.collection != null) Pill(entry.collection!, icon: Icons.collections_bookmark_outlined),
            for (final t in entry.tags) Pill('#$t'),
          ]),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------ reader
class WisdomReader extends ConsumerStatefulWidget {
  const WisdomReader({super.key, required this.entries, required this.initial});
  final List<WisdomEntry> entries;
  final int initial;
  @override
  ConsumerState<WisdomReader> createState() => _WisdomReaderState();
}

class _WisdomReaderState extends ConsumerState<WisdomReader> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  Timer? _timer;
  int _autoplay = 0; // seconds; 0 = off

  static const _options = [0, 10, 30, 60, 180, 300, 600, 1200, 1800];

  void _go(int dir) {
    final n = widget.entries.length;
    final next = (_index + dir) % n;
    _pc.animateToPage(next < 0 ? next + n : next, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  void _setAutoplay(int s) {
    _timer?.cancel();
    setState(() => _autoplay = s);
    if (s > 0) _timer = Timer.periodic(Duration(seconds: s), (_) => _go(1));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  String _label(int s) {
    if (s == 0) return context.t('Off');
    return s < 60 ? '${s}s' : '${s ~/ 60} ${context.t('min')}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final live = watchList(ref, wisdomProvider);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(context.isAr ? -1 : 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(context.isAr ? 1 : -1),
        const SingleActivator(LogicalKeyboardKey.space): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: dark ? const Color(0xFF0B0C10) : const Color(0xFFFBFAF7),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            title: Text('${_index + 1} / ${entries.length}'),
            actions: [
              PopupMenuButton<int>(
                tooltip: context.t('Autoplay'),
                initialValue: _autoplay,
                onSelected: _setAutoplay,
                itemBuilder: (c) => [for (final o in _options) PopupMenuItem(value: o, child: Text(_label(o)))],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Icon(_autoplay > 0 ? Icons.pause_circle_outline : Icons.play_circle_outline),
                    const SizedBox(width: 4),
                    Text(_label(_autoplay)),
                  ]),
                ),
              ),
            ],
          ),
          body: PageView.builder(
            controller: _pc,
            itemCount: entries.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (c, i) {
              final e = live.where((x) => x.id == entries[i].id).firstOrNull ?? entries[i];
              final cat = wisdomCat(e.category);
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(children: [
                      Icon(cat.$2, color: cat.$3, size: 36),
                      const SizedBox(height: 8),
                      Text(context.t(cat.$1), style: TextStyle(color: cat.$3, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 24),
                      if (e.title != null) ...[
                        Text(e.title!, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 18),
                      ],
                      SelectableText(
                        e.content,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w400, height: 1.8),
                      ),
                      const SizedBox(height: 24),
                      IconButton(
                        iconSize: 30,
                        icon: Icon(e.favorite ? Icons.star_rounded : Icons.star_border_rounded,
                            color: e.favorite ? Colors.amber : null),
                        onPressed: () =>
                            runSafe(context, () => ref.read(wisdomProvider.notifier).patch(e.id, {'favorite': !e.favorite})),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton.filledTonal(onPressed: () => _go(-1), icon: const Icon(Icons.chevron_left_rounded)),
                const SizedBox(width: 16),
                IconButton.filledTonal(
                  onPressed: () {
                    final r = math.Random().nextInt(entries.length);
                    _pc.jumpToPage(r);
                  },
                  icon: const Icon(Icons.shuffle_rounded),
                ),
                const SizedBox(width: 16),
                IconButton.filledTonal(onPressed: () => _go(1), icon: const Icon(Icons.chevron_right_rounded)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ editor
class WisdomEditor extends ConsumerStatefulWidget {
  const WisdomEditor({super.key, this.entry});
  final WisdomEntry? entry;
  @override
  ConsumerState<WisdomEditor> createState() => _WisdomEditorState();
}

class _WisdomEditorState extends ConsumerState<WisdomEditor> {
  late final TextEditingController _title, _content, _tags, _collection;
  String _cat = 'mindset';
  bool _fav = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _title = TextEditingController(text: e?.title ?? '');
    _content = TextEditingController(text: e?.content ?? '');
    _tags = TextEditingController(text: e?.tags.join(', ') ?? '');
    _collection = TextEditingController(text: e?.collection ?? '');
    _cat = e?.category ?? 'mindset';
    _fav = e?.favorite ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _tags.dispose();
    _collection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final collections = {for (final w in watchList(ref, wisdomProvider)) if (w.collection != null) w.collection!};
    return EditorFrame(
      title: context.t(e == null ? 'New entry' : 'Edit entry'),
      saving: _saving,
      onDelete: e == null
          ? null
          : () async {
              if (!await confirmDialog(context, context.t('Delete this entry?'))) return;
              final ok = await runSafe(context, () => ref.read(wisdomProvider.notifier).remove(e.id));
              if (ok && mounted) Navigator.pop(context);
            },
      onSave: () async {
        if (_content.text.trim().isEmpty) {
          toast(context, context.t('Content is required'), error: true);
          return;
        }
        setState(() => _saving = true);
        final data = {
          'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
          'content': _content.text.trim(),
          'category': _cat,
          'tags': splitTags(_tags.text),
          'collection': _collection.text.trim().isEmpty ? null : _collection.text.trim(),
          'favorite': _fav,
        };
        final n = ref.read(wisdomProvider.notifier);
        final ok = await runSafe(context, () async {
          if (e == null) {
            await n.add(data);
          } else {
            await n.patch(e.id, data);
          }
        });
        if (!mounted) return;
        setState(() => _saving = false);
        if (ok) Navigator.pop(context);
      },
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in kWisdomCategories.entries)
            ChoiceChip(
              avatar: Icon(c.value.$2, size: 16, color: c.value.$3),
              label: Text(context.t(c.value.$1)),
              selected: _cat == c.key,
              onSelected: (_) => setState(() => _cat = c.key),
            ),
        ]),
        TextField(controller: _title, decoration: deco(context, context.t('Title (optional)'))),
        TextField(
          controller: _content,
          minLines: 5,
          maxLines: 16,
          maxLength: 5000,
          autofocus: e == null,
          decoration: deco(context, context.t('Write the lesson, insight or affirmation')),
        ),
        TextField(controller: _tags, decoration: deco(context, context.t('Tags (comma separated)'), icon: Icons.tag_rounded)),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _collection.text),
          optionsBuilder: (v) => collections.where((c) => matchesQuery(c, v.text)),
          onSelected: (v) => _collection.text = v,
          fieldViewBuilder: (ctx, ctrl, focus, submit) => TextField(
            controller: ctrl,
            focusNode: focus,
            onChanged: (v) => _collection.text = v,
            decoration: deco(context, context.t('Collection'), icon: Icons.collections_bookmark_outlined),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.star_rounded, color: Colors.amber),
          title: Text(context.t('Favorite')),
          value: _fav,
          onChanged: (v) => setState(() => _fav = v),
        ),
      ],
    );
  }
}
