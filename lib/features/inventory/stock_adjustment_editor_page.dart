import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/responsive.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/attachments_panel.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/search_select.dart';
import '../finance/finance_providers.dart';
import '../trade/trade_models.dart';
import '../trade/trade_providers.dart';

class _AdjLine {
  _AdjLine({this.productId, this.remove = false, String qty = '', String cost = '', String note = ''})
      : qty = TextEditingController(text: qty),
        cost = TextEditingController(text: cost),
        note = TextEditingController(text: note);

  String? productId;

  /// True when the line takes stock out. Only count corrections and other
  /// adjustments can go either way; the reason decides for the rest.
  bool remove;
  final TextEditingController qty;
  final TextEditingController cost;
  final TextEditingController note;

  void dispose() {
    qty.dispose();
    cost.dispose();
    note.dispose();
  }
}

double _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

String _plain(num v) {
  final s = v.toStringAsFixed(4);
  return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Creates or edits a draft stock adjustment.
class StockAdjustmentEditorPage extends ConsumerStatefulWidget {
  const StockAdjustmentEditorPage({super.key, this.adjustmentId});

  final String? adjustmentId;

  @override
  ConsumerState<StockAdjustmentEditorPage> createState() => _StockAdjustmentEditorPageState();
}

class _StockAdjustmentEditorPageState extends ConsumerState<StockAdjustmentEditorPage> {
  late final String _id = widget.adjustmentId ?? newUuid();
  String? _date;
  String? _warehouse;
  String _reason = 'count_correction';
  final _notes = TextEditingController();
  final List<_AdjLine> _lines = [];
  bool _loading = false;
  bool _saving = false;
  String? _loadError;
  String? _error;

  bool get _isEdit => widget.adjustmentId != null;
  bool get _reduceOnly => reducingReasons.contains(_reason);
  bool get _increaseOnly => increasingReasons.contains(_reason);

  @override
  void initState() {
    super.initState();
    _date = _iso(DateTime.now());
    if (_isEdit) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      _lines.add(_AdjLine());
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final wh = await ref.read(defaultWarehouseProvider.future);
        if (mounted && _warehouse == null) setState(() => _warehouse = wh);
      });
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await ref
          .read(supabaseProvider)
          .from('stock_adjustments')
          .select('*, stock_adjustment_lines(line_no, product_id, quantity_change, unit_cost, note)')
          .eq('id', _id)
          .single();
      if (a['status'] != 'draft' && a['status'] != 'rejected') throw 'Only draft or rejected adjustments can be edited.';
      final rows = List<Map<String, dynamic>>.from(a['stock_adjustment_lines'] as List)..sort((x, y) => (x['line_no'] as int).compareTo(y['line_no'] as int));
      if (!mounted) return;
      setState(() {
        _date = a['adj_date'] as String?;
        _warehouse = a['warehouse_id'] as String?;
        _reason = '${a['reason']}';
        _notes.text = (a['notes'] as String?) ?? '';
        _lines
          ..clear()
          ..addAll([
            for (final r in rows)
              _AdjLine(
                productId: r['product_id'] as String?,
                remove: (r['quantity_change'] as num) < 0,
                qty: _plain((r['quantity_change'] as num).abs()),
                cost: r['unit_cost'] == null ? '' : _plain(r['unit_cost'] as num),
                note: (r['note'] as String?) ?? '',
              ),
          ]);
        if (_lines.isEmpty) _lines.add(_AdjLine());
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e is String ? e : friendlyError(e);
        });
      }
    }
  }

  bool _removes(_AdjLine l) => _reduceOnly || (!_increaseOnly && l.remove);

  Future<void> _save(String then) async {
    final m = ref.read(activeMembershipProvider);
    if (m == null) return;
    setState(() => _error = null);
    if (_warehouse == null) {
      setState(() => _error = 'Choose the warehouse.');
      return;
    }
    final lines = <Map<String, dynamic>>[];
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      if (l.productId == null) {
        setState(() => _error = 'Line ${i + 1}: choose an item.');
        return;
      }
      final qty = _num(l.qty);
      if (qty <= 0) {
        setState(() => _error = 'Line ${i + 1}: enter a quantity greater than zero.');
        return;
      }
      final removes = _removes(l);
      if (!removes && l.cost.text.trim().isEmpty) {
        setState(() => _error = 'Line ${i + 1}: enter the unit cost of the stock being added.');
        return;
      }
      lines.add({
        'product_id': l.productId,
        'quantity_change': removes ? -qty : qty,
        'unit_cost': removes ? null : _num(l.cost),
        'note': l.note.text.trim().isEmpty ? null : l.note.text.trim(),
      });
    }

    setState(() => _saving = true);
    try {
      final client = ref.read(supabaseProvider);
      await client.rpc('save_stock_adjustment', params: {
        'p_id': _id,
        'p_org': m.orgId,
        'p_date': _date,
        'p_warehouse': _warehouse,
        'p_reason': _reason,
        'p_notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'p_lines': lines,
      });
      var done = 'Saved as draft';
      if (then == 'submit') {
        await client.rpc('submit_stock_adjustment', params: {'p_id': _id});
        done = 'Submitted for approval';
      } else if (then == 'post') {
        await client.rpc('post_stock_adjustment', params: {'p_id': _id});
        done = 'Adjustment posted. Stock has been updated.';
      }
      invalidateTrade(ref);
      if (!mounted) return;
      showToast(context, done);
      context.go('/inventory/adjustments/$_id');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!perms.canView(Modules.inventory) || !(perms.can(Modules.inventory, PermAction.create) || perms.can(Modules.inventory, PermAction.edit))) return const NoAccessView();
    if (_loading) return const LoadingView();
    if (_loadError != null) {
      return EmptyState(icon: Icons.info_outline_rounded, title: 'This form cannot be opened', message: _loadError, actionLabel: 'Back to adjustments', onAction: () => context.go('/inventory/adjustments'));
    }

    final catalog = ref.watch(productCatalogProvider).valueOrNull ?? <Map<String, dynamic>>[];
    final warehouses = ref.watch(warehouseOptions).valueOrNull ?? const <Option>[];
    final onHand = ref.watch(stockOnHandProvider((org: m.orgId, warehouse: _warehouse))).valueOrNull ?? <Map<String, dynamic>>[];
    final productOptions = [for (final p in catalog) if (isStockItem(p)) Option(p['id'] as String, '${p['sku']}  ${p['name']}')];
    final fieldWidth = context.isMobile ? double.infinity : 330.0;
    final canPost = perms.can(Modules.inventory, PermAction.approve);

    return AppPage(
      title: _isEdit ? 'Edit stock adjustment' : 'New stock adjustment',
      subtitle: 'Changes stay in draft until they are approved and posted',
      maxWidth: 1100,
      children: [
        SectionCard(
          title: 'Details',
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(width: fieldWidth, child: AppDateField(label: 'Date', required: true, value: _date, onChanged: (v) => setState(() => _date = v))),
              SizedBox(width: fieldWidth, child: SearchSelectField(label: 'Warehouse', required: true, hint: 'Select warehouse', options: warehouses, value: _warehouse, onChanged: (v) => setState(() => _warehouse = v))),
              SizedBox(
                width: fieldWidth,
                child: AppDropdown<String>(
                  label: 'Reason',
                  required: true,
                  value: _reason,
                  items: [for (final e in adjustmentReasons.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _reason = v ?? 'count_correction'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Items',
          subtitle: _reduceOnly ? 'This reason takes stock out.' : (_increaseOnly ? 'Opening stock adds stock at the cost you enter.' : 'Choose whether each line adds or removes stock.'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < _lines.length; i++) ...[
                KeyedSubtree(key: ObjectKey(_lines[i]), child: _lineEditor(i, productOptions, onHand)),
                const SizedBox(height: 12),
              ],
              AppButton(label: 'Add line', icon: Icons.add_rounded, kind: AppButtonKind.ghost, compact: true, onPressed: () => setState(() => _lines.add(_AdjLine()))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Notes and documents',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(controller: _notes, label: 'Notes', maxLines: 3),
              const SizedBox(height: 16),
              AttachmentsPanel(entityType: 'stock_adjustment', entityId: _id),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AppButton(label: 'Save draft', kind: AppButtonKind.secondary, loading: _saving, onPressed: () => _save('draft')),
            AppButton(label: 'Save and submit for approval', loading: _saving, onPressed: () => _save('submit')),
            if (canPost) AppButton(label: 'Save, approve and post', kind: AppButtonKind.secondary, loading: _saving, onPressed: () => _save('post')),
            AppButton(label: 'Cancel', kind: AppButtonKind.ghost, onPressed: _saving ? null : () => context.go(_isEdit ? '/inventory/adjustments/$_id' : '/inventory/adjustments')),
          ],
        ),
      ],
    );
  }

  Widget _lineEditor(int i, List<Option> productOptions, Rows onHand) {
    final l = _lines[i];
    final removes = _removes(l);
    double? current;
    if (l.productId != null) {
      current = 0;
      for (final r in onHand) {
        if (r['product_id'] == l.productId) current = (current ?? 0) + (r['quantity'] as num).toDouble();
      }
    }

    final item = SearchSelectField(
      label: 'Item',
      hint: 'Select item',
      options: productOptions,
      value: l.productId,
      onChanged: (v) => setState(() {
        l.productId = v;
        if (v != null && l.cost.text.isEmpty) {
          final cat = ref.read(productCatalogProvider).valueOrNull ?? <Map<String, dynamic>>[];
          for (final p in cat) {
            if (p['id'] == v && ((p['purchase_price'] as num?) ?? 0) > 0) l.cost.text = _plain(p['purchase_price'] as num);
          }
        }
      }),
    );
    final direction = AppDropdown<bool>(
      label: 'Change',
      value: removes,
      items: const [DropdownMenuItem(value: false, child: Text('Add stock')), DropdownMenuItem(value: true, child: Text('Remove stock'))],
      onChanged: (_reduceOnly || _increaseOnly) ? null : (v) => setState(() => l.remove = v ?? false),
    );
    final qty = AppTextField(controller: l.qty, label: 'Quantity', keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}));
    final cost = AppTextField(controller: l.cost, label: 'Unit cost', enabled: !removes, hint: removes ? 'Average cost' : null, keyboardType: const TextInputType.numberWithOptions(decimal: true));
    final note = AppTextField(controller: l.note, label: 'Note');
    final remove = IconButton(
      tooltip: 'Remove line',
      onPressed: _lines.length <= 1 ? null : () => setState(() => _lines.removeAt(i).dispose()),
      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF9FBFA), borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: AppColors.border)),
      child: LayoutBuilder(
        builder: (context, cons) {
          final wide = cons.maxWidth >= 760;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 5, child: item),
                  const SizedBox(width: 12),
                  SizedBox(width: 160, child: direction),
                  const SizedBox(width: 12),
                  SizedBox(width: 110, child: qty),
                  const SizedBox(width: 12),
                  SizedBox(width: 130, child: cost),
                  remove,
                ])
              else ...[
                item,
                const SizedBox(height: 12),
                Row(children: [Expanded(child: direction), const SizedBox(width: 12), Expanded(child: qty)]),
                const SizedBox(height: 12),
                cost,
              ],
              const SizedBox(height: 12),
              if (wide) Row(children: [Expanded(child: note), const SizedBox(width: 52)]) else ...[note, Align(alignment: Alignment.centerRight, child: remove)],
              if (current != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Currently ${qtyText(current)} on hand${_warehouse == null ? ' across all warehouses' : ' in this warehouse'}', style: AppText.small)),
            ],
          );
        },
      ),
    );
  }
}
