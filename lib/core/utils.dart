import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'i18n.dart';

// ---------------------------------------------------------------- dates
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime today() => dateOnly(DateTime.now());
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

DateTime startOfWeek(DateTime d, int weekStartDay) {
  final x = dateOnly(d);
  return addDays(x, -((x.weekday - weekStartDay) % 7));
}

bool sameDay(DateTime? a, DateTime? b) =>
    a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

bool inRange(DateTime d, DateTime start, DateTime endExclusive) =>
    !d.isBefore(start) && d.isBefore(endExclusive);

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String isoUtc(DateTime d) => d.toUtc().toIso8601String();

DateTime? parseDateTime(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  final p = DateTime.tryParse(s);
  if (p == null) return null;
  return p.isUtc ? p.toLocal() : p;
}

int? parseHm(String? s) {
  if (s == null || !s.contains(':')) return null;
  final p = s.split(':');
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String hm(int minutes) {
  final m = math.max(0, math.min(minutes, 24 * 60 - 1));
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

String lang(BuildContext context) => Localizations.localeOf(context).languageCode;

String fmtDate(BuildContext context, DateTime d, [String pattern = 'EEE d MMM']) =>
    DateFormat(pattern, lang(context)).format(d);

String fmtRelDate(BuildContext context, DateTime d) {
  final t = today();
  if (sameDay(d, t)) return context.t('Today');
  if (sameDay(d, addDays(t, 1))) return context.t('Tomorrow');
  if (sameDay(d, addDays(t, -1))) return context.t('Yesterday');
  return fmtDate(context, d, d.year == t.year ? 'EEE d MMM' : 'd MMM y');
}

String fmtMinutes(BuildContext context, int minutes) {
  final ar = lang(context) == 'ar';
  final h = minutes ~/ 60, m = minutes % 60;
  final hs = ar ? 'س' : 'h', ms = ar ? 'د' : 'm';
  if (h == 0) return '$m$ms';
  if (m == 0) return '$h$hs';
  return '$h$hs $m$ms';
}

String fmtMoney(num v, String currency) => '${NumberFormat('#,##0.##').format(v)} $currency';

String pct(double v) => '${(v * 100).round()}%';

// ---------------------------------------------------------------- colors
const kPalette = [
  '#4F46E5', '#0EA5E9', '#06B6D4', '#14B8A6', '#10B981', '#84CC16',
  '#F59E0B', '#F97316', '#EF4444', '#EC4899', '#8B5CF6', '#64748B',
];

Color hexColor(String? hex, [Color fallback = const Color(0xFF4F46E5)]) {
  if (hex == null) return fallback;
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

// ---------------------------------------------------------------- search
final _diacritics = RegExp('[ً-ْٰـ]');
final _alef = RegExp('[أإآٱ]');

String normalizeText(String s) => s
    .toLowerCase()
    .replaceAll(_diacritics, '')
    .replaceAll(_alef, 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي');

/// Every word of [query] must appear in [haystack] (Arabic-aware).
bool matchesQuery(String haystack, String query) {
  final words = normalizeText(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final h = normalizeText(haystack);
  return words.every(h.contains);
}

List<String> splitLines(String s) =>
    s.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

List<String> splitTags(String s) =>
    s.split(RegExp('[,،#]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();

final urlRegex = RegExp(r'https?://[^\s)]+');
