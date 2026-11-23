import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../core/utils.dart';
import '../../data/derived.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

class TimeScreen extends ConsumerWidget {
  const TimeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(timeEntriesProvider);
    return Scaffold(
      appBar: lifeAppBar(context, context.t('Time Tracking'), subtitle: context.t('Where does my time go?')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAdaptiveSheet(context, const _EntryEditor()),
        icon: const Icon(Icons.more_time_rounded),
        label: Text(context.t('Manual entry')),
      ),
      body: asyncGate(context, [async], () {
        final entries = async.value!;
        final projects = watchList(ref, projectsProvider);
        final areas = watchList(ref, areasProvider);
        final ws = ref.watch(weekStartProvider);
        final t0 = today();
        final wStart = startOfWeek(t0, ws);
        final todayMin = minutesBetween(entries, t0, addDays(t0, 1));
        final weekMin = minutesBetween(entries, wStart, addDays(wStart, 7));
        final elapsedDays = t0.difference(wStart).inDays + 1;
        final byArea = minutesByArea(entries, projects, wStart, addDays(wStart, 7));
        final running = entries.where((e) => e.running).firstOrNull;
        final theme = Theme.of(context);

        final days = [for (var i = 6; i >= 0; i--) addDays(t0, -i)];
        final perDay = [for (final d in days) minutesBetween(entries, d, addDays(d, 1))];
        final maxDay = perDay.fold<int>(60, (a, b) => b > a ? b : a);

        final valid = entries.where((e) => e.isValid).toList();
        final grouped = <DateTime, List<TimeEntry>>{};
        for (final e in valid.take(150)) {
          grouped.putIfAbsent(dateOnly(e.startedAt), () => []).add(e);
        }

        final wide = MediaQuery.sizeOf(context).width >= 900;

        final chart = AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(context.t('Last 7 days'), icon: Icons.bar_chart_rounded),
            SizedBox(
              height: 180,
              child: BarChart(BarChartData(
                maxY: maxDay / 60 * 1.15,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(color: theme.colorScheme.outlineVariant.withValues(alpha: .4), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, m) => Text('${v.toStringAsFixed(v < 2 ? 1 : 0)}h', style: theme.textTheme.labelSmall),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, m) => Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(fmtDate(context, days[v.toInt()], 'E'), style: theme.textTheme.labelSmall),
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < 7; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: perDay[i] / 60,
                        width: 22,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        color: i == 6 ? theme.colorScheme.primary : theme.colorScheme.primary.withValues(alpha: .45),
                      ),
                    ]),
                ],
              )),
            ),
          ]),
        );

        final areaCard = AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(context.t('This week by life area'), icon: Icons.donut_large_rounded),
            if (byArea.isEmpty)
              Padding(padding: const EdgeInsets.all(12), child: Text(context.t('No tracked time this week.')))
            else
              SizedBox(
                height: 180,
                child: Row(children: [
                  Expanded(
                    child: PieChart(PieChartData(
                      centerSpaceRadius: 42,
                      sectionsSpace: 2,
                      sections: [
                        for (final e in byArea.entries)
                          PieChartSectionData(
                            value: e.value.toDouble(),
                            color: hexColor(areas.where((a) => a.id == e.key).firstOrNull?.color, Colors.grey),
                            title: '',
                            radius: 36,
                          ),
                      ],
                    )),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ListView(children: [
                      for (final e in byArea.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            CircleAvatar(radius: 5, backgroundColor: hexColor(areas.where((a) => a.id == e.key).firstOrNull?.color, Colors.grey)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(areas.where((a) => a.id == e.key).firstOrNull?.name ?? context.t('Unassigned'),
                                  overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                            ),
                            Text(fmtMinutes(context, e.value), style: theme.textTheme.labelMedium),
                          ]),
                        ),
                    ]),
                  ),
                ]),
              ),
          ]),
        );

        return ListView(
          padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 100),
          children: [
            _TimerCard(running: running),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (c, box) {
              final w = box.maxWidth >= 720 ? (box.maxWidth - 24) / 3 : box.maxWidth;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: w, child: StatCard(icon: Icons.today_rounded, label: context.t('Today'), value: fmtMinutes(context, todayMin))),
                SizedBox(width: w, child: StatCard(icon: Icons.date_range_rounded, label: context.t('This week'), value: fmtMinutes(context, weekMin), color: const Color(0xFF8B5CF6))),
                SizedBox(width: w, child: StatCard(icon: Icons.av_timer_rounded, label: context.t('Daily average (week)'), value: fmtMinutes(context, weekMin ~/ elapsedDays), color: const Color(0xFF10B981))),
              ]);
            }),
            const SizedBox(height: 14),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: chart),
                const SizedBox(width: 14),
                Expanded(child: areaCard),
              ])
            else ...[
              chart,
              const SizedBox(height: 14),
              areaCard,
            ],
            const SizedBox(height: 18),
            SectionHeader(context.t('Sessions'), icon: Icons.history_rounded),
            if (grouped.isEmpty) Text(context.t('No sessions yet. Start the timer above.')),
            for (final g in grouped.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                child: Row(children: [
                  Text(fmtRelDate(context, g.key), style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(fmtMinutes(context, g.value.fold(0, (s, e) => s + e.minutes)), style: theme.textTheme.labelLarge),
                ]),
              ),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  for (final e in g.value)
                    Builder(builder: (_) {
                      final p = projects.where((p) => p.id == e.projectId).firstOrNull;
                      final a = areas.where((a) => a.id == entryAreaId(e, projects)).firstOrNull;
                      return ListTile(
                        dense: true,
                        leading: Container(width: 4, height: 30, color: hexColor(a?.color, Colors.grey)),
                        title: Text(e.description ?? p?.name ?? context.t('Untitled session')),
                        subtitle: Text([
                          '${hm(e.startedAt.hour * 60 + e.startedAt.minute)} – ${hm(e.endedAt!.hour * 60 + e.endedAt!.minute)}',
                          if (p != null) p.name,
                          if (a != null) a.name,
                        ].join('  ·  ')),
                        trailing: Text(fmtMinutes(context, e.minutes), style: const TextStyle(fontWeight: FontWeight.w700)),
                        onTap: () => showAdaptiveSheet(context, _EntryEditor(entry: e)),
                      );
                    }),
                ]),
              ),
            ],
          ],
        );
      }, onRetry: () => ref.invalidate(timeEntriesProvider)),
    );
  }
}

class _TimerCard extends ConsumerStatefulWidget {
  const _TimerCard({required this.running});
  final TimeEntry? running;
  @override
  ConsumerState<_TimerCard> createState() => _TimerCardState();
}

class _TimerCardState extends ConsumerState<_TimerCard> {
  final _desc = TextEditingController();
  String? _projectId, _areaId;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.running != null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _desc.dispose();
    super.dispose();
  }

  String _elapsed(DateTime start) {
    final d = DateTime.now().difference(start);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.running;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final n = ref.read(timeEntriesProvider.notifier);
    if (r != null) {
      final p = watchList(ref, projectsProvider).where((p) => p.id == r.projectId).firstOrNull;
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: [cs.primary, const Color(0xFF7C3AED)]),
        ),
        child: Row(children: [
          const Icon(Icons.timer_rounded, color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.description ?? p?.name ?? context.t('Tracking…'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              Text(_elapsed(r.startedAt),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: cs.primary),
            onPressed: () => runSafe(context, () => n.patch(r.id, {'ended_at': isoUtc(DateTime.now())})),
            icon: const Icon(Icons.stop_rounded),
            label: Text(context.t('Stop')),
          ),
        ]),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final fields = [
      TextField(controller: _desc, decoration: deco(context, context.t('What are you working on?'), icon: Icons.edit_outlined)),
      idDropdown<Project>(
        context: context,
        label: context.t('Project'),
        value: _projectId,
        items: watchList(ref, projectsProvider).where((p) => !p.isClosed).toList(),
        labelOf: (p) => p.name,
        onChanged: (v) => setState(() => _projectId = v),
      ),
      idDropdown<LifeArea>(
        context: context,
        label: context.t('Life area'),
        value: _areaId,
        items: watchList(ref, areasProvider),
        labelOf: (a) => a.name,
        onChanged: (v) => setState(() => _areaId = v),
      ),
    ];
    final start = FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size(130, 50)),
      onPressed: () => runSafe(context, () async {
        await n.add({
          'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          'project_id': _projectId,
          'area_id': _areaId,
          'started_at': isoUtc(DateTime.now()),
        });
        _desc.clear();
      }),
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(context.t('Start')),
    );
    return AppCard(
      child: wide
          ? Row(children: [
              Expanded(flex: 3, child: fields[0]),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: fields[1]),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: fields[2]),
              const SizedBox(width: 10),
              start,
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              fields[0],
              const SizedBox(height: 10),
              fields[1],
              const SizedBox(height: 10),
              fields[2],
              const SizedBox(height: 12),
              start,
            ]),
    );
  }
}

class _EntryEditor extends ConsumerStatefulWidget {
  const _EntryEditor({this.entry});
  final TimeEntry? entry;
  @override
  ConsumerState<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends ConsumerState<_EntryEditor> {
  late final TextEditingController _desc;
  late DateTime _day;
  late int _start, _end;
  String? _projectId, _areaId;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _desc = TextEditingController(text: e?.description ?? '');
    final now = DateTime.now();
    _day = dateOnly(e?.startedAt ?? now);
    _start = e == null ? (now.hour * 60 - 60).clamp(0, 1439) : e.startedAt.hour * 60 + e.startedAt.minute;
    _end = e?.endedAt == null ? (now.hour * 60 + now.minute) : e!.endedAt!.hour * 60 + e.endedAt!.minute;
    _projectId = e?.projectId;
    _areaId = e?.areaId;
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final m = start ? _start : _end;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (t == null) return;
    setState(() => start ? _start = t.hour * 60 + t.minute : _end = t.hour * 60 + t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final n = ref.read(timeEntriesProvider.notifier);
    final dur = _end > _start ? _end - _start : _end + 1440 - _start;
    return EditorFrame(
      title: context.t(e == null ? 'Manual entry' : 'Edit session'),
      onDelete: e == null
          ? null
          : () async {
              final ok = await runSafe(context, () => n.remove(e.id));
              if (ok && mounted) Navigator.pop(context);
            },
      onSave: () async {
        final s = DateTime(_day.year, _day.month, _day.day, _start ~/ 60, _start % 60);
        final end = s.add(Duration(minutes: dur));
        final data = {
          'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          'project_id': _projectId,
          'area_id': _areaId,
          'started_at': isoUtc(s),
          'ended_at': isoUtc(end),
        };
        final ok = await runSafe(context, () async {
          if (e == null) {
            await n.add(data);
          } else {
            await n.patch(e.id, data);
          }
        });
        if (ok && mounted) Navigator.pop(context);
      },
      children: [
        TextField(controller: _desc, decoration: deco(context, context.t('Description'))),
        DateField(label: context.t('Date'), value: _day, allowNone: false, onChanged: (d) => setState(() => _day = d ?? _day)),
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: () => _pick(true),
              child: InputDecorator(decoration: deco(context, context.t('Start')), child: Text(hm(_start))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _pick(false),
              child: InputDecorator(decoration: deco(context, context.t('End')), child: Text(hm(_end))),
            ),
          ),
        ]),
        Text('${context.t('Duration')}: ${fmtMinutes(context, dur)}'),
        idDropdown<Project>(
          context: context,
          label: context.t('Project'),
          value: _projectId,
          items: watchList(ref, projectsProvider),
          labelOf: (p) => p.name,
          onChanged: (v) => setState(() => _projectId = v),
        ),
        idDropdown<LifeArea>(
          context: context,
          label: context.t('Life area'),
          value: _areaId,
          items: watchList(ref, areasProvider),
          labelOf: (a) => a.name,
          onChanged: (v) => setState(() => _areaId = v),
        ),
      ],
    );
  }
}
