import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

const kMoods = {1: ('😞', 'Awful'), 2: ('😕', 'Bad'), 3: ('😐', 'Okay'), 4: ('🙂', 'Good'), 5: ('😄', 'Great')};
const kMoodColors = {1: Color(0xFFEF4444), 2: Color(0xFFF97316), 3: Color(0xFFF59E0B), 4: Color(0xFF84CC16), 5: Color(0xFF10B981)};

Future<void> showJournalEditor(BuildContext context, {DateTime? date}) =>
    showAdaptiveSheet(context, JournalEditor(date: date ?? today()));

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});
  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(journalProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: lifeAppBar(context, context.t('Journal')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showJournalEditor(context),
        icon: const Icon(Icons.edit_rounded),
        label: Text(context.t('Write today')),
      ),
      body: asyncGate(context, [async], () {
        final all = async.value!;
        final t0 = today();
        final days = [for (var i = 6; i >= 0; i--) addDays(t0, -i)];
        int? moodOn(DateTime d) => all.where((j) => sameDay(j.date, d)).firstOrNull?.mood;
        final moods = days.map(moodOn).whereType<int>().toList();
        final avg = moods.isEmpty ? null : moods.reduce((a, b) => a + b) / moods.length;
        final list = all.where((j) => _q.isEmpty || matchesQuery('${j.content} ${j.tags.join(' ')}', _q)).toList();
        final todayEntry = all.where((j) => sameDay(j.date, t0)).firstOrNull;

        return ListView(
          padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 100),
          children: [
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(context.t('Mood — last 7 days'), style: theme.textTheme.titleMedium)),
                  if (avg != null)
                    Pill('${context.t('Average')} ${avg.toStringAsFixed(1)} ${kMoods[avg.round()]!.$1}',
                        color: kMoodColors[avg.round()]),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  height: 150,
                  child: moods.isEmpty
                      ? Center(child: Text(context.t('No mood recorded this week.')))
                      : LineChart(LineChartData(
                          minY: 0.5,
                          maxY: 5.5,
                          minX: 0,
                          maxX: 6,
                          gridData: FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                interval: 1,
                                getTitlesWidget: (v, m) => v % 1 == 0 && v >= 1 && v <= 5
                                    ? Text(kMoods[v.toInt()]!.$1, style: const TextStyle(fontSize: 14))
                                    : const SizedBox.shrink(),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1,
                                reservedSize: 24,
                                getTitlesWidget: (v, m) => Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(fmtDate(context, days[v.toInt().clamp(0, 6)], 'E'), style: theme.textTheme.labelSmall),
                                ),
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              isCurved: true,
                              barWidth: 3,
                              color: theme.colorScheme.primary,
                              dotData: FlDotData(show: true),
                              belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withValues(alpha: .08)),
                              spots: [
                                for (var i = 0; i < 7; i++)
                                  if (moodOn(days[i]) != null) FlSpot(i.toDouble(), moodOn(days[i])!.toDouble()),
                              ],
                            ),
                          ],
                        )),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            if (todayEntry == null)
              AppCard(
                onTap: () => showJournalEditor(context),
                child: Row(children: [
                  Icon(Icons.wb_sunny_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.t('How was your day? Tap to write today\'s entry.'))),
                ]),
              ),
            const SizedBox(height: 14),
            TextField(
              decoration: deco(context, context.t('Search journal'), icon: Icons.search_rounded),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 14),
            for (final j in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => showJournalEditor(context, date: j.date),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Column(children: [
                      Text('${j.date.day}', style: theme.textTheme.headlineSmall),
                      Text(fmtDate(context, j.date, 'MMM'), style: theme.textTheme.labelSmall),
                      const SizedBox(height: 6),
                      if (j.mood != null) Text(kMoods[j.mood]!.$1, style: const TextStyle(fontSize: 22)),
                    ]),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(fmtDate(context, j.date, 'EEEE'), style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(j.content.isEmpty ? '—' : j.content, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
                        if (j.tags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, children: [for (final t in j.tags) Pill('#$t')]),
                        ],
                      ]),
                    ),
                  ]),
                ),
              ),
          ],
        );
      }, onRetry: () => ref.invalidate(journalProvider)),
    );
  }
}

class JournalEditor extends ConsumerStatefulWidget {
  const JournalEditor({super.key, required this.date});
  final DateTime date;
  @override
  ConsumerState<JournalEditor> createState() => _JournalEditorState();
}

class _JournalEditorState extends ConsumerState<JournalEditor> {
  late DateTime _date = widget.date;
  late final TextEditingController _text, _tags;
  int? _mood; // no default: never assume a mood
  bool _saving = false;
  String? _error;

  JournalEntry? _existing(DateTime d) => watchList(ref, journalProvider).where((j) => sameDay(j.date, d)).firstOrNull;

  @override
  void initState() {
    super.initState();
    final e = ref.read(journalProvider).valueOrNull?.where((j) => sameDay(j.date, widget.date)).firstOrNull;
    _text = TextEditingController(text: e?.content ?? '');
    _tags = TextEditingController(text: e?.tags.join(', ') ?? '');
    _mood = e?.mood;
  }

  @override
  void dispose() {
    _text.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _loadDate(DateTime d) {
    final e = readList(ref, journalProvider).where((j) => sameDay(j.date, d)).firstOrNull;
    setState(() {
      _date = d;
      _text.text = e?.content ?? '';
      _tags.text = e?.tags.join(', ') ?? '';
      _mood = e?.mood;
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = _existing(_date);
    return EditorFrame(
      title: fmtDate(context, _date, 'EEEE d MMMM y'),
      saving: _saving,
      onDelete: e == null
          ? null
          : () async {
              if (!await confirmDialog(context, context.t('Delete this entry?'))) return;
              final ok = await runSafe(context, () => ref.read(journalProvider.notifier).remove(e.id));
              if (ok && mounted) Navigator.pop(context);
            },
      onSave: () async {
        setState(() {
          _saving = true;
          _error = null;
        });
        final data = {'date': ymd(_date), 'content': _text.text, 'mood': _mood, 'tags': splitTags(_tags.text)};
        final n = ref.read(journalProvider.notifier);
        try {
          if (e == null) {
            await n.add(data);
          } else {
            await n.patch(e.id, data);
          }
          if (mounted) Navigator.pop(context);
        } catch (err) {
          // Keep the text in the editor and show the error.
          if (mounted) setState(() => _error = '${context.t('Save failed')}: $err');
        } finally {
          if (mounted) setState(() => _saving = false);
        }
      },
      children: [
        DateField(label: context.t('Date'), value: _date, allowNone: false, onChanged: (d) => _loadDate(d ?? _date)),
        FieldLabel(context.t('Mood (optional)')),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          for (final m in kMoods.entries)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _mood = _mood == m.key ? null : m.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _mood == m.key ? kMoodColors[m.key]!.withValues(alpha: .18) : null,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _mood == m.key ? kMoodColors[m.key]! : Colors.transparent, width: 2),
                ),
                child: Column(children: [
                  Text(m.value.$1, style: const TextStyle(fontSize: 28)),
                  Text(context.t(m.value.$2), style: const TextStyle(fontSize: 11)),
                ]),
              ),
            ),
        ]),
        TextField(
          controller: _text,
          minLines: 8,
          maxLines: 20,
          autofocus: e == null,
          decoration: deco(context, context.t('What happened? How did you feel? What did you learn?')),
        ),
        TextField(controller: _tags, decoration: deco(context, context.t('Tags (comma separated)'), icon: Icons.tag_rounded)),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    );
  }
}
