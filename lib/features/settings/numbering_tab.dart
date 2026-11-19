import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/feedback.dart';

const _docLabels = <String, String>{
  'sales_quotation': 'Sales quotation',
  'sales_order': 'Sales order',
  'sales_invoice': 'Sales invoice',
  'delivery_challan': 'Delivery challan',
  'purchase_requisition': 'Purchase requisition',
  'purchase_order': 'Purchase order',
  'goods_receipt': 'Goods receipt',
  'supplier_bill': 'Supplier bill',
  'journal': 'Journal voucher',
  'payment': 'Payment voucher',
  'receipt': 'Receipt voucher',
  'contra': 'Contra voucher',
  'debit_note': 'Debit note',
  'credit_note': 'Credit note',
  'expense': 'Expense',
  'income': 'Income',
  'stock_adjustment': 'Stock adjustment',
  'stock_transfer': 'Stock transfer',
  'customer': 'Customer code',
  'supplier': 'Supplier code',
  'product': 'Product SKU',
};

final _sequencesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final orgId = ref.watch(activeMembershipProvider.select((m) => m?.orgId));
  if (orgId == null) return <Map<String, dynamic>>[];
  final rows = await ref.watch(supabaseProvider).from('doc_sequences').select().eq('org_id', orgId);
  final list = List<Map<String, dynamic>>.from(rows);
  final keys = _docLabels.keys.toList();
  int rank(Map<String, dynamic> r) {
    final i = keys.indexOf('${r['doc_type']}');
    return i < 0 ? keys.length : i;
  }

  list.sort((a, b) => rank(a).compareTo(rank(b)));
  return list;
});

String _preview(String prefix, int padding, int next) => '$prefix-${next.toString().padLeft(padding, '0')}';

/// Prefix, padding and next number for every document type.
class NumberingTab extends ConsumerWidget {
  const NumberingTab({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, Map<String, dynamic> row) async {
    final saved = await showAdaptiveForm<bool>(context, builder: (_) => _NumberingForm(row: row));
    if (saved == true) {
      ref.invalidate(_sequencesProvider);
      if (context.mounted) showToast(context, 'Numbering rule saved');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_sequencesProvider);
    final canEdit = ref.watch(permsProvider).can(Modules.settings, PermAction.edit);
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(_sequencesProvider)),
      data: (rows) => AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_docLabels['${rows[i]['doc_type']}'] ?? '${rows[i]['doc_type']}', style: AppText.bodyStrong),
                          const SizedBox(height: 2),
                          Text(
                            'Next number: ${_preview('${rows[i]['prefix']}', rows[i]['padding'] as int, (rows[i]['next_number'] as num).toInt())}',
                            style: AppText.small,
                          ),
                        ],
                      ),
                    ),
                    if (canEdit)
                      IconButton(
                        tooltip: 'Edit numbering rule',
                        onPressed: () => _edit(context, ref, rows[i]),
                        icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NumberingForm extends ConsumerStatefulWidget {
  const _NumberingForm({required this.row});
  final Map<String, dynamic> row;

  @override
  ConsumerState<_NumberingForm> createState() => _NumberingFormState();
}

class _NumberingFormState extends ConsumerState<_NumberingForm> {
  final _key = GlobalKey<FormState>();
  late final _prefix = TextEditingController(text: '${widget.row['prefix']}');
  late final _padding = TextEditingController(text: '${widget.row['padding']}');
  late final _next = TextEditingController(text: '${(widget.row['next_number'] as num).toInt()}');
  bool _saving = false;
  String? _error;

  int get _currentNext => (widget.row['next_number'] as num).toInt();

  @override
  void dispose() {
    _prefix.dispose();
    _padding.dispose();
    _next.dispose();
    super.dispose();
  }

  String get _example {
    final pad = int.tryParse(_padding.text) ?? 5;
    final next = int.tryParse(_next.text) ?? _currentNext;
    final prefix = _prefix.text.trim().isEmpty ? '...' : _prefix.text.trim().toUpperCase();
    return _preview(prefix, pad.clamp(1, 12).toInt(), next);
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final orgId = ref.read(activeMembershipProvider)?.orgId;
    if (orgId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).from('doc_sequences').update({
        'prefix': _prefix.text.trim().toUpperCase(),
        'padding': int.parse(_padding.text),
        'next_number': int.parse(_next.text),
      }).eq('org_id', orgId).eq('doc_type', widget.row['doc_type'] as Object);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _docLabels['${widget.row['doc_type']}'] ?? '${widget.row['doc_type']}';
    return Form(
      key: _key,
      child: FormShell(
        title: 'Numbering: $label',
        subtitle: 'Example: $_example',
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(label: 'Cancel', kind: AppButtonKind.secondary, onPressed: _saving ? null : () => Navigator.of(context).pop()),
            const SizedBox(width: 12),
            AppButton(label: 'Save', loading: _saving, onPressed: _save),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              controller: _prefix,
              label: 'Prefix',
              required: true,
              hint: 'For example INV',
              onChanged: (_) => setState(() {}),
              validator: (v) => RegExp(r'^[A-Za-z0-9-]{1,10}$').hasMatch((v ?? '').trim()) ? null : 'Use 1 to 10 letters, digits or hyphens',
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _padding,
              label: 'Number length',
              required: true,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return (n == null || n < 1 || n > 12) ? 'Enter a length from 1 to 12' : null;
              },
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _next,
              label: 'Next number',
              required: true,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                if (n == null || n < 1) return 'Enter a whole number';
                if (n < _currentNext) return 'Cannot go below $_currentNext, numbers already issued would repeat';
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}
