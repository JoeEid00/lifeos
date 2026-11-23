import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import 'search_palette.dart';

final shellScaffoldKey = GlobalKey<ScaffoldState>();

bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= 900;
double pagePad(BuildContext c) => MediaQuery.sizeOf(c).width >= 700 ? 24 : 14;

// ------------------------------------------------------------ app bar
PreferredSizeWidget lifeAppBar(
  BuildContext context,
  String title, {
  String? subtitle,
  List<Widget> actions = const [],
  PreferredSizeWidget? bottom,
}) {
  final wide = isWide(context);
  final canPop = GoRouter.of(context).canPop();
  final theme = Theme.of(context);
  return AppBar(
    toolbarHeight: 68,
    backgroundColor: theme.scaffoldBackgroundColor,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    automaticallyImplyLeading: canPop,
    leading: (!wide && !canPop)
        ? IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => shellScaffoldKey.currentState?.openDrawer(),
          )
        : null,
    titleSpacing: wide && !canPop ? 24 : null,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis),
        if (subtitle != null)
          Text(subtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis),
      ],
    ),
    actions: [
      ...actions,
      IconButton(
        tooltip: '${context.t('Search')}  (Ctrl+K)',
        icon: const Icon(Icons.search_rounded),
        onPressed: () => openSearch(context),
      ),
      const SizedBox(width: 8),
    ],
    bottom: bottom,
  );
}

// ------------------------------------------------------------ surfaces
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: color ?? (dark ? AppTheme.darkCard : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? cs.outlineVariant.withValues(alpha: dark ? .35 : .55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.icon, this.action, this.trailing});
  final String title;
  final IconData? icon;
  final Widget? action;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 20, color: theme.colorScheme.primary), const SizedBox(width: 8)],
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        if (trailing != null)
          Text(trailing!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (action != null) action!,
      ]),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.icon, required this.label, required this.value, this.color, this.sub, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final String? sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return AppCard(
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: c, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis),
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (sub != null)
              Text(sub!,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar(this.value, {super.key, this.color, this.height = 8});
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        color: color ?? cs.primary,
        backgroundColor: (color ?? cs.primary).withValues(alpha: .12),
      ),
    );
  }
}

class ProgressRing extends StatelessWidget {
  const ProgressRing(this.value, {super.key, this.size = 56, this.color, this.stroke = 6});
  final double value;
  final double size;
  final Color? color;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(fit: StackFit.expand, children: [
        CircularProgressIndicator(
          value: value.clamp(0.0, 1.0),
          strokeWidth: stroke,
          color: c,
          backgroundColor: c.withValues(alpha: .12),
          strokeCap: StrokeCap.round,
        ),
        Center(
          child: Text(pct(value),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * .24, color: c)),
        ),
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color, this.icon, this.onTap});
  final String label;
  final Color? color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: .08), shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 14),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Shows a spinner on first load, an error with retry, or the content.
Widget asyncGate(BuildContext context, List<AsyncValue<dynamic>> values, Widget Function() builder,
    {VoidCallback? onRetry}) {
  for (final v in values) {
    if (v.hasError && !v.hasValue) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: context.t('Could not load data'),
        subtitle: '${v.error}',
        action: onRetry == null
            ? null
            : FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(context.t('Retry'))),
      );
    }
  }
  if (values.any((v) => !v.hasValue)) return const Center(child: CircularProgressIndicator());
  return builder();
}

// ------------------------------------------------------------ feedback
void toast(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
  ));
}

/// Runs [action]; on failure shows an error snackbar. Returns true on success.
Future<bool> runSafe(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) toast(context, success);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '${context.t('Save failed')}: $e', error: true);
    return false;
  }
}

Future<bool> confirmDialog(BuildContext context, String title, {String? message, String? confirm}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.t('Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm ?? context.t('Delete')),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> promptText(BuildContext context, String title,
    {String initial = '', String? hint, int maxLines = 1}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: c,
          autofocus: true,
          maxLines: maxLines,
          minLines: 1,
          decoration: deco(context, hint ?? title),
          onSubmitted: maxLines == 1 ? (v) => Navigator.pop(d, v) : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(context.t('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: Text(context.t('Save'))),
      ],
    ),
  );
  return r;
}

// ------------------------------------------------------------ forms
InputDecoration deco(BuildContext context, String label, {String? hint, IconData? icon, Widget? suffix}) {
  final cs = Theme.of(context).colorScheme;
  final r = BorderRadius.circular(12);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon, size: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: cs.surfaceContainerHighest.withValues(alpha: .35),
    border: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: cs.outlineVariant)),
    enabledBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: .6))),
    focusedBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: cs.primary, width: 1.6)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );
}

/// Bottom sheet on phones, centered dialog on wide screens.
Future<T?> showAdaptiveSheet<T>(BuildContext context, Widget child) {
  if (MediaQuery.sizeOf(context).width >= 700) {
    return showDialog<T>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620, maxHeight: 780), child: child),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: child,
    ),
  );
}

class EditorFrame extends StatelessWidget {
  const EditorFrame({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.onDelete,
    this.saving = false,
    this.saveLabel,
    this.extraActions = const [],
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;
  final bool saving;
  final String? saveLabel;
  final List<Widget> extraActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 8, 6),
        child: Row(children: [
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          ...extraActions,
          if (onDelete != null)
            IconButton(
              tooltip: context.t('Delete'),
              onPressed: saving ? null : onDelete,
              icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
            ),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                children[i],
              ],
            ],
          ),
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(children: [
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.t('Cancel'))),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: saving ? null : onSave,
            child: saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(saveLabel ?? context.t('Save')),
          ),
        ]),
      ),
    ]);
  }
}

Widget idDropdown<T extends Entity>({
  required BuildContext context,
  required String label,
  required String? value,
  required List<T> items,
  required String Function(T) labelOf,
  required ValueChanged<String?> onChanged,
  String? noneLabel,
  IconData? icon,
  Key? key,
}) {
  final valid = items.any((e) => e.id == value) ? value : null;
  return DropdownButtonFormField<String?>(
    key: key ?? ValueKey('dd-$label-$valid-${items.length}'),
    initialValue: valid,
    isExpanded: true,
    decoration: deco(context, label, icon: icon),
    borderRadius: BorderRadius.circular(12),
    items: [
      DropdownMenuItem<String?>(value: null, child: Text(noneLabel ?? context.t('None'))),
      for (final e in items)
        DropdownMenuItem<String?>(value: e.id, child: Text(labelOf(e), overflow: TextOverflow.ellipsis)),
    ],
    onChanged: onChanged,
  );
}

Widget choiceDropdown({
  required BuildContext context,
  required String label,
  required String value,
  required Map<String, String> options,
  required ValueChanged<String> onChanged,
  IconData? icon,
}) {
  return DropdownButtonFormField<String>(
    key: ValueKey('cd-$label-$value'),
    initialValue: options.containsKey(value) ? value : options.keys.first,
    isExpanded: true,
    decoration: deco(context, label, icon: icon),
    borderRadius: BorderRadius.circular(12),
    items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}

class ColorPicker extends StatelessWidget {
  const ColorPicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final hex in kPalette)
        InkWell(
          onTap: () => onChanged(hex),
          customBorder: const CircleBorder(),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: hexColor(hex),
              shape: BoxShape.circle,
              border: Border.all(
                color: value.toUpperCase() == hex ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: value.toUpperCase() == hex ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
          ),
        ),
    ]);
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));
}

/// Date field with quick chips (Today / Tomorrow / End of week / Next week / No date).
class DateField extends ConsumerWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.allowNone = true});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowNone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(weekStartProvider);
    final t = today();
    final quick = <String, DateTime?>{
      'Today': t,
      'Tomorrow': addDays(t, 1),
      'End of week': addDays(startOfWeek(t, ws), 6),
      'Next week': addDays(startOfWeek(t, ws), 7),
      if (allowNone) 'No date': null,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: value ?? t,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (d != null) onChanged(d);
        },
        child: InputDecorator(
          decoration: deco(context, label, icon: Icons.event_outlined),
          child: Text(value == null ? context.t('No date') : fmtRelDate(context, value!)),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in quick.entries)
          ChoiceChip(
            label: Text(context.t(e.key)),
            visualDensity: VisualDensity.compact,
            selected: e.value == null ? value == null : sameDay(value, e.value),
            onSelected: (_) => onChanged(e.value),
          ),
      ]),
    ]);
  }
}

/// Simple multi-line list editor (steps, links…).
class StringListEditor extends StatefulWidget {
  const StringListEditor({
    super.key,
    required this.items,
    required this.onChanged,
    required this.hint,
    this.checked,
    this.onToggle,
    this.icon = Icons.drag_indicator_rounded,
  });
  final List<String> items;
  final List<bool>? checked;
  final ValueChanged<List<String>> onChanged;
  final void Function(int index)? onToggle;
  final String hint;
  final IconData icon;

  @override
  State<StringListEditor> createState() => _StringListEditorState();
}

class _StringListEditorState extends State<StringListEditor> {
  final _c = TextEditingController();

  void _add() {
    final v = _c.text.trim();
    if (v.isEmpty) return;
    widget.onChanged([...widget.items, v]);
    _c.clear();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < widget.items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            if (widget.checked != null)
              Checkbox(value: widget.checked![i], onChanged: (_) => widget.onToggle?.call(i))
            else
              Padding(padding: const EdgeInsets.all(8), child: Icon(widget.icon, size: 18)),
            Expanded(
              child: Text(widget.items[i],
                  style: TextStyle(
                    decoration:
                        (widget.checked?[i] ?? false) ? TextDecoration.lineThrough : TextDecoration.none,
                  )),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () {
                final l = [...widget.items]..removeAt(i);
                widget.onChanged(l);
              },
            ),
          ]),
        ),
      TextField(
        controller: _c,
        decoration: deco(context, widget.hint,
            suffix: IconButton(icon: const Icon(Icons.add_rounded), onPressed: _add)),
        onSubmitted: (_) => _add(),
      ),
    ]);
  }
}

// ------------------------------------------------------------ icons for areas
const kAreaIcons = <String, IconData>{
  'work': Icons.work_outline_rounded,
  'health': Icons.favorite_outline_rounded,
  'fitness': Icons.fitness_center_rounded,
  'finance': Icons.account_balance_wallet_outlined,
  'relationships': Icons.people_outline_rounded,
  'learning': Icons.school_outlined,
  'social': Icons.groups_outlined,
  'travel': Icons.flight_takeoff_rounded,
  'growth': Icons.self_improvement_rounded,
  'home': Icons.home_outlined,
  'spirit': Icons.spa_outlined,
  'fun': Icons.celebration_outlined,
  'family': Icons.family_restroom_rounded,
  'creative': Icons.palette_outlined,
};

IconData areaIcon(String key) => kAreaIcons[key] ?? Icons.blur_circular_rounded;

const kPriorityColors = [Color(0xFF94A3B8), Color(0xFF0EA5E9), Color(0xFFF59E0B), Color(0xFFEF4444)];
const kPriorityLabels = ['None', 'Low', 'Medium', 'High'];
