import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permissions/permissions.dart';
import '../../core/state/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../shared/crud/crud_config.dart';
import '../../shared/widgets/adaptive_dialog.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_inputs.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/search_select.dart';
import '../trade/trade_models.dart';
import '../trade/trade_providers.dart';
import 'payment_access.dart';
import 'payment_models.dart';
import 'payment_providers.dart';

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One receipt or supplier payment: what it paid, what is left as an advance,
/// and the actions to apply, unapply or cancel it.
class PaymentDetailPage extends ConsumerStatefulWidget {
  const PaymentDetailPage({super.key, required this.side, required this.paymentId});

  final LedgerSide side;
  final String paymentId;

  @override
  ConsumerState<PaymentDetailPage> createState() => _PaymentDetailPageState();
}

class _PaymentDetailPageState extends ConsumerState<PaymentDetailPage> {
  bool _busy = false;

  LedgerSide get side => widget.side;
  String get id => widget.paymentId;

  Future<void> _run(Future<dynamic> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      invalidateTrade(ref);
      if (mounted) showToast(context, done);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final label = side.paymentLabel.toLowerCase();
    final reason = await promptDialog(
      context,
      title: 'Cancel $label',
      label: 'Reason',
      confirmLabel: 'Cancel $label',
      message: 'The accounting entry is reversed and every ${side.documentLabel} it paid is open again. The $label stays in your records as cancelled.',
      danger: true,
    );
    if (reason == null) return;
    await _run(() => ref.read(supabaseProvider).rpc('cancel_payment', params: {'p_id': id, 'p_reason': reason}), '${side.paymentLabel} cancelled');
  }

  Future<void> _unapply(String allocationId, String docNumber) async {
    final reason = await promptDialog(
      context,
      title: 'Remove from $docNumber',
      label: 'Reason',
      confirmLabel: 'Remove',
      message: 'The amount goes back to the ${side.advanceLabel.toLowerCase()} and $docNumber is open again for that amount.',
      danger: true,
    );
    if (reason == null) return;
    await _run(() => ref.read(supabaseProvider).rpc('unapply_allocation', params: {'p_alloc': allocationId, 'p_reason': reason}), 'Removed from $docNumber');
  }

  Future<void> _apply(Map<String, dynamic> p, double unallocated) async {
    final done = await showAdaptiveForm<bool>(
      context,
      maxWidth: 560,
      builder: (_) => _ApplyAdvanceForm(side: side, paymentId: id, partyId: '${p['party_id']}', unallocated: unallocated),
    );
    if (done == true) invalidateTrade(ref);
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permsProvider);
    final m = ref.watch(activeMembershipProvider);
    if (m == null) return const LoadingView();
    if (!canViewLedger(perms, side)) return const NoAccessView();
    final async = ref.watch(paymentDetailProvider(id));

    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(paymentDetailProvider)),
      data: (p) {
        if (p == null || p['kind'] != side.paymentKind) {
          return EmptyState(
            icon: Icons.search_off_rounded,
            title: '${side.paymentLabel} not found',
            message: 'It may not exist, or you may not have access to it.',
            actionLabel: 'Back to ${side.title.toLowerCase()}',
            onAction: () => context.go(side.basePath),
          );
        }
        final status = '${p['status']}';
        final amount = (p['amount'] as num).toDouble();
        final allocs = [
          for (final a in (p['payment_allocations'] as List)) Map<String, dynamic>.from(a as Map),
        ]
          ..removeWhere((a) => a['reversed_at'] != null)
          ..sort((a, b) => '${a['alloc_date']}'.compareTo('${b['alloc_date']}'));
        final applied = roundMoney(allocs.fold<double>(0, (s, a) => s + (a['amount'] as num).toDouble()));
        final unallocated = status == 'posted' ? roundMoney(amount - applied) : 0.0;
        final canRecord = canRecordPayment(perms, side);
        final canReverse = canReversePayment(perms);
        final party = p['party'] as Map?;
        final voucher = p['voucher'] as Map?;
        String money(double v) => Fmt.money(v, currency: m.currency);

        final actions = <Widget>[
          if (status == 'posted' && unallocated > 0 && canRecord)
            AppButton(label: 'Apply to ${side.documentLabel}', icon: Icons.link_rounded, onPressed: _busy ? null : () => _apply(p, unallocated)),
          if (status == 'posted' && canReverse)
            AppButton(label: 'Cancel ${side.paymentLabel.toLowerCase()}', icon: Icons.block_rounded, kind: AppButtonKind.danger, onPressed: _busy ? null : _cancel),
        ];

        Widget info(String label, String value) => SizedBox(
              width: 210,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: AppText.small), const SizedBox(height: 2), Text(value, style: AppText.bodyStrong)]),
            );

        return AppPage(
          title: '${p['number']}',
          subtitle: side.isReceivable ? 'Customer receipt' : 'Supplier payment',
          maxWidth: 1000,
          actions: actions,
          children: [
            if (status == 'cancelled' && p['cancel_reason'] != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                child: Row(children: [
                  const Icon(Icons.block_rounded, size: 19, color: AppColors.danger),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Cancelled: ${p['cancel_reason']}', style: const TextStyle(color: AppColors.danger, fontSize: 13.5, fontWeight: FontWeight.w600))),
                ]),
              ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [StatusBadge.status(status), const Spacer(), Text(money(amount), style: AppText.kpi)]),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 24,
                    runSpacing: 14,
                    children: [
                      info(side.partyLabel, '${party?['name'] ?? '--'}'),
                      info('Date', Fmt.date(DateTime.tryParse('${p['pay_date']}'))),
                      info(side.isReceivable ? 'Deposited to' : 'Paid from', '${(p['account'] as Map?)?['name'] ?? '--'}'),
                      if (p['method'] != null) info('Method', '${(p['method'] as Map)['name']}'),
                      if (p['reference'] != null) info('Cheque or transaction number', '${p['reference']}'),
                      info('Recorded by', '${(p['creator'] as Map?)?['full_name'] ?? '--'}'),
                    ],
                  ),
                  if (p['notes'] != null) ...[const SizedBox(height: 14), Text('${p['notes']}', style: AppText.body)],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (party != null) AppButton(label: 'Open ${side.partyLabel.toLowerCase()} profile', icon: Icons.person_outline_rounded, kind: AppButtonKind.ghost, compact: true, onPressed: () => context.go(side.profilePath('${party['id']}'))),
                      if (voucher != null && perms.canView(Modules.finance))
                        AppButton(label: 'Accounting entry ${voucher['voucher_no']}', icon: Icons.receipt_long_outlined, kind: AppButtonKind.ghost, compact: true, onPressed: () => context.go('/finance/vouchers/${voucher['id']}')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Applied to ${side.documentLabel}s',
              subtitle: unallocated > 0 ? '${money(unallocated)} is not applied yet and is held as ${side.isReceivable ? 'a customer advance' : 'an advance to the supplier'}' : null,
              child: allocs.isEmpty
                  ? Text(status == 'cancelled' ? 'Nothing is applied. This ${side.paymentLabel.toLowerCase()} was cancelled.' : 'Nothing is applied yet. The whole amount is held as ${side.isReceivable ? 'a customer advance' : 'an advance to the supplier'}.', style: AppText.body)
                  : Column(
                      children: [
                        for (final a in allocs) ...[
                          _allocationRow(a, m.currency, status == 'posted' && canReverse),
                          if (a != allocs.last) const Divider(height: 1),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _allocationRow(Map<String, dynamic> a, String currency, bool canRemove) {
    final doc = a['document'] as Map?;
    final number = '${doc?['number'] ?? '--'}';
    final path = doc == null ? null : tradeDocumentPath('${doc['doc_type']}', '${doc['id']}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(side.isReceivable ? Icons.receipt_long_outlined : Icons.description_outlined, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: path == null ? null : () => context.go(path),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(number, style: AppText.bodyStrong),
                Text('Applied ${Fmt.date(DateTime.tryParse('${a['alloc_date']}'))}${doc?['due_date'] == null ? '' : ', due ${Fmt.date(DateTime.tryParse('${doc!['due_date']}'))}'}', style: AppText.small),
              ]),
            ),
          ),
          Text(Fmt.money((a['amount'] as num).toDouble(), currency: currency), style: AppText.bodyStrong),
          if (canRemove) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Remove from $number',
              onPressed: _busy ? null : () => _unapply('${a['id']}', number),
              icon: const Icon(Icons.link_off_rounded, size: 20, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Applies part of an advance to an open invoice or bill.
class _ApplyAdvanceForm extends ConsumerStatefulWidget {
  const _ApplyAdvanceForm({required this.side, required this.paymentId, required this.partyId, required this.unallocated});

  final LedgerSide side;
  final String paymentId;
  final String partyId;
  final double unallocated;

  @override
  ConsumerState<_ApplyAdvanceForm> createState() => _ApplyAdvanceFormState();
}

class _ApplyAdvanceFormState extends ConsumerState<_ApplyAdvanceForm> {
  String? _doc;
  String _date = _iso(DateTime.now());
  final _amount = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = roundMoney(double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0);
    if (_doc == null) {
      setState(() => _error = 'Choose the ${widget.side.documentLabel}.');
      return;
    }
    if (amount <= 0 || amount > widget.unallocated) {
      setState(() => _error = 'Enter an amount up to ${widget.unallocated.toStringAsFixed(2)}.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).rpc('apply_advance', params: {'p_payment': widget.paymentId, 'p_document': _doc, 'p_amount': amount, 'p_date': _date});
      if (!mounted) return;
      showToast(context, 'Advance applied');
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
    final side = widget.side;
    final items = m == null
        ? const <Map<String, dynamic>>[]
        : (ref.watch(openItemsProvider((org: m.orgId, side: side.key, party: widget.partyId, asOf: null))).valueOrNull ?? const <Map<String, dynamic>>[]);
    final options = [
      for (final r in items) Option('${r['document_id']}', '${r['number']}  (owes ${Fmt.money((r['balance'] as num).toDouble(), currency: currency)})'),
    ];
    final w = context.isMobile ? double.infinity : 250.0;

    return FormShell(
      title: 'Apply to ${side.documentLabel}',
      subtitle: '${Fmt.money(widget.unallocated, currency: currency)} is available to apply.',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(label: 'Cancel', kind: AppButtonKind.ghost, onPressed: _saving ? null : () => Navigator.of(context).pop()),
          const SizedBox(width: 10),
          AppButton(label: 'Apply', loading: _saving, onPressed: _submit),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchSelectField(
            label: side.documentLabel == 'invoice' ? 'Invoice' : 'Bill',
            required: true,
            hint: options.isEmpty ? 'Nothing is open' : 'Select ${side.documentLabel}',
            options: options,
            value: _doc,
            onChanged: (v) => setState(() {
              _doc = v;
              for (final r in items) {
                if ('${r['document_id']}' == v) {
                  final owes = (r['balance'] as num).toDouble();
                  _amount.text = (owes < widget.unallocated ? owes : widget.unallocated).toStringAsFixed(2);
                }
              }
            }),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(width: w, child: AppTextField(controller: _amount, label: 'Amount', required: true, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
              SizedBox(width: w, child: AppDateField(label: 'Date', required: true, value: _date, onChanged: (v) => setState(() => _date = v ?? _date))),
            ],
          ),
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
}
