import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

Future<void> showShoppingEditor(BuildContext context, {ShoppingItem? item}) =>
    showAdaptiveSheet(context, ShoppingEditor(item: item));

class ShoppingScreen extends ConsumerStatefulWidget {
  const ShoppingScreen({super.key});
  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen> {
  String _filter = 'tobuy';
  String? _cat;

  Future<void> _togglePurchased(ShoppingItem i) async {
    if (i.purchased) {
      await runSafe(context, () => ref.read(shoppingProvider.notifier).patch(i.id, {'purchased': false, 'purchased_at': null}));
      return;
    }
    final c = TextEditingController(text: (i.actualPaid ?? i.estimatedTotal).toStringAsFixed(i.estimatedTotal % 1 == 0 ? 0 : 2));
    final cur = ref.read(settingsProvider).currency;
    final paid = await showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(i.name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: deco(context, '${context.t('Total actually paid')} ($cur)'),
          onSubmitted: (v) => Navigator.pop(d, double.tryParse(v) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(context.t('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(d, double.tryParse(c.text) ?? 0), child: Text(context.t('Mark as bought'))),
        ],
      ),
    );
    if (paid == null) return;
    await runSafe(context, () => ref.read(shoppingProvider.notifier).patch(i.id, {
          'purchased': true,
          'actual_paid': paid,
          'purchased_at': ymd(today()),
        }));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(shoppingProvider);
    final cur = ref.watch(settingsProvider).currency;
    final cats = watchList(ref, categoriesProvider).where((c) => c.kind == 'shopping').toList();
    return Scaffold(
      appBar: lifeAppBar(context, context.t('Shopping')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showShoppingEditor(context),
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: Text(context.t('Item')),
      ),
      body: asyncGate(context, [async], () {
        final all = async.value!;
        final now = DateTime.now();
        final mStart = startOfMonth(now);
        final mEnd = DateTime(now.year, now.month + 1, 1);
        final monthSpent = all.where((i) => i.purchased && inRange(i.spendDate, mStart, mEnd)).fold<double>(0, (s, i) => s + i.spent);
        final totalSpent = all.fold<double>(0, (s, i) => s + i.spent);
        final planned = all.where((i) => !i.purchased).fold<double>(0, (s, i) => s + i.estimatedTotal);
        final list = all.where((i) {
          if (_filter == 'tobuy' && i.purchased) return false;
          if (_filter == 'bought' && !i.purchased) return false;
          if (_cat != null && i.categoryId != _cat) return false;
          return true;
        }).toList()
          ..sort((a, b) {
            if (a.purchased != b.purchased) return a.purchased ? 1 : -1;
            return (b.purchasedAt ?? b.createdAt).compareTo(a.purchasedAt ?? a.createdAt);
          });

        // Spending by category this month
        final byCat = <String?, double>{};
        for (final i in all.where((i) => i.purchased && inRange(i.spendDate, mStart, mEnd))) {
          byCat[i.categoryId] = (byCat[i.categoryId] ?? 0) + i.spent;
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(pagePad(context), 4, pagePad(context), 100),
          children: [
            LayoutBuilder(builder: (c, box) {
              final w = box.maxWidth >= 720 ? (box.maxWidth - 24) / 3 : box.maxWidth;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: w, child: StatCard(icon: Icons.calendar_month_rounded, label: context.t('Spent this month'), value: fmtMoney(monthSpent, cur), color: const Color(0xFF4F46E5))),
                SizedBox(width: w, child: StatCard(icon: Icons.shopping_cart_checkout_rounded, label: context.t('Planned (estimated)'), value: fmtMoney(planned, cur), color: const Color(0xFFF59E0B))),
                SizedBox(width: w, child: StatCard(icon: Icons.account_balance_wallet_outlined, label: context.t('Total spent'), value: fmtMoney(totalSpent, cur), color: const Color(0xFF10B981))),
              ]);
            }),
            if (byCat.isNotEmpty) ...[
              const SizedBox(height: 14),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SectionHeader(context.t('This month by category')),
                  for (final e in byCat.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Builder(builder: (_) {
                        final cat = cats.where((c) => c.id == e.key).firstOrNull;
                        return Row(children: [
                          SizedBox(width: 110, child: Text(cat?.name ?? context.t('Uncategorized'), overflow: TextOverflow.ellipsis)),
                          Expanded(child: ProgressBar(monthSpent == 0 ? 0 : e.value / monthSpent, color: hexColor(cat?.color, Colors.grey))),
                          const SizedBox(width: 10),
                          Text(fmtMoney(e.value, cur), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]);
                      }),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in {'tobuy': 'To buy', 'bought': 'Bought', 'all': 'All'}.entries)
                ChoiceChip(label: Text(context.t(f.value)), selected: _filter == f.key, onSelected: (_) => setState(() => _filter = f.key)),
              for (final c in cats)
                FilterChip(
                  avatar: CircleAvatar(radius: 5, backgroundColor: hexColor(c.color)),
                  label: Text(c.name),
                  selected: _cat == c.id,
                  onSelected: (_) => setState(() => _cat = _cat == c.id ? null : c.id),
                ),
            ]),
            const SizedBox(height: 12),
            if (list.isEmpty)
              EmptyState(icon: Icons.shopping_bag_outlined, title: context.t('Your list is empty'))
            else
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  for (var k = 0; k < list.length; k++) ...[
                    if (k > 0) const Divider(height: 1, indent: 56),
                    Builder(builder: (_) {
                      final i = list[k];
                      final cat = cats.where((c) => c.id == i.categoryId).firstOrNull;
                      final qty = i.quantity % 1 == 0 ? i.quantity.toInt().toString() : i.quantity.toString();
                      return ListTile(
                        leading: Checkbox(
                          value: i.purchased,
                          shape: const CircleBorder(),
                          onChanged: (_) => _togglePurchased(i),
                        ),
                        title: Text(i.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              decoration: i.purchased ? TextDecoration.lineThrough : null,
                            )),
                        subtitle: Wrap(spacing: 6, runSpacing: 4, children: [
                          Pill('× $qty'),
                          if (cat != null) Pill(cat.name, color: hexColor(cat.color)),
                          if (i.purchased && i.purchasedAt != null) Pill(fmtRelDate(context, i.purchasedAt!), icon: Icons.event_available_rounded),
                          if (!i.purchased && i.targetDate != null) Pill(fmtRelDate(context, i.targetDate!), icon: Icons.event_rounded),
                        ]),
                        trailing: Text(
                          i.purchased
                              ? fmtMoney(i.actualPaid ?? 0, cur)
                              : (i.estimatedPrice == null ? '' : '≈ ${fmtMoney(i.estimatedTotal, cur)}'),
                          style: TextStyle(fontWeight: FontWeight.w700, color: i.purchased ? Colors.green : null),
                        ),
                        onTap: () => showShoppingEditor(context, item: i),
                      );
                    }),
                  ],
                ]),
              ),
          ],
        );
      }, onRetry: () => ref.invalidate(shoppingProvider)),
    );
  }
}

class ShoppingEditor extends ConsumerStatefulWidget {
  const ShoppingEditor({super.key, this.item});
  final ShoppingItem? item;
  @override
  ConsumerState<ShoppingEditor> createState() => _ShoppingEditorState();
}

class _ShoppingEditorState extends ConsumerState<ShoppingEditor> {
  late final TextEditingController _name, _qty, _price, _paid, _notes;
  String? _cat;
  bool _purchased = false;
  DateTime? _purchasedAt, _target;
  bool _saving = false;

  String _n(double? v) => v == null ? '' : (v % 1 == 0 ? v.toInt().toString() : v.toString());

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _name = TextEditingController(text: i?.name ?? '');
    _qty = TextEditingController(text: _n(i?.quantity ?? 1));
    _price = TextEditingController(text: _n(i?.estimatedPrice));
    _paid = TextEditingController(text: _n(i?.actualPaid));
    _notes = TextEditingController(text: i?.notes ?? '');
    _cat = i?.categoryId;
    _purchased = i?.purchased ?? false;
    _purchasedAt = i?.purchasedAt;
    _target = i?.targetDate;
  }

  @override
  void dispose() {
    for (final c in [_name, _qty, _price, _paid, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final cur = ref.watch(settingsProvider).currency;
    return EditorFrame(
      title: context.t(i == null ? 'New item' : 'Edit item'),
      saving: _saving,
      onDelete: i == null
          ? null
          : () async {
              if (!await confirmDialog(context, context.t('Delete this item?'))) return;
              final ok = await runSafe(context, () => ref.read(shoppingProvider.notifier).remove(i.id));
              if (ok && mounted) Navigator.pop(context);
            },
      onSave: () async {
        if (_name.text.trim().isEmpty) {
          toast(context, context.t('Name is required'), error: true);
          return;
        }
        setState(() => _saving = true);
        final data = {
          'name': _name.text.trim(),
          'quantity': double.tryParse(_qty.text) ?? 1,
          'estimated_price': double.tryParse(_price.text),
          'actual_paid': double.tryParse(_paid.text),
          'category_id': _cat,
          'purchased': _purchased,
          'purchased_at': _purchased ? ymd(_purchasedAt ?? today()) : null,
          'target_date': _target == null ? null : ymd(_target!),
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        };
        final n = ref.read(shoppingProvider.notifier);
        final ok = await runSafe(context, () async {
          if (i == null) {
            await n.add(data);
          } else {
            await n.patch(i.id, data);
          }
        });
        if (!mounted) return;
        setState(() => _saving = false);
        if (ok) Navigator.pop(context);
      },
      children: [
        TextField(controller: _name, autofocus: i == null, decoration: deco(context, context.t('Item'))),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: deco(context, context.t('Quantity')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: deco(context, '${context.t('Estimated unit price')} ($cur)'),
            ),
          ),
        ]),
        idDropdown<ItemCategory>(
          context: context,
          label: context.t('Category'),
          value: _cat,
          items: watchList(ref, categoriesProvider).where((c) => c.kind == 'shopping').toList(),
          labelOf: (c) => c.name,
          onChanged: (v) => setState(() => _cat = v),
        ),
        DateField(label: context.t('Buy by'), value: _target, onChanged: (d) => setState(() => _target = d)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.t('Bought')),
          value: _purchased,
          onChanged: (v) => setState(() {
            _purchased = v;
            if (v) _purchasedAt ??= today();
          }),
        ),
        if (_purchased) ...[
          TextField(
            controller: _paid,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: deco(context, '${context.t('Total actually paid')} ($cur)', icon: Icons.payments_outlined),
          ),
          DateField(
            label: context.t('Purchase date'),
            value: _purchasedAt,
            allowNone: false,
            onChanged: (d) => setState(() => _purchasedAt = d),
          ),
        ],
        TextField(controller: _notes, minLines: 1, maxLines: 4, decoration: deco(context, context.t('Notes'))),
      ],
    );
  }
}
