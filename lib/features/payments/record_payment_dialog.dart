import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/responsive.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/crud/option_sources.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/search_select.dart';
import '../trade/trade_providers.dart';
import 'payment_models.dart';
import 'payment_providers.dart';

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Opens the form for recording a customer receipt or a supplier payment.
/// Pass [partyId] to start from one customer or supplier and [documentId] to
/// start from one invoice or bill. Returns true when a payment was recorded.
Future<bool> showRecordPayment(BuildContext context, {required LedgerSide side, String? partyId, String? documentId}) async {
  final saved = await showAdaptiveForm<bool>(
    context,
    maxWidth: 720,
    builder: (_) => RecordPaymentForm(side: side, partyId: partyId, documentId: documentId),
  );
  return saved == true;
}

class RecordPaymentForm extends ConsumerStatefulWidget {
  const RecordPaymentForm({super.key, required this.side, this.partyId, this.documentId});

  final LedgerSide side;
  final String? partyId;
  final String? documentId;

  @override
  ConsumerState<RecordPaymentForm> createState() => _RecordPaymentFormState();
}

class _RecordPaymentFormState extends ConsumerState<RecordPaymentForm> {
  /// Fixed for this form, so a retry after a dropped connection cannot record the payment twice.
  late final String _id = newUuid();
  String? _party;
  String _date = _iso(DateTime.now());
  String? _account;
  String? _method;
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  List<OpenItem> _items = const [];
  final Map<String, TextEditingController> _alloc = {};
  bool _auto = true;
  bool _loadingItems = false;
  bool _saving = false;
  String? _error;

  LedgerSide get side => widget.side;

  @override
  void initState() {
    super.initState();
    _party = widget.partyId;
    if (_party != null) WidgetsBinding.instance.addPostFrameCallback((_) => _loadItems());
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    for (final c in _alloc.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _val(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

  Future<void> _loadItems() async {
    final m = ref.read(activeMembershipProvider);
    final party = _party;
    if (m == null || party == null) return;
    setState(() => _loadingItems = true);
    try {
      final rows = await ref.refresh(openItemsProvider((org: m.orgId, side: side.key, party: party, asOf: null)).future);
      if (!mounted || _party != party) return;
      final items = [for (final r in rows) OpenItem.fromRow(r)];
      for (final c in _alloc.values) {
        c.dispose();
      }
      _alloc.clear();
      for (final i in items) {
        _alloc[i.id] = TextEditingController();
      }
      setState(() {
        _items = items;
        _loadingItems = false;
        _auto = true;
        final doc = widget.documentId;
        if (doc != null && _amount.text.trim().isEmpty) {
          for (final i in items) {
            if (i.id == doc) _amount.text = i.balance.toStringAsFixed(2);
          }
        }
        _reallocate();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingItems = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  /// Fills the amounts applied to each document, oldest due date first.
  void _reallocate() {
    final alloc = allocateOldestFirst(_val(_amount), _items, firstId: widget.documentId);
    final by = {for (final a in alloc) a.documentId: a.amount};
    for (final i in _items) {
      final v = by[i.id];
      _alloc[i.id]!.text = v == null ? '' : v.toStringAsFixed(2);
    }
  }

  List<Allocation> get _allocations => [
        for (final i in _items)
          if (_val(_alloc[i.id]!) > 0) Allocation(i.id, roundMoney(_val(_alloc[i.id]!))),
      ];

  Future<void> _submit() async {
    final m = ref.read(activeMembershipProvider);
    if (m == null) return;
    final amount = roundMoney(_val(_amount));
    final allocations = _allocations;
    String? problem;
    if (_party == null) {
      problem = 'Choose the ${side.partyLabel.toLowerCase()}.';
    } else if (_account == null) {
      problem = 'Choose the cash or bank account.';
    } else if (amount <= 0) {
      problem = 'Enter an amount greater than zero.';
    } else if (totalAllocated(allocations) > amount) {
      problem = 'The amounts applied are more than the ${side.paymentLabel.toLowerCase()}.';
    } else {
      for (final a in allocations) {
        final item = _items.firstWhere((i) => i.id == a.documentId);
        if (!withinBalance(a.amount, item.balance)) {
          problem = '${item.number} has only ${Fmt.money(item.balance, currency: m.currency)} still to pay.';
          break;
        }
      }
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).rpc('record_payment', params: {
        'p_id': _id,
        'p_org': m.orgId,
        'p_kind': side.paymentKind,
        'p_party': _party,
        'p_date': _date,
        'p_fin': _account,
        'p_method': _method,
        'p_amount': amount,
        'p_reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        'p_notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'p_allocations': [for (final a in allocations) a.toJson()],
      });
      invalidateTrade(ref);
      if (!mounted) return;
      showToast(context, '${side.paymentLabel} recorded');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(activeMembershipProvider);
    final currency = m?.currency ?? 'BDT';
    final parties = ref.watch(side.isReceivable ? customerOptions : supplierOptions).valueOrNull ?? const <Option>[];
    final accounts = ref.watch(cashBankOptions).valueOrNull ?? const <Option>[];
    final methods = ref.watch(paymentMethodOptions).valueOrNull ?? const <Option>[];
    final w = context.isMobile ? double.infinity : 320.0;
    final amount = roundMoney(_val(_amount));
    final allocations = _allocations;
    final applied = totalAllocated(allocations);
    final advance = advanceOf(amount, allocations);

    Widget field(Widget child) => SizedBox(width: w, child: child);

    return FormShell(
      title: side.recordLabel,
      subtitle: side.isReceivable ? 'Money received from a customer.' : 'Money paid to a supplier.',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(label: 'Cancel', kind: AppButtonKind.ghost, onPressed: _saving ? null : () => Navigator.of(context).pop()),
          const SizedBox(width: 10),
          AppButton(label: side.recordLabel, loading: _saving, onPressed: _submit),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              field(SearchSelectField(
                label: side.partyLabel,
                required: true,
                hint: 'Select ${side.partyLabel.toLowerCase()}',
                enabled: widget.partyId == null,
                options: parties,
                value: _party,
                onChanged: (v) {
                  setState(() => _party = v);
                  _loadItems();
                },
              )),
              field(AppDateField(label: 'Date', required: true, value: _date, onChanged: (v) => setState(() => _date = v ?? _date))),
              field(AppTextField(
                controller: _amount,
                label: 'Amount',
                required: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {
                  if (_auto) _reallocate();
                }),
              )),
              field(SearchSelectField(
                label: side.isReceivable ? 'Deposit to' : 'Pay from',
                required: true,
                hint: 'Select cash or bank account',
                options: accounts,
                value: _account,
                onChanged: (v) => setState(() => _account = v),
              )),
              field(SearchSelectField(label: 'Method', hint: 'Optional', clearable: true, options: methods, value: _method, onChanged: (v) => setState(() => _method = v))),
              field(AppTextField(controller: _reference, label: 'Cheque or transaction number', hint: 'Optional')),
            ],
          ),
          const SizedBox(height: 20),
          if (_party != null) _allocationSection(currency, applied, advance) else Text('Choose a ${side.partyLabel.toLowerCase()} to see what is open.', style: AppText.body),
          const SizedBox(height: 16),
          AppTextField(controller: _notes, label: 'Notes', maxLines: 2, hint: 'Optional'),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
        ],
      ),
    );
  }

  Widget _allocationSection(String currency, double applied, double advance) {
    String money(double v) => Fmt.money(v, currency: currency);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF9FBFA), borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Apply to open ${side.documentLabel}s', style: AppText.h3)),
              if (_items.isNotEmpty)
                AppButton(
                  label: 'Oldest first',
                  kind: AppButtonKind.ghost,
                  compact: true,
                  onPressed: () => setState(() {
                    _auto = true;
                    _reallocate();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingItems)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator(minHeight: 2))
          else if (_items.isEmpty)
            Text('Nothing is open for this ${side.partyLabel.toLowerCase()}. The whole amount is kept as ${side.isReceivable ? 'a customer advance' : 'an advance to the supplier'}, which you can apply later.', style: AppText.body)
          else
            for (final i in _items) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.isOpening ? '${i.number}  (opening balance)' : i.number, style: AppText.bodyStrong),
                          Text(
                            '${i.reference == null ? '' : '${i.reference}, '}due ${Fmt.date(i.dueDate)}${i.overdue ? ', ${i.daysPastDue} days overdue' : ''}',
                            style: AppText.small.copyWith(color: i.overdue ? AppColors.danger : AppColors.textMuted),
                          ),
                          Text('Owes ${money(i.balance)}', style: AppText.small),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 130,
                      child: TextFormField(
                        controller: _alloc[i.id],
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() => _auto = false),
                        style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary),
                        decoration: AppInput.decoration(hint: '0.00'),
                      ),
                    ),
                  ],
                ),
              ),
              if (i != _items.last) const Divider(height: 1),
            ],
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: Text('Applied to documents', style: AppText.body)), Text(money(applied), style: AppText.bodyStrong)]),
          if (advance > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Expanded(child: Text('Kept as ${side.advanceLabel.toLowerCase()}', style: AppText.body)),
                Text(money(advance), style: AppText.bodyStrong.copyWith(color: AppColors.info)),
              ]),
            ),
        ],
      ),
    );
  }
}
